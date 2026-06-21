import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:yanegi/onboarding/auth_bootstrapper.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthBootstrapper();
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({
    super.key,
    this.auth,
    this.firestore,
    this.requireFirebaseInitialization = true,
    this.firebaseInitializer,
    this.authStateChangesBuilder,
    this.onboardingStepBuilder,
    this.mapPageBuilder,
    this.welcomePageBuilder,
    this.loadingBuilder,
  });

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final bool requireFirebaseInitialization;
  final Future<FirebaseApp> Function()? firebaseInitializer;
  final Stream<User?> Function(FirebaseAuth auth)? authStateChangesBuilder;
  final Widget Function(String step, OnboardingData data)?
      onboardingStepBuilder;
  final WidgetBuilder? mapPageBuilder;
  final WidgetBuilder? welcomePageBuilder;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return AuthBootstrapper(
      auth: auth,
      firestore: firestore,
      requireFirebaseInitialization: requireFirebaseInitialization,
      firebaseInitializer: firebaseInitializer,
      authStateChangesBuilder: authStateChangesBuilder,
      onboardingStepBuilder: onboardingStepBuilder,
      mapPageBuilder: mapPageBuilder,
      welcomePageBuilder: welcomePageBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}
