import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../utils/media_url_resolver.dart';

class EventModel {
  const EventModel({
    required this.id,
    required this.title,
    required this.hostId,
    required this.status,
    required this.isActive,
    required this.visibility,
    required this.isApprovalRequired,
    required this.location,
    required this.locationName,
    required this.startTime,
    required this.endTime,
    required this.participants,
    required this.participantsCount,
    required this.maxCapacity,
    required this.bannerUrl,
    required this.eventAvatar,
    required this.hostName,
    required this.raw,
  });

  final String id;
  final String title;
  final String hostId;
  final String status;
  final bool isActive;
  final String visibility;
  final bool isApprovalRequired;
  final LatLng? location;
  final String locationName;
  final DateTime? startTime;
  final DateTime? endTime;
  final List<String> participants;
  final int participantsCount;
  final int maxCapacity;
  final String bannerUrl;
  final String eventAvatar;
  final String hostName;
  final Map<String, dynamic> raw;

  bool get isPublic => visibility != 'private';

  factory EventModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Event data is null for ${doc.id}');
    }

    final location = _resolveLocation(data);
    final participants =
        List<String>.from(data['participants'] ?? const <String>[]);
    final participantsCount = _toInt(
      data['participantsCount'],
      fallback: participants.length,
    );

    return EventModel(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      hostId: ((data['hostId'] ?? data['host_id']) ?? '').toString().trim(),
      status: (data['status'] ?? 'active').toString().toLowerCase(),
      isActive: data['isActive'] != false,
      visibility: (data['visibility'] ?? 'public').toString(),
      isApprovalRequired: data['isApprovalRequired'] == true,
      location: location,
      locationName: (data['locationName'] ?? data['location'] ?? '').toString(),
      startTime: _toDateTime(data['startAt'] ?? data['startTime']),
      endTime: _toDateTime(data['endAt'] ?? data['endTime']),
      participants: participants,
      participantsCount: participantsCount,
      maxCapacity: _toInt(data['maxCapacity'], fallback: 0),
      bannerUrl: resolveRemoteMediaUrl(<dynamic>[
        data['thumbnailUrl'],
        data['bannerUrl'],
        data['bannerImagePath'],
        data['imageUrl'],
      ]),
      eventAvatar: (data['eventAvatar'] ?? data['emoji'] ?? '').toString(),
      hostName: (data['hostName'] ?? data['host_name'] ?? '').toString(),
      raw: Map<String, dynamic>.from(data),
    );
  }

  static LatLng? _resolveLocation(Map<String, dynamic> data) {
    final rawLocation = data['location'];
    final locationGeoPoint = data['locationGeoPoint'] as GeoPoint?;

    if (rawLocation is GeoPoint) {
      return _safeLatLng(rawLocation.latitude, rawLocation.longitude);
    }
    if (rawLocation is Map<String, dynamic>) {
      final lat = (rawLocation['lat'] as num?)?.toDouble();
      final lng = (rawLocation['lng'] as num?)?.toDouble();
      return _safeLatLng(lat, lng);
    }

    final directLat = (data['lat'] as num?)?.toDouble();
    final directLng = (data['lng'] as num?)?.toDouble();
    final direct = _safeLatLng(directLat, directLng);
    if (direct != null) return direct;

    if (locationGeoPoint != null) {
      return _safeLatLng(locationGeoPoint.latitude, locationGeoPoint.longitude);
    }
    return null;
  }

  static LatLng? _safeLatLng(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return LatLng(lat, lng);
  }

  static DateTime? _toDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    return null;
  }

  static int _toInt(dynamic raw, {required int fallback}) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }
}
