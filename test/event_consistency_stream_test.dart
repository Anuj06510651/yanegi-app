import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:yanegi/controllers/filter_controller.dart';
import 'package:yanegi/models/event_model.dart';
import 'package:yanegi/services/explore_recommendation_service.dart';

void main() {
  group('Event consistency across explore/map/event-detail source', () {
    test('update event reflects through explore stream', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u1'),
      );

      final service = ExploreRecommendationService(
        firestore: firestore,
        auth: auth,
      );

      final eventRef = firestore.collection('events').doc('event_live');
      await eventRef.set({
        'title': 'Old title',
        'hostId': 'host_1',
        'status': 'active',
        'visibility': 'public',
        'isActive': true,
        'isApprovalRequired': false,
        'participants': ['host_1'],
        'participantsCount': 1,
        'maxCapacity': 10,
        'location': {'lat': 28.6139, 'lng': 77.2090},
        'locationName': 'Delhi',
        'startAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2))),
        'endAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 4))),
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });

      final pages = <ExploreFeedPage>[];
      final updatedSeen = Completer<void>();

      final sub = service
          .watchRankedEventsPage(
        request: ExploreFeedRequest(
          filter: FilterModel(),
          userLocation: const LatLng(28.61, 77.20),
        ),
      )
          .listen((page) {
        pages.add(page);
        final hasUpdatedTitle = page.items.any((item) =>
            item.eventId == 'event_live' && item.title == 'Updated title');
        if (hasUpdatedTitle && !updatedSeen.isCompleted) {
          updatedSeen.complete();
        }
      });

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await eventRef.update({'title': 'Updated title'});

      await updatedSeen.future.timeout(const Duration(seconds: 3));
      await sub.cancel();

      expect(pages, isNotEmpty);
      expect(
        pages.last.items.where((e) => e.eventId == 'event_live').single.title,
        'Updated title',
      );
    });

    test('join update reflects instantly in explore participants count',
        () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u_join'),
      );

      final service = ExploreRecommendationService(
        firestore: firestore,
        auth: auth,
      );

      final eventRef = firestore.collection('events').doc('event_join');
      await eventRef.set({
        'title': 'Join Event',
        'hostId': 'host_2',
        'status': 'active',
        'visibility': 'public',
        'isActive': true,
        'isApprovalRequired': false,
        'participants': ['host_2'],
        'participantsCount': 1,
        'maxCapacity': 10,
        'location': {'lat': 28.6139, 'lng': 77.2090},
        'locationName': 'Delhi',
        'startAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 3))),
        'endAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 5))),
        'createdAt': Timestamp.fromDate(DateTime.now()),
      });

      final participantsUpdated = Completer<void>();
      late final StreamSubscription<ExploreFeedPage> sub;
      sub = service
          .watchRankedEventsPage(
        request: ExploreFeedRequest(
          filter: FilterModel(),
          userLocation: const LatLng(28.61, 77.20),
        ),
      )
          .listen((page) {
        final item = page.items.where((e) => e.eventId == 'event_join');
        if (item.isEmpty) return;
        if (item.single.participantsCount == 2 &&
            !participantsUpdated.isCompleted) {
          participantsUpdated.complete();
        }
      });

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await eventRef.update({
        'participants': ['host_2', 'u_join'],
        'participantsCount': 2,
      });

      await participantsUpdated.future.timeout(const Duration(seconds: 3));
      await sub.cancel();
    });

    test('single event source has no model mismatch', () async {
      final firestore = FakeFirebaseFirestore();
      final eventRef = firestore.collection('events').doc('event_model');
      await eventRef.set({
        'title': 'Unified Event',
        'hostId': 'host_3',
        'status': 'active',
        'visibility': 'public',
        'isActive': true,
        'isApprovalRequired': true,
        'participants': ['host_3'],
        'participantsCount': 1,
        'maxCapacity': 15,
        'location': {'lat': 28.6139, 'lng': 77.2090},
        'locationName': 'Delhi',
        'startAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2))),
        'endAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(hours: 6))),
      });

      final doc = await eventRef.get();
      final model = EventModel.fromFirestore(doc);

      expect(model.id, 'event_model');
      expect(model.title, 'Unified Event');
      expect(model.hostId, 'host_3');
      expect(model.location, isNotNull);
      expect(model.participantsCount, 1);
      expect(model.maxCapacity, 15);
      expect(model.isApprovalRequired, true);
      expect(model.visibility, 'public');
    });
  });
}
