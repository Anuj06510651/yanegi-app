import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'block_service.dart';
import 'notification_service.dart';
import 'notification_types.dart';
import 'rate_limiter_service.dart';
import '../models/user_profile.dart';

/// Frontend service for friend operations.
/// Uses the existing notification system for friend requests.
class FriendService {
  FriendService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    BlockService? blockService,
    NotificationService? notificationService,
    RateLimiterService? rateLimiter,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _blockService = blockService,
        _notificationService =
            notificationService ?? NotificationService(firestore: firestore),
        _rateLimiter = rateLimiter ??
            RateLimiterService(firestore: firestore, auth: auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final BlockService? _blockService;
  final NotificationService _notificationService;
  final RateLimiterService _rateLimiter;

  /// The reason the most recent mutating operation returned `false`.
  /// Reset to `null` on success. Read this after a `false` return to surface
  /// a specific error message in the UI.
  final ValueNotifier<FriendRequestError?> lastError =
      ValueNotifier<FriendRequestError?>(null);

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _friendRequests =>
      _firestore.collection('friend_requests');
  CollectionReference<Map<String, dynamic>> get _friends =>
      _firestore.collection('friends');

  String? get _currentUid => _auth.currentUser?.uid;

  String _requestId(String fromUser, String toUser) => '${fromUser}_$toUser';

  Future<bool> _isInteractionBlocked(String uid, String otherUid) {
    return (_blockService ?? BlockService()).isBlockedEitherWay(uid, otherUid);
  }

  DocumentReference<Map<String, dynamic>> _friendEdgeRef(
    String userId,
    String friendId,
  ) {
    return _friends.doc(userId).collection('list').doc(friendId);
  }

  Future<void> _createNotification({
    required String receiverId,
    required String type,
    required String message,
    String? dedupeKey,
    Duration dedupeWindow = const Duration(minutes: 2),
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || receiverId == currentUser.uid) return;

    final effectiveDedupeKey =
        dedupeKey ?? '$type:${currentUser.uid}:$receiverId:$message';

    // Deduplication is handled by NotificationService.sendNotification via
    // deterministic doc IDs — no pre-check query needed here.
    final senderDoc = await _users.doc(currentUser.uid).get();
    final senderData = senderDoc.data() ?? const <String, dynamic>{};
    final senderName =
        (senderData['name'] ?? senderData['username'] ?? 'Someone').toString();
    final senderAvatar =
        (senderData['avatarUrl'] ?? senderData['avatar_url'] ?? '').toString();

    final sent = await _notificationService.sendWithRetry(
      () => _notificationService.sendNotification(
        userId: receiverId,
        type: type,
        senderId: currentUser.uid,
        senderName: senderName,
        senderAvatar: senderAvatar,
        message: message,
        title: message,
        body: message,
        dedupeKey: effectiveDedupeKey,
        dedupeWindow: dedupeWindow,
        actionStatus: type == NotificationType.friendRequest ? 'pending' : null,
      ),
      userId: receiverId,
      type: type,
      senderId: currentUser.uid,
      metadata: <String, dynamic>{
        'dedupeKey': effectiveDedupeKey,
      },
    );
    if (!sent) {
      debugPrint(
          'FRIEND NOTIFICATION FAILURE: type=$type receiver=$receiverId permanently failed after retries');
    }
  }

  Future<FriendRelationshipState> getFriendState(
    String currentUser,
    String targetUser,
  ) async {
    // Mirror the same three deterministic-path lookups used by friendStateStream.
    // Previous implementation ran 4 collection queries (two field-name variants
    // each direction) — expensive, required indexes, and fired on every unrelated
    // request change in the collection. Three doc reads by known ID are cheaper,
    // index-free, and consistent with the stream.
    try {
      final results = await Future.wait([
        _friendEdgeRef(currentUser, targetUser).get(),
        _friendRequests.doc(_requestId(currentUser, targetUser)).get(),
        _friendRequests.doc(_requestId(targetUser, currentUser)).get(),
      ]);

      if (results[0].exists) return FriendRelationshipState.friend;

      final sentStatus =
          (results[1].data()?['status'] ?? '').toString().toLowerCase();
      if (results[1].exists && sentStatus == 'pending') {
        return FriendRelationshipState.requestSent;
      }

      final receivedStatus =
          (results[2].data()?['status'] ?? '').toString().toLowerCase();
      if (results[2].exists && receivedStatus == 'pending') {
        return FriendRelationshipState.requestReceived;
      }

      return FriendRelationshipState.notFriend;
    } catch (_) {
      return FriendRelationshipState.notFriend;
    }
  }

  Stream<FriendRelationshipState> friendStateStream(
    String currentUser,
    String targetUser,
  ) {
    if (currentUser.trim().isEmpty || targetUser.trim().isEmpty) {
      return Stream.value(FriendRelationshipState.notFriend);
    }

    return Stream.multi((controller) {
      // Streams are created inside the callback so each listener (StreamBuilder)
      // gets its own Firestore subscriptions. Creating them outside would share
      // single-subscription streams across listeners, throwing "already listened".
      final friendDocStream = _friendEdgeRef(currentUser, targetUser).snapshots();
      final sentRequestStream =
          _friendRequests.doc(_requestId(currentUser, targetUser)).snapshots();
      final receivedRequestStream =
          _friendRequests.doc(_requestId(targetUser, currentUser)).snapshots();

      bool isFriend = false;
      bool sentPending = false;
      bool receivedPending = false;

      void emit() {
        if (isFriend) {
          controller.add(FriendRelationshipState.friend);
          return;
        }
        if (sentPending) {
          controller.add(FriendRelationshipState.requestSent);
          return;
        }
        if (receivedPending) {
          controller.add(FriendRelationshipState.requestReceived);
          return;
        }
        controller.add(FriendRelationshipState.notFriend);
      }

      final subFriend = friendDocStream.listen(
        (snap) {
          isFriend = snap.exists;
          emit();
        },
        onError: (_, __) {
          isFriend = false;
          emit();
        },
      );

      // A sent request is pending only when the doc exists AND status is
      // 'pending'. Accepted/rejected/cancelled/blocked docs must not show
      // as pending — their state is captured by the edge doc or ignored.
      final subSent = sentRequestStream.listen(
        (snap) {
          sentPending = snap.exists &&
              (snap.data()?['status'] ?? '').toString().toLowerCase() ==
                  'pending';
          emit();
        },
        onError: (_, __) {
          sentPending = false;
          emit();
        },
      );

      final subReceived = receivedRequestStream.listen(
        (snap) {
          receivedPending = snap.exists &&
              (snap.data()?['status'] ?? '').toString().toLowerCase() ==
                  'pending';
          emit();
        },
        onError: (_, __) {
          receivedPending = false;
          emit();
        },
      );

      controller.onCancel = () async {
        await subFriend.cancel();
        await subSent.cancel();
        await subReceived.cancel();
      };
    });
  }

  Stream<List<String>> friendIdsStream(String userId) {
    if (userId.trim().isEmpty) return Stream.value(const <String>[]);

    return _friends
        .doc(userId)
        .collection('list')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => d.id).toList());
  }

  // ─── FRIEND REQUEST ───────────────────────────────────────

  Future<bool> createFriendRequest({
    required String senderId,
    required String receiverId,
  }) async {
    if (senderId.trim().isEmpty || receiverId.trim().isEmpty) return false;
    if (senderId == receiverId) return false;

    final requestId = _requestId(senderId, receiverId);
    final requestRef = _friendRequests.doc(requestId);
    final reverseRequestRef =
        _friendRequests.doc(_requestId(receiverId, senderId));
    var created = false;
    var staleCleaned = false;

    debugPrint(
        'FRIEND FLOW START: createFriendRequest sender=$senderId receiver=$receiverId docId=$requestId');

    try {
      await _firestore.runTransaction((txn) async {
        // Read BOTH edges atomically so partial corruption (one edge missing) is detected.
        final senderEdge = await txn.get(_friendEdgeRef(senderId, receiverId));
        final receiverEdge =
            await txn.get(_friendEdgeRef(receiverId, senderId));

        debugPrint(
            'FRIEND CONSISTENCY CHECK: sender=$senderId receiver=$receiverId '
            'senderEdge=${senderEdge.exists} receiverEdge=${receiverEdge.exists}');

        // Real friendship requires BOTH edges. This is the ONLY "already friends" guard.
        if (senderEdge.exists && receiverEdge.exists) {
          debugPrint(
              'FRIEND FLOW: already friends (both edges exist), skipping');
          return;
        }

        final existing = await txn.get(requestRef);
        final existingStatus =
            (existing.data()?['status'] ?? '').toString().toLowerCase();
        if (existingStatus == 'pending') {
          debugPrint('FRIEND FLOW: request already pending, skipping');
          return;
        }

        final reverse = await txn.get(reverseRequestRef);
        final reverseStatus =
            (reverse.data()?['status'] ?? '').toString().toLowerCase();
        if (reverseStatus == 'pending') {
          debugPrint('FRIEND FLOW: reverse request already pending, skipping');
          return;
        }

        // Terminal-state cleanup: any non-pending, non-absent doc at this doc ID
        // would block a fresh CREATE (rules only allow CREATE when the doc is
        // absent). Delete and re-create in a second transaction.
        //
        // Forward stale statuses (existing request A→B):
        //   accepted  — incomplete edges (corruption)
        //   blocked   — post-unblock GC
        //   declined / cancelled / rejected — terminal; either party may re-send
        //
        // Reverse stale statuses (existing request B→A):
        //   accepted / blocked — same corruption / GC reasons; only these two
        //   require cleanup on the reverse because a 'declined'/'cancelled' B→A
        //   doc does not occupy the A→B doc ID, so it can't block the create.
        final bool isStaleForward = existingStatus == 'accepted' ||
            existingStatus == 'blocked' ||
            existingStatus == 'declined' ||
            existingStatus == 'cancelled' ||
            existingStatus == 'rejected';
        final bool isStaleReverse =
            reverseStatus == 'accepted' || reverseStatus == 'blocked';
        if (isStaleForward || isStaleReverse) {
          debugPrint(
              'STALE REQUEST FOUND: requestId=$requestId '
              'existingStatus=$existingStatus reverseStatus=$reverseStatus '
              'senderEdge=${senderEdge.exists} receiverEdge=${receiverEdge.exists}');

          if (isStaleForward) {
            debugPrint('STALE REQUEST DELETED: friend_requests/$requestId');
            txn.delete(requestRef);
          }
          if (isStaleReverse) {
            debugPrint(
                'STALE REQUEST DELETED: friend_requests/${_requestId(receiverId, senderId)}');
            txn.delete(reverseRequestRef);
          }
          staleCleaned = true;
          // Do not create the pending request in this same transaction — deleting
          // and re-creating the same doc id within one txn is treated as an update,
          // which the rules reject. Create it in a second txn (below).
          return;
        }

        debugPrint('FRIEND FLOW: WRITE START friend_requests/$requestId');
        txn.set(requestRef, {
          'fromUser': senderId,
          'toUser': receiverId,
          'fromUserId': senderId,
          'toUserId': receiverId,
          'senderId': senderId,
          'receiverId': receiverId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        created = true;
      });
    } catch (e, stack) {
      debugPrint(
          'FRIEND FLOW FAILURE: createFriendRequest transaction error=$e');
      debugPrintStack(stackTrace: stack);
      return false;
    }

    // Second transaction: after deleting the stale accepted request, create a
    // fresh pending request (doc now absent → governed by the CREATE rule).
    if (staleCleaned && !created) {
      try {
        await _firestore.runTransaction((txn) async {
          final existing = await txn.get(requestRef);
          final existingStatus =
              (existing.data()?['status'] ?? '').toString().toLowerCase();
          if (existingStatus == 'pending') {
            debugPrint('FRIEND FLOW: request already pending after cleanup');
            return;
          }
          debugPrint(
              'FRIEND FLOW: WRITE START (post-cleanup) friend_requests/$requestId');
          txn.set(requestRef, {
            'fromUser': senderId,
            'toUser': receiverId,
            'fromUserId': senderId,
            'toUserId': receiverId,
            'senderId': senderId,
            'receiverId': receiverId,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          created = true;
        });
      } catch (e, stack) {
        debugPrint(
            'FRIEND FLOW FAILURE: createFriendRequest post-cleanup error=$e');
        debugPrintStack(stackTrace: stack);
        return false;
      }
    }

    if (!created) {
      debugPrint(
          'FRIEND FLOW: createFriendRequest not created (duplicate/already friends)');
      return false;
    }

    debugPrint('FRIEND FLOW SUCCESS: friend_requests/$requestId created');

    final senderDoc = await _users.doc(senderId).get();
    final senderData = senderDoc.data() ?? const <String, dynamic>{};
    final senderName =
        (senderData['name'] ?? senderData['username'] ?? 'Someone').toString();
    final senderAvatar =
        (senderData['avatarUrl'] ?? senderData['avatar_url'] ?? '').toString();

    debugPrint(
        'FRIEND NOTIFICATION START: type=friend_request receiver=$receiverId '
        'dedupeKey=friend_request:$senderId:$receiverId '
        'docPath=notifications/dedupe_<hash($receiverId|friend_request:$senderId:$receiverId)>');
    final notifSent = await _notificationService.sendWithRetry(
      () => _notificationService.sendNotification(
        userId: receiverId,
        type: NotificationType.friendRequest,
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        message: 'sent you a friend request',
        title: 'sent you a friend request',
        body: 'sent you a friend request',
        actionStatus: 'pending',
        dedupeKey: 'friend_request:$senderId:$receiverId',
      ),
      userId: receiverId,
      type: NotificationType.friendRequest,
      senderId: senderId,
      metadata: <String, dynamic>{
        'dedupeKey': 'friend_request:$senderId:$receiverId',
      },
    );
    if (notifSent) {
      debugPrint(
          'FRIEND NOTIFICATION SUCCESS: friend_request sent to $receiverId');
    } else {
      debugPrint(
          'FRIEND NOTIFICATION FAILURE: friend_request permanently failed receiver=$receiverId');
    }

    return true;
  }

  /// Sends a friend request by creating a notification entry.
  ///
  /// Enforces both per-hour (30) and per-day (100) sliding-window quotas via
  /// [RateLimiterService] before any Firestore write. Quota is recorded only
  /// when the request actually commits, so failed sends don't burn quota.
  Future<bool> sendFriendRequest(String toUid) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty) {
      lastError.value = FriendRequestError.networkError;
      return false;
    }
    if (uid == toUid) {
      lastError.value = FriendRequestError.selfRequest;
      return false;
    }

    debugPrint('FRIEND FLOW START: sendFriendRequest uid=$uid toUid=$toUid');
    try {
      final hourCheck =
          await _rateLimiter.check(RateLimiterService.friendRequestPerHour);
      if (!hourCheck.allowed) {
        debugPrint(
            'FRIEND FLOW BLOCKED: rate limit hour exceeded uid=$uid retryAfter=${hourCheck.retryAfter}');
        lastError.value = FriendRequestError.rateLimited;
        return false;
      }
      final dayCheck =
          await _rateLimiter.check(RateLimiterService.friendRequestPerDay);
      if (!dayCheck.allowed) {
        debugPrint(
            'FRIEND FLOW BLOCKED: rate limit day exceeded uid=$uid retryAfter=${dayCheck.retryAfter}');
        lastError.value = FriendRequestError.rateLimited;
        return false;
      }

      final isBlocked = await _isInteractionBlocked(uid, toUid);
      debugPrint(
          'FRIEND FLOW: block check result uid=$uid toUid=$toUid blocked=$isBlocked');
      if (isBlocked) {
        debugPrint(
            'FRIEND FLOW FAILURE: RULE BLOCKED — sendFriendRequest blocked uid=$uid toUid=$toUid');
        lastError.value = FriendRequestError.blocked;
        return false;
      }

      final success = await createFriendRequest(
        senderId: uid,
        receiverId: toUid,
      );
      if (success) {
        lastError.value = null;
        unawaited(
            _rateLimiter.record(RateLimiterService.friendRequestPerHour));
        unawaited(
            _rateLimiter.record(RateLimiterService.friendRequestPerDay));
      } else {
        if (lastError.value == null) {
          lastError.value = FriendRequestError.requestAlreadyPending;
        }
      }
      debugPrint(
          'FRIEND FLOW ${success ? 'SUCCESS' : 'FAILURE'}: sendFriendRequest uid=$uid toUid=$toUid');
      return success;
    } catch (e, stack) {
      debugPrint(
          'FRIEND FLOW FAILURE: sendFriendRequest error=$e uid=$uid toUid=$toUid');
      debugPrintStack(stackTrace: stack);
      lastError.value = FriendRequestError.networkError;
      return false;
    }
  }

  Future<bool> acceptFriendRequest(String fromUid) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty || fromUid.trim().isEmpty) {
      return false;
    }

    debugPrint(
        'FRIEND FLOW START: acceptFriendRequest uid=$uid fromUid=$fromUid');
    try {
      final isBlocked = await _isInteractionBlocked(uid, fromUid);
      debugPrint(
          'FRIEND FLOW: block check result uid=$uid fromUid=$fromUid blocked=$isBlocked');
      if (isBlocked) {
        debugPrint(
            'FRIEND FLOW FAILURE: RULE BLOCKED — acceptFriendRequest uid=$uid fromUid=$fromUid');
        lastError.value = FriendRequestError.blocked;
        return false;
      }

      final requestId = _requestId(fromUid, uid);
      final requestRef = _friendRequests.doc(requestId);

      debugPrint(
          'FRIEND FLOW: WRITE START acceptFriendRequest txn friend_requests/$requestId');
      await _firestore.runTransaction((txn) async {
        final requestSnap = await txn.get(requestRef);
        if (!requestSnap.exists) {
          throw StateError('no_request');
        }
        final requestData = requestSnap.data() ?? const <String, dynamic>{};
        final requestStatus =
            (requestData['status'] ?? '').toString().toLowerCase();
        if (requestStatus != 'pending') {
          throw StateError('not_pending:$requestStatus');
        }
        if ((requestData['fromUserId'] ?? requestData['senderId'] ?? '')
                .toString() !=
            fromUid) {
          throw StateError('sender_mismatch');
        }
        if ((requestData['toUserId'] ?? requestData['receiverId'] ?? '')
                .toString() !=
            uid) {
          throw StateError('receiver_mismatch');
        }

        txn.set(
          requestRef,
          {
            'status': 'accepted',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        txn.set(
          _friendEdgeRef(uid, fromUid),
          {
            'friendId': fromUid,
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        txn.set(
          _friendEdgeRef(fromUid, uid),
          {
            'friendId': uid,
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        txn.set(
          _users.doc(uid),
          {
            'friends': FieldValue.arrayUnion([fromUid]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        txn.set(
          _users.doc(fromUid),
          {
            'friends': FieldValue.arrayUnion([uid]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      debugPrint(
          'FRIEND FLOW SUCCESS: acceptFriendRequest txn complete uid=$uid fromUid=$fromUid — both edges + users updated');

      try {
        debugPrint(
            'FRIEND NOTIFICATION START: type=friend_accept receiver=$fromUid dedupeKey=friend_accept:$uid:$fromUid');
        await _createNotification(
          receiverId: fromUid,
          type: NotificationType.friendAccept,
          message: 'accepted your friend request',
          dedupeKey: 'friend_accept:$uid:$fromUid',
        );
        debugPrint(
            'FRIEND NOTIFICATION SUCCESS: friend_accept sent to $fromUid');
      } catch (notificationError, stack) {
        debugPrint(
            'FRIEND NOTIFICATION FAILURE: friend_accept non-fatal error=$notificationError');
        debugPrintStack(stackTrace: stack);
      }

      lastError.value = null;
      debugPrint(
          'FRIEND FLOW SUCCESS: acceptFriendRequest complete uid=$uid fromUid=$fromUid');
      return true;
    } catch (e, stack) {
      debugPrint(
          'FRIEND FLOW FAILURE: acceptFriendRequest error=$e uid=$uid fromUid=$fromUid');
      debugPrintStack(stackTrace: stack);
      final msg = e is StateError ? e.message : '';
      if (msg == 'no_request') {
        lastError.value = FriendRequestError.noRequestFound;
      } else if (msg.startsWith('not_pending')) {
        lastError.value = FriendRequestError.requestNotPending;
      } else if (msg == 'sender_mismatch') {
        lastError.value = FriendRequestError.senderMismatch;
      } else if (msg == 'receiver_mismatch') {
        lastError.value = FriendRequestError.receiverMismatch;
      } else {
        lastError.value = FriendRequestError.networkError;
      }
      return false;
    }
  }

  Future<bool> declineFriendRequest(String fromUid) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty || fromUid.trim().isEmpty) {
      return false;
    }

    debugPrint(
        'FRIEND FLOW START: declineFriendRequest uid=$uid fromUid=$fromUid');
    try {
      final isBlocked = await _isInteractionBlocked(uid, fromUid);
      debugPrint(
          'FRIEND FLOW: block check result uid=$uid fromUid=$fromUid blocked=$isBlocked');
      if (isBlocked) {
        debugPrint(
            'FRIEND FLOW FAILURE: RULE BLOCKED — declineFriendRequest uid=$uid fromUid=$fromUid');
        lastError.value = FriendRequestError.blocked;
        return false;
      }

      final requestRef = _friendRequests.doc(_requestId(fromUid, uid));
      debugPrint(
          'FRIEND FLOW: WRITE START declineFriendRequest txn friend_requests/${_requestId(fromUid, uid)}');
      await _firestore.runTransaction((txn) async {
        final requestSnap = await txn.get(requestRef);
        if (!requestSnap.exists) {
          throw StateError('no_request');
        }
        final requestData = requestSnap.data() ?? const <String, dynamic>{};
        final requestStatus =
            (requestData['status'] ?? '').toString().toLowerCase();
        if (requestStatus != 'pending') {
          throw StateError('not_pending:$requestStatus');
        }
        if ((requestData['toUserId'] ?? requestData['receiverId'] ?? '')
                .toString() !=
            uid) {
          throw StateError('receiver_mismatch');
        }

        txn.set(
          requestRef,
          {
            'status': 'declined',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      lastError.value = null;
      debugPrint(
          'FRIEND FLOW SUCCESS: declineFriendRequest complete uid=$uid fromUid=$fromUid');
      return true;
    } catch (e, stack) {
      debugPrint(
          'FRIEND FLOW FAILURE: declineFriendRequest error=$e uid=$uid fromUid=$fromUid');
      debugPrintStack(stackTrace: stack);
      final msg = e is StateError ? e.message : '';
      if (msg == 'no_request') {
        lastError.value = FriendRequestError.noRequestFound;
      } else if (msg.startsWith('not_pending')) {
        lastError.value = FriendRequestError.requestNotPending;
      } else if (msg == 'receiver_mismatch') {
        lastError.value = FriendRequestError.receiverMismatch;
      } else {
        lastError.value = FriendRequestError.networkError;
      }
      return false;
    }
  }

  /// Cancels an outgoing friend request that is still pending.
  ///
  /// Only the original sender may cancel. Returns `false` if no pending request
  /// exists, the caller is not the sender, or a Firestore error occurs.
  /// After cancellation the doc status is `cancelled`; the sender may re-send
  /// after the doc is cleaned up on the next [createFriendRequest] call.
  Future<bool> cancelFriendRequest(String toUid) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty || toUid.trim().isEmpty) return false;
    if (uid == toUid) return false;

    final requestRef = _friendRequests.doc(_requestId(uid, toUid));
    debugPrint(
        'FRIEND FLOW START: cancelFriendRequest uid=$uid toUid=$toUid');
    try {
      await _firestore.runTransaction((txn) async {
        final requestSnap = await txn.get(requestRef);
        if (!requestSnap.exists) {
          throw StateError('no_request');
        }
        final requestData = requestSnap.data() ?? const <String, dynamic>{};
        final status =
            (requestData['status'] ?? '').toString().toLowerCase();
        if (status != 'pending') {
          throw StateError('not_pending:$status');
        }
        final storedSender =
            (requestData['fromUserId'] ?? requestData['senderId'] ?? '')
                .toString();
        if (storedSender != uid) {
          throw StateError('not_sender');
        }
        txn.set(
          requestRef,
          {
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      lastError.value = null;
      debugPrint(
          'FRIEND FLOW SUCCESS: cancelFriendRequest uid=$uid toUid=$toUid');
      return true;
    } catch (e, stack) {
      debugPrint(
          'FRIEND FLOW FAILURE: cancelFriendRequest error=$e uid=$uid toUid=$toUid');
      debugPrintStack(stackTrace: stack);
      final msg = e is StateError ? e.message : '';
      if (msg == 'no_request') {
        lastError.value = FriendRequestError.noRequestFound;
      } else if (msg.startsWith('not_pending')) {
        lastError.value = FriendRequestError.requestNotPending;
      } else if (msg == 'not_sender') {
        lastError.value = FriendRequestError.notSender;
      } else {
        lastError.value = FriendRequestError.networkError;
      }
      return false;
    }
  }

  // ─── REMOVE FRIEND ────────────────────────────────────────

  /// Removes a friend bidirectionally.
  ///
  /// The `friends/{uid}/list/{friendUid}` edge docs are the source of truth for
  /// friendship (drives `friendStateStream` and the friends list). Those edge
  /// deletes — plus removing the friend from the caller's own `friends` array —
  /// are always permitted by rules, so they go in the primary batch.
  ///
  /// The cross-user write that removes the caller from the OTHER user's `friends`
  /// array is rule-gated on that array currently containing the caller. When the
  /// legacy array is inconsistent (missing field / already absent) that write is
  /// denied. We do it best-effort in a separate call so a stale array can never
  /// block the actual un-friend. (Previously this lived in the same batch, so any
  /// array inconsistency failed the whole remove — the reported "remove not
  /// working" bug.)
  Future<bool> removeFriend(String friendUid) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty || friendUid.trim().isEmpty) {
      return false;
    }
    if (uid == friendUid) return false;

    debugPrint('FRIEND FLOW START: removeFriend uid=$uid friendUid=$friendUid');
    try {
      final batch = _firestore.batch();

      // Source of truth: both friendship edges.
      batch.delete(_friendEdgeRef(uid, friendUid));
      batch.delete(_friendEdgeRef(friendUid, uid));

      // Own friends array (own-doc update is always permitted by the allowlist rule).
      batch.set(
        _users.doc(uid),
        {
          'friends': FieldValue.arrayRemove([friendUid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
      debugPrint('FRIEND_REMOVED: uid=$uid friendUid=$friendUid (edges deleted)');
    } catch (e, stack) {
      debugPrint(
          'FRIEND FLOW FAILURE: removeFriend primary batch error=$e uid=$uid friendUid=$friendUid');
      debugPrintStack(stackTrace: stack);
      return false;
    }

    // Best-effort: remove self from the other user's legacy friends array.
    // A denial here (stale/inconsistent array) must not fail the un-friend.
    try {
      await _users.doc(friendUid).set(
        {
          'friends': FieldValue.arrayRemove([uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint(
          'FRIEND FLOW: removeFriend cross-user array update skipped (non-fatal) error=$e');
    }

    return true;
  }

  // ─── CLEANUP UTILITY ─────────────────────────────────────

  /// DEBUG / ADMIN ONLY — not exposed in any production UI.
  ///
  /// Scans `friend_requests` with `status: 'accepted'` for [userId] and DELETES
  /// any request whose friendship edges do not BOTH exist. These are corrupted
  /// legacy records (accepted-but-not-actually-friends) left by older partial
  /// transactions. Deleting them lets a fresh pending request be created later.
  ///
  /// This does NOT fabricate friendship edges — a deleted stale request simply
  /// returns the pair to the NONE state, so a normal Add Friend → pending →
  /// accept flow can re-establish the friendship cleanly.
  ///
  /// Returns the number of stale accepted requests deleted.
  ///
  /// Call from a developer screen or Flutter test only:
  ///   final count = await friendService.cleanupCorruptedFriendRequests(uid);
  Future<int> cleanupCorruptedFriendRequests(String userId) async {
    if (userId.trim().isEmpty) return 0;
    debugPrint('FRIEND CLEANUP SCAN: starting for userId=$userId');
    int deletedCount = 0;

    final sentDocs = await _friendRequests
        .where('fromUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();
    final receivedDocs = await _friendRequests
        .where('toUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'accepted')
        .get();

    final seen = <String>{};
    final allDocs = [...sentDocs.docs, ...receivedDocs.docs]
        .where((d) => seen.add(d.id))
        .toList();

    debugPrint(
        'FRIEND CLEANUP SCAN: found ${allDocs.length} accepted request(s) for userId=$userId');

    for (final doc in allDocs) {
      final data = doc.data();
      final fromId =
          (data['fromUserId'] ?? data['fromUser'] ?? data['senderId'] ?? '')
              .toString()
              .trim();
      final toId =
          (data['toUserId'] ?? data['toUser'] ?? data['receiverId'] ?? '')
              .toString()
              .trim();

      if (fromId.isEmpty || toId.isEmpty || fromId == toId) continue;

      final senderEdge = await _friendEdgeRef(fromId, toId).get();
      final receiverEdge = await _friendEdgeRef(toId, fromId).get();

      if (senderEdge.exists && receiverEdge.exists) {
        debugPrint(
            'FRIEND CLEANUP SCAN: $fromId ↔ $toId healthy — keeping request');
        continue;
      }

      debugPrint(
          'CORRUPTED ACCEPTED REQUEST: ${doc.id} '
          'senderEdge=${senderEdge.exists} receiverEdge=${receiverEdge.exists}');

      try {
        await doc.reference.delete();
        deletedCount++;
        debugPrint('STALE REQUEST DELETED: ${doc.id}');
      } catch (e, stack) {
        debugPrint('FRIEND CLEANUP FAILED: ${doc.id} error=$e');
        debugPrintStack(stackTrace: stack);
      }
    }

    debugPrint(
        'FRIEND CLEANUP SCAN: complete deletedCount=$deletedCount for userId=$userId');
    return deletedCount;
  }

  // ─── FRIENDS LIST ─────────────────────────────────────────

  /// Fetches full UserProfile objects for all friends of a user.
  Future<List<UserProfile>> getFriendsList(String uid) async {
    try {
      final friendsSnapshot = await _friends.doc(uid).collection('list').get();
      final friendUids = friendsSnapshot.docs.map((d) => d.id).toList();

      if (friendUids.isEmpty) return [];

      // Batch fetch friends (Firestore `in` supports max 10 per query)
      final List<UserProfile> friends = [];
      for (int i = 0; i < friendUids.length; i += 10) {
        final chunk = friendUids.skip(i).take(10).toList();
        final snapshot =
            await _users.where(FieldPath.documentId, whereIn: chunk).get();

        friends.addAll(
          snapshot.docs.map((doc) => UserProfile.fromFirestore(doc)),
        );
      }

      return friends;
    } catch (e) {
      debugPrint('Failed to fetch friends list: $e');
      return [];
    }
  }

  // ─── MUTUAL FRIENDS ───────────────────────────────────────

  /// Counts friends shared between [currentUid] and [targetUid].
  ///
  /// Strategy: two `friends/{uid}/list` collection reads + a set intersection.
  /// No N+1 — friend identities are the subcollection doc IDs, so no per-friend
  /// document fetch is needed. `friends/*/list` is readable by any signed-in
  /// user (public social graph), so both reads are permitted.
  Future<int> mutualFriendsCount(String currentUid, String targetUid) async {
    if (currentUid.trim().isEmpty || targetUid.trim().isEmpty) return 0;
    if (currentUid == targetUid) return 0;

    try {
      final results = await Future.wait([
        _friends.doc(currentUid).collection('list').get(),
        _friends.doc(targetUid).collection('list').get(),
      ]);
      final mine = results[0].docs.map((d) => d.id).toSet();
      final theirs = results[1].docs.map((d) => d.id).toSet();
      final count = mine.intersection(theirs).length;
      debugPrint(
          'MUTUAL_COUNT_CALCULATED: $currentUid ∩ $targetUid = $count');
      return count;
    } catch (e, stack) {
      debugPrint('mutualFriendsCount failed: $e');
      debugPrintStack(stackTrace: stack);
      return 0;
    }
  }

  // ─── FRIENDSHIP STATUS ────────────────────────────────────

  /// Checks the friendship status between two users.
  Future<FriendshipStatus> getFriendshipStatus(
      String uid, String otherUid) async {
    try {
      final state = await getFriendState(uid, otherUid);
      switch (state) {
        case FriendRelationshipState.friend:
          return FriendshipStatus.friends;
        case FriendRelationshipState.requestSent:
        case FriendRelationshipState.requestReceived:
          return FriendshipStatus.pending;
        case FriendRelationshipState.notFriend:
          return FriendshipStatus.none;
      }
    } catch (e) {
      debugPrint('Failed to check friendship status: $e');
      return FriendshipStatus.none;
    }
  }
}

enum FriendRelationshipState {
  notFriend,
  requestSent,
  requestReceived,
  friend,
}

enum FriendshipStatus {
  none,
  pending,
  friends,
}

/// Discriminated error reason surfaced by [FriendService.lastError].
///
/// After any operation that returns `false`, the UI can read
/// `friendService.lastError.value` to display a specific message instead of a
/// generic "Something went wrong".
enum FriendRequestError {
  /// Tried to send a request to oneself.
  selfRequest,

  /// A block exists between the two users (either direction).
  blocked,

  /// Client-side rate limit exceeded for this action.
  rateLimited,

  /// Both friendship edge docs already exist — users are already friends.
  alreadyFriends,

  /// A pending request already exists for this pair.
  requestAlreadyPending,

  /// Accept / decline / cancel: no pending request was found.
  noRequestFound,

  /// Accept / decline: the request is no longer in `pending` status.
  requestNotPending,

  /// Accept: stored sender UID does not match the provided `fromUid`.
  senderMismatch,

  /// Accept / decline: stored receiver UID does not match the caller.
  receiverMismatch,

  /// Cancel: caller is not the sender of the request.
  notSender,

  /// Firestore transaction or network error.
  networkError,
}
