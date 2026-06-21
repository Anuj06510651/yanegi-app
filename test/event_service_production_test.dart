// ignore_for_file: depend_on_referenced_packages

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yanegi/services/event_service.dart';

EventService _serviceFor({
  required String uid,
  required FirebaseFirestore firestore,
  required DateTime now,
}) {
  return EventService(
    firestore: firestore,
    auth: MockFirebaseAuth(mockUser: MockUser(uid: uid), signedIn: true),
    blockCheckOverride: (_, __) async => false,
    nowProvider: () => now,
  );
}

Future<void> _seedUser(FirebaseFirestore firestore, String uid) async {
  await firestore.collection('users').doc(uid).set({
    'name': uid,
    'username': uid,
  });
}

Future<void> _seedEvent({
  required FirebaseFirestore firestore,
  required String eventId,
  required String hostId,
  required DateTime startAt,
  required DateTime endAt,
  required bool isApprovalRequired,
  int maxCapacity = 10,
  int participantsCount = 1,
  String status = EventService.statusActive,
  bool isActive = true,
  List<String>? participants,
  String chatId = 'grp_event_1',
}) async {
  await firestore.collection('events').doc(eventId).set({
    'eventId': eventId,
    'hostId': hostId,
    'title': 'Test Event',
    'description': 'desc',
    'activityType': 'hiking',
    'locationName': 'Park',
    'locationGeoPoint': const GeoPoint(12.0, 77.0),
    'startAt': Timestamp.fromDate(startAt.toUtc()),
    'endAt': Timestamp.fromDate(endAt.toUtc()),
    'participants': participants ?? [hostId],
    'participantsCount': participantsCount,
    'maxCapacity': maxCapacity,
    'visibility': 'public',
    'isApprovalRequired': isApprovalRequired,
    'status': status,
    'isActive': isActive,
    'chatId': chatId,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await firestore.collection('chats').doc(chatId).set({
    'chatId': chatId,
    'eventId': eventId,
    'type': 'group',
    'participantIds': participants ?? [hostId],
    'createdBy': hostId,
    'isActive': true,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  await firestore
      .collection('event_participants')
      .doc(eventId)
      .collection('users')
      .doc(hostId)
      .set({
    'userId': hostId,
    'eventId': eventId,
    'status': 'joined',
    'isVisible': true,
    'joinedAt': FieldValue.serverTimestamp(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // EventService's default-constructed MediaStorageService transitively touches
  // FirebaseFirestore.instance, which requires a Firebase app to exist. Mock the
  // core platform so construction succeeds in the test harness. Test-only; does
  // not affect production behavior.
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('EventService production hardening', () {
    final now = DateTime.utc(2026, 1, 10, 12, 0, 0);

    test('rejects creating event in the past', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      final service =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);

      expect(
        () => service.createEvent(
          title: 'Past Event',
          location: const GeoPoint(12.0, 77.0),
          hostId: 'host_1',
          eventAvatar: '🎯',
          startAt: now.subtract(const Duration(hours: 1)),
          endAt: now.add(const Duration(hours: 1)),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects creating event with negative capacity', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      final service =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);

      expect(
        () => service.createEvent(
          title: 'Invalid Capacity Event',
          location: const GeoPoint(12.0, 77.0),
          hostId: 'host_1',
          eventAvatar: '🎯',
          startAt: now.add(const Duration(hours: 2)),
          endAt: now.add(const Duration(hours: 3)),
          maxCapacity: -5,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects creating event with zero capacity', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      final service =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);

      expect(
        () => service.createEvent(
          title: 'Zero Capacity Event',
          location: const GeoPoint(12.0, 77.0),
          hostId: 'host_1',
          eventAvatar: '🎯',
          startAt: now.add(const Duration(hours: 2)),
          endAt: now.add(const Duration(hours: 3)),
          maxCapacity: 0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('accepts creating event with valid capacity', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      final service =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);

      final eventId = await service.createEvent(
        title: 'Valid Capacity Event',
        location: const GeoPoint(12.0, 77.0),
        hostId: 'host_1',
        eventAvatar: '🎯',
        startAt: now.add(const Duration(hours: 2)),
        endAt: now.add(const Duration(hours: 3)),
        maxCapacity: 10,
      );

      final eventDoc = await firestore.collection('events').doc(eventId).get();
      expect(eventDoc.exists, true);
      expect(eventDoc.data()?['maxCapacity'], 10);
    });

    test('creates canonical event schema with UTC start/end fields', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      final service =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);

      final eventId = await service.createEvent(
        title: 'Morning Run',
        location: const GeoPoint(12.0, 77.0),
        hostId: 'host_1',
        eventAvatar: '🏃',
        startAt: now.add(const Duration(hours: 2)),
        endAt: now.add(const Duration(hours: 4)),
      );

      final eventDoc = await firestore.collection('events').doc(eventId).get();
      final data = eventDoc.data()!;
      expect(data['eventId'], eventId);
      expect(data['hostId'], 'host_1');
      expect(data['status'], EventService.statusActive);
      expect(data['participantsCount'], 1);
      expect(data['startAt'], isA<Timestamp>());
      expect(data['endAt'], isA<Timestamp>());

      final chatId = (data['chatId'] ?? '').toString();
      expect(chatId, isNotEmpty);

      final chatDoc = await firestore.collection('chats').doc(chatId).get();
      expect(chatDoc.exists, true);
      final chatData = chatDoc.data()!;
      expect(chatData['chatId'], chatId);
      expect(chatData['createdBy'], 'host_1');
      expect(List<String>.from(chatData['participantIds'] ?? const <String>[]),
          contains('host_1'));
      expect(chatData.containsKey('adminId'), false);
      expect(chatData.containsKey('participants'), false);
    });

    test('blocks direct join when event is full', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_full',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: false,
        maxCapacity: 1,
        participantsCount: 1,
      );

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);
      expect(
        () => service.addUserToEventAndChat(
            eventId: 'event_full', userId: 'user_2'),
        throwsA(isA<StateError>()),
      );
    });

    test('prevents approval bypass on approval-required events', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_approval',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);
      expect(
        () => service.addUserToEventAndChat(
          eventId: 'event_approval',
          userId: 'user_2',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('prevents duplicate pending join request', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_req',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);
      await service.requestToJoinEvent(eventId: 'event_req', userId: 'user_2');

      expect(
        () =>
            service.requestToJoinEvent(eventId: 'event_req', userId: 'user_2'),
        throwsA(isA<StateError>()),
      );
    });

    test('blocks joining ended event and auto-completes lifecycle/chat',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_ended_join',
        hostId: 'host_1',
        startAt: now.subtract(const Duration(hours: 4)),
        endAt: now.subtract(const Duration(hours: 1)),
        isApprovalRequired: false,
      );

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);
      await expectLater(
        () => service.addUserToEventAndChat(
          eventId: 'event_ended_join',
          userId: 'user_2',
        ),
        throwsA(isA<StateError>()),
      );

      final eventDoc =
          await firestore.collection('events').doc('event_ended_join').get();
      final chatDoc =
          await firestore.collection('chats').doc('grp_event_1').get();
      expect(eventDoc.data()!['status'], EventService.statusCompleted);
      expect(eventDoc.data()!['isActive'], false);
      expect(chatDoc.data()!['isActive'], false);
    });

    test(
        'refreshEventLifecycle marks expired event completed and chat inactive',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_refresh',
        hostId: 'host_1',
        startAt: now.subtract(const Duration(hours: 3)),
        endAt: now.subtract(const Duration(minutes: 5)),
        isApprovalRequired: false,
      );

      final service =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);
      await service.refreshEventLifecycle(eventId: 'event_refresh');

      final eventDoc =
          await firestore.collection('events').doc('event_refresh').get();
      final chatDoc =
          await firestore.collection('chats').doc('grp_event_1').get();
      expect(eventDoc.data()!['status'], EventService.statusCompleted);
      expect(chatDoc.data()!['isActive'], false);
    });

    test('syncEventLifecycle alias auto-completes expired event + chat',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_sync_alias',
        hostId: 'host_1',
        startAt: now.subtract(const Duration(hours: 2)),
        endAt: now.subtract(const Duration(minutes: 10)),
        isApprovalRequired: false,
      );

      final service =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);
      await service.syncEventLifecycle('event_sync_alias');

      final eventDoc =
          await firestore.collection('events').doc('event_sync_alias').get();
      final chatDoc =
          await firestore.collection('chats').doc('grp_event_1').get();

      expect(eventDoc.data()!['status'], EventService.statusCompleted);
      expect(eventDoc.data()!['isActive'], false);
      expect(chatDoc.data()!['isActive'], false);
    });

    test('canonical user state API resolves pending/joined/notJoined',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_joined');
      await _seedUser(firestore, 'user_pending');
      await _seedUser(firestore, 'user_none');

      await _seedEvent(
        firestore: firestore,
        eventId: 'event_state_joined',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 4)),
        isApprovalRequired: true,
      );
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_state_pending',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 4)),
        isApprovalRequired: true,
      );
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_state_none',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 4)),
        isApprovalRequired: true,
      );

      await firestore
          .collection('event_participants')
          .doc('event_state_joined')
          .collection('users')
          .doc('user_joined')
          .set({
        'userId': 'user_joined',
        'eventId': 'event_state_joined',
        'status': 'joined',
      });

      await firestore
          .collection('event_participants')
          .doc('event_state_pending')
          .collection('users')
          .doc('user_pending')
          .set({
        'eventId': 'event_state_pending',
        'userId': 'user_pending',
        'status': 'pending',
      });

      final joinedService =
          _serviceFor(uid: 'user_joined', firestore: firestore, now: now);
      final pendingService =
          _serviceFor(uid: 'user_pending', firestore: firestore, now: now);
      final noneService =
          _serviceFor(uid: 'user_none', firestore: firestore, now: now);

      expect(
        await joinedService.getUserEventState(
          userId: 'user_joined',
          eventId: 'event_state_joined',
        ),
        UserEventState.joined,
      );

      expect(
        await pendingService.getUserEventState(
          userId: 'user_pending',
          eventId: 'event_state_pending',
        ),
        UserEventState.pending,
      );

      expect(
        await noneService.getUserEventState(
          userId: 'user_none',
          eventId: 'event_state_none',
        ),
        UserEventState.notJoined,
      );
    });

    test('batch user states stay consistent with single-event resolver',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');

      await _seedEvent(
        firestore: firestore,
        eventId: 'event_batch_joined',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 2)),
        endAt: now.add(const Duration(hours: 5)),
        isApprovalRequired: true,
      );
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_batch_pending',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 2)),
        endAt: now.add(const Duration(hours: 5)),
        isApprovalRequired: true,
      );
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_batch_none',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 2)),
        endAt: now.add(const Duration(hours: 5)),
        isApprovalRequired: true,
      );

      await firestore
          .collection('event_participants')
          .doc('event_batch_joined')
          .collection('users')
          .doc('user_2')
          .set({
        'userId': 'user_2',
        'eventId': 'event_batch_joined',
        'status': 'joined',
      });
      await firestore
          .collection('event_participants')
          .doc('event_batch_pending')
          .collection('users')
          .doc('user_2')
          .set({
        'eventId': 'event_batch_pending',
        'userId': 'user_2',
        'status': 'pending',
      });

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);
      final batchStates = await service.getUserEventStatesForEvents(
        userId: 'user_2',
        eventIds: const [
          'event_batch_joined',
          'event_batch_pending',
          'event_batch_none',
        ],
      );

      expect(
        batchStates['event_batch_joined'],
        await service.getUserEventState(
          userId: 'user_2',
          eventId: 'event_batch_joined',
        ),
      );
      expect(
        batchStates['event_batch_pending'],
        await service.getUserEventState(
          userId: 'user_2',
          eventId: 'event_batch_pending',
        ),
      );
      expect(
        batchStates['event_batch_none'],
        await service.getUserEventState(
          userId: 'user_2',
          eventId: 'event_batch_none',
        ),
      );
    });

    test(
        'fetchAllUserEventStates returns one consistent map and reflects transitions',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');

      await _seedEvent(
        firestore: firestore,
        eventId: 'event_fetch_joined',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_fetch_pending',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );

      await firestore
          .collection('event_participants')
          .doc('event_fetch_joined')
          .collection('users')
          .doc('user_2')
          .set({
        'eventId': 'event_fetch_joined',
        'userId': 'user_2',
        'status': 'joined',
      });

      await firestore
          .collection('event_participants')
          .doc('event_fetch_pending')
          .collection('users')
          .doc('user_2')
          .set({
        'eventId': 'event_fetch_pending',
        'userId': 'user_2',
        'status': 'pending',
      });

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);

      final firstMap = await service.fetchAllUserEventStates('user_2');
      expect(firstMap['event_fetch_joined'], UserEventState.joined);
      expect(firstMap['event_fetch_pending'], UserEventState.pending);

      await firestore
          .collection('event_participants')
          .doc('event_fetch_pending')
          .collection('users')
          .doc('user_2')
          .set({'status': 'joined'}, SetOptions(merge: true));

      final secondMap = await service.fetchAllUserEventStates('user_2');
      expect(secondMap['event_fetch_pending'], UserEventState.joined);
    });

    test('realtime membership stream reflects pending -> joined transition',
        () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_stream_sync',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);

      await firestore
          .collection('event_participants')
          .doc('event_stream_sync')
          .collection('users')
          .doc('user_2')
          .set({
        'eventId': 'event_stream_sync',
        'userId': 'user_2',
        'status': 'pending',
      });

      final pendingSnapshot = await service
          .watchUserEventMembership(userId: 'user_2')
          .firstWhere((snapshot) =>
              snapshot.pendingEventIds.contains('event_stream_sync'))
          .timeout(const Duration(seconds: 2));
      expect(pendingSnapshot.pendingEventIds, contains('event_stream_sync'));

      await firestore
          .collection('event_participants')
          .doc('event_stream_sync')
          .collection('users')
          .doc('user_2')
          .set({
        'userId': 'user_2',
        'eventId': 'event_stream_sync',
        'status': 'joined',
      });

      final joinedSnapshot = await service
          .watchUserEventMembership(userId: 'user_2')
          .firstWhere(
            (snapshot) =>
                snapshot.joinedEventIds.contains('event_stream_sync') &&
                !snapshot.pendingEventIds.contains('event_stream_sync'),
          )
          .timeout(const Duration(seconds: 2));

      expect(joinedSnapshot.joinedEventIds, contains('event_stream_sync'));
      expect(
          joinedSnapshot.pendingEventIds, isNot(contains('event_stream_sync')));
    });

    test('watchUserEventState and host shortcut stay consistent', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_screen_consistency',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );

      final service =
          _serviceFor(uid: 'user_2', firestore: firestore, now: now);

      await firestore
          .collection('event_participants')
          .doc('event_screen_consistency')
          .collection('users')
          .doc('user_2')
          .set({
        'eventId': 'event_screen_consistency',
        'userId': 'user_2',
        'status': 'pending',
      });

      final streamState = await service
          .watchUserEventState(
            userId: 'user_2',
            eventId: 'event_screen_consistency',
            hostId: 'host_1',
          )
          .firstWhere((state) => state == UserEventState.pending)
          .timeout(const Duration(seconds: 2));

      final singleState = await service.getUserEventState(
        userId: 'user_2',
        eventId: 'event_screen_consistency',
      );
      final batchState = (await service.getUserEventStatesForEvents(
        userId: 'user_2',
        eventIds: const ['event_screen_consistency'],
      ))['event_screen_consistency'];

      expect(streamState, UserEventState.pending);
      expect(singleState, UserEventState.pending);
      expect(batchState, UserEventState.pending);

      final hostState = await service
          .watchUserEventState(
            userId: 'host_1',
            eventId: 'event_screen_consistency',
            hostId: 'host_1',
          )
          .first
          .timeout(const Duration(seconds: 2));
      expect(hostState, UserEventState.joined);
    });

    test('only host can approve join request', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedUser(firestore, 'user_3');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_host_approve',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );
      await firestore
          .collection('event_requests')
          .doc('event_host_approve_user_2')
          .set({
        'eventId': 'event_host_approve',
        'userId': 'user_2',
        'senderId': 'user_2',
        'hostId': 'host_1',
        'status': 'pending',
      });

      final nonHostService =
          _serviceFor(uid: 'user_3', firestore: firestore, now: now);
      await expectLater(
        () => nonHostService.approveJoinRequest(
          eventId: 'event_host_approve',
          requesterUserId: 'user_2',
        ),
        throwsA(isA<StateError>()),
      );

      final hostService =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);
      await hostService.approveJoinRequest(
        eventId: 'event_host_approve',
        requesterUserId: 'user_2',
      );

      final requestDoc = await firestore
          .collection('event_requests')
          .doc('event_host_approve_user_2')
          .get();
      final participantDoc = await firestore
          .collection('event_participants')
          .doc('event_host_approve')
          .collection('users')
          .doc('user_2')
          .get();
      final eventDoc =
          await firestore.collection('events').doc('event_host_approve').get();

      expect(requestDoc.data()!['status'], 'accepted');
      expect(participantDoc.data()!['status'], 'active');
      expect(List<String>.from(eventDoc.data()!['participants']),
          contains('user_2'));
    });

    test('only host can reject join request', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedUser(firestore, 'user_3');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_host_reject',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );
      await firestore
          .collection('event_requests')
          .doc('event_host_reject_user_2')
          .set({
        'eventId': 'event_host_reject',
        'userId': 'user_2',
        'senderId': 'user_2',
        'hostId': 'host_1',
        'status': 'pending',
      });

      final nonHostService =
          _serviceFor(uid: 'user_3', firestore: firestore, now: now);
      await expectLater(
        () => nonHostService.rejectJoinRequest(
          eventId: 'event_host_reject',
          requesterUserId: 'user_2',
        ),
        throwsA(isA<StateError>()),
      );

      final hostService =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);
      await hostService.rejectJoinRequest(
        eventId: 'event_host_reject',
        requesterUserId: 'user_2',
      );

      final requestDoc = await firestore
          .collection('event_requests')
          .doc('event_host_reject_user_2')
          .get();
      expect(requestDoc.data()!['status'], 'rejected');
    });

    test('soft delete closes event, chat, participants and requests', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedUser(firestore, 'host_1');
      await _seedUser(firestore, 'user_2');
      await _seedEvent(
        firestore: firestore,
        eventId: 'event_delete',
        hostId: 'host_1',
        startAt: now.add(const Duration(hours: 1)),
        endAt: now.add(const Duration(hours: 3)),
        isApprovalRequired: true,
      );

      await firestore
          .collection('event_participants')
          .doc('event_delete')
          .collection('users')
          .doc('user_2')
          .set({
        'userId': 'user_2',
        'eventId': 'event_delete',
        'status': 'joined',
      });
      await firestore
          .collection('event_requests')
          .doc('event_delete_user_2')
          .set({
        'eventId': 'event_delete',
        'userId': 'user_2',
        'hostId': 'host_1',
        'status': 'pending',
      });

      final hostService =
          _serviceFor(uid: 'host_1', firestore: firestore, now: now);
      await hostService.softDeleteEvent(
          eventId: 'event_delete', hostId: 'host_1');

      final eventDoc =
          await firestore.collection('events').doc('event_delete').get();
      final chatDoc =
          await firestore.collection('chats').doc('grp_event_1').get();
      final participantDoc = await firestore
          .collection('event_participants')
          .doc('event_delete')
          .collection('users')
          .doc('user_2')
          .get();
      final requestDoc = await firestore
          .collection('event_requests')
          .doc('event_delete_user_2')
          .get();

      expect(eventDoc.data()!['status'], EventService.statusDeleted);
      expect(chatDoc.data()!['isActive'], false);
      expect(participantDoc.data()!['status'], 'removed');
      expect(requestDoc.data()!['status'], 'cancelled');
    });
  });
}
