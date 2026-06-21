import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yanegi/services/user_presence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserPresenceService', () {
    test('marks user online on start', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'presence_u1', email: 'presence@test.dev'),
      );

      final service = UserPresenceService(
        firestore: firestore,
        auth: auth,
        heartbeatInterval: const Duration(seconds: 1),
      );
      addTearDown(service.stop);

      await service.start();

      final userDoc =
          await firestore.collection('users').doc('presence_u1').get();
      expect(userDoc.data()?['isOnline'], true);
    });

    test('marks user offline with lastSeen on background', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'presence_u2', email: 'presence2@test.dev'),
      );

      final service = UserPresenceService(
        firestore: firestore,
        auth: auth,
        heartbeatInterval: const Duration(seconds: 1),
      );
      addTearDown(service.stop);

      await service.start();
      service.handleLifecycleStateForTest(AppLifecycleState.paused);

      final userDoc =
          await firestore.collection('users').doc('presence_u2').get();
      final data = userDoc.data() ?? const <String, dynamic>{};

      expect(data['isOnline'], false);
      expect(data.containsKey('lastSeen'), true);
    });
  });
}
