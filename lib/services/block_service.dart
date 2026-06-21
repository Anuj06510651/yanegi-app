import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class BlockRelationship {
  final bool blockedByMe;
  final bool blockedByThem;

  const BlockRelationship({
    required this.blockedByMe,
    required this.blockedByThem,
  });

  bool get isBlockedEitherWay => blockedByMe || blockedByThem;
}

class BlockService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _blockedUsers =>
      _firestore.collection('blocked_users');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _friendRequests =>
      _firestore.collection('friend_requests');
  CollectionReference<Map<String, dynamic>> get _friends =>
      _firestore.collection('friends');

  String? get _currentUid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _blockEdgeRef(
    String blockerUid,
    String blockedUid,
  ) {
    return _blockedUsers.doc(blockerUid).collection('list').doc(blockedUid);
  }

  DocumentReference<Map<String, dynamic>> _friendEdgeRef(
    String userId,
    String friendId,
  ) {
    return _friends.doc(userId).collection('list').doc(friendId);
  }

  Future<bool> hasBlocked(String blockerUid, String blockedUid) async {
    if (blockerUid.trim().isEmpty || blockedUid.trim().isEmpty) return false;
    final doc = await _blockEdgeRef(blockerUid, blockedUid).get();
    return doc.exists;
  }

  Future<bool> isBlockedEitherWay(String userA, String userB) async {
    if (userA.trim().isEmpty || userB.trim().isEmpty) return false;
    if (userA == userB) return false;

    final currentUid = _currentUid;
    if (currentUid == null) return false;

    final other = (currentUid == userA) ? userB : userA;
    final blockedByMe = await hasBlocked(currentUid, other);
    if (blockedByMe) return true;
    return hasBlocked(other, currentUid);
  }

  Future<BlockRelationship> getRelationship(String userA, String userB) async {
    if (userA.trim().isEmpty || userB.trim().isEmpty || userA == userB) {
      return const BlockRelationship(blockedByMe: false, blockedByThem: false);
    }

    final currentUid = _currentUid;
    if (currentUid == null) {
      return const BlockRelationship(blockedByMe: false, blockedByThem: false);
    }

    final other = (currentUid == userA) ? userB : userA;
    final blockedByMe = await hasBlocked(currentUid, other);
    final blockedByThem = await hasBlocked(other, currentUid);
    return BlockRelationship(blockedByMe: blockedByMe, blockedByThem: blockedByThem);
  }

  Stream<BlockRelationship> relationshipStream(String userA, String userB) {
    if (userA.trim().isEmpty || userB.trim().isEmpty || userA == userB) {
      return Stream.value(
        const BlockRelationship(blockedByMe: false, blockedByThem: false),
      );
    }

    final byMeStream = _blockEdgeRef(userA, userB).snapshots();
    final byThemStream = _blockEdgeRef(userB, userA).snapshots();

    return Stream.multi((controller) {
      var blockedByMe = false;
      var blockedByThem = false;

      void emit() {
        controller.add(
          BlockRelationship(
            blockedByMe: blockedByMe,
            blockedByThem: blockedByThem,
          ),
        );
      }

      final subA = byMeStream.listen((doc) {
        blockedByMe = doc.exists;
        emit();
      }, onError: (_, __) {
        blockedByMe = false;
        emit();
      });

      final subB = byThemStream.listen((doc) {
        blockedByThem = doc.exists;
        emit();
      }, onError: (_, __) {
        blockedByThem = false;
        emit();
      });

      controller.onCancel = () async {
        await subA.cancel();
        await subB.cancel();
      };
    });
  }

  Future<void> blockUser({required String targetUid}) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty || targetUid.trim().isEmpty) return;
    if (uid == targetUid) return;

    // Phase 1 — canonical block edge (MUST succeed; standalone write so no
    // unrelated failure can prevent the block from being recorded).
    await _blockEdgeRef(uid, targetUid).set(
      {
        'blockerUid': uid,
        'blockedUid': targetUid,
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // Phase 2 — delete friend subcollection edges (either party may delete).
    // Deleting a non-existent doc in a batch is a no-op, so this is safe even
    // when removeFriend() already ran beforehand.
    try {
      final edgeBatch = _firestore.batch();
      edgeBatch.delete(_friendEdgeRef(uid, targetUid));
      edgeBatch.delete(_friendEdgeRef(targetUid, uid));
      await edgeBatch.commit();
    } catch (e) {
      debugPrint('blockUser: friend edge cleanup non-fatal: $e');
    }

    // Phase 3 — remove target from own friends array (own-update, always allowed).
    try {
      await _users.doc(uid).update({
        'friends': FieldValue.arrayRemove([targetUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('blockUser: own friends array cleanup non-fatal: $e');
    }

    // Phase 4 — remove self from target's friends array (cross-user write).
    // This succeeds only when the blocker is still in the target's friends array.
    // If removeFriend() already ran this fails silently — that is expected.
    try {
      await _users.doc(targetUid).update({
        'friends': FieldValue.arrayRemove([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('blockUser: cross-user friends array cleanup non-fatal: $e');
    }

    // Phase 5 — delete any friend_requests between the two users.
    // The block edge written in Phase 1 satisfies the Firestore delete rule,
    // so any status (pending, accepted, blocked, etc.) can be cleaned up.
    try {
      final results = await Future.wait([
        _friendRequests.doc('${uid}_$targetUid').get(),
        _friendRequests.doc('${targetUid}_$uid').get(),
      ]);
      final cleanupBatch = _firestore.batch();
      var hasWork = false;
      for (final doc in results) {
        if (doc.exists) {
          cleanupBatch.delete(doc.reference);
          hasWork = true;
        }
      }
      if (hasWork) await cleanupBatch.commit();
    } catch (e) {
      debugPrint('blockUser: friend_request cleanup non-fatal: $e');
    }
  }

  Future<void> unblockUser({required String targetUid}) async {
    final uid = _currentUid;
    if (uid == null || uid.trim().isEmpty || targetUid.trim().isEmpty) return;
    if (uid == targetUid) return;

    // Step 1: Remove the block edge.
    await _blockEdgeRef(uid, targetUid).delete();

    // Step 2: Clean up any stale friend_request docs so createFriendRequest()
    // can write a fresh 'pending' doc after unblock without hitting stale state.
    try {
      final results = await Future.wait([
        _friendRequests.doc('${uid}_$targetUid').get(),
        _friendRequests.doc('${targetUid}_$uid').get(),
      ]);
      final cleanupBatch = _firestore.batch();
      var hasWork = false;
      for (final doc in results) {
        if (doc.exists) {
          final status = (doc.data()?['status'] ?? '').toString();
          // Only delete docs with statuses that would block a new friend request.
          // Firestore delete rule allows 'blocked' and 'accepted'-with-no-edges.
          if (status == 'blocked' || status == 'accepted') {
            cleanupBatch.delete(doc.reference);
            hasWork = true;
          }
        }
      }
      if (hasWork) await cleanupBatch.commit();
    } catch (e) {
      debugPrint('unblockUser: friend_request cleanup failed (non-fatal): $e');
    }
  }

  Future<List<String>> getBlockedUserIds(String uid) async {
    if (uid.trim().isEmpty) return const <String>[];
    final snapshot = await _blockedUsers.doc(uid).collection('list').get();
    return snapshot.docs.map((d) => d.id).toList();
  }
}
