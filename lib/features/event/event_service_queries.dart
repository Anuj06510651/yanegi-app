part of '../../services/event_service.dart';

extension EventQueriesApi on EventService {
  Future<UserEventState> getUserEventState({
    required String userId,
    required String eventId,
  }) async {
    final uid = userId.trim();
    final eid = eventId.trim();
    if (uid.isEmpty || eid.isEmpty) return UserEventState.notJoined;

    await refreshEventLifecycle(eventId: eid);

    final eventDoc = await _events.doc(eid).get();
    final eventData = eventDoc.data() ?? const <String, dynamic>{};
    final hostId =
        (eventData['hostId'] ?? eventData['host_id'] ?? '').toString().trim();
    if (hostId.isNotEmpty && hostId == uid) {
      return UserEventState.joined;
    }

    final participantDoc =
        await _participantRef(eventId: eid, userId: uid).get();
    final participantData = participantDoc.data() ?? const <String, dynamic>{};
    final participantStatus =
        (participantData['status'] ?? '').toString().toLowerCase();
    if (_isJoinedParticipantStatus(participantStatus)) {
      return UserEventState.joined;
    }

    if (_isPendingParticipantStatus(participantStatus)) {
      return UserEventState.pending;
    }

    return UserEventState.notJoined;
  }

  Future<Map<String, UserEventState>> getUserEventStatesForEvents({
    required String userId,
    required Iterable<String> eventIds,
  }) async {
    final uid = userId.trim();
    final ids = eventIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final states = <String, UserEventState>{
      for (final id in ids) id: UserEventState.notJoined,
    };

    if (uid.isEmpty || ids.isEmpty) {
      return states;
    }

    final membership = await _loadUserMembership(userId: uid);

    for (final id in ids) {
      if (membership.joinedEventIds.contains(id)) {
        states[id] = UserEventState.joined;
      } else if (membership.pendingEventIds.contains(id)) {
        states[id] = UserEventState.pending;
      }
    }

    return states;
  }

  Stream<UserEventMembershipSnapshot> watchUserEventMembership({
    required String userId,
  }) {
    final uid = userId.trim();

    if (uid.isEmpty) {
      return Stream.value(UserEventMembershipSnapshot.empty);
    }

    final cached = _membershipStreamCache[uid];
    if (cached != null) return cached;

    // Same StreamController.broadcast() pattern as getEvents(): the cache
    // entry is removed in onCancel so the next caller always gets a live
    // stream. asBroadcastStream() would leave a dead entry after the last
    // listener cancels — subsequent StreamBuilders would subscribe but never
    // receive events.
    StreamSubscription<UserEventMembershipSnapshot>? sub;
    StreamController<UserEventMembershipSnapshot>? controller;

    controller = StreamController<UserEventMembershipSnapshot>.broadcast(
      onListen: () {
        sub = _buildMembershipQuery(uid).listen(
          (snap) => controller?.add(snap),
          onError: (Object e, StackTrace st) => controller?.addError(e, st),
        );
      },
      onCancel: () {
        sub?.cancel();
        sub = null;
        _membershipStreamCache.remove(uid);
      },
    );

    _membershipStreamCache[uid] = controller.stream;
    return controller.stream;
  }

  Stream<Map<String, UserEventState>> watchUserEventStates(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) {
      return Stream.value(const <String, UserEventState>{});
    }

    return watchUserEventMembership(userId: uid).map((membership) {
      final stateByEventId = <String, UserEventState>{};

      for (final eventId in membership.joinedEventIds) {
        final id = eventId.trim();
        if (id.isNotEmpty) {
          stateByEventId[id] = UserEventState.joined;
        }
      }

      for (final eventId in membership.pendingEventIds) {
        final id = eventId.trim();
        if (id.isNotEmpty && !stateByEventId.containsKey(id)) {
          stateByEventId[id] = UserEventState.pending;
        }
      }

      return Map<String, UserEventState>.unmodifiable(stateByEventId);
    });
  }

  Stream<UserEventState> watchUserEventState({
    required String userId,
    required String eventId,
    String? hostId,
  }) {
    final uid = userId.trim();
    final eid = eventId.trim();
    final normalizedHostId = (hostId ?? '').trim();
    if (uid.isEmpty || eid.isEmpty) {
      return Stream.value(UserEventState.notJoined);
    }

    if (normalizedHostId.isNotEmpty && normalizedHostId == uid) {
      return Stream.value(UserEventState.joined);
    }

    return watchUserEventStates(uid).map(
      (stateByEventId) => stateByEventId[eid] ?? UserEventState.notJoined,
    );
  }

  Future<Map<String, UserEventState>> fetchAllUserEventStates(
      String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return const <String, UserEventState>{};

    final membership = await _loadUserMembership(userId: uid);
    final stateByEventId = <String, UserEventState>{
      for (final eventId in membership.pendingEventIds)
        eventId: UserEventState.pending,
    };

    for (final eventId in membership.joinedEventIds) {
      stateByEventId[eventId] = UserEventState.joined;
    }

    return Map<String, UserEventState>.unmodifiable(stateByEventId);
  }
}
