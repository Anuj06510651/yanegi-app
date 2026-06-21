part of '../../services/event_service.dart';

extension EventJoinApprovalApi on EventService {
  Future<void> requestToJoinEvent({
    required String eventId,
    required String userId,
  }) async {
    debugPrint('JOIN REQUEST START');
    final effectiveUserId = _resolveAuthenticatedUid(fallbackUid: userId);
    if (eventId.trim().isEmpty || effectiveUserId.trim().isEmpty) {
      throw ArgumentError('eventId and userId must be non-empty');
    }

    final quotaCheck =
        await _rateLimiter.check(RateLimiterService.eventJoinPerHour);
    if (!quotaCheck.allowed) {
      throw StateError(
        'You’re sending join requests too quickly. Please wait and try again.',
      );
    }

    final eventRef = _events.doc(eventId);
    final preflightEventDoc = await eventRef.get();
    if (!preflightEventDoc.exists) {
      throw StateError('Event not found');
    }
    final preflightEventData =
        preflightEventDoc.data() ?? const <String, dynamic>{};
    final preflightHostId =
        (preflightEventData['hostId'] ?? preflightEventData['host_id'] ?? '')
            .toString()
            .trim();
    if (preflightHostId.isEmpty) {
      throw StateError('Event host missing');
    }
    await _assertUsersNotBlocked(effectiveUserId, preflightHostId);

    final reqRef = _eventRequests.doc('${eventId}_$effectiveUserId');
    final participantRef =
        _participantRef(eventId: eventId, userId: effectiveUserId);
    late final String hostId;

    // Read user's visibility preference before the transaction.
    // The requester CAN read their own settings (users/{uid}/settings/main is owner-only).
    // approveJoinRequest reads isVisible from the participant doc, so it must be set here.
    final isVisibleInEvents =
        await _showProfileInEventsEnabled(effectiveUserId);
    debugPrint(
        'FLOW STEP: requestToJoinEvent preflight isVisible=$isVisibleInEvents user=$effectiveUserId');

    try {
      debugPrint(
          'FLOW STEP: requestToJoinEvent transaction start eventId=$eventId user=$effectiveUserId host=$preflightHostId');
      await _firestore.runTransaction((txn) async {
        debugPrint('QUERY START: events/$eventId (inside txn)');
        final eventSnap = await txn.get(eventRef);
        debugPrint('QUERY SUCCESS: events/$eventId exists=${eventSnap.exists}');
        if (!eventSnap.exists) {
          throw StateError('Event not found');
        }

        final eventData = eventSnap.data() ?? {};
        final refreshedEndAt = _toDateTime(eventData['endAt']);
        if (refreshedEndAt != null &&
            !refreshedEndAt.toUtc().isAfter(_nowUtc())) {
          throw StateError('Event has already ended.');
        }
        if (!_isEventActive(eventData)) {
          throw StateError('Event is no longer active');
        }

        hostId = (eventData['hostId'] ?? eventData['host_id'] ?? '')
            .toString()
            .trim();
        if (hostId.isEmpty) {
          throw StateError('Event host missing');
        }
        if (hostId != preflightHostId) {
          throw StateError('Event host changed. Please try again.');
        }
        if (hostId == effectiveUserId) {
          throw StateError('Host is already part of this event.');
        }

        final maxCapacity =
            int.tryParse('${eventData['maxCapacity'] ?? 0}') ?? 0;
        final participantsCount =
            int.tryParse('${eventData['participantsCount'] ?? 0}') ?? 0;
        if (maxCapacity > 0 && participantsCount >= maxCapacity) {
          throw StateError('Event is full.');
        }
        if (eventData['isApprovalRequired'] != true) {
          throw StateError('This event allows direct join.');
        }

        debugPrint(
            'QUERY START: event_participants/$eventId/users/$effectiveUserId');
        final participantDoc = await txn.get(participantRef);
        debugPrint(
            'QUERY SUCCESS: participant exists=${participantDoc.exists} status=${participantDoc.data()?['status']}');
        final participantData =
            participantDoc.data() ?? const <String, dynamic>{};
        final participantStatus =
            (participantData['status'] ?? '').toString().toLowerCase();
        if (_isJoinedParticipantStatus(participantStatus)) {
          throw StateError('You are already a participant in this event');
        }
        if (_isPendingParticipantStatus(participantStatus)) {
          throw StateError('Join request already pending.');
        }

        debugPrint('QUERY START: event_requests/${eventId}_$effectiveUserId');
        final requestDoc = await txn.get(reqRef);
        debugPrint(
            'QUERY SUCCESS: event_request exists=${requestDoc.exists} status=${requestDoc.data()?['status']}');
        final existingReqData = requestDoc.data() ?? const <String, dynamic>{};
        final existingStatus =
            (existingReqData['status'] ?? '').toString().toLowerCase();
        if (existingStatus == 'pending') {
          throw StateError('Join request already pending.');
        }

        debugPrint('TXN WRITING PARTICIPANT');
        debugPrint(
            'WRITE START: event_participants/$eventId/users/$effectiveUserId status=pending isVisible=$isVisibleInEvents');
        txn.set(
          participantRef,
          {
            'userId': effectiveUserId,
            'eventId': eventId,
            'status': EventService.participantStatusPending,
            'isVisible': isVisibleInEvents,
            'updatedAt': FieldValue.serverTimestamp(),
            'joinedAt': FieldValue.delete(),
            'leftAt': FieldValue.delete(),
            'removedAt': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );

        debugPrint(
            'WRITE START: event_requests/${eventId}_$effectiveUserId status=pending isRerequest=${requestDoc.exists}');
        txn.set(
          reqRef,
          {
            'eventId': eventId,
            'senderId': effectiveUserId,
            'hostId': hostId,
            'userId': effectiveUserId,
            'status': EventService.participantStatusPending,
            'createdAt': requestDoc.exists
                ? existingReqData['createdAt']
                : FieldValue.serverTimestamp(),
            // 'timestamp' intentionally omitted: the event_requests update rule
            // only permits ['status', 'updatedAt'] in affectedKeys, so writing
            // 'timestamp' on a re-request causes an immediate permission-denied.
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        debugPrint(
            'FLOW STEP: requestToJoinEvent transaction writes queued — committing');
      });
    } catch (e, st) {
      debugPrint('WRITE FAILED: requestToJoinEvent transaction error=$e');
      debugPrint('$st');
      rethrow;
    }
    debugPrint(
        'WRITE SUCCESS: requestToJoinEvent transaction committed eventId=$eventId user=$effectiveUserId host=$hostId');

    unawaited(_rateLimiter.record(RateLimiterService.eventJoinPerHour));

    debugPrint('JOIN REQUEST TXN COMPLETE');

    debugPrint(
        'Request created: eventId=$eventId userId=$effectiveUserId hostId=$hostId');

    debugPrint('JOIN REQUEST CREATING NOTIFICATION');
    try {
      debugPrint('Creating notification for host: $hostId');
      final eventTitle =
          (preflightEventData['title'] ?? '').toString().trim();
      final requestMessage = eventTitle.isNotEmpty
          ? 'wants to join: "$eventTitle"'
          : 'wants to join your event';
      await _createNotification(
        senderId: effectiveUserId,
        receiverId: hostId,
        type: NotificationType.eventRequest,
        message: requestMessage,
        eventId: eventId,
        dedupeKey: 'event_request:$eventId:$effectiveUserId:$hostId',
      );
      debugPrint('Notification created');
      debugPrint(
          'Event request notification created: eventId=$eventId userId=$effectiveUserId hostId=$hostId');
      debugPrint('JOIN REQUEST SUCCESS');
    } catch (e, stack) {
      // Keep request flow successful even if host notification write is blocked.
      debugPrint('Event request notification creation failed: $e');
      debugPrint('Event request notification create failed: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  // ── Waitlist ──────────────────────────────────────────────────────────────────

  /// Adds the current user to the waitlist for a full event.
  ///
  /// Throws [StateError] if:
  ///  • User is not authenticated
  ///  • Event does not exist or is not active
  ///  • Event is NOT full (they should join directly)
  ///  • User is blocked by/from the host
  Future<void> joinWaitlist({required String eventId}) async {
    final uid = _resolveAuthenticatedUid(fallbackUid: '');
    if (uid.isEmpty) throw StateError('User not authenticated');
    if (eventId.trim().isEmpty) throw ArgumentError('eventId required');

    final eventData = await _loadEventOrThrow(eventId);
    final status = (eventData['status'] ?? '').toString().toLowerCase();
    if (status != EventService.statusActive)
      throw StateError('Event is not active');
    if (eventData['isDeleted'] == true) throw StateError('Event not found');

    final maxCap = int.tryParse('${eventData['maxCapacity'] ?? 0}') ?? 0;
    final pCount = int.tryParse('${eventData['participantsCount'] ?? 0}') ?? 0;
    if (maxCap > 0 && pCount < maxCap) {
      throw StateError('Event has available spots — join directly.');
    }

    final hostId = (eventData['hostId'] ?? '').toString().trim();
    await _assertUsersNotBlocked(uid, hostId);

    await _participantRef(eventId: eventId, userId: uid).set(
      {
        'userId': uid,
        'eventId': eventId,
        'status': EventService.participantStatusWaitlisted,
        'waitlistedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'removedAt': FieldValue.delete(),
        'leftAt': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }

  /// Removes the current user from the waitlist.
  Future<void> leaveWaitlist({required String eventId}) async {
    final uid = _resolveAuthenticatedUid(fallbackUid: '');
    if (uid.isEmpty) throw StateError('User not authenticated');
    if (eventId.trim().isEmpty) throw ArgumentError('eventId required');

    await _participantRef(eventId: eventId, userId: uid).update({
      'status': EventService.participantStatusLeft,
      'leftAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> approveJoinRequest({
    required String eventId,
    required String requesterUserId,
  }) async {
    final hostUid = _resolveAuthenticatedUid(fallbackUid: '');
    if (hostUid.isEmpty) {
      throw StateError('Authenticated host is required.');
    }

    debugPrint(
        'APPROVE FLOW START: eventId=$eventId requester=$requesterUserId host=$hostUid');
    await _assertUsersNotBlocked(hostUid, requesterUserId);
    final eventRef = _events.doc(eventId);
    final requestRef = _eventRequests.doc('${eventId}_$requesterUserId');
    final participantRef =
        _participantRef(eventId: eventId, userId: requesterUserId);

    debugPrint(
        'FLOW STEP: approveJoinRequest transaction start eventId=$eventId requester=$requesterUserId host=$hostUid');
    try {
      return await _firestore.runTransaction<String>((txn) async {
        debugPrint('QUERY START: events/$eventId (approveJoinRequest txn)');
        final eventSnap = await txn.get(eventRef);
        debugPrint('QUERY SUCCESS: events/$eventId exists=${eventSnap.exists}');
        if (!eventSnap.exists) {
          throw StateError('Event not found');
        }

        final eventData = eventSnap.data() ?? {};
        final hostId = (eventData['hostId'] ?? '').toString();
        if (hostId != hostUid) {
          throw StateError('Only host can approve join requests.');
        }

        // Atomically re-verify that neither party has blocked the other.
        // The pre-transaction _assertUsersNotBlocked call provides an early
        // fast-fail but is non-atomic — a block applied in the window between
        // that call and this point would otherwise slip through undetected.
        // Both reads are permitted by the blocked_users rule:
        //   blocked_users/{hostUid}/list/{...}  → auth.uid == userId ✓
        //   blocked_users/{requesterUid}/list/{hostUid} → auth.uid == blockedUid ✓
        final blockByHostSnap = await txn.get(
          _firestore
              .collection('blocked_users')
              .doc(hostUid)
              .collection('list')
              .doc(requesterUserId),
        );
        final blockByRequesterSnap = await txn.get(
          _firestore
              .collection('blocked_users')
              .doc(requesterUserId)
              .collection('list')
              .doc(hostUid),
        );
        if (blockByHostSnap.exists || blockByRequesterSnap.exists) {
          throw StateError('Action unavailable due to block settings');
        }
        debugPrint(
            'QUERY SUCCESS: block check clear host=$hostUid requester=$requesterUserId');

        debugPrint('QUERY START: event_requests/${eventId}_$requesterUserId');
        final requestDoc = await txn.get(requestRef);
        debugPrint(
            'QUERY SUCCESS: event_request exists=${requestDoc.exists} status=${requestDoc.data()?['status']}');
        if (!requestDoc.exists) {
          throw StateError('No pending join request found.');
        }
        final requestData = requestDoc.data() ?? const <String, dynamic>{};
        final requestStatus =
            (requestData['status'] ?? '').toString().toLowerCase();
        if (requestStatus != 'pending') {
          throw StateError('No pending join request found.');
        }
        if ((requestData['userId'] ?? requestData['senderId'] ?? '')
                .toString() !=
            requesterUserId) {
          throw StateError('Join request user mismatch.');
        }

        final refreshedEndAt = _toDateTime(eventData['endAt']);
        if (refreshedEndAt != null &&
            !refreshedEndAt.toUtc().isAfter(_nowUtc())) {
          throw StateError('Event has already ended.');
        }
        if (!_isEventActive(eventData)) {
          throw StateError('Event is no longer active');
        }

        final maxCapacity =
            int.tryParse('${eventData['maxCapacity'] ?? 0}') ?? 0;
        final participants =
            List<String>.from(eventData['participants'] ?? const <String>[]);
        final participantsCount =
            int.tryParse('${eventData['participantsCount'] ?? 0}') ??
                participants.length;
        if (!participants.contains(requesterUserId) &&
            maxCapacity > 0 &&
            participantsCount >= maxCapacity) {
          throw StateError('Event is full.');
        }

        // Read isVisible from the participant doc set by requester during requestToJoinEvent.
        // We cannot cross-read users/{requesterUserId}/settings/main (owner-only rule),
        // so the requester's own setting is used here as stored at join-request time.
        debugPrint(
            'QUERY START: event_participants/$eventId/users/$requesterUserId (isVisible)');
        final participantSnap = await txn.get(participantRef);
        final isVisibleInEvents =
            participantSnap.data()?['isVisible'] as bool? ?? true;
        debugPrint(
            'QUERY SUCCESS: participant isVisible=$isVisibleInEvents exists=${participantSnap.exists}');

        var chatId = (eventData['chatId'] ?? '').toString();
        final chatWasMissing = chatId.isEmpty;

        if (chatWasMissing) {
          chatId = 'grp_$eventId';
          debugPrint(
              'FLOW STEP: approveJoinRequest — chat missing, creating fallback chatId=$chatId');
          debugPrint('WRITE START: chats/$chatId (fallback create)');
          txn.set(
            _chats.doc(chatId),
            {
              'chatId': chatId,
              'type': 'group',
              'eventId': eventId,
              'participantIds': [hostId, requesterUserId],
              'createdBy': hostId,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'isActive': true,
              'lastMessage': '',
              'lastMessageAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          debugPrint('WRITE SUCCESS: chats/$chatId (fallback create)');
        } else {
          // Chat already exists — add requester to participantIds.
          debugPrint(
              'FLOW STEP: approveJoinRequest — existing chat, adding requester to participantIds');
          debugPrint(
              'WRITE START: chats/$chatId arrayUnion participantIds requester=$requesterUserId');
          txn.set(
            _chats.doc(chatId),
            {
              'participantIds': FieldValue.arrayUnion([requesterUserId]),
              'updatedAt': FieldValue.serverTimestamp(),
              'isActive': true,
            },
            SetOptions(merge: true),
          );
          debugPrint('WRITE SUCCESS: chats/$chatId participantIds updated');
        }

        // Single consolidated event update — avoids the double-update clobber bug where
        // a second txn.update on the same doc replaces the first in the SDK write buffer,
        // losing the chatId field written by the first update.
        final eventUpdate = <String, dynamic>{
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (chatWasMissing) {
          eventUpdate['chatId'] = chatId;
        }
        if (!participants.contains(requesterUserId)) {
          eventUpdate['participants'] =
              FieldValue.arrayUnion([requesterUserId]);
          eventUpdate['participantsCount'] = participantsCount + 1;
        }
        debugPrint(
            'WRITE START: events/$eventId update participants+count+chatId payload=${eventUpdate.keys.toList()}');
        txn.update(eventRef, eventUpdate);
        debugPrint('WRITE SUCCESS: events/$eventId updated');

        debugPrint(
            'WRITE START: event_participants/$eventId/users/$requesterUserId status=active isVisible=$isVisibleInEvents');
        txn.set(
          participantRef,
          {
            'userId': requesterUserId,
            'eventId': eventId,
            'status': EventService._legacyParticipantStatusActive,
            'isVisible': isVisibleInEvents,
            'joinedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'removedAt': FieldValue.delete(),
            'leftAt': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
        debugPrint(
            'WRITE SUCCESS: event_participants/$eventId/users/$requesterUserId');

        debugPrint(
            'WRITE START: event_requests/${eventId}_$requesterUserId status=accepted');
        txn.update(requestRef, {
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('WRITE SUCCESS: event_requests/${eventId}_$requesterUserId');

        debugPrint(
            'FLOW STEP: approveJoinRequest transaction writes queued — committing chatId=$chatId');
        return chatId;
      });
    } catch (e, st) {
      debugPrint('WRITE FAILED: approveJoinRequest transaction error=$e');
      debugPrint('$st');
      rethrow;
    }
  }

  Future<void> rejectJoinRequest({
    required String eventId,
    required String requesterUserId,
  }) async {
    final hostUid = _resolveAuthenticatedUid(fallbackUid: '');
    if (hostUid.isEmpty) {
      throw StateError('Authenticated host is required.');
    }

    final eventRef = _events.doc(eventId);
    final requestRef = _eventRequests.doc('${eventId}_$requesterUserId');
    final participantRef =
        _participantRef(eventId: eventId, userId: requesterUserId);

    await _firestore.runTransaction((txn) async {
      final eventSnap = await txn.get(eventRef);
      if (!eventSnap.exists) {
        throw StateError('Event not found');
      }
      final eventData = eventSnap.data() ?? {};
      final hostId = (eventData['hostId'] ?? '').toString();
      if (hostId != hostUid) {
        throw StateError('Only host can reject join requests.');
      }

      final requestDoc = await txn.get(requestRef);
      if (!requestDoc.exists) {
        throw StateError('No pending join request found.');
      }
      final requestData = requestDoc.data() ?? const <String, dynamic>{};
      final requestStatus =
          (requestData['status'] ?? '').toString().toLowerCase();
      if (requestStatus != 'pending') {
        throw StateError('No pending join request found.');
      }

      txn.update(requestRef, {
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      txn.set(
          participantRef,
          {
            'userId': requesterUserId,
            'eventId': eventId,
            'status': EventService.participantStatusRemoved,
            'removedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }
}
