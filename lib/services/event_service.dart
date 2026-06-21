import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'block_service.dart';
import 'media_storage_service.dart';
import 'notification_service.dart';
import 'notification_types.dart';
import 'rate_limiter_service.dart';

part '../features/event/event_service_creation.dart';
part '../features/event/event_service_participation.dart';
part '../features/event/event_service_join_approval.dart';
part '../features/event/event_service_lifecycle.dart';
part '../features/event/event_service_queries.dart';

enum UserEventState {
  notJoined,
  pending,
  waitlisted,
  joined,
}

class UserEventMembershipSnapshot {
  const UserEventMembershipSnapshot({
    required this.joinedEventIds,
    required this.pendingEventIds,
    this.waitlistedEventIds = const <String>{},
  });

  final Set<String> joinedEventIds;
  final Set<String> pendingEventIds;
  final Set<String> waitlistedEventIds;

  bool isJoined(String eventId) => joinedEventIds.contains(eventId.trim());
  bool isPending(String eventId) => pendingEventIds.contains(eventId.trim());
  bool isWaitlisted(String eventId) =>
      waitlistedEventIds.contains(eventId.trim());

  UserEventState stateFor(String eventId) {
    final id = eventId.trim();
    if (id.isEmpty) return UserEventState.notJoined;
    if (joinedEventIds.contains(id)) return UserEventState.joined;
    if (pendingEventIds.contains(id)) return UserEventState.pending;
    if (waitlistedEventIds.contains(id)) return UserEventState.waitlisted;
    return UserEventState.notJoined;
  }

  static const empty = UserEventMembershipSnapshot(
    joinedEventIds: <String>{},
    pendingEventIds: <String>{},
    waitlistedEventIds: <String>{},
  );
}

class EventService {
  EventService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    BlockService? blockService,
    MediaStorageService? mediaStorageService,
    NotificationService? notificationService,
    RateLimiterService? rateLimiter,
    DateTime Function()? nowProvider,
    Future<bool> Function(String userA, String userB)? blockCheckOverride,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _blockService = blockService,
        _mediaStorageService = mediaStorageService ?? MediaStorageService(),
        _notificationService =
            notificationService ?? NotificationService(firestore: firestore),
        _rateLimiter =
            rateLimiter ?? RateLimiterService(firestore: firestore, auth: auth),
        _nowProvider = nowProvider ?? DateTime.now,
        _blockCheckOverride = blockCheckOverride;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final BlockService? _blockService;
  final MediaStorageService _mediaStorageService;
  final NotificationService _notificationService;
  final RateLimiterService _rateLimiter;
  final DateTime Function() _nowProvider;
  final Future<bool> Function(String userA, String userB)? _blockCheckOverride;
  // Keyed by limit so getEvents(30) and getEvents(100) produce independent
  // streams instead of both returning the first-requested limit.
  final Map<int, Stream<QuerySnapshot<Map<String, dynamic>>>>
      _eventsStreamByLimit = {};
  final Map<String, Stream<UserEventMembershipSnapshot>>
      _membershipStreamCache = {};
  static const double _nearbyRadiusKm = 10.0;
  static const Duration _eventCreateCooldown = Duration(minutes: 5);
  static const Duration _defaultEventDuration = Duration(hours: 2);
  static const int _maxAllowedCapacity = 500;

  static const String statusActive = 'active';
  static const String statusCompleted = 'completed';
  static const String statusDeleted = 'deleted';
  static const String participantStatusPending = 'pending';
  static const String participantStatusWaitlisted = 'waitlisted';
  static const String participantStatusJoined = 'joined';
  static const String _legacyParticipantStatusActive = 'active';
  static const String participantStatusLeft = 'left';
  static const String participantStatusRemoved = 'removed';

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('events');

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  CollectionReference<Map<String, dynamic>> get _eventRequests =>
      _firestore.collection('event_requests');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _participantRef({
    required String eventId,
    required String userId,
  }) {
    return _firestore
        .collection('event_participants')
        .doc(eventId)
        .collection('users')
        .doc(userId);
  }

  bool _isJoinedParticipantStatus(String status) {
    return status == participantStatusJoined ||
        status == _legacyParticipantStatusActive;
  }

  bool _isPendingParticipantStatus(String status) {
    return status == participantStatusPending;
  }

  bool _isWaitlistedParticipantStatus(String status) {
    return status == participantStatusWaitlisted;
  }

  DocumentReference<Map<String, dynamic>> _chatMemberRef({
    required String chatId,
    required String userId,
  }) {
    return _chats.doc(chatId).collection('chat_members').doc(userId);
  }

  DateTime _nowUtc() => _nowProvider().toUtc();

  String _resolveAuthenticatedUid({required String fallbackUid}) {
    final authUid = (_auth.currentUser?.uid ?? '').trim();
    if (authUid.isEmpty) return fallbackUid.trim();
    if (fallbackUid.trim().isNotEmpty && fallbackUid.trim() != authUid) {
      throw StateError('Authenticated user mismatch.');
    }
    return authUid;
  }

  DateTime? _toDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  DateTime _resolveEventEndAt({
    required DateTime startAt,
    required DateTime? endAt,
  }) {
    return (endAt ?? startAt.add(_defaultEventDuration)).toUtc();
  }

  void _validateCreateEventPayload({
    required String title,
    required GeoPoint location,
    required DateTime startAt,
    required DateTime endAt,
    required int maxCapacity,
  }) {
    if (title.trim().isEmpty) {
      throw StateError('Event title is required.');
    }
    if (location.latitude.isNaN || location.longitude.isNaN) {
      throw StateError('Valid event location is required.');
    }
    if (maxCapacity < 2 || maxCapacity > _maxAllowedCapacity) {
      throw StateError(
          'maxCapacity must be between 2 and $_maxAllowedCapacity.');
    }

    final now = _nowUtc();
    if (!startAt.toUtc().isAfter(now)) {
      throw StateError('Event start time must be in the future.');
    }
    if (!endAt.toUtc().isAfter(startAt.toUtc())) {
      throw StateError('Event end time must be after start time.');
    }
  }

  Future<Map<String, dynamic>> _loadEventOrThrow(String eventId) async {
    final eventDoc = await _events.doc(eventId).get();
    if (!eventDoc.exists) {
      throw StateError('Event not found');
    }
    final data = eventDoc.data() ?? const <String, dynamic>{};
    return <String, dynamic>{
      ...data,
      'eventId': eventDoc.id,
    };
  }

  Future<bool> _markCompletedIfExpired({
    required String eventId,
    required Map<String, dynamic> eventData,
  }) async {
    final status =
        (eventData['status'] ?? statusActive).toString().toLowerCase();
    if (status != statusActive || eventData['isActive'] == false) {
      return false;
    }

    final endAt = _toDateTime(eventData['endAt']);
    if (endAt == null || !endAt.toUtc().isBefore(_nowUtc())) {
      return false;
    }

    final chatId = (eventData['chatId'] ?? '').toString();
    final batch = _firestore.batch();
    batch.update(_events.doc(eventId), {
      'status': statusCompleted,
      'isActive': false,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (chatId.isNotEmpty) {
      batch.set(
        _chats.doc(chatId),
        {
          'isActive': false,
          'closedReason': 'event_completed',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    // Cancel all pending join requests now that the event is over.
    // Only the host can update event_requests (hostId rule), so we gate on
    // the current auth user being the host. If triggered by a requester
    // checking the event, the cleanup is skipped — it will run the next time
    // the host's session touches the event.
    final currentUid = (_auth.currentUser?.uid ?? '').trim();
    final storedHostId = (eventData['hostId'] ?? '').toString().trim();
    if (currentUid.isNotEmpty && currentUid == storedHostId) {
      unawaited(
          _cancelAllPendingRequests(eventId: eventId, hostId: currentUid));
    }

    return true;
  }

  /// Bulk-cancels every pending `event_requests` doc for [eventId] and marks
  /// the corresponding `event_participants` docs as removed. Called after an
  /// event is marked completed so pending requesters don't see a stale status.
  Future<void> _cancelAllPendingRequests({
    required String eventId,
    required String hostId,
  }) async {
    try {
      final snapshot = await _eventRequests
          .where('eventId', isEqualTo: eventId)
          .where('hostId', isEqualTo: hostId)
          .where('status', isEqualTo: participantStatusPending)
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final userId = (doc.data()['userId'] ?? doc.data()['senderId'] ?? '')
            .toString()
            .trim();
        if (userId.isNotEmpty) {
          batch.set(
            _participantRef(eventId: eventId, userId: userId),
            {
              'status': participantStatusRemoved,
              'removedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }
      await batch.commit();
      debugPrint(
          'EVENT CLEANUP: cancelled ${snapshot.docs.length} pending request(s) for completed event=$eventId');
    } catch (e) {
      debugPrint(
          'EVENT CLEANUP: failed to cancel pending requests for event=$eventId: $e');
    }
  }

  /// Writes [data] to every document in [docs] using consecutive [WriteBatch]es
  /// of at most 500 operations each (the Firestore SDK limit). Each batch is
  /// awaited before the next starts so a failure is isolated to a known chunk.
  ///
  /// Use [batch.update] semantics — callers must only pass docs that exist.
  Future<void> _updateInBatches(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, dynamic> data,
  ) async {
    if (docs.isEmpty) return;
    const int batchLimit = 500;
    for (var i = 0; i < docs.length; i += batchLimit) {
      final chunk = docs.sublist(i, min(i + batchLimit, docs.length));
      final batch = _firestore.batch();
      for (final doc in chunk) {
        batch.update(doc.reference, data);
      }
      await batch.commit();
      debugPrint(
          '_updateInBatches: committed ${chunk.length} write(s) (offset $i)');
    }
  }

  Future<void> _assertEventJoinable({
    required String eventId,
    required Map<String, dynamic> eventData,
  }) async {
    final movedToCompleted =
        await _markCompletedIfExpired(eventId: eventId, eventData: eventData);
    if (movedToCompleted) {
      throw StateError('Event has already ended.');
    }

    if (!_isEventActive(eventData)) {
      throw StateError('Event is no longer active');
    }
  }

  bool _isEventActive(Map<String, dynamic> data) {
    final status = (data['status'] ?? statusActive).toString().toLowerCase();
    if (status != statusActive) return false;
    if (data['isActive'] == false) return false;

    final endAt = _toDateTime(data['endAt']);
    if (endAt != null && endAt.toUtc().isBefore(_nowUtc())) {
      return false;
    }

    return true;
  }

  Future<void> _assertUsersNotBlocked(String userA, String userB) async {
    final isBlocked = _blockCheckOverride != null
        ? await _blockCheckOverride(userA, userB)
        : await (_blockService ?? BlockService()).isBlockedEitherWay(
            userA,
            userB,
          );
    if (isBlocked) {
      throw StateError('Action unavailable due to block settings');
    }
  }

  Future<void> _enforceEventCreateCooldown(String hostId) async {
    final userDoc = await _userRef(hostId).get();
    if (!userDoc.exists) return;

    _assertEventCreateCooldownFromUserData(
      userDoc.data() ?? const <String, dynamic>{},
    );
  }

  void _assertEventCreateCooldownFromUserData(Map<String, dynamic> data) {
    final rawLastCreatedAt =
        data['lastEventCreatedAt'] ?? data['last_event_created_at'];

    DateTime? lastCreatedAt;
    if (rawLastCreatedAt is Timestamp) {
      lastCreatedAt = rawLastCreatedAt.toDate();
    } else if (rawLastCreatedAt is DateTime) {
      lastCreatedAt = rawLastCreatedAt;
    } else if (rawLastCreatedAt is String) {
      lastCreatedAt = DateTime.tryParse(rawLastCreatedAt);
    }

    if (lastCreatedAt == null) return;

    final elapsed = _nowProvider().difference(lastCreatedAt);
    if (elapsed < _eventCreateCooldown) {
      final remaining = _eventCreateCooldown - elapsed;
      final minutes = remaining.inMinutes;
      final seconds = remaining.inSeconds % 60;
      throw Exception(
        'Please wait ${minutes}m ${seconds}s before creating another event.',
      );
    }
  }

  Future<void> _createNotification({
    required String senderId,
    required String receiverId,
    required String type,
    required String message,
    String? eventId,
    String? chatId,
    String? dedupeKey,
  }) async {
    if (senderId == receiverId) return;

    final dedupe = dedupeKey ??
        '$type:$senderId:$receiverId:${eventId ?? ''}:${chatId ?? ''}:$message';

    // NOTE: cross-user dedupe pre-check removed. Firestore rules only allow a
    // user to read their own notifications (userId == auth.uid), so querying
    // another user's notifications always returns permission-denied. Dedupe is
    // enforced instead by the deterministic document ID inside
    // NotificationService.sendNotification (the dedupe_<hash> write-or-skip
    // transaction), which uses admin-path writes that satisfy rules.

    final senderDoc = await _firestore.collection('users').doc(senderId).get();
    final senderData = senderDoc.data() ?? {};
    final senderName =
        (senderData['name'] ?? senderData['username'] ?? 'Someone').toString();
    final senderAvatar = (senderData['avatarUrl'] ??
            senderData['avatar_url'] ??
            senderData['photoUrl'] ??
            senderData['avatarEmoji'] ??
            '')
        .toString();
    String eventBannerUrl = '';
    if (eventId != null && eventId.trim().isNotEmpty) {
      try {
        final eventDoc =
            await _firestore.collection('events').doc(eventId).get();
        final eventData = eventDoc.data() ?? const <String, dynamic>{};
        eventBannerUrl =
            (eventData['bannerUrl'] ?? eventData['bannerImagePath'] ?? '')
                .toString();
      } catch (e, stack) {
        eventBannerUrl = '';
        debugPrint('Event banner lookup failed for notification: $e');
        debugPrintStack(stackTrace: stack);
      }
    }

    debugPrint(
        'NOTIFICATION CREATE START: type=$type receiver=$receiverId sender=$senderId');
    debugPrint(
        'NOTIFICATION PAYLOAD: {userId: $receiverId, type: $type, eventId: $eventId}');
    try {
      await _notificationService.sendWithRetry(
        () => _notificationService.sendNotification(
          userId: receiverId,
          type: type,
          senderId: senderId,
          senderName: senderName,
          senderAvatar: senderAvatar,
          eventId: eventId,
          message: message,
          title: message,
          body: message,
          chatId: chatId,
          dedupeKey: dedupe,
          dedupeWindow: const Duration(minutes: 3),
          eventBannerUrl: eventBannerUrl,
        ),
        userId: receiverId,
        type: type,
        senderId: senderId,
        metadata: <String, dynamic>{
          if (eventId != null) 'eventId': eventId,
          if (chatId != null) 'chatId': chatId,
          'dedupeKey': dedupe,
        },
      );
      debugPrint('NOTIFICATION WRITE SUCCESS: type=$type receiver=$receiverId');
    } catch (e, st) {
      debugPrint('NOTIFICATION WRITE FAILED: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  DocumentReference<Map<String, dynamic>> _mainSettingsRef(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('main');
  }

  Future<Map<String, dynamic>> _readMainSettings(String uid) async {
    final doc = await _mainSettingsRef(uid).get();
    return doc.data() ?? const <String, dynamic>{};
  }

  Future<bool> _showProfileInEventsEnabled(String userId,
      {bool defaultValue = true}) async {
    final settings = await _readMainSettings(userId);

    final raw = settings['showProfileInEvents'];

    return raw is bool ? raw : defaultValue;
  }

  bool _nearbyActivityEnabled(Map<String, dynamic> settings,
      {bool defaultValue = true}) {
    final raw = settings['nearbyActivity'];
    return raw is bool ? raw : defaultValue;
  }

  // Push-notification-enabled gating now lives server-side in the
  // onNotificationCreate Cloud Function. Clients do not enqueue push.

  GeoPoint? _parseUserGeo(Map<String, dynamic> userData) {
    final raw = userData['location'];
    if (raw is GeoPoint) return raw;
    if (raw is Map<String, dynamic>) {
      final lat = (raw['lat'] ?? raw['latitude']) as num?;
      final lng = (raw['lng'] ?? raw['longitude']) as num?;
      if (lat != null && lng != null) {
        return GeoPoint(lat.toDouble(), lng.toDouble());
      }
    }

    final lat = userData['latitude'] as num?;
    final lng = userData['longitude'] as num?;
    if (lat != null && lng != null) {
      return GeoPoint(lat.toDouble(), lng.toDouble());
    }

    final legacyGeo = userData['locationGeoPoint'];
    if (legacyGeo is GeoPoint) return legacyGeo;
    return null;
  }

  double _haversineKm(GeoPoint a, GeoPoint b) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final s = (sin(dLat / 2) * sin(dLat / 2)) +
        (cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(s), sqrt(1 - s));
    return earthRadiusKm * c;
  }

  double _degToRad(double v) => v * 0.017453292519943295;

  Future<void> _notifyNearbyUsers({
    required String eventId,
    required String hostId,
    required String title,
    required GeoPoint eventLocation,
    required String chatId,
  }) async {
    try {
      final usersSnapshot =
          await _firestore.collection('users').limit(500).get();

      // Filter to nearby non-host users — pure local computation, no I/O.
      final nearbyUserIds = usersSnapshot.docs
          .where((doc) {
            if (doc.id == hostId) return false;
            final loc = _parseUserGeo(doc.data());
            if (loc == null) return false;
            return _haversineKm(eventLocation, loc) <= _nearbyRadiusKm;
          })
          .map((doc) => doc.id)
          .toList();

      if (nearbyUserIds.isEmpty) return;
      debugPrint(
          '_notifyNearbyUsers: ${nearbyUserIds.length} nearby user(s) within ${_nearbyRadiusKm}km event=$eventId');

      // NOTE: The previous implementation read users/{uid}/settings/main for
      // each nearby user to check the nearbyActivity preference. That read is
      // PERMISSION_DENIED: the settings subcollection is owner-only
      // (auth.uid == userId) and the host cannot read another user's settings.
      // In practice this caused a FirebaseException on the first iteration,
      // aborting the loop — no nearby notifications were ever delivered.
      //
      // The nearbyActivity opt-out must instead be enforced server-side in the
      // onNotificationCreate Cloud Function, which runs as the admin service
      // account and can read settings without rule restrictions. Client-side
      // we send to all eligible nearby users and trust the Function to gate push.

      // Pre-fetch sender profile + event banner in parallel — one read each,
      // shared across all recipients. Previously _createNotification re-read
      // both on every iteration (N reads of the same two docs).
      final senderDocFuture = _firestore.collection('users').doc(hostId).get();
      final eventDocFuture = _firestore.collection('events').doc(eventId).get();

      final senderDoc = await senderDocFuture;
      final eventDoc = await eventDocFuture;

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

      final message = 'A new event "$title" is happening near you.';

      // Send all nearby notifications in parallel instead of sequentially.
      var sent = 0;
      await Future.wait(nearbyUserIds.map((userId) async {
        final dedupeKey = 'nearby_event:$eventId:$hostId:$userId';
        try {
          final ok = await _notificationService.sendWithRetry(
            () => _notificationService.sendNotification(
              userId: userId,
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
            userId: userId,
            type: NotificationType.eventCreated,
            senderId: hostId,
            metadata: <String, dynamic>{
              'eventId': eventId,
              'chatId': chatId,
              'dedupeKey': dedupeKey,
            },
          );
          if (ok) sent++;
        } catch (e, stack) {
          debugPrint('_notifyNearbyUsers: send failed for userId=$userId: $e');
          debugPrintStack(stackTrace: stack);
        }
      }));

      // Push fan-out is handled server-side by the onNotificationCreate Cloud
      // Function trigger. The receiver's push-enabled setting and dedupe are
      // evaluated there. Clients are forbidden from writing to push_queue.
      debugPrint(
          '_notifyNearbyUsers: sent=$sent/${nearbyUserIds.length} event=$eventId');
    } catch (e, stack) {
      debugPrint('_notifyNearbyUsers failed: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  // Public events only (for map/explore/search feeds)

  /// Notifies the first (oldest) waitlisted user that a spot opened.
  /// Fire-and-forget — never blocks the caller, never throws.
  Future<void> _notifyFirstWaitlistedUser({
    required String eventId,
    required String senderId,
    required String eventTitle,
  }) async {
    if (eventId.trim().isEmpty || senderId.trim().isEmpty) return;
    try {
      final snap = await _firestore
          .collection('event_participants')
          .doc(eventId)
          .collection('users')
          .where('status', isEqualTo: participantStatusWaitlisted)
          .orderBy('waitlistedAt')
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return;
      final data = snap.docs.first.data();
      final recipientId =
          (data['userId'] ?? snap.docs.first.id).toString().trim();
      if (recipientId.isEmpty || recipientId == senderId) return;

      // Fetch event banner for a richer notification card.
      final eventDoc = await _events.doc(eventId).get();
      final eventData = eventDoc.data() ?? const <String, dynamic>{};
      final bannerUrl = ((eventData['bannerUrl'] ??
              eventData['bannerImagePath'] ??
              '') as String)
          .trim();
      final resolvedTitle = eventTitle.isNotEmpty
          ? eventTitle
          : (eventData['title'] ?? 'an event').toString();

      await _notificationService.sendWithRetry(
        () => _notificationService.sendNotification(
          userId: recipientId,
          type: NotificationType.waitlistSpotAvailable,
          senderId: senderId,
          eventId: eventId,
          message: 'A spot opened in $resolvedTitle. Join now before it fills up!',
          title: 'A spot opened in $resolvedTitle',
          body: 'A spot opened in $resolvedTitle. Join now before it fills up!',
          eventBannerUrl: bannerUrl,
          dedupeKey: 'waitlist_spot:$eventId:$recipientId',
          dedupeWindow: const Duration(minutes: 10),
        ),
        userId: recipientId,
        type: NotificationType.waitlistSpotAvailable,
        senderId: senderId,
      );
      debugPrint('[Waitlist] notified $recipientId for event $eventId');
    } catch (e, stack) {
      debugPrint('[Waitlist] _notifyFirstWaitlistedUser failed: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// Builds the raw (single-subscription) Firestore query stream for a user's
  /// event membership. Extracted so the broadcast controller wrapper in
  /// [watchUserEventMembership] stays readable.
  Stream<UserEventMembershipSnapshot> _buildMembershipQuery(String uid) {
    return _firestore
        .collectionGroup('users')
        .where('userId', isEqualTo: uid)
        .where(
          'status',
          whereIn: const [
            participantStatusJoined,
            participantStatusPending,
            participantStatusWaitlisted,
            _legacyParticipantStatusActive,
          ],
        )
        .snapshots()
        .map((snapshot) {
          final joined = <String>{};
          final pending = <String>{};
          final waitlisted = <String>{};

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final eventId = (data['eventId'] ?? '').toString().trim();
            if (eventId.isEmpty) continue;
            final status = (data['status'] ?? '').toString().toLowerCase();
            if (_isJoinedParticipantStatus(status)) {
              joined.add(eventId);
            } else if (_isPendingParticipantStatus(status)) {
              pending.add(eventId);
            } else if (_isWaitlistedParticipantStatus(status)) {
              waitlisted.add(eventId);
            }
          }

          return UserEventMembershipSnapshot(
            joinedEventIds: joined,
            pendingEventIds: pending,
            waitlistedEventIds: waitlisted,
          );
        })
        .distinct((a, b) =>
            setEquals(a.joinedEventIds, b.joinedEventIds) &&
            setEquals(a.pendingEventIds, b.pendingEventIds) &&
            setEquals(a.waitlistedEventIds, b.waitlistedEventIds));
  }

  Future<UserEventMembershipSnapshot> _loadUserMembership({
    required String userId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return UserEventMembershipSnapshot.empty;

    final activeParticipantSnap = await _firestore
        .collectionGroup('users')
        .where('userId', isEqualTo: uid)
        .where('status', whereIn: const [
      participantStatusJoined,
      participantStatusPending,
      _legacyParticipantStatusActive,
    ]).get();

    final joinedEventIds = <String>{};
    final pendingEventIds = <String>{};

    for (final doc in activeParticipantSnap.docs) {
      final data = doc.data();
      final eventId = (data['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) continue;

      final status = (data['status'] ?? '').toString().toLowerCase();
      if (_isJoinedParticipantStatus(status)) {
        joinedEventIds.add(eventId);
        continue;
      }

      if (_isPendingParticipantStatus(status)) {
        pendingEventIds.add(eventId);
      }
    }

    return UserEventMembershipSnapshot(
      joinedEventIds: joinedEventIds,
      pendingEventIds: pendingEventIds,
    );
  }
}
