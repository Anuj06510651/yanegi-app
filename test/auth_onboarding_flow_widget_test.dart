import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/onboarding/app_entry.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';
import 'package:yanegi/onboarding/screens/name_username_screen.dart';
import 'package:yanegi/services/auth_flow_service.dart';

void main() {
  group('Authentication + onboarding flow (widget/integration-style)', () {
    late FakeFirebaseFirestore firestore;
    late MockUser mockUser;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      mockUser = MockUser(
        uid: 'uid-123',
        email: 'user@example.com',
        displayName: 'Test User',
      );
      auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);
    });

    testWidgets(
      '1) EXISTING USER FLOW: loads map directly for completed profile',
      (tester) async {
        await firestore.collection('users').doc(mockUser.uid).set({
          'uid': mockUser.uid,
          'hasCompletedProfile': true,
        });

        await tester.pumpWidget(
          _buildTestApp(
            auth: auth,
            firestore: firestore,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('map-page')), findsOneWidget);
        expect(find.byKey(const Key('step-username')), findsNothing);
      },
    );

    testWidgets(
      '2a) NEW USER FLOW: missing user doc opens onboarding first step',
      (tester) async {
        await tester.pumpWidget(
          _buildTestApp(
            auth: auth,
            firestore: firestore,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('step-username')), findsOneWidget);
        expect(find.byKey(const Key('map-page')), findsNothing);
      },
    );

    testWidgets(
      '2b) NEW USER FLOW: incomplete profile opens onboarding route',
      (tester) async {
        await firestore.collection('users').doc(mockUser.uid).set({
          'uid': mockUser.uid,
          'hasCompletedProfile': false,
          'name': '',
          'username': '',
        });

        await tester.pumpWidget(
          _buildTestApp(
            auth: auth,
            firestore: firestore,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('step-username')), findsOneWidget);
        expect(find.byKey(const Key('map-page')), findsNothing);
      },
    );

    testWidgets(
      '3a) ONBOARDING STEP CONTROL: save success (step state update) advances to next step',
      (tester) async {
        await firestore.collection('users').doc(mockUser.uid).set({
          'uid': mockUser.uid,
          'hasCompletedProfile': false,
          'name': 'Test User',
          'username': 'testuser',
        });

        await tester.pumpWidget(
          _buildTestApp(
            auth: auth,
            firestore: firestore,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('step-demographics')), findsOneWidget);

        await firestore.collection('users').doc(mockUser.uid).set({
          'hasCompletedProfile': false,
        }, SetOptions(merge: true));

        await tester.pumpAndSettle();
        expect(find.byKey(const Key('step-demographics')), findsOneWidget);
      },
    );

    testWidgets(
      '3b) ONBOARDING STEP CONTROL: save failure stays on same step and shows error',
      (tester) async {
        final screen = MaterialApp(
          home: NameUsernameScreen(
            data: OnboardingData(),
            authFlowService: _FailingAuthFlowService(),
          ),
        );

        await tester.pumpWidget(screen);
        await tester.pumpAndSettle();

        expect(find.text("What's your name?"), findsOneWidget);

        await tester.enterText(find.byType(TextField).at(0), 'Tester');
        await tester.enterText(find.byType(TextField).at(1), 'tester123');
        await tester.pump();
        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not save this step. Please retry.'),
          findsWidgets,
        );
        expect(find.text("What's your name?"), findsOneWidget);
      },
    );

    testWidgets(
      '4) STARTUP RESOLUTION: shows loading first, then routes correctly',
      (tester) async {
        await firestore.collection('users').doc(mockUser.uid).set({
          'uid': mockUser.uid,
          'hasCompletedProfile': true,
        });

        await tester.pumpWidget(
          _buildTestApp(
            auth: auth,
            firestore: firestore,
          ),
        );

        expect(find.byKey(const Key('loading-state')), findsOneWidget);
        expect(find.byKey(const Key('map-page')), findsNothing);
        expect(find.byKey(const Key('step-username')), findsNothing);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byKey(const Key('map-page')), findsOneWidget);
        expect(find.byKey(const Key('step-username')), findsNothing);
      },
    );

    testWidgets(
      '5) APP RESTART TEST: completed user always lands on map without onboarding repeat',
      (tester) async {
        await firestore.collection('users').doc(mockUser.uid).set({
          'uid': mockUser.uid,
          'hasCompletedProfile': true,
        });

        await tester.pumpWidget(
          _buildTestApp(
            auth: auth,
            firestore: firestore,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('map-page')), findsOneWidget);
        expect(find.byKey(const Key('step-username')), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          _buildTestApp(
            auth: auth,
            firestore: firestore,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('map-page')), findsOneWidget);
        expect(find.byKey(const Key('step-username')), findsNothing);
      },
    );

    testWidgets(
      '6) NAVIGATION STABILITY: cached decision does not reroute on rebuild',
      (tester) async {
        final observer = _CountingNavigatorObserver();

        await firestore.collection('users').doc(mockUser.uid).set({
          'uid': mockUser.uid,
          'hasCompletedProfile': true,
        });

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: AuthWrapper(
              auth: auth,
              firestore: firestore,
              requireFirebaseInitialization: false,
              authStateChangesBuilder: (_) =>
                  Stream<User?>.value(auth.currentUser),
              onboardingStepBuilder: (step, _) => _ScreenMarker('step-$step'),
              mapPageBuilder: (_) => const _ScreenMarker('map-page'),
              loadingBuilder: (_) => const _ScreenMarker('loading-state'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialPushCount = observer.pushCount;
        expect(find.byKey(const Key('map-page')), findsOneWidget);

        await firestore.collection('users').doc(mockUser.uid).set({
          'hasCompletedProfile': false,
          'name': '',
          'username': '',
        }, SetOptions(merge: true));

        await tester.pump();

        expect(observer.pushCount, initialPushCount);
        expect(find.byKey(const Key('map-page')), findsOneWidget);
        expect(find.byKey(const Key('step-username')), findsNothing);

        final didRebootstrap = AuthBootstrapperController.rebootstrap(
          resetNavigation: false,
        );
        expect(didRebootstrap, isTrue);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(observer.pushCount, initialPushCount);
        expect(find.byKey(const Key('map-page')), findsNothing);
        expect(find.byKey(const Key('step-username')), findsOneWidget);

        final mapCount = find.byKey(const Key('map-page')).evaluate().length;
        final onboardingCount =
            find.byKey(const Key('step-username')).evaluate().length;
        expect(mapCount + onboardingCount, 1);
      },
    );
  });
}

Widget _buildTestApp({
  required FirebaseAuth auth,
  required FirebaseFirestore firestore,
}) {
  return MaterialApp(
    home: AuthWrapper(
      auth: auth,
      firestore: firestore,
      requireFirebaseInitialization: false,
      authStateChangesBuilder: (_) => Stream<User?>.value(auth.currentUser),
      onboardingStepBuilder: (step, _) => _ScreenMarker('step-$step'),
      mapPageBuilder: (_) => const _ScreenMarker('map-page'),
      loadingBuilder: (_) => const _ScreenMarker('loading-state'),
    ),
  );
}

class _ScreenMarker extends StatelessWidget {
  const _ScreenMarker(this.marker);

  final String marker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          marker,
          key: Key(marker),
        ),
      ),
    );
  }
}

class _CountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

class _AlwaysAvailableAuthFlowService extends AuthFlowService {
  _AlwaysAvailableAuthFlowService();

  @override
  Future<bool> isUsernameAvailable(
    String username, {
    String? exceptUserId,
  }) async {
    return true;
  }
}

class _FailingAuthFlowService extends _AlwaysAvailableAuthFlowService {
  @override
  Future<void> completeProfile({
    required String name,
    required String username,
  }) {
    throw StateError('forced save failure');
  }
}
