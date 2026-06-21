part of '../../services/event_service.dart';

extension EventParticipationApi on EventService {
  Future<String> addUserToEventAndChat({
    required String eventId,
    required String userId,
    bool bypassApprovalCheck = false,
  }) async {
    final authUid = (_auth.currentUser?.uid ?? '').trim();
    final effectiveUserId = userId.trim();
    if (effectiveUserId.isEmpty) {
      throw ArgumentError('userId is required');
    }
    if (authUid.isEmpty) {
      throw StateError('Authenticated user is required.');
    }
    if (!bypassApprovalCheck && authUid != effectiveUserId) {
      throw StateError('Authenticated user mismatch.');
    }
    final eventRef = _events.doc(eventId);

    final eventDoc = await eventRef.get();
    if (!eventDoc.exists) {
      throw StateError('Event not found');
    }
    final eventData = eventDoc.data() ?? {};
    await _assertEventJoinable(eventId: eventId, eventData: eventData);
    final hostId =
        (eventData['hostId'] ?? eventData['host_id'] ?? '').toString();
    if (hostId.isNotEmpty) {
      await _assertUsersNotBlocked(effectiveUserId, hostId);
    }
    final isVisibleInEvents =
        await _showProfileInEventsEnabled(effectiveUserId);

    return _firestore.runTransaction((txn) async {
      final eventSnap = await txn.get(eventRef);
      if (!eventSnap.exists) {
        throw StateError('Event not found');
      }

      final eventData = eventSnap.data() ?? {};
      final refreshedEndAt = _toDateTime(eventData['endAt']);
      final now = _nowUtc();
      if (refreshedEndAt != null && !refreshedEndAt.toUtc().isAfter(now)) {
        throw StateError('Event has already ended.');
      }
      if (!_isEventActive(eventData)) {
        throw StateError('Event is no longer active');
      }

      final requiresApproval = eventData['isApprovalRequired'] == true;
      if (requiresApproval && !bypassApprovalCheck) {
        throw StateError('This event requires host approval to join.');
      }

      final maxCapacity = int.tryParse('${eventData['maxCapacity'] ?? 0}') ?? 0;
      final participantsCount =
          int.tryParse('${eventData['participantsCount'] ?? 0}') ?? 0;
      if (maxCapacity > 0 && participantsCount >= maxCapacity) {
        throw StateError('Event is full.');
      }

      final participants =
          List<String>.from(eventData['participants'] ?? const <String>[]);
      final hostId =
          (eventData['hostId'] ?? eventData['host_id'] ?? '').toString();
      if (hostId.isEmpty) {
        throw StateError('Event host missing');
      }

      if (bypassApprovalCheck && authUid != hostId) {
        throw StateError('Only host can bypass approval checks.');
      }

      var chatId = (eventData['chatId'] ?? '').toString();
      if (chatId.isEmpty) {
        chatId = 'grp_$eventId';
        final chatRef = _chats.doc(chatId);
        txn.set(
          chatRef,
          {
            'chatId': chatId,
            'type': 'group',
            'eventId': eventId,
            'participantIds': [hostId],
            'createdBy': hostId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'isActive': true,
            'lastMessage': '',
            'lastMessageAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      if (!participants.contains(effectiveUserId)) {
        final nextCount = participantsCount + 1;
        txn.update(eventRef, {
          'participants': FieldValue.arrayUnion([effectiveUserId]),
          'participantsCount': nextCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      txn.update(_chats.doc(chatId), {
        'participantIds': FieldValue.arrayUnion([effectiveUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      txn.set(
          _participantRef(eventId: eventId, userId: effectiveUserId),
          {
            'userId': effectiveUserId,
            'eventId': eventId,
            'status': EventService._legacyParticipantStatusActive,
            'isVisible': isVisibleInEvents,
            'joinedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'removedAt': FieldValue.delete(),
            'leftAt': FieldValue.delete(),
          },
          SetOptions(merge: true));

      return chatId;
    });
  }

  Future<void> removeUserFromEventAndChat({
    required String eventId,
    required String userId,
  }) async {
    final effectiveUserId = _resolveAuthenticatedUid(fallbackUid: userId);
    final eventRef = _events.doc(eventId);

    await _firestore.runTransaction((txn) async {
      final eventSnap = await txn.get(eventRef);
      if (!eventSnap.exists) {
        throw StateError('Event not found');
      }

      final eventData = eventSnap.data() ?? {};
      final participants =
          List<String>.from(eventData['participants'] ?? const <String>[]);
      final eventHostId =
          (eventData['hostId'] ?? eventData['host_id'] ?? '').toString();
      final chatId = (eventData['chatId'] ?? '').toString();

      if (eventHostId == effectiveUserId) {
        throw StateError('Host cannot leave their own event');
      }

      txn.update(eventRef, {
        'participants': FieldValue.arrayRemove([effectiveUserId]),
        'participantsCount': participants.contains(effectiveUserId)
            ? participants.length - 1
            : participants.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      txn.set(
          _participantRef(eventId: eventId, userId: effectiveUserId),
          {
            'userId': effectiveUserId,
            'eventId': eventId,
            'status': EventService.participantStatusLeft,
            'leftAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      if (chatId.isNotEmpty) {
        txn.update(_chats.doc(chatId), {
          'participantIds': FieldValue.arrayRemove([effectiveUserId]),
          'deletedFor': FieldValue.arrayUnion([effectiveUserId]),
          'unreadCount.$effectiveUserId': 0,
          'typing.$effectiveUserId': {
            'isTyping': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });

        txn.set(
          _chatMemberRef(chatId: chatId, userId: effectiveUserId),
          {
            'chatId': chatId,
            'userId': effectiveUserId,
            'isDeleted': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    // A spot just opened — notify the first waitlisted user (fire-and-forget).
    unawaited(_notifyFirstWaitlistedUser(
      eventId: eventId,
      senderId: effectiveUserId,
      eventTitle: '', // resolved internally from Firestore
    ));
  }

  Future<void> removeParticipantAsHost({
    required String eventId,
    required String hostId,
    required String userId,
  }) async {
    if (eventId.trim().isEmpty ||
        hostId.trim().isEmpty ||
        userId.trim().isEmpty) {
      throw ArgumentError('eventId, hostId, and userId must be non-empty');
    }

    final effectiveHostId = _resolveAuthenticatedUid(fallbackUid: hostId);
    if (effectiveHostId == userId) {
      throw StateError('Host cannot remove self');
    }

    final eventRef = _events.doc(eventId);

    final participantDoc =
        await _participantRef(eventId: eventId, userId: userId).get();
    final participantData = participantDoc.data() ?? const <String, dynamic>{};
    final participantStatus =
        (participantData['status'] ?? '').toString().toLowerCase();
    if (participantStatus == EventService.participantStatusRemoved) {
      throw StateError('User is already removed from this event');
    }

    await _firestore.runTransaction((txn) async {
      final eventSnap = await txn.get(eventRef);
      if (!eventSnap.exists) {
        throw StateError('Event not found');
      }

      final eventData = eventSnap.data() ?? {};
      final participants =
          List<String>.from(eventData['participants'] ?? const <String>[]);
      final eventHostId =
          (eventData['hostId'] ?? eventData['host_id'] ?? '').toString();
      final chatId = (eventData['chatId'] ?? '').toString();
      if (eventHostId != effectiveHostId) {
        throw StateError('Only host can remove participant');
      }

      if (effectiveHostId == userId) {
        throw StateError('Host cannot remove self');
      }

      txn.update(eventRef, {
        'participants': FieldValue.arrayRemove([userId]),
        'participantsCount': participants.contains(userId)
            ? participants.length - 1
            : participants.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      txn.set(
          _participantRef(eventId: eventId, userId: userId),
          {
            'userId': userId,
            'eventId': eventId,
            'status': EventService.participantStatusRemoved,
            'removedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));

      if (chatId.isNotEmpty) {
        txn.update(_chats.doc(chatId), {
          'participantIds': FieldValue.arrayRemove([userId]),
          'deletedFor': FieldValue.arrayUnion([userId]),
          'unreadCount.$userId': 0,
          'typing.$userId': {
            'isTyping': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });

        txn.set(
          _chatMemberRef(chatId: chatId, userId: userId),
          {
            'chatId': chatId,
            'userId': userId,
            'isDeleted': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    debugPrint('User removed');

    // A spot just opened — notify the first waitlisted user (fire-and-forget).
    unawaited(_notifyFirstWaitlistedUser(
      eventId: eventId,
      senderId: effectiveHostId,
      eventTitle: '', // resolved internally from Firestore
    ));
  }

  Future<String> joinEventDirect({
    required String eventId,
    required String userId,
  }) async {
    final quotaCheck =
        await _rateLimiter.check(RateLimiterService.eventJoinPerHour);
    if (!quotaCheck.allowed) {
      throw StateError(
        'You’re joining events too quickly. Please wait and try again.',
      );
    }
    final chatId =
        await addUserToEventAndChat(eventId: eventId, userId: userId);
    unawaited(_rateLimiter.record(RateLimiterService.eventJoinPerHour));
    return chatId;
  }
}
