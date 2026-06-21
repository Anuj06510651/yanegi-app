import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/activity_notification_model.dart';
import 'event_service.dart';
import 'friend_service.dart';
import 'notification_service.dart';
import 'notification_types.dart';
import 'user_service.dart';

class ActivityNotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  final EventService _eventService = EventService();
  final FriendService _friendService = FriendService();
  final NotificationService _notificationService = NotificationService();

  CollectionReference get _notifications =>
      _firestore.collection('notifications');

  Query<Map<String, dynamic>> _baseQueryForUser(String uid) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);
  }

  // Fetch notifications (latest page, real-time)
  Stream<List<ActivityNotification>> getNotifications({int? limit}) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    Query<Map<String, dynamic>> notificationsQuery =
        _baseQueryForUser(user.uid);

    if (limit != null && limit > 0) {
      notificationsQuery = notificationsQuery.limit(limit);
    }

    return notificationsQuery.snapshots().transform(
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              List<ActivityNotification>>.fromHandlers(
            handleData: (snapshot, sink) {
              final items = snapshot.docs.map((doc) {
                final data = Map<String, dynamic>.from(doc.data());
                data['type'] = normalizeType((data['type'] ?? '').toString());
                if (kDebugMode) {
                  final hasRequiredFields = data.containsKey('userId') &&
                      data.containsKey('type') &&
                      data.containsKey('createdAt') &&
                      (data.containsKey('read') || data.containsKey('isRead'));
                  if (!hasRequiredFields) {
                    debugPrint(
                      'Notification ${doc.id} is missing required fields (userId/type/createdAt/read).',
                    );
                  }
                }
                return ActivityNotification.fromMap(data, id: doc.id);
              }).toList();
              items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              sink.add(items);
            },
            handleError: (error, stackTrace, sink) {
              debugPrint('Notifications stream failed: $error');
              debugPrintStack(stackTrace: stackTrace);
              sink.add(const <ActivityNotification>[]);
            },
          ),
        );
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
      getLatestNotificationsCursor({
    int limit = 20,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final snapshot = await _baseQueryForUser(user.uid).limit(limit).get();
      if (snapshot.docs.isEmpty) return null;
      return snapshot.docs.last;
    } catch (e, stack) {
      debugPrint('Latest notifications cursor failed: $e');
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  Future<NotificationPage> fetchOlderNotificationsPage({
    required QueryDocumentSnapshot<Map<String, dynamic>> startAfter,
    int limit = 20,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const NotificationPage(
        items: [],
        lastVisible: null,
        hasMore: false,
      );
    }

    try {
      final snapshot = await _baseQueryForUser(user.uid)
          .startAfterDocument(startAfter)
          .limit(limit)
          .get();

      final items = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['type'] = normalizeType((data['type'] ?? '').toString());
        return ActivityNotification.fromMap(data, id: doc.id);
      }).toList();

      return NotificationPage(
        items: items,
        lastVisible: snapshot.docs.isNotEmpty ? snapshot.docs.last : startAfter,
        hasMore: snapshot.docs.length == limit,
      );
    } catch (e, stack) {
      debugPrint('Older notifications fetch failed: $e');
      debugPrintStack(stackTrace: stack);
      return const NotificationPage(
        items: [],
        lastVisible: null,
        hasMore: false,
      );
    }
  }

  Stream<int> unreadCountStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(0);

    return _baseQueryForUser(user.uid).snapshots().transform(
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>,
              int>.fromHandlers(
            handleData: (snapshot, sink) {
              var unread = 0;
              for (final doc in snapshot.docs) {
                final data = doc.data();
                final isRead = data['read'] == true || data['isRead'] == true;
                if (!isRead) unread++;
              }
              sink.add(unread);
            },
            handleError: (error, stackTrace, sink) {
              debugPrint('Unread notifications stream failed: $error');
              debugPrintStack(stackTrace: stackTrace);
              sink.add(0);
            },
          ),
        );
  }

  // Mark as read
  Future<void> markAsRead(String notificationId) async {
    await _notifications.doc(notificationId).update({
      'read': true,
      'isRead': true,
    });
  }

  Future<void> markAllAsRead(Iterable<String> notificationIds) async {
    final ids = notificationIds.where((e) => e.trim().isNotEmpty).toList();
    if (ids.isEmpty) return;

    final batch = _firestore.batch();
    for (final id in ids) {
      batch.update(_notifications.doc(id), {
        'read': true,
        'isRead': true,
      });
    }
    await batch.commit();
  }

  Future<void> markAllCurrentUserNotificationsAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snapshot = await _baseQueryForUser(user.uid).get();

    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    var unreadFound = false;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final isRead = data['read'] == true || data['isRead'] == true;
      if (isRead) continue;
      unreadFound = true;
      batch.update(doc.reference, {
        'read': true,
        'isRead': true,
      });
    }
    if (!unreadFound) return;
    await batch.commit();
  }

  // Create a generic notification
  Future<void> createNotification({
    required String receiverId,
    required String type,
    required String message,
    String? title,
    String? eventId,
    String? eventBannerUrl,
    String? chatId,
    String? dedupeKey,
    Duration dedupeWindow = const Duration(minutes: 2),
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Don't notify self
    if (receiverId == currentUser.uid) return;

    final effectiveDedupeKey = dedupeKey ??
        '$type:${currentUser.uid}:$receiverId:${eventId ?? ''}:${chatId ?? ''}:$message';

    // Deduplication is handled by NotificationService.sendNotification via a
    // deterministic doc ID (dedupe_{base64(receiverId|dedupeKey)}) checked
    // inside a Firestore transaction. That read is allowed because either the
    // doc doesn't exist (resource == null guard) or the sender reads their own
    // sent notification (senderId == auth.uid).
    //
    // The previous query-based dedup (.where('userId', == receiverId)) was
    // permanently broken: the notifications LIST rule requires userId == auth.uid
    // for collection queries, so querying another user's notifications always
    // returned PERMISSION_DENIED, which was silently swallowed — dedup never ran
    // and every call path sent duplicate notifications.

    final senderData = await _userService.getUser(currentUser.uid);
    final senderName =
        senderData?['name'] ?? senderData?['username'] ?? 'Someone';
    final senderAvatar =
        senderData?['avatarUrl'] ?? senderData?['avatar_url'] ?? '';

    String resolvedEventBannerUrl = (eventBannerUrl ?? '').toString();
    if (resolvedEventBannerUrl.trim().isEmpty &&
        eventId != null &&
        eventId.trim().isNotEmpty) {
      try {
        final eventDoc =
            await _firestore.collection('events').doc(eventId).get();
        final eventData = eventDoc.data() ?? const <String, dynamic>{};
        resolvedEventBannerUrl =
            (eventData['bannerUrl'] ?? eventData['bannerImagePath'] ?? '')
                .toString();
      } catch (e, stack) {
        resolvedEventBannerUrl = '';
        debugPrint('Event banner lookup failed for notification: $e');
        debugPrintStack(stackTrace: stack);
      }
    }

    await _notificationService.sendWithRetry(
      () => _notificationService.sendNotification(
        userId: receiverId,
        type: type,
        senderId: currentUser.uid,
        senderName: senderName,
        senderAvatar: senderAvatar,
        eventId: eventId,
        message: message,
        title: title ?? message,
        body: message,
        chatId: chatId,
        dedupeKey: effectiveDedupeKey,
        dedupeWindow: dedupeWindow,
        actionStatus: type == NotificationType.friendRequest ? 'pending' : null,
        eventBannerUrl: resolvedEventBannerUrl,
      ),
      userId: receiverId,
      type: type,
      senderId: currentUser.uid,
      metadata: <String, dynamic>{
        if (eventId != null) 'eventId': eventId,
        if (chatId != null) 'chatId': chatId,
        'dedupeKey': effectiveDedupeKey,
      },
    );
  }

  // Friend logic
  Future<void> acceptFriendRequest(ActivityNotification notification) async {
    final accepted =
        await _friendService.acceptFriendRequest(notification.senderId);
    if (!accepted) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final pendingFriendNotifications = await _firestore
        .collection('notifications')
        .where('type', isEqualTo: 'friend_request')
        .where('senderId', isEqualTo: notification.senderId)
        .where('userId', isEqualTo: currentUser.uid)
        .where('actionStatus', isEqualTo: 'pending')
        .get();

    for (final doc in pendingFriendNotifications.docs) {
      await doc.reference.update({
        'actionStatus': 'accepted',
        'read': true,
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('Notification updated to accepted');
      }
    }

    if (pendingFriendNotifications.docs.isEmpty &&
        notification.id.trim().isNotEmpty) {
      await _notifications.doc(notification.id).set(
        {
          'type': 'friend_request',
          'actionStatus': 'accepted',
          'read': true,
          'isRead': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (kDebugMode) {
        print('Notification updated to accepted');
      }
    }
  }

  Future<void> declineFriendRequest(ActivityNotification notification) async {
    final declined =
        await _friendService.declineFriendRequest(notification.senderId);
    if (!declined) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final pendingFriendNotifications = await _firestore
        .collection('notifications')
        .where('type', isEqualTo: 'friend_request')
        .where('senderId', isEqualTo: notification.senderId)
        .where('userId', isEqualTo: currentUser.uid)
        .where('actionStatus', isEqualTo: 'pending')
        .get();

    for (final doc in pendingFriendNotifications.docs) {
      await doc.reference.update({
        'actionStatus': 'declined',
        'read': true,
        'isRead': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('Notification updated to declined');
      }
    }

    if (pendingFriendNotifications.docs.isEmpty &&
        notification.id.trim().isNotEmpty) {
      await _notifications.doc(notification.id).set(
        {
          'type': 'friend_request',
          'actionStatus': 'declined',
          'read': true,
          'isRead': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (kDebugMode) {
        print('Notification updated to declined');
      }
    }
  }

  // Event logic
  Future<bool> acceptEventRequest(ActivityNotification notification) async {
    if (notification.eventId == null) return false;
    final user = _auth.currentUser;
    if (user == null) return false;
    final requesterUid = notification.senderId.trim();
    if (requesterUid.isEmpty) return false;

    debugPrint('FLOW STEP: acceptEventRequest start notificationId=${notification.id} eventId=${notification.eventId} requester=$requesterUid host=${user.uid}');

    late final String chatId;
    try {
      debugPrint('FLOW STEP: calling approveJoinRequest eventId=${notification.eventId} requester=$requesterUid');
      chatId = await _eventService.approveJoinRequest(
        eventId: notification.eventId!,
        requesterUserId: requesterUid,
      );
      debugPrint('WRITE SUCCESS: approveJoinRequest transaction completed chatId=$chatId');
    } on StateError catch (e, stack) {
      debugPrint('WRITE FAILED: approveJoinRequest error=$e');
      debugPrintStack(stackTrace: stack);
      final msg = e.message.toLowerCase();
      // Event-ended and event-full are user-visible conditions — rethrow so
      // the UI can surface a specific message and trigger cleanup.
      if (msg.contains('already ended') ||
          msg.contains('no longer active') ||
          msg.contains('is full')) {
        // Best-effort: mark the specific pending request as rejected so the
        // requester's pending state clears even before the host's next session
        // triggers the bulk cleanup in _markCompletedIfExpired.
        unawaited(_cleanupExpiredEventRequest(
          eventId: notification.eventId!,
          requesterUid: requesterUid,
        ));
        rethrow;
      }
      return false;
    } catch (e, stack) {
      debugPrint('WRITE FAILED: approveJoinRequest error=$e');
      debugPrintStack(stackTrace: stack);
      return false;
    }

    debugPrint('QUERY START: users/${user.uid} (host profile for notification)');
    final hostProfile = await _userService.getUser(user.uid);
    final hostDisplayName =
        (hostProfile?['name'] ?? hostProfile?['username'] ?? 'Host')
            .toString()
            .trim();
    debugPrint('QUERY SUCCESS: hostDisplayName=$hostDisplayName');

    debugPrint('QUERY START: events/${notification.eventId} (banner + title for notification)');
    final eventDoc =
        await _firestore.collection('events').doc(notification.eventId).get();
    final eventData = eventDoc.data() ?? const <String, dynamic>{};
    final eventTitle = (eventData['title'] ?? 'this event').toString();
    final eventBannerUrl =
        (eventData['bannerUrl'] ?? eventData['bannerImagePath'] ?? '')
            .toString();
    debugPrint('QUERY SUCCESS: eventTitle=$eventTitle bannerUrl=${eventBannerUrl.isNotEmpty}');

    // Only write fields in the notification update allowlist:
    // ['read', 'isRead', 'actionStatus', 'type', 'updatedAt']
    // senderId / senderName / message / title are NOT updatable per rules.
    if (!notification.id.startsWith('event_request_')) {
      debugPrint('WRITE START: notifications/${notification.id} markAccepted (host notification)');
      try {
        await _notifications.doc(notification.id).set(
          {
            'type': NotificationType.eventAccept,
            'actionStatus': 'accepted',
            'read': true,
            'isRead': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        debugPrint('WRITE SUCCESS: notifications/${notification.id} marked accepted');
      } catch (e, stack) {
        debugPrint('WRITE FAILED: notifications/${notification.id} status update (non-fatal) error=$e');
        debugPrintStack(stackTrace: stack);
      }
    }

    debugPrint('FLOW STEP: sending event_accept notification to requester=$requesterUid');
    try {
      final dedupeKey =
          'event_accept:${notification.eventId}:$requesterUid:${user.uid}';
      debugPrint('WRITE START: notifications event_accept receiver=$requesterUid dedupeKey=$dedupeKey');
      await createNotification(
        receiverId: requesterUid,
        type: NotificationType.eventAccept,
        message: 'accepted your request to join $eventTitle',
        title: '$hostDisplayName accepted your request to join $eventTitle',
        eventId: notification.eventId,
        eventBannerUrl: eventBannerUrl,
        chatId: chatId,
        dedupeKey: dedupeKey,
      );
      debugPrint('WRITE SUCCESS: event_accept notification delivered to receiver=$requesterUid');
    } catch (e, stack) {
      debugPrint('WRITE FAILED: event_accept notification delivery error=$e');
      debugPrintStack(stackTrace: stack);
    }

    // Notify the requester's friends who are already in the event — FOMO trigger.
    // Fire-and-forget: never blocks the accept flow, never fails it.
    unawaited(sendFriendJoinedEventNotifications(
      joinerId: requesterUid,
      eventId: notification.eventId!,
      chatId: chatId,
    ));

    debugPrint('FLOW STEP: acceptEventRequest complete — participant added, chat updated, notification sent');
    return true;
  }

  Future<void> declineEventRequest(ActivityNotification notification) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final eventId = notification.eventId?.trim() ?? '';
    if (eventId.isEmpty) return;
    final requesterUid = notification.senderId.trim();
    if (requesterUid.isEmpty) return;

    // Step 1 — try to reject the pending join request.
    //
    // Possible throws from rejectJoinRequest:
    //  • 'No pending join request found.' — request already cancelled/rejected/
    //    accepted (double-tap, auto-cleanup, requester self-cancelled). Stale —
    //    we still want to mark the host notification as actioned so it clears.
    //  • 'Event not found' — event doc was hard-deleted (should not happen with
    //    soft-delete, but treat as stale for the same reason).
    //  • 'Only host can reject join requests.' / 'Authenticated host is required.'
    //    — real auth failures. Rethrow so the UI can show an error.
    var requestWasActuallyRejected = false;
    try {
      await _eventService.rejectJoinRequest(
        eventId: eventId,
        requesterUserId: requesterUid,
      );
      requestWasActuallyRejected = true;
    } on StateError catch (e) {
      final msg = e.message.toLowerCase();
      final isStale = msg.contains('no pending') ||
          msg.contains('not found') ||
          msg.contains('event not found');
      if (!isStale) rethrow; // authorization or unexpected error — let UI handle
      debugPrint(
          'declineEventRequest: request already non-pending ($msg) — marking host notification and skipping requester notification');
    }

    // Step 2 — always mark the host's own notification as read and actioned.
    // Regardless of whether the request was still pending, the host tapped
    // "Decline" and the card should leave their feed.
    if (!notification.id.startsWith('event_request_')) {
      try {
        await _notifications.doc(notification.id).update({
          'type': NotificationType.eventReject,
          'actionStatus': 'declined',
          'read': true,
          'isRead': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint(
            'declineEventRequest: host notification ${notification.id} marked declined');
      } catch (e, stack) {
        debugPrint(
            'declineEventRequest: host notification update failed (non-fatal): $e');
        debugPrintStack(stackTrace: stack);
      }
    }

    // Step 3 — notify the requester only when the request was genuinely
    // pending when we processed it.
    //
    // If the request was already cancelled (event ended, requester self-
    // cancelled, auto-cleanup) or already rejected (double-tap), sending
    // a fresh "your request was declined" notification is confusing — the
    // requester already knows or already got the right message.
    if (!requestWasActuallyRejected) return;

    String eventTitle = 'the event';
    String hostDisplayName = 'The host';
    try {
      final eventDoc =
          await _firestore.collection('events').doc(eventId).get();
      eventTitle =
          (eventDoc.data()?['title'] ?? 'the event').toString().trim();
      if (eventTitle.isEmpty) eventTitle = 'the event';
      final hostProfile = await _userService.getUser(user.uid);
      hostDisplayName =
          (hostProfile?['name'] ?? hostProfile?['username'] ?? 'The host')
              .toString()
              .trim();
      if (hostDisplayName.isEmpty) hostDisplayName = 'The host';
    } catch (_) {}

    try {
      await createNotification(
        receiverId: requesterUid,
        type: NotificationType.eventReject,
        message: 'declined your request to join $eventTitle',
        title: '$hostDisplayName declined your request to join $eventTitle',
        eventId: notification.eventId,
        dedupeKey: 'event_rejected:${notification.eventId}:$requesterUid',
      );
      debugPrint(
          'declineEventRequest: rejection notification sent to requester=$requesterUid');
    } catch (e, stack) {
      debugPrint(
          'declineEventRequest: rejection notification to requester failed (non-fatal): $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// Best-effort cleanup for a single expired join request.
  /// Called when the host tries to approve after the event has ended so the
  /// requester's pending state clears immediately without waiting for the host's
  /// next session to trigger the bulk _cancelAllPendingRequests sweep.
  Future<void> _cleanupExpiredEventRequest({
    required String eventId,
    required String requesterUid,
  }) async {
    try {
      final batch = _firestore.batch();
      batch.update(
        _firestore
            .collection('event_requests')
            .doc('${eventId}_$requesterUid'),
        {
          'status': 'rejected',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.set(
        _firestore
            .collection('event_participants')
            .doc(eventId)
            .collection('users')
            .doc(requesterUid),
        {
          'status': 'removed',
          'removedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      debugPrint(
          'CLEANUP: cleared pending request for expired event=$eventId requester=$requesterUid');
    } catch (e) {
      debugPrint(
          'CLEANUP: failed to clear expired request event=$eventId requester=$requesterUid: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

extension FriendJoinedEventNotification on ActivityNotificationService {
  static const int _maxRecipients = 20;

  /// Notifies friends of [joinerId] who are already active participants of
  /// [eventId] that the joiner has joined. Fire-and-forget — never throws.
  ///
  /// Edge cases handled:
  ///  • Skips the joiner themselves.
  ///  • Skips the event host (they receive join-approval flow separately).
  ///  • Skips if either party has a block relationship.
  ///  • Skips if the event is deleted or no longer active.
  ///  • Caps at [_maxRecipients] to prevent burst spam.
  ///  • 1-hour dedup per (eventId, joinerId, recipientId) triple.
  Future<void> sendFriendJoinedEventNotifications({
    required String joinerId,
    required String eventId,
    String chatId = '',
  }) async {
    if (joinerId.trim().isEmpty || eventId.trim().isEmpty) return;

    try {
      // ── 1. Validate event ──────────────────────────────────────────────────
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      if (!eventDoc.exists) return;
      final eventData = eventDoc.data()!;
      if ((eventData['status'] ?? '') != 'active') return;
      if (eventData['isDeleted'] == true) return;
      final hostId = (eventData['hostId'] ?? '').toString().trim();
      final eventTitle = (eventData['title'] ?? 'an event').toString().trim();
      final eventBanner = ((eventData['bannerUrl'] ??
              eventData['bannerImagePath'] ??
              '') as String)
          .trim();

      // ── 2. Fetch joiner's friend IDs ───────────────────────────────────────
      final friendsSnap = await _firestore
          .collection('friends')
          .doc(joinerId)
          .collection('list')
          .get();
      if (friendsSnap.docs.isEmpty) return;
      final friendIds = friendsSnap.docs.map((d) => d.id).toSet();

      // ── 3. Fetch active event participants ─────────────────────────────────
      final participantsSnap = await _firestore
          .collection('event_participants')
          .doc(eventId)
          .collection('users')
          .where('status', whereIn: ['active', 'joined'])
          .get();
      final participantIds = participantsSnap.docs
          .map((d) => (d.data()['userId'] ?? d.id).toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      // ── 4. Intersect + filter ──────────────────────────────────────────────
      final candidates = friendIds
          .intersection(participantIds)
          .where((id) => id != joinerId && id != hostId)
          .take(_maxRecipients)
          .toList();
      if (candidates.isEmpty) return;

      // ── 5. Joiner display name ─────────────────────────────────────────────
      final joinerDoc = await _userService.getUser(joinerId);
      final joinerName =
          ((joinerDoc?['name'] ?? joinerDoc?['username'] ?? 'Someone')
                  as String)
              .trim();

      // ── 6. Send — skip on block ────────────────────────────────────────────
      for (final recipientId in candidates) {
        try {
          final blocked = await _isBlockedEitherWay(joinerId, recipientId);
          if (blocked) continue;

          await _notificationService.sendWithRetry(
            () => _notificationService.sendNotification(
              userId: recipientId,
              type: NotificationType.friendJoinedEvent,
              senderId: joinerId,
              senderName: joinerName,
              eventId: eventId,
              message: 'joined $eventTitle',
              title: '$joinerName joined $eventTitle',
              body: '$joinerName joined $eventTitle',
              chatId: chatId.isNotEmpty ? chatId : null,
              eventBannerUrl: eventBanner,
              dedupeKey: 'friend_joined:$eventId:$joinerId:$recipientId',
              dedupeWindow: const Duration(hours: 1),
            ),
            userId: recipientId,
            type: NotificationType.friendJoinedEvent,
            senderId: joinerId,
          );
        } catch (e) {
          debugPrint('[FriendJoin] notification to $recipientId skipped: $e');
        }
      }
    } catch (e, stack) {
      debugPrint('[FriendJoin] sendFriendJoinedEventNotifications failed: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// Returns true if either user has blocked the other.
  Future<bool> _isBlockedEitherWay(String userA, String userB) async {
    try {
      final results = await Future.wait([
        _firestore
            .collection('blocked_users')
            .doc(userA)
            .collection('list')
            .doc(userB)
            .get(),
        _firestore
            .collection('blocked_users')
            .doc(userB)
            .collection('list')
            .doc(userA)
            .get(),
      ]);
      return results.any((doc) => doc.exists);
    } catch (_) {
      return false; // default to unblocked on error
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class NotificationPage {
  final List<ActivityNotification> items;
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastVisible;
  final bool hasMore;

  const NotificationPage({
    required this.items,
    required this.lastVisible,
    required this.hasMore,
  });
}
