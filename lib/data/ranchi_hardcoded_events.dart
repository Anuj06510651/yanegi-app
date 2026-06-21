import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../models/event_node.dart';
import '../models/ranked_explore_event.dart';

class RanchiHardcodedEvent {
  final String id;
  final String title;
  final String description;
  final String locationName;
  final double lat;
  final double lng;
  final DateTime startAt;
  final DateTime endAt;
  final String emoji;
  final int maxCapacity;
  final List<String> tags;
  final String hostId;
  final String hostName;

  const RanchiHardcodedEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.locationName,
    required this.lat,
    required this.lng,
    required this.startAt,
    required this.endAt,
    required this.emoji,
    required this.maxCapacity,
    required this.tags,
    required this.hostId,
    required this.hostName,
  });

  LatLng get latLng => LatLng(lat, lng);

  EventNode toEventNode() {
    return EventNode(
      id: id,
      latLng: latLng,
      emoji: emoji,
      label: title,
      activityLevel: 0.6,
      bannerImagePath: null,
      currentAttendees: 1,
      maxCapacity: maxCapacity,
      categories: tags,
      vibes: tags,
      date: endAt,
      isPublic: true,
      visibility: 'global',
      isApprovalRequired: false,
      hostId: hostId,
      hostName: hostName,
      locationText: locationName,
      participants: const <String>[],
    );
  }

  RankedExploreEvent toRankedExploreEvent({
    required DateTime now,
    LatLng? userLocation,
  }) {
    final distance = userLocation == null
        ? double.infinity
        : const Distance().as(LengthUnit.Kilometer, userLocation, latLng);

    return RankedExploreEvent(
      eventId: id,
      title: title,
      hostId: hostId,
      thumbnailUrl: null,
      bannerUrl: null,
      avatarUrl: null,
      location: latLng,
      participantsCount: 1,
      maxParticipants: maxCapacity,
      vibes: tags,
      categories: tags,
      createdAt: now,
      eventTime: startAt,
      visibility: 'global',
      isPublic: true,
      isApprovalRequired: false,
      participantIds: const <String>[],
      hostName: hostName,
      locationName: locationName,
      friendJoined: false,
      friendHost: false,
      distanceKm: distance,
      score: 70,
    );
  }

  Map<String, dynamic> toEventData() {
    final tsStart = Timestamp.fromDate(startAt);
    final tsEnd = Timestamp.fromDate(endAt);

    return {
      'eventId': id,
      'hostId': hostId,
      'hostName': hostName,
      'host_name': hostName,
      'title': title,
      'description': description,
      'activityType': tags.isNotEmpty ? tags.first : 'general',
      'location': locationName,
      'locationName': locationName,
      'lat': lat,
      'lng': lng,
      'locationGeoPoint': GeoPoint(lat, lng),
      'approximateLocation': {
        'lat': lat,
        'lng': lng,
      },
      'startAt': tsStart,
      'endAt': tsEnd,
      'timezone': 'Asia/Kolkata',
      'ageRange': {
        'min': 18,
        'max': 35,
      },
      'ageRangeLabel': 'Age: 18–35',
      'hideExactLocationUntilApproved': false,
      'participants': const <String>[],
      'participantsCount': 1,
      'maxCapacity': maxCapacity,
      'maxParticipants': maxCapacity,
      'visibility': 'global',
      'isApprovalRequired': false,
      'eventAvatar': emoji,
      'emoji': emoji,
      'bannerImagePath': '',
      'bannerUrl': '',
      'time':
          '${startAt.hour.toString().padLeft(2, '0')}:${startAt.minute.toString().padLeft(2, '0')}',
      'tags': tags,
      'vibes': tags,
      'categories': tags,
      'status': 'active',
      'isActive': true,
      'isDeleted': false,
      'createdAt': Timestamp.fromDate(DateTime.now()),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
  }
}

class RanchiHardcodedEvents {
  static final List<RanchiHardcodedEvent> events = <RanchiHardcodedEvent>[];

  static RanchiHardcodedEvent? byId(String id) {
    for (final event in events) {
      if (event.id == id) return event;
    }
    return null;
  }

  static List<EventNode> toEventNodes() {
    return events.map((event) => event.toEventNode()).toList(growable: false);
  }

  static List<RankedExploreEvent> toRankedEvents({
    required DateTime now,
    LatLng? userLocation,
  }) {
    return const <RankedExploreEvent>[];
  }
}
