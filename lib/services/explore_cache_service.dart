import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../models/ranked_explore_event.dart';

/// Hive-backed persistent cache for the Explore feed.
///
/// Stores the last successfully fetched page so that on cold start the UI
/// shows content immediately while the live Firestore fetch completes in
/// the background.  Cache entries older than [_ttl] are treated as absent.
class ExploreCacheService {
  static const _boxName = 'yanegi_explore_v1';
  static const _pageKey = 'explore_latest';
  static const _timestampKey = 'explore_ts';
  static const Duration _ttl = Duration(minutes: 5);

  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  static void save(List<RankedExploreEvent> items) {
    final box = _box;
    if (box == null) return;
    try {
      final encoded = jsonEncode(items.map(_toJson).toList());
      box.put(_pageKey, encoded);
      box.put(_timestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[ExploreCacheService] save error: $e');
    }
  }

  /// Returns cached items if they exist and are within TTL, otherwise null.
  static List<RankedExploreEvent>? load() {
    final box = _box;
    if (box == null) return null;
    final raw = box.get(_pageKey) as String?;
    final tsMs = box.get(_timestampKey) as int?;
    if (raw == null || tsMs == null) return null;
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    if (DateTime.now().difference(fetchedAt) >= _ttl) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final items = list
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .whereType<RankedExploreEvent>()
          .toList();
      return items.isEmpty ? null : items;
    } catch (e) {
      debugPrint('[ExploreCacheService] load error: $e');
      return null;
    }
  }

  static void clear() {
    _box?.delete(_pageKey);
    _box?.delete(_timestampKey);
  }

  // ── Serialization ──────────────────────────────────────────────────────────

  static Map<String, dynamic> _toJson(RankedExploreEvent e) => {
        'eventId': e.eventId,
        'title': e.title,
        'hostId': e.hostId,
        'thumbnailUrl': e.thumbnailUrl,
        'bannerUrl': e.bannerUrl,
        'avatarUrl': e.avatarUrl,
        'lat': e.location.latitude,
        'lng': e.location.longitude,
        'participantsCount': e.participantsCount,
        'maxParticipants': e.maxParticipants,
        'vibes': e.vibes,
        'categories': e.categories,
        'createdAt': e.createdAt.millisecondsSinceEpoch,
        'eventTime': e.eventTime?.millisecondsSinceEpoch,
        'visibility': e.visibility,
        'isPublic': e.isPublic,
        'isApprovalRequired': e.isApprovalRequired,
        'participantIds': e.participantIds,
        'hostName': e.hostName,
        'locationName': e.locationName,
        'friendJoined': e.friendJoined,
        'friendHost': e.friendHost,
        'friendParticipantIds': e.friendParticipantIds,
        'distanceKm': e.distanceKm.isFinite ? e.distanceKm : null,
        'score': e.score,
      };

  static RankedExploreEvent? _fromJson(Map<String, dynamic> j) {
    try {
      return RankedExploreEvent(
        eventId: j['eventId'] as String,
        title: j['title'] as String,
        hostId: j['hostId'] as String,
        thumbnailUrl: j['thumbnailUrl'] as String?,
        bannerUrl: j['bannerUrl'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        location: LatLng(
          (j['lat'] as num).toDouble(),
          (j['lng'] as num).toDouble(),
        ),
        participantsCount: (j['participantsCount'] as num).toInt(),
        maxParticipants: (j['maxParticipants'] as num).toInt(),
        vibes: List<String>.from(j['vibes'] as List? ?? const []),
        categories: List<String>.from(j['categories'] as List? ?? const []),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (j['createdAt'] as num).toInt(),
        ),
        eventTime: j['eventTime'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (j['eventTime'] as num).toInt(),
              )
            : null,
        visibility: j['visibility'] as String? ?? 'public',
        isPublic: j['isPublic'] as bool? ?? true,
        isApprovalRequired: j['isApprovalRequired'] as bool? ?? true,
        participantIds: List<String>.from(
          j['participantIds'] as List? ?? const [],
        ),
        hostName: j['hostName'] as String? ?? 'Unknown',
        locationName: j['locationName'] as String? ?? '',
        friendJoined: j['friendJoined'] as bool? ?? false,
        friendHost: j['friendHost'] as bool? ?? false,
        friendParticipantIds: List<String>.from(
          j['friendParticipantIds'] as List? ?? const [],
        ),
        distanceKm:
            j['distanceKm'] != null ? (j['distanceKm'] as num).toDouble() : double.infinity,
        score: (j['score'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
