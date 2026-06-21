import 'package:latlong2/latlong.dart';

enum ExploreJoinState { notJoined, requested, joined }

class RankedExploreEvent {
  final String eventId;
  final String title;
  final String hostId;
  final String? thumbnailUrl;
  final String? bannerUrl;
  final String? avatarUrl;
  final LatLng location;
  final int participantsCount;
  final int maxParticipants;
  final List<String> vibes;
  final List<String> categories;
  final DateTime createdAt;
  final DateTime? eventTime;
  final String visibility;
  final bool isPublic;
  final bool isApprovalRequired;
  final List<String> participantIds;
  final String hostName;
  final String locationName;
  final bool friendJoined;
  final bool friendHost;
  // Actual UIDs of friends who are active participants (≤ all of them).
  final List<String> friendParticipantIds;
  final double distanceKm;
  final int score;
  final ExploreJoinState joinState;

  const RankedExploreEvent({
    required this.eventId,
    required this.title,
    required this.hostId,
    required this.thumbnailUrl,
    required this.bannerUrl,
    required this.avatarUrl,
    required this.location,
    required this.participantsCount,
    required this.maxParticipants,
    required this.vibes,
    required this.categories,
    required this.createdAt,
    required this.eventTime,
    required this.visibility,
    required this.isPublic,
    this.isApprovalRequired = true,
    required this.participantIds,
    required this.hostName,
    required this.locationName,
    required this.friendJoined,
    required this.friendHost,
    this.friendParticipantIds = const [],
    required this.distanceKm,
    required this.score,
    this.joinState = ExploreJoinState.notJoined,
  });

  RankedExploreEvent copyWith({
    ExploreJoinState? joinState,
  }) {
    return RankedExploreEvent(
      eventId: eventId,
      title: title,
      hostId: hostId,
      thumbnailUrl: thumbnailUrl,
      bannerUrl: bannerUrl,
      avatarUrl: avatarUrl,
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
      participantIds: participantIds,
      hostName: hostName,
      locationName: locationName,
      friendJoined: friendJoined,
      friendHost: friendHost,
      friendParticipantIds: friendParticipantIds,
      distanceKm: distanceKm,
      score: score,
      joinState: joinState ?? this.joinState,
    );
  }
}
