part of '../../services/event_service.dart';

extension EventLifecycleApi on EventService {
  /// Notifies all of the host's friends that a new event was created.
  ///
  /// Reads friends from the `friends/{hostId}/list` subcollection — the source
  /// of truth for friendship. The `event_created` notification CREATE rule also
  /// requires a friendship edge to exist, so reading from edges (not the legacy
  /// `users.friends` array) guarantees every send is rule-valid.
  ///
  /// Duplicate suppression is handled by the deterministic `dedupeKey`
  /// (`event_created_by_friend:{host}:{friend}:{eventId}`) inside
  /// `NotificationService.sendNotification`. Push fan-out is server-side via the
  /// `onNotificationCreate` Cloud Function. Call unawaited — never block createEvent.
  Future<void> notifyFriendsAboutNewEvent({
    required String eventId,
    required String hostId,
    required String title,
    required String chatId,
  }) async {
    try {
      // Fetch friends list, sender profile, and event banner in parallel.
      // Previously _createNotification re-read the sender profile + event banner
      // on every call — for N friends that was 2N redundant reads of the same docs.
      final friendsSnapFuture =
          _firestore.collection('friends').doc(hostId).collection('list').get();
      final senderDocFuture = _firestore.collection('users').doc(hostId).get();
      final eventDocFuture = _firestore.collection('events').doc(eventId).get();

      // Start all three fetches concurrently, then await each.
      final friendsSnap = await friendsSnapFuture;
      final senderDoc = await senderDocFuture;
      final eventDoc = await eventDocFuture;

      final friendIds = friendsSnap.docs
          .map((d) => d.id)
          .where((id) => id != hostId)
          .toList();

      if (friendIds.isEmpty) return;
      debugPrint(
          'EVENT_NOTIFICATION: event=$eventId notifying ${friendIds.length} friend(s)');

      final senderData = senderDoc.data() ?? const <String, dynamic>{};
      final senderName =
          (senderData['name'] ?? senderData['username'] ?? 'Someone')
              .toString();
      final senderAvatar = (senderData['avatarUrl'] ??
              senderData['avatar_url'] ??
              senderData['photoUrl'] ??
              senderData['avatarEmoji'] ??
              '')
          .toString();
      final eventData = eventDoc.data() ?? const <String, dynamic>{};
      final eventBannerUrl =
          (eventData['bannerUrl'] ?? eventData['bannerImagePath'] ?? '')
              .toString();

      final message = 'created a new event "$title".';

      // Send all friend notifications in parallel. Each uses a deterministic
      // dedupeKey so concurrent or duplicate calls for the same event+friend
      // pair are idempotent.
      var sent = 0;
      await Future.wait(friendIds.map((friendId) async {
        final dedupeKey = 'event_created_by_friend:$hostId:$friendId:$eventId';
        try {
          final ok = await _notificationService.sendWithRetry(
            () => _notificationService.sendNotification(
              userId: friendId,
              type: NotificationType.eventCreated,
              senderId: hostId,
              senderName: senderName,
              senderAvatar: senderAvatar,
              eventId: eventId,
              message: message,
              title: message,
              body: message,
              chatId: chatId,
              dedupeKey: dedupeKey,
              dedupeWindow: const Duration(minutes: 3),
              eventBannerUrl: eventBannerUrl,
            ),
            userId: friendId,
            type: NotificationType.eventCreated,
            senderId: hostId,
            metadata: <String, dynamic>{
              'eventId': eventId,
              'chatId': chatId,
              'dedupeKey': dedupeKey,
            },
          );
          if (ok) sent++;
        } catch (e) {
          debugPrint(
              'EVENT_NOTIFICATION: send failed for friend=$friendId: $e');
        }
      }));

      debugPrint(
          'EVENT_NOTIFICATION_SENT: event=$eventId sent=$sent/${friendIds.length}');
    } catch (e, stack) {
      debugPrint('notifyFriendsAboutNewEvent failed: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getEvents({
    int limit = 30,
  }) {
    final cached = _eventsStreamByLimit[limit];
    if (cached != null) return cached;

    // Use StreamController.broadcast() instead of asBroadcastStream() so the
    // cache entry is automatically removed when the last listener cancels.
    // asBroadcastStream() cancels the underlying Firestore subscription on last
    // cancel but keeps a dead stream in the cache — the next caller gets a
    // stream that never emits. The controller approach removes the cache entry
    // in onCancel, so the next call creates a fresh live stream.
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    StreamController<QuerySnapshot<Map<String, dynamic>>>? controller;

    controller =
        StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(
      onListen: () {
        sub = _events
            .where('visibility', isEqualTo: 'public')
            .where('status', isEqualTo: EventService.statusActive)
            .limit(limit)
            .snapshots()
            .listen(
              (snap) => controller?.add(snap),
              onError: (Object e, StackTrace st) => controller?.addError(e, st),
            );
      },
      onCancel: () {
        sub?.cancel();
        sub = null;
        _eventsStreamByLimit.remove(limit);
      },
    );

    _eventsStreamByLimit[limit] = controller.stream;
    return controller.stream;
  }

  /// Clears all stream caches. Call this on sign-out so a subsequent sign-in
  /// (possibly as a different user) does not receive stale data. Active
  /// streams remain live until their own last listener cancels — calling this
  /// only prevents new callers from receiving the old streams.
  void clearCaches() {
    _eventsStreamByLimit.clear();
    _membershipStreamCache.clear();
    debugPrint('EventService: stream caches cleared');
  }

  Future<void> softDeleteEvent({
    required String eventId,
    required String hostId,
  }) async {
    final effectiveHostId = _resolveAuthenticatedUid(fallbackUid: hostId);
    final eventRef = _events.doc(eventId);
    final eventDoc = await eventRef.get();
    if (!eventDoc.exists) {
      throw StateError('Event not found');
    }

    final eventData = eventDoc.data() ?? {};
    final eventHostId =
        (eventData['hostId'] ?? eventData['host_id'] ?? '').toString();
    if (eventHostId != effectiveHostId) {
      throw StateError('Only host can delete this event');
    }

    final chatId = (eventData['chatId'] ?? '').toString();

    final batch = _firestore.batch();
    batch.update(eventRef, {
      'status': 'deleted',
      'isActive': false,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': effectiveHostId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (chatId.isNotEmpty) {
      batch.update(_chats.doc(chatId), {
        'isActive': false,
        'closedReason': 'event_deleted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    debugPrint(
        'softDeleteEvent: event+chat marked deleted eventId=$eventId chatId=$chatId');

    // Fetch participants and pending requests in parallel — after batch 1 commits
    // so any join that raced with the deletion and succeeded before the event was
    // marked inactive is included in the result sets.
    //
    // Only query PENDING requests: the event_requests update rule requires
    // resource.data.status == 'pending' for the host update branch. Querying
    // accepted/rejected requests and trying to update them to 'cancelled' would
    // yield PERMISSION_DENIED and abort the entire cleanup. The status filter
    // fixes that pre-existing rule-violation bug.
    debugPrint(
        'softDeleteEvent: fetching participants + pending requests eventId=$eventId');
    final fetchResults = await Future.wait([
      _firestore
          .collection('event_participants')
          .doc(eventId)
          .collection('users')
          .get(),
      _eventRequests
          .where('eventId', isEqualTo: eventId)
          .where('hostId', isEqualTo: effectiveHostId)
          .where('status', isEqualTo: EventService.participantStatusPending)
          .get(),
    ]);
    final participantDocs = fetchResults[0].docs;
    final requestDocs = fetchResults[1].docs;
    debugPrint(
        'softDeleteEvent: participants=${participantDocs.length} pendingRequests=${requestDocs.length}');

    // Run participant and request batches concurrently — they touch different
    // collections and have no ordering dependency.
    await Future.wait([
      _updateInBatches(
        participantDocs,
        {
          'status': EventService.participantStatusRemoved,
          'removedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
      _updateInBatches(
        requestDocs,
        {
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      ),
    ]);

    debugPrint(
        'softDeleteEvent: complete eventId=$eventId participants=${participantDocs.length} requests=${requestDocs.length}');
    if (chatId.isNotEmpty) {
      debugPrint('softDeleteEvent: chat frozen chatId=$chatId');
    }
  }

  Future<void> refreshEventLifecycle({required String eventId}) async {
    final eventData = await _loadEventOrThrow(eventId);
    await _markCompletedIfExpired(eventId: eventId, eventData: eventData);
  }

  Future<void> syncEventLifecycle(String eventId) {
    return refreshEventLifecycle(eventId: eventId);
  }
}
