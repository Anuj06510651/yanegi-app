part of '../../services/event_service.dart';

extension EventCreationApi on EventService {
  Future<String> createEvent({
    required String title,
    required GeoPoint location,
    required String hostId,
    required String eventAvatar,
    required DateTime startAt,
    DateTime? endAt,
    String description = '',
    int maxCapacity = 10,
    String visibility = 'public',
    bool isApprovalRequired = true,
    String? bannerImagePath,
    String? timeLabel,
    List<String> tags = const [],
    String locationName = '',
    bool hideExactLocationUntilApproved = false,
    GeoPoint? approximateLocation,
    int ageRangeMin = 18,
    int ageRangeMax = 30,
    String meetingPoint = '',
  }) async {
    if (maxCapacity < 2) {
      throw Exception('Invalid capacity');
    }

    final effectiveHostId = _resolveAuthenticatedUid(fallbackUid: hostId);
    if (effectiveHostId.isEmpty || effectiveHostId == 'unknown_user') {
      throw ArgumentError('Authenticated host user is required');
    }

    final normalizedStartAt = startAt.toUtc();
    final normalizedEndAt = _resolveEventEndAt(
      startAt: normalizedStartAt,
      endAt: endAt,
    );
    _validateCreateEventPayload(
      title: title,
      location: location,
      startAt: normalizedStartAt,
      endAt: normalizedEndAt,
      maxCapacity: maxCapacity,
    );

    if (ageRangeMin < 13 || ageRangeMax < ageRangeMin || ageRangeMax > 120) {
      throw StateError('Invalid age range.');
    }

    final normalizedTitle = title.trim();
    final normalizedDescription = description.trim();
    final normalizedLocationName = locationName.trim();
    final normalizedTags =
        tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();
    final activityType =
        normalizedTags.isNotEmpty ? normalizedTags.first : 'general';

    // Rate limiting disabled for dev/testing.
    // await _enforceEventCreateCooldown(effectiveHostId);
    // final quotaCheck =
    //     await _rateLimiter.check(RateLimiterService.eventCreatePerDay);
    // if (!quotaCheck.allowed) {
    //   throw StateError(
    //     'You can only create a few events per day. Please wait and try again.',
    //   );
    // }

    final docRef = _events.doc();
    final chatId = 'grp_${docRef.id}';
    final chatRef = _chats.doc(chatId);
    String? resolvedBannerUrl = bannerImagePath;

    if (bannerImagePath != null &&
        bannerImagePath.trim().isNotEmpty &&
        !bannerImagePath.startsWith('http') &&
        File(bannerImagePath).existsSync()) {
      resolvedBannerUrl = await _mediaStorageService.uploadEventImage(
        eventId: docRef.id,
        localFilePath: bannerImagePath,
      );
    }

    final normalizedVisibility = visibility == 'private' ? 'private' : 'public';
    final createdAt = FieldValue.serverTimestamp();

    final eventPayload = {
      'eventId': docRef.id,
      'hostId': effectiveHostId,
      'title': normalizedTitle,
      'description': normalizedDescription,
      'activityType': activityType,
      'location': normalizedLocationName,
      'lat': location.latitude,
      'lng': location.longitude,
      'locationGeoPoint': location,
      'approximateLocation': {
        'lat': (approximateLocation ?? location).latitude,
        'lng': (approximateLocation ?? location).longitude,
      },
      'startAt': Timestamp.fromDate(normalizedStartAt),
      'endAt': Timestamp.fromDate(normalizedEndAt),
      'timezone': 'UTC',
      'ageRange': {
        'min': ageRangeMin,
        'max': ageRangeMax,
      },
      'ageRangeLabel': 'Age: $ageRangeMin–$ageRangeMax',
      'hideExactLocationUntilApproved': hideExactLocationUntilApproved,
      'locationName': normalizedLocationName,
      'participants': [effectiveHostId],
      'participantsCount': 1,
      'maxCapacity': maxCapacity,
      'visibility': normalizedVisibility,
      'isApprovalRequired': isApprovalRequired,
      'eventAvatar': eventAvatar,
      'emoji': eventAvatar,
      'bannerImagePath': resolvedBannerUrl,
      'bannerUrl': resolvedBannerUrl,
      'time': timeLabel,
      'tags': normalizedTags,
      'chatId': chatId,
      'status': EventService.statusActive,
      'isActive': true,
      'isDeleted': false,
      'createdAt': createdAt,
      'updatedAt': createdAt,
      if (meetingPoint.trim().isNotEmpty) 'meetingPoint': meetingPoint.trim(),
    };

    debugPrint(
        'FLOW STEP: createEvent transaction start eventId=${docRef.id} host=$effectiveHostId chatId=$chatId');
    await _firestore.runTransaction((txn) async {
      final hostRef = _userRef(effectiveHostId);
      debugPrint('QUERY START: users/$effectiveHostId (cooldown check)');
      final hostSnapshot = await txn.get(hostRef);
      debugPrint(
          'QUERY SUCCESS: users/$effectiveHostId exists=${hostSnapshot.exists}');
      if (hostSnapshot.exists) {
        _assertEventCreateCooldownFromUserData(
          hostSnapshot.data() ?? const <String, dynamic>{},
        );
      }

      debugPrint('WRITE START: events/${docRef.id}');
      txn.set(docRef, eventPayload);
      debugPrint('WRITE START: chats/$chatId');
      txn.set(
        chatRef,
        {
          'chatId': chatId,
          'type': 'group',
          'eventId': docRef.id,
          'participantIds': [effectiveHostId],
          'createdBy': effectiveHostId,
          'createdAt': createdAt,
          'updatedAt': createdAt,
          'isActive': true,
          'lastMessage': '',
          'lastMessageAt': createdAt,
        },
        SetOptions(merge: true),
      );
      debugPrint('WRITE START: users/$effectiveHostId lastEventCreatedAt');
      txn.set(
        hostRef,
        {
          'lastEventCreatedAt': createdAt,
          'updatedAt': createdAt,
        },
        SetOptions(merge: true),
      );
      debugPrint(
          'WRITE START: event_participants/${docRef.id}/users/$effectiveHostId (host, status=active)');
      txn.set(
        _participantRef(eventId: docRef.id, userId: effectiveHostId),
        {
          'userId': effectiveHostId,
          'eventId': docRef.id,
          'status': EventService._legacyParticipantStatusActive,
          'isVisible': true,
          'joinedAt': createdAt,
          'updatedAt': createdAt,
        },
        SetOptions(merge: true),
      );
      debugPrint(
          'FLOW STEP: createEvent transaction writes queued — committing');
    });
    debugPrint(
        'WRITE SUCCESS: createEvent transaction committed eventId=${docRef.id} chatId=$chatId');

    unawaited(_rateLimiter.record(RateLimiterService.eventCreatePerDay));

    // Fire-and-forget so notification fan-out never blocks createEvent's return.
    unawaited(notifyFriendsAboutNewEvent(
      eventId: docRef.id,
      hostId: effectiveHostId,
      title: normalizedTitle,
      chatId: chatId,
    ));

    unawaited(_notifyNearbyUsers(
      eventId: docRef.id,
      hostId: effectiveHostId,
      title: normalizedTitle,
      eventLocation: location,
      chatId: chatId,
    ));

    return docRef.id;
  }

  Future<String> ensureGroupChatForEvent({required String eventId}) async {
    final eventRef = _events.doc(eventId);
    final eventDoc = await eventRef.get();

    if (!eventDoc.exists) {
      throw StateError('Event not found');
    }

    final eventData = eventDoc.data() ?? {};
    final existingChatId = (eventData['chatId'] ?? '').toString();
    if (existingChatId.isNotEmpty) return existingChatId;

    final hostId =
        (eventData['hostId'] ?? eventData['host_id'] ?? '').toString();
    if (hostId.isEmpty) {
      throw StateError('Event host missing');
    }

    final query = await _chats
        .where('type', isEqualTo: 'group')
        .where('eventId', isEqualTo: eventId)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final chatId = query.docs.first.id;
      await eventRef.update({'chatId': chatId});
      return chatId;
    }

    final chatRef = _chats.doc('grp_$eventId');
    final chatId = chatRef.id;

    final batch = _firestore.batch();
    batch.set(
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
    batch.update(eventRef, {'chatId': chatId});
    await batch.commit();

    return chatId;
  }
}
