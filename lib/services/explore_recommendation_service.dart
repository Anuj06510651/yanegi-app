import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/filter_controller.dart';
import '../models/event_model.dart';
import '../models/ranked_explore_event.dart';
import 'explore_cache_service.dart';

class ExploreFeedRequest {
  final FilterModel filter;
  final LatLng? userLocation;

  const ExploreFeedRequest({
    required this.filter,
    required this.userLocation,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ExploreFeedRequest) return false;

    return filter.radiusKm == other.filter.radiusKm &&
        filter.dateFilter == other.filter.dateFilter &&
        filter.freeOnly == other.filter.freeOnly &&
        filter.friendsGoing == other.filter.friendsGoing &&
        filter.smallGroups == other.filter.smallGroups &&
        filter.publicOnly == other.filter.publicOnly &&
        filter.searchQuery == other.filter.searchQuery &&
        _sameList(filter.categories, other.filter.categories) &&
        _sameList(filter.vibes, other.filter.vibes) &&
        _sameLocation(userLocation, other.userLocation);
  }

  @override
  int get hashCode {
    return Object.hash(
      filter.radiusKm,
      filter.dateFilter,
      filter.freeOnly,
      filter.friendsGoing,
      filter.smallGroups,
      filter.publicOnly,
      filter.searchQuery,
      Object.hashAll(filter.categories),
      Object.hashAll(filter.vibes),
      userLocation?.latitude.toStringAsFixed(5),
      userLocation?.longitude.toStringAsFixed(5),
    );
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;

    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }

  static bool _sameLocation(LatLng? a, LatLng? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;

    return a.latitude.toStringAsFixed(5) == b.latitude.toStringAsFixed(5) &&
        a.longitude.toStringAsFixed(5) == b.longitude.toStringAsFixed(5);
  }
}

class ExploreFeedPage {
  final List<RankedExploreEvent> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const ExploreFeedPage({
    required this.items,
    required this.lastDocument,
    required this.hasMore,
  });
}

class ExploreRecommendationService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ExploreRecommendationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const Duration _cacheTtl = Duration(seconds: 30);

  static const int _exploreFetchLimit = 20;

  static const double _minLatitude = -90;
  static const double _maxLatitude = 90;

  static const double _minLongitude = -180;
  static const double _maxLongitude = 180;

  final Map<int, _ExploreCacheEntry> _cache = {};
  final Map<int, Future<ExploreFeedPage>> _ongoingRequests = {};

  int? _activeRequestHash;

  Query<Map<String, dynamic>> _eventsQuery({
    required DateTime now,
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? startAfterDocument,
  }) {
    final nowTs = Timestamp.fromDate(now);

    var query = _firestore
        .collection('events')
        .where('status', isEqualTo: 'active')
        .where('visibility', isEqualTo: 'public')
        .where('startAt', isGreaterThanOrEqualTo: nowTs)
        .orderBy('startAt')
        .limit(limit);

    if (startAfterDocument != null) {
      query = query.startAfterDocument(startAfterDocument);
    }

    return query;
  }

  /// Clears the in-memory explore page cache. Call this on sign-out so a
  /// new user does not briefly see the previous user's ranked feed (which
  /// contains user-specific friendJoined / friendHost flags derived from
  /// the previous user's friend list).
  void clearCache() {
    _cache.clear();
    _ongoingRequests.clear();
    _activeRequestHash = null;
    // Also drop the persisted page so a new user never sees the previous user's
    // ranked feed on cold start.
    ExploreCacheService.clear();
    debugPrint('ExploreRecommendationService: cache cleared');
  }

  void _retainOnlyActiveRequest(int requestHash) {
    if (_activeRequestHash != null && _activeRequestHash != requestHash) {
      _cache.clear();
    }

    _activeRequestHash = requestHash;
  }

  ExploreFeedPage? getCachedPage({
    required ExploreFeedRequest request,
  }) {
    final requestHash = request.hashCode;

    _retainOnlyActiveRequest(requestHash);

    final cached = _cache[requestHash];

    if (cached == null) return null;

    if (DateTime.now().difference(cached.createdAt) >= _cacheTtl) {
      _cache.remove(requestHash);
      return null;
    }

    return cached.page;
  }

  Future<List<RankedExploreEvent>> getRankedEvents({
    required ExploreFeedRequest request,
  }) async {
    final page = await getRankedEventsPage(
      request: request,
    );

    return page.items;
  }

  Future<ExploreFeedPage> getRankedEventsPage({
    required ExploreFeedRequest request,
    DocumentSnapshot<Map<String, dynamic>>? startAfterDocument,
    int limit = _exploreFetchLimit,
    bool bypassCache = false,
  }) async {
    final requestHash = request.hashCode;
    if (_ongoingRequests.containsKey(requestHash)) {
      return _ongoingRequests[requestHash]!;
    }

    final isFirstPage = startAfterDocument == null;

    if (isFirstPage) {
      _retainOnlyActiveRequest(requestHash);
    }

    final cached = _cache[requestHash];

    if (!bypassCache &&
        isFirstPage &&
        cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheTtl) {
      return cached.page;
    }

    final future = () async {
      final currentUid = _auth.currentUser?.uid;

      final friendIds = await _fetchFriendIds(currentUid);

      final now = DateTime.now();

      final query = _eventsQuery(
        now: now,
        limit: limit,
        startAfterDocument: startAfterDocument,
      );

      final snapshot = await query.get();

      final lastDocument =
          snapshot.docs.isEmpty ? startAfterDocument : snapshot.docs.last;

      final hasMore = snapshot.docs.length == limit;

      final allActiveEvents = <RankedExploreEvent>[];

      for (final doc in snapshot.docs) {
        final model = EventModel.fromFirestore(doc);

        final data = model.raw;

        if (!_isActiveEvent(model, now)) continue;

        final location = model.location;

        if (location == null) continue;

        final participants = model.participants;

        final maxParticipants = _toInt(
          data['maxParticipants'] ?? model.maxCapacity,
          fallback: model.maxCapacity <= 0 ? 10 : model.maxCapacity,
        );

        final participantsCount = model.participantsCount;

        final hostId = model.hostId;

        final vibes = List<String>.from(
          data['vibes'] ?? data['tags'] ?? const <String>[],
        );

        final categories = List<String>.from(
          data['categories'] ?? data['tags'] ?? const <String>[],
        );

        final createdAt = _toDateTime(
              data['createdAt'] ?? data['created_at'],
            ) ??
            now;

        final eventTime = model.startTime ??
            _toDateTime(
              data['time'] ?? data['timestamp'],
            );

        final visibility = model.visibility;

        final isPublic = model.isPublic;

        final isApprovalRequired = model.isApprovalRequired;

        final distanceKm = request.userLocation == null
            ? double.infinity
            : _haversineKm(
                request.userLocation!,
                location,
              );

        final friendJoined = participants.any(friendIds.contains);

        final friendHost = friendIds.contains(hostId);

        // Collect friend UIDs who are active participants (used for avatars).
        final friendParticipantIds = participants
            .where(friendIds.contains)
            .toList();
        if (friendHost &&
            hostId.isNotEmpty &&
            !friendParticipantIds.contains(hostId)) {
          friendParticipantIds.insert(0, hostId);
        }

        final item = RankedExploreEvent(
          eventId: doc.id,
          title: model.title.isEmpty
              ? (data['label'] ?? 'Event').toString()
              : model.title,
          hostId: hostId,
          thumbnailUrl: model.bannerUrl.isEmpty ? null : model.bannerUrl,
          bannerUrl: model.bannerUrl.isEmpty ? null : model.bannerUrl,
          avatarUrl: (data['avatarUrl'] ?? data['hostAvatarUrl'])?.toString(),
          location: location,
          participantsCount: participantsCount,
          maxParticipants: maxParticipants,
          vibes: vibes,
          categories: categories,
          createdAt: createdAt,
          eventTime: eventTime,
          visibility: visibility,
          isPublic: isPublic,
          isApprovalRequired: isApprovalRequired,
          participantIds: participants,
          hostName: model.hostName.isEmpty ? 'Unknown' : model.hostName,
          locationName: model.locationName,
          friendJoined: friendJoined,
          friendHost: friendHost,
          friendParticipantIds: friendParticipantIds,
          distanceKm: distanceKm,
          score: _scoreEvent(
            distanceKm: distanceKm,
            participantsCount: participantsCount,
            friendJoined: friendJoined,
            friendHost: friendHost,
            createdAt: createdAt,
            now: now,
          ),
        );

        allActiveEvents.add(item);
      }

      allActiveEvents.sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);

        if (scoreCompare != 0) {
          return scoreCompare;
        }

        return b.createdAt.compareTo(
          a.createdAt,
        );
      });

      final filtered = allActiveEvents.where((item) {
        return _passesFilters(
          item: item,
          filter: request.filter,
          now: now,
          hasUserLocation: request.userLocation != null,
        );
      }).toList();

      final finalEvents = filtered.take(limit).toList(growable: false);

      final page = ExploreFeedPage(
        items: finalEvents,
        lastDocument: lastDocument,
        hasMore: hasMore,
      );

      if (isFirstPage) {
        _cache
          ..clear()
          ..[requestHash] = _ExploreCacheEntry(
            createdAt: DateTime.now(),
            page: page,
          );

        // Persist the fresh first page for instant cold-start rendering on the
        // next launch (5-minute TTL enforced by ExploreCacheService).
        ExploreCacheService.save(page.items);
      }

      return page;
    }();

    _ongoingRequests[requestHash] = future;

    try {
      return await future;
    } finally {
      _ongoingRequests.remove(requestHash);
    }
  }

  // 🔥 FULLY FIXED
  // NO REALTIME STREAMS
  // NO INFINITE OFFLINE RETRIES

  Stream<ExploreFeedPage> watchRankedEventsPage({
    required ExploreFeedRequest request,
    int limit = _exploreFetchLimit,
  }) async* {
    final requestHash = request.hashCode;

    _retainOnlyActiveRequest(requestHash);

    final cached = getCachedPage(
      request: request,
    );

    if (cached != null) {
      debugPrint(
        "EXPLORE CACHE: returning cached page",
      );

      yield cached;
    } else {
      // Cold start with no warm in-memory cache: render the last persisted page
      // immediately (within its 5-minute TTL) while the live fetch runs below.
      final persisted = ExploreCacheService.load();
      if (persisted != null && persisted.isNotEmpty) {
        debugPrint(
          "EXPLORE CACHE: returning persisted page (${persisted.length})",
        );
        yield ExploreFeedPage(
          items: persisted,
          lastDocument: null,
          hasMore: false,
        );
      }
    }

    try {
      debugPrint(
        "EXPLORE FETCH: loading fresh explore feed",
      );

      final freshPage = await getRankedEventsPage(
        request: request,
        limit: limit,
        bypassCache: true,
      );

      debugPrint(
        "EXPLORE FETCH: loaded ${freshPage.items.length} events",
      );

      yield freshPage;

      debugPrint(
        "EXPLORE FETCH: success",
      );
    } catch (e, st) {
      debugPrint(
        "EXPLORE FETCH ERROR: $e",
      );

      debugPrintStack(
        stackTrace: st,
      );

      if (cached != null) {
        debugPrint(
          "EXPLORE CACHE: fallback after fetch failure",
        );

        yield cached;
      } else {
        yield const ExploreFeedPage(
          items: [],
          lastDocument: null,
          hasMore: false,
        );
      }
    }
  }

  Future<Set<String>> _fetchFriendIds(
    String? currentUid,
  ) async {
    if (currentUid == null || currentUid.isEmpty) {
      return <String>{};
    }

    // Read from the production subcollection schema: friends/{uid}/list/{friendId}.
    // Rules allow the owner to read their own list (request.auth.uid == userId).
    final snap = await _firestore
        .collection('friends')
        .doc(currentUid)
        .collection('list')
        .get();

    return snap.docs
        .map((doc) => doc.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  bool _isActiveEvent(
    EventModel model,
    DateTime now,
  ) {
    if (!model.isActive) return false;

    final status = model.status;

    if (status != 'active') return false;

    final data = model.raw;

    final endAt = model.endTime ?? _toDateTime(data['endsAt']);

    if (endAt != null && endAt.isBefore(now)) {
      return false;
    }

    final startAt = _toDateTime(data['startAt']);

    if (startAt != null &&
        startAt.isBefore(
          now.subtract(
            const Duration(days: 1),
          ),
        )) {
      return false;
    }

    return true;
  }

  bool _passesFilters({
    required RankedExploreEvent item,
    required FilterModel filter,
    required DateTime now,
    required bool hasUserLocation,
  }) {
    // ── 1. Search query ─────────────────────────────────────────────────────
    // Match against title, host name, location name, vibes, and categories.
    // All comparisons are case-insensitive. Whitespace-only queries are ignored.
    final query = filter.searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final hit = item.title.toLowerCase().contains(query) ||
          item.hostName.toLowerCase().contains(query) ||
          item.locationName.toLowerCase().contains(query) ||
          item.vibes.any((v) => v.toLowerCase().contains(query)) ||
          item.categories.any((c) => c.toLowerCase().contains(query));
      if (!hit) return false;
    }

    // ── 2. Categories ────────────────────────────────────────────────────────
    // At least one of the event's categories must match a selected filter
    // category. Matching is case-insensitive; an empty selection passes all.
    if (filter.categories.isNotEmpty) {
      final itemCats =
          item.categories.map((c) => c.toLowerCase()).toSet();
      final matched =
          filter.categories.any((c) => itemCats.contains(c.toLowerCase()));
      if (!matched) return false;
    }

    // ── 3. Vibes ─────────────────────────────────────────────────────────────
    // Same OR semantics as categories but against the item's vibes list.
    if (filter.vibes.isNotEmpty) {
      final itemVibes = item.vibes.map((v) => v.toLowerCase()).toSet();
      final matched =
          filter.vibes.any((v) => itemVibes.contains(v.toLowerCase()));
      if (!matched) return false;
    }

    // ── 4. Date filter ───────────────────────────────────────────────────────
    // 'anytime' skips this check entirely. For the other values, the event
    // must have a non-null eventTime. Events whose eventTime is null are
    // passed through rather than hidden — unknown date ≠ wrong date.
    if (filter.dateFilter != 'anytime') {
      final eventTime = item.eventTime;
      if (eventTime != null) {
        switch (filter.dateFilter) {
          case 'today':
            if (!_isSameDay(eventTime, now)) return false;
            break;
          case 'tomorrow':
            final tomorrow = now.add(const Duration(days: 1));
            if (!_isSameDay(eventTime, tomorrow)) return false;
            break;
          case 'weekend':
            // Friday is included for "weekend" (Fri–Sun).
            final weekday = eventTime.weekday;
            if (weekday != DateTime.friday &&
                weekday != DateTime.saturday &&
                weekday != DateTime.sunday) {
              return false;
            }
            break;
        }
      }
      // eventTime == null → skip date filter for this event.
    }

    // ── 5. Distance / radius ─────────────────────────────────────────────────
    // Only applied when the caller has a user location. Items without GPS
    // coordinates have distanceKm == double.infinity and are caught by the
    // location-null guard upstream (they never reach _passesFilters), so we
    // don't need a special case for infinity here.
    if (hasUserLocation && filter.radiusKm > 0) {
      if (item.distanceKm.isFinite && item.distanceKm > filter.radiusKm) {
        return false;
      }
    }

    // ── 6. Friends going ─────────────────────────────────────────────────────
    // Requires at least one friend among participants or the host. Both flags
    // are computed in getRankedEventsPage from the user's friend-edge list.
    if (filter.friendsGoing && !item.friendJoined && !item.friendHost) {
      return false;
    }

    // ── 7. Small groups ──────────────────────────────────────────────────────
    // Threshold matches the map filter (≤ 6 people). Events with an unknown
    // capacity (maxParticipants == 0) are excluded from this check to avoid
    // incorrectly hiding them.
    if (filter.smallGroups &&
        item.maxParticipants > 0 &&
        item.maxParticipants > 6) {
      return false;
    }

    // ── 8. Public only ───────────────────────────────────────────────────────
    if (filter.publicOnly && !item.isPublic) return false;

    // ── 9. Free only ─────────────────────────────────────────────────────────
    // RankedExploreEvent carries no price field so this filter cannot be
    // evaluated here. All events pass. To enable: add a price field to
    // RankedExploreEvent and populate it in getRankedEventsPage.

    return true;
  }

  int _scoreEvent({
    required double distanceKm,
    required int participantsCount,
    required bool friendJoined,
    required bool friendHost,
    required DateTime createdAt,
    required DateTime now,
  }) {
    var score = 0;

    final nearby = distanceKm.isFinite && distanceKm <= 10;

    if (nearby) score += 50;

    if (friendJoined || friendHost) {
      score += 40;
    }

    if (participantsCount >= 12) {
      score += 30;
    }

    if (now.difference(createdAt).inHours <= 72) {
      score += 20;
    } else {
      score += 10;
    }

    return score;
  }

  int _toInt(
    dynamic value, {
    required int fallback,
  }) {
    if (value is int) return value;

    if (value is double) {
      return value.round();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        fallback;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) return value;

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  bool _isSameDay(
    DateTime a,
    DateTime b,
  ) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  double _haversineKm(
    LatLng from,
    LatLng to,
  ) {
    const earthRadiusKm = 6371.0;

    final dLat = _degToRad(to.latitude - from.latitude);

    final dLon = _degToRad(to.longitude - from.longitude);

    final lat1 = _degToRad(from.latitude);

    final lat2 = _degToRad(to.latitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 *
        math.atan2(
          math.sqrt(a),
          math.sqrt(1 - a),
        );

    return earthRadiusKm * c;
  }

  double _degToRad(double degree) {
    return degree * (math.pi / 180.0);
  }

  LatLng? _safeLatLng(
    double? lat,
    double? lng,
  ) {
    if (lat == null || lng == null) {
      return null;
    }

    if (!lat.isFinite || !lng.isFinite) {
      return null;
    }

    if (lat < _minLatitude || lat > _maxLatitude) {
      return null;
    }

    if (lng < _minLongitude || lng > _maxLongitude) {
      return null;
    }

    return LatLng(lat, lng);
  }
}

class _ExploreCacheEntry {
  final DateTime createdAt;
  final ExploreFeedPage page;

  _ExploreCacheEntry({
    required this.createdAt,
    required this.page,
  });
}
