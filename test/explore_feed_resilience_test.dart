import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yanegi/controllers/filter_controller.dart';
import 'package:yanegi/models/ranked_explore_event.dart';
import 'package:yanegi/providers/explore_feed_provider.dart';
import 'package:yanegi/services/explore_recommendation_service.dart';

void main() {
  group('ExploreRecommendationService resilience', () {
    test('returns empty list when events are missing/invalid location data',
        () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u_explore_1'),
      );
      final service = ExploreRecommendationService(
        firestore: firestore,
        auth: auth,
      );

      final now = DateTime.now().add(const Duration(hours: 2));
      await firestore.collection('events').doc('bad_event').set({
        'status': 'active',
        'isActive': true,
        'visibility': 'public',
        'startAt': Timestamp.fromDate(now),
        'title': 'Broken Coordinates',
        'location': {
          'lat': 999,
          'lng': 999,
        },
      });

      final page = await service.getRankedEventsPage(
        request: ExploreFeedRequest(
          filter: FilterModel(),
          userLocation: const LatLng(28.61, 77.20),
        ),
      );

      expect(page.items, isEmpty);
    });
  });

  group('ExplorePaginatedFeedController resilience', () {
    test('keeps existing items when refresh fails', () async {
      final service = _StubExploreService(
        initialPage: _page(
          items: [_event('event_1')],
          hasMore: true,
        ),
      )..throwOnGet = true;

      final request = ExploreFeedRequest(
        filter: FilterModel(),
        userLocation: const LatLng(28.61, 77.20),
      );

      final container = ProviderContainer(
        overrides: [
          exploreRecommendationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      final initial =
          await container.read(explorePaginatedFeedProvider(request).future);
      expect(initial.items, hasLength(1));

      await container
          .read(explorePaginatedFeedProvider(request).notifier)
          .refreshFeed();

      final state = container.read(explorePaginatedFeedProvider(request));
      expect(state.hasValue, true);
      expect(state.value!.items, hasLength(1));
      expect(state.value!.isRefreshing, false);
    });

    test('loadMore completes safely even if provider is disposed mid-flight',
        () async {
      final delayedPageCompleter = Completer<ExploreFeedPage>();
      final service = _StubExploreService(
        initialPage: _page(
          items: [_event('event_1')],
          hasMore: true,
        ),
        delayedGetPage: delayedPageCompleter.future,
      );

      final request = ExploreFeedRequest(
        filter: FilterModel(),
        userLocation: const LatLng(28.61, 77.20),
      );

      final container = ProviderContainer(
        overrides: [
          exploreRecommendationServiceProvider.overrideWithValue(service),
        ],
      );

      await container.read(explorePaginatedFeedProvider(request).future);

      final loadMoreFuture = container
          .read(explorePaginatedFeedProvider(request).notifier)
          .loadMore();

      container.dispose();
      delayedPageCompleter.complete(
        _page(items: [_event('event_2')], hasMore: false),
      );

      await expectLater(loadMoreFuture, completes);
    });
  });
}

class _StubExploreService extends ExploreRecommendationService {
  _StubExploreService({
    required this.initialPage,
    this.delayedGetPage,
  }) : super(
          firestore: FakeFirebaseFirestore(),
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: 'stub_uid'),
          ),
        );

  final ExploreFeedPage initialPage;
  final Future<ExploreFeedPage>? delayedGetPage;
  bool throwOnGet = false;

  @override
  Stream<ExploreFeedPage> watchRankedEventsPage({
    required ExploreFeedRequest request,
    int limit = 20,
  }) async* {
    yield initialPage;
  }

  @override
  Future<ExploreFeedPage> getRankedEventsPage({
    required ExploreFeedRequest request,
    DocumentSnapshot<Map<String, dynamic>>? startAfterDocument,
    int limit = 20,
    bool bypassCache = false,
  }) async {
    if (throwOnGet) {
      throw StateError('simulated network failure');
    }

    if (startAfterDocument != null && delayedGetPage != null) {
      return delayedGetPage!;
    }

    return initialPage;
  }
}

ExploreFeedPage _page({
  required List<RankedExploreEvent> items,
  required bool hasMore,
}) {
  return ExploreFeedPage(
    items: items,
    lastDocument: null,
    hasMore: hasMore,
  );
}

RankedExploreEvent _event(String id) {
  return RankedExploreEvent(
    eventId: id,
    title: 'Event $id',
    hostId: 'host_1',
    thumbnailUrl: null,
    bannerUrl: null,
    avatarUrl: null,
    location: const LatLng(28.61, 77.20),
    participantsCount: 1,
    maxParticipants: 10,
    vibes: const <String>[],
    categories: const <String>[],
    createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    eventTime: DateTime.now().add(const Duration(hours: 4)),
    visibility: 'public',
    isPublic: true,
    isApprovalRequired: false,
    participantIds: const <String>[],
    hostName: 'Host',
    locationName: 'City',
    friendJoined: false,
    friendHost: false,
    distanceKm: 1,
    score: 20,
  );
}
