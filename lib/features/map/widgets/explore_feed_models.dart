part of '../../../screens/map_screen.dart';

enum _MarkerVisualMode { closeWithPill, mediumEmojiOnly, farCluster }

enum _ExploreCardType { banner, avatar, suggestion }

class _ExploreRefreshingRow {
  const _ExploreRefreshingRow();
}

class _ExploreFeedListFooter {
  const _ExploreFeedListFooter({
    required this.isLoadingMore,
    required this.hasMore,
  });

  final bool isLoadingMore;
  final bool hasMore;
}

class _ExploreFeedItem {
  final String id;
  final RankedExploreEvent ranked;
  final EventNode node;
  final String title;
  final String emoji;
  final _ExploreCardType type;
  final String timeText;
  final String distanceText;
  final String peopleText;
  final String socialProofText;
  final String spotsLeftText;

  const _ExploreFeedItem({
    required this.id,
    required this.ranked,
    required this.node,
    required this.title,
    required this.emoji,
    required this.type,
    required this.timeText,
    required this.distanceText,
    required this.peopleText,
    required this.socialProofText,
    required this.spotsLeftText,
  });

  factory _ExploreFeedItem.suggestion({required String id}) {
    final fallbackRanked = RankedExploreEvent(
      eventId: id,
      title: 'Find people nearby',
      hostId: '',
      thumbnailUrl: null,
      bannerUrl: null,
      avatarUrl: null,
      location: const LatLng(0, 0),
      participantsCount: 0,
      maxParticipants: 0,
      vibes: const <String>[],
      categories: const <String>[],
      createdAt: DateTime.now(),
      eventTime: null,
      visibility: 'public',
      isPublic: true,
      participantIds: const <String>[],
      hostName: 'Yanegi',
      locationName: '',
      friendJoined: false,
      friendHost: false,
      distanceKm: double.infinity,
      score: 0,
    );

    final fallbackNode = EventNode(
      id: id,
      latLng: const LatLng(0, 0),
      emoji: '✨',
      label: 'Find people nearby',
    );

    return _ExploreFeedItem(
      id: id,
      ranked: fallbackRanked,
      node: fallbackNode,
      title: 'Find people nearby',
      emoji: '✨',
      type: _ExploreCardType.suggestion,
      timeText: 'Anytime',
      distanceText: 'Nearby',
      peopleText: 'Try broadening your filters',
      socialProofText: 'Popular around you',
      spotsLeftText: '',
    );
  }

  double get layoutWeight {
    switch (type) {
      case _ExploreCardType.banner:
        return 2.8;
      case _ExploreCardType.avatar:
        return 1.5;
      case _ExploreCardType.suggestion:
        return 1.6;
    }
  }
}
