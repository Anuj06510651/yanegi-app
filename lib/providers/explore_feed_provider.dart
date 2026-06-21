import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ranked_explore_event.dart';
import '../services/event_service.dart';
import '../services/explore_recommendation_service.dart';

enum HomeTab { map, explore, chat, profile }

final activeTabProvider = StateProvider<HomeTab>((ref) => HomeTab.map);

final exploreRecommendationServiceProvider =
    Provider<ExploreRecommendationService>((ref) {
  final service = ExploreRecommendationService();
  // Clear user-specific explore cache (friendJoined/friendHost flags) on
  // sign-out so the next user never sees the previous user's ranked feed.
  ref.onDispose(service.clearCache);
  return service;
});

final eventServiceProvider = Provider<EventService>((ref) {
  final service = EventService();
  // Clear stream caches on sign-out so a new user's membership queries
  // always start fresh instead of hitting the previous user's cached streams.
  ref.onDispose(service.clearCaches);
  return service;
});

final watchUserEventStatesProvider =
    StreamProvider.family<Map<String, UserEventState>, String>(
  (ref, userId) {
    final service = ref.read(eventServiceProvider);
    return service.watchUserEventStates(userId);
  },
);

final eventParticipationStateProvider =
    StreamProvider.family<UserEventState, String>(
  (ref, eventId) {
    final normalizedEventId = eventId.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    if (uid.isEmpty || normalizedEventId.isEmpty) {
      return Stream<UserEventState>.value(UserEventState.notJoined);
    }

    final participantDoc = FirebaseFirestore.instance
        .collection('event_participants')
        .doc(normalizedEventId)
        .collection('users')
        .doc(uid);

    return participantDoc.snapshots().map((snapshot) {
      if (!snapshot.exists) return UserEventState.notJoined;
      final data = snapshot.data();
      if (data == null) return UserEventState.notJoined;

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status == EventService.participantStatusPending) {
        return UserEventState.pending;
      }
      if (status == EventService.participantStatusWaitlisted) {
        return UserEventState.waitlisted;
      }
      if (status == EventService.participantStatusJoined ||
          status == 'active') {
        return UserEventState.joined;
      }
      return UserEventState.notJoined;
    });
  },
);

class ExplorePaginatedFeedState {
  final List<RankedExploreEvent> items;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isRefreshing;

  const ExplorePaginatedFeedState({
    required this.items,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isRefreshing,
  });

  ExplorePaginatedFeedState copyWith({
    List<RankedExploreEvent>? items,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isRefreshing,
  }) {
    return ExplorePaginatedFeedState(
      items: items ?? this.items,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
    );
  }
}

final explorePaginatedFeedProvider = StreamNotifierProviderFamily<
    ExplorePaginatedFeedController,
    ExplorePaginatedFeedState,
    ExploreFeedRequest>(
  ExplorePaginatedFeedController.new,
);

class ExplorePaginatedFeedController extends FamilyStreamNotifier<
    ExplorePaginatedFeedState, ExploreFeedRequest> {
  ExploreFeedPage? _lastPage;
  bool _loadingMore = false;
  Map<String, UserEventState> _latestUserEventStates =
      const <String, UserEventState>{};

  ExploreJoinState _toJoinState({
    required String eventId,
    required String hostId,
    required String currentUid,
  }) {
    final normalizedUid = currentUid.trim();
    if (normalizedUid.isNotEmpty && hostId.trim() == normalizedUid) {
      return ExploreJoinState.joined;
    }

    final state =
        _latestUserEventStates[eventId.trim()] ?? UserEventState.notJoined;
    switch (state) {
      case UserEventState.joined:
        return ExploreJoinState.joined;
      case UserEventState.pending:
        return ExploreJoinState.requested;
      case UserEventState.waitlisted:
        // Treat waitlisted as "requested" in the explore feed join button
        // (shows a disabled state so the user doesn't try to join again).
        return ExploreJoinState.requested;
      case UserEventState.notJoined:
        return ExploreJoinState.notJoined;
    }
  }

  List<RankedExploreEvent> _withLiveParticipationState(
    List<RankedExploreEvent> items,
  ) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return items
        .map(
          (item) => item.copyWith(
            joinState: _toJoinState(
              eventId: item.eventId,
              hostId: item.hostId,
              currentUid: currentUid,
            ),
          ),
        )
        .toList(growable: false);
  }

  void _setStateSafely(AsyncValue<ExplorePaginatedFeedState> value) {
    try {
      state = value;
    } catch (_) {
      // Provider might have been disposed during fast navigation.
    }
  }

  @override
  Stream<ExplorePaginatedFeedState> build(ExploreFeedRequest request) async* {
    final service = ref.read(exploreRecommendationServiceProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (uid.trim().isNotEmpty) {
      ref.listen<AsyncValue<Map<String, UserEventState>>>(
        watchUserEventStatesProvider(uid),
        (_, next) {
          final nextStates = next.valueOrNull;
          if (nextStates == null) return;
          _latestUserEventStates = nextStates;

          final current = state.valueOrNull;
          if (current == null) return;
          _setStateSafely(
            AsyncData(
              current.copyWith(
                items: _withLiveParticipationState(current.items),
              ),
            ),
          );
        },
      );
    } else {
      _latestUserEventStates = const <String, UserEventState>{};
    }

    await for (final page in service.watchRankedEventsPage(request: request)) {
      _lastPage = page;
      yield ExplorePaginatedFeedState(
        items: _withLiveParticipationState(page.items),
        hasMore: page.hasMore,
        isLoadingMore: false,
        isRefreshing: false,
      );
    }
  }

  Future<void> refreshFeed() async {
    _loadingMore = false;
    final current = state.valueOrNull;

    if (current == null) {
      _setStateSafely(const AsyncLoading());
      _setStateSafely(await AsyncValue.guard(() async {
        final service = ref.read(exploreRecommendationServiceProvider);
        final firstPage = await service.getRankedEventsPage(
          request: arg,
          bypassCache: true,
        );
        _lastPage = firstPage;

        return ExplorePaginatedFeedState(
          items: _withLiveParticipationState(firstPage.items),
          hasMore: firstPage.hasMore,
          isLoadingMore: false,
          isRefreshing: false,
        );
      }));
      return;
    }

    _setStateSafely(AsyncData(current.copyWith(isRefreshing: true)));
    try {
      final service = ref.read(exploreRecommendationServiceProvider);
      final firstPage = await service.getRankedEventsPage(
        request: arg,
        bypassCache: true,
      );
      _lastPage = firstPage;

      _setStateSafely(AsyncData(
        ExplorePaginatedFeedState(
          items: _withLiveParticipationState(firstPage.items),
          hasMore: firstPage.hasMore,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      ));
    } catch (_) {
      _setStateSafely(AsyncData(current.copyWith(isRefreshing: false)));
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _loadingMore) return;

    _loadingMore = true;
    _setStateSafely(AsyncData(current.copyWith(isLoadingMore: true)));

    try {
      final service = ref.read(exploreRecommendationServiceProvider);
      final nextPage = await service.getRankedEventsPage(
        request: arg,
        startAfterDocument: _lastPage?.lastDocument,
        bypassCache: true,
      );

      _lastPage = nextPage;
      final mergedItems = _mergeByEventId(
        current.items,
        _withLiveParticipationState(nextPage.items),
      );

      _setStateSafely(AsyncData(
        current.copyWith(
          items: mergedItems,
          hasMore: nextPage.hasMore,
          isLoadingMore: false,
          isRefreshing: false,
        ),
      ));
    } catch (_) {
      _setStateSafely(AsyncData(current.copyWith(isLoadingMore: false)));
    } finally {
      _loadingMore = false;
    }
  }

  List<RankedExploreEvent> _mergeByEventId(
    List<RankedExploreEvent> existing,
    List<RankedExploreEvent> incoming,
  ) {
    final byId = <String, RankedExploreEvent>{
      for (final item in existing) item.eventId: item,
    };

    for (final item in incoming) {
      byId[item.eventId] = item;
    }

    return byId.values.toList(growable: false);
  }
}
