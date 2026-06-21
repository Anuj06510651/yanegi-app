// ignore_for_file: depend_on_referenced_packages

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yanegi/services/user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // UserService's default-constructed dependencies transitively touch
  // FirebaseFirestore.instance, which needs a Firebase app to exist. Mock the
  // core platform so construction succeeds. Test-only; no production impact.
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('UserService username identity rules', () {
    test('blocks duplicate username owned by another user', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'user_1', email: 'u1@example.com'),
      );

      final service = UserService(firestore: firestore, auth: auth);

      await firestore.collection('users').doc('user_1').set({
        'userId': 'user_1',
        'name': 'User 1',
        'username': 'oldname',
        'usernameLower': 'oldname',
        'usernameEditCount': 0,
      });

      await firestore.collection('users').doc('user_2').set({
        'userId': 'user_2',
        'name': 'User 2',
        'username': 'takenname',
        'usernameLower': 'takenname',
      });

      await expectLater(
        () => service.updateProfileFields(
          name: 'User 1',
          username: 'takenname',
          bio: 'Bio',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Username taken',
          ),
        ),
      );
    });

    test('blocks username changes after 2 edits within the same month',
        () async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'user_1', email: 'u1@example.com'),
      );

      final service = UserService(firestore: firestore, auth: auth);

      await firestore.collection('users').doc('user_1').set({
        'userId': 'user_1',
        'name': 'User 1',
        'username': 'starter',
        'usernameLower': 'starter',
        'usernameEditCount': 2,
        'lastEditTime': Timestamp.fromDate(
          DateTime.now().toUtc().subtract(const Duration(days: 1)),
        ),
      });

      await expectLater(
        () => service.updateProfileFields(
          name: 'User 1',
          username: 'thirdchange',
          bio: 'Bio',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Limit reached',
          ),
        ),
      );
    });
  });
}
