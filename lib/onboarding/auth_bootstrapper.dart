import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:yanegi/auth/screens/map_page.dart';
import 'package:yanegi/firebase_options.dart';
import 'package:yanegi/onboarding/model/onboarding_data.dart';
import 'package:yanegi/onboarding/screens/avatar_upload_screen.dart';
import 'package:yanegi/onboarding/screens/bio_screen.dart';
import 'package:yanegi/onboarding/screens/demographics_screen.dart';
import 'package:yanegi/onboarding/screens/name_username_screen.dart';
import 'package:yanegi/onboarding/screens/vibe_tags_screen.dart';
import 'package:yanegi/onboarding/screens/welcome_screen.dart';
import 'package:yanegi/models/user_profile.dart';
import 'package:yanegi/services/local_profile_cache.dart';
import 'package:yanegi/services/user_service.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

class AuthBootstrapperController {
  AuthBootstrapperController._();

  static _AuthBootstrapperState? _activeState;

  static bool rebootstrap({
    BuildContext? navigationContext,
    bool resetNavigation = true,
  }) {
    final state = _activeState;
    if (state == null || !state.mounted) return false;

    state.rebootstrap(
      navigationContext: navigationContext,
      resetNavigation: resetNavigation,
    );
    return true;
  }

  static void _attach(_AuthBootstrapperState state) {
    _activeState = state;
  }

  static void _detach(_AuthBootstrapperState state) {
    if (identical(_activeState, state)) {
      _activeState = null;
    }
  }
}

class AuthBootstrapper extends StatefulWidget {
  const AuthBootstrapper({
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
  State<AuthBootstrapper> createState() => _AuthBootstrapperState();
}

enum _BootstrapPhase { resolving, resolved, failed }

enum _BootstrapDestination { welcome, onboarding, map }

class _AuthBootstrapperState extends State<AuthBootstrapper> {
  _BootstrapPhase _phase = _BootstrapPhase.resolving;
  _BootstrapDecision? _decision;
  Object? _error;
  int _generation = 0;

  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    AuthBootstrapperController._attach(this);
    _startBootstrap();
  }

  @override
  void dispose() {
    AuthBootstrapperController._detach(this);
    super.dispose();
  }

  void rebootstrap({
    BuildContext? navigationContext,
    bool resetNavigation = true,
  }) {
    if (resetNavigation && navigationContext != null) {
      try {
        Navigator.of(navigationContext, rootNavigator: true).popUntil(
          (route) => route.isFirst,
        );
      } catch (_) {
        // Some widget tests mount auth screens without a root navigator.
      }
    }

    setState(_setResolving);
    _startBootstrap();
  }

  void _setResolving() {
    _phase = _BootstrapPhase.resolving;
    _decision = null;
    _error = null;
  }

  void _startBootstrap() {
    final generation = ++_generation;

    unawaited(
      _resolveStartup().then(
        (decision) {
          if (!mounted || generation != _generation) return;
          setState(() {
            _phase = _BootstrapPhase.resolved;
            _decision = decision;
            _error = null;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!mounted || generation != _generation) return;
          debugPrint('AUTH BOOTSTRAP ERROR: $error');
          debugPrintStack(stackTrace: stackTrace);
          setState(() {
            _phase = _BootstrapPhase.failed;
            _decision = null;
            _error = error;
          });
        },
      ),
    );
  }

  Future<_BootstrapDecision> _resolveStartup() async {
    debugPrint('AUTH BOOTSTRAP: firebase init check');
    await _ensureFirebaseInitialized();

    debugPrint('AUTH BOOTSTRAP: waiting for auth restore');
    final user = await _restoredAuthUser();
    debugPrint('AUTH BOOTSTRAP: restored uid = ${user?.uid}');

    if (user == null) {
      return const _BootstrapDecision(_BootstrapDestination.welcome);
    }

    // Fast-path: local Hive cache already knows the user completed onboarding.
    // Route immediately and refresh the server doc in the background so the
    // cache stays current for the next launch.
    final cachedHasCompleted = LocalProfileCache.loadHasCompleted(user.uid);
    if (cachedHasCompleted == true) {
      debugPrint('AUTH BOOTSTRAP: cache hit — routing to map instantly');
      _refreshUserDocInBackground(user.uid);
      return const _BootstrapDecision(_BootstrapDestination.map);
    }

    debugPrint('AUTH BOOTSTRAP: cache miss — fetching from server');
    final userDoc = await _fetchUserDocument(user.uid);
    final userData = userDoc.data();

    if (!userDoc.exists) {
      debugPrint('AUTH BOOTSTRAP: creating missing user doc before routing');
      await UserService(
        firestore: _firestore,
        auth: _auth,
      ).createOrGetUser(
        uid: user.uid,
        email: user.email,
        authProvider: _primaryProviderId(user),
      );

      return _BootstrapDecision(
        _BootstrapDestination.onboarding,
        onboardingStep: OnboardingData.stepUsername,
        onboardingData: _buildOnboardingData(null),
      );
    }

    final hasCompletedProfile = userData?['hasCompletedProfile'] == true;
    debugPrint(
      'AUTH BOOTSTRAP: hasCompletedProfile = $hasCompletedProfile',
    );

    // Persist the freshly-fetched profile to the local cache so the next cold
    // start can render display fields instantly while Firestore refreshes in
    // the background. Routing is unaffected by this write.
    LocalProfileCache.save(
      UserProfile.fromMap(userData ?? const <String, dynamic>{}, user.uid),
      hasCompletedProfile: hasCompletedProfile,
    );

    if (hasCompletedProfile) {
      return const _BootstrapDecision(_BootstrapDestination.map);
    }

    final step = _inferOnboardingStep(userData);
    return _BootstrapDecision(
      _BootstrapDestination.onboarding,
      onboardingStep: step,
      onboardingData: _buildOnboardingData(userData),
    );
  }

  void _refreshUserDocInBackground(String uid) {
    unawaited(
      _fetchUserDocument(uid).then((doc) {
        if (!doc.exists) return;
        final data = doc.data();
        LocalProfileCache.save(
          UserProfile.fromMap(data ?? const <String, dynamic>{}, uid),
          hasCompletedProfile: data?['hasCompletedProfile'] == true,
        );
        debugPrint('AUTH BOOTSTRAP: background profile refresh complete');
      }).catchError((Object _) {}),
    );
  }

  Future<void> _ensureFirebaseInitialized() async {
    if (!widget.requireFirebaseInitialization) return;
    if (Firebase.apps.isNotEmpty) return;

    final initializer = widget.firebaseInitializer;
    if (initializer != null) {
      await initializer();
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<User?> _restoredAuthUser() {
    final auth = _auth;
    final authStream =
        widget.authStateChangesBuilder?.call(auth) ?? auth.authStateChanges();
    return authStream.first;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchUserDocument(
    String uid,
  ) async {
    final ref = _firestore.collection('users').doc(uid);

    try {
      return await ref.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable' && error.code != 'deadline-exceeded') {
        rethrow;
      }

      debugPrint(
        'AUTH BOOTSTRAP: server profile fetch unavailable, using cache',
      );
      return ref.get(const GetOptions(source: Source.cache));
    }
  }

  OnboardingData _buildOnboardingData(Map<String, dynamic>? userData) {
    final data = OnboardingData();

    data.name = (userData?['name'] as String?)?.trim();
    data.username = (userData?['username'] as String?)?.trim();
    data.gender = (userData?['gender'] as String?)?.trim();

    final rawDob = userData?['dob'];
    if (rawDob is String && rawDob.trim().isNotEmpty) {
      data.dob = DateTime.tryParse(rawDob);
    }

    data.vibes = ((userData?['vibes'] as List?) ?? const <dynamic>[])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();

    data.bio = (userData?['bio'] as String?)?.trim();
    data.avatarPath = _firstNonEmptyString([
      userData?['photoUrl'],
      userData?['avatarUrl'],
      userData?['avatar_url'],
      userData?['profileImage'],
      userData?['profile_image'],
    ]);

    return data;
  }

  String _inferOnboardingStep(Map<String, dynamic>? userData) {
    final hasName = (userData?['name'] as String?)?.trim().isNotEmpty == true;
    final hasUsername =
        (userData?['username'] as String?)?.trim().isNotEmpty == true;
    if (!(hasName && hasUsername)) {
      return OnboardingData.stepUsername;
    }

    final hasGender =
        (userData?['gender'] as String?)?.trim().isNotEmpty == true;
    final hasDob = (userData?['dob'] as String?)?.trim().isNotEmpty == true;
    if (!(hasGender && hasDob)) {
      return OnboardingData.stepDemographics;
    }

    final hasVibes = ((userData?['vibes'] as List?) ?? const <dynamic>[])
            .where((e) => e.toString().trim().isNotEmpty)
            .length >=
        3;
    if (!hasVibes) {
      return OnboardingData.stepVibe;
    }

    final hasBio = (userData?['bio'] as String?)?.trim().isNotEmpty == true;
    if (!hasBio) {
      return OnboardingData.stepBio;
    }

    return OnboardingData.stepPhoto;
  }

  String? _primaryProviderId(User user) {
    if (user.providerData.isEmpty) return null;
    final providerId = user.providerData.first.providerId.trim();
    return providerId.isEmpty ? null : providerId;
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _BootstrapPhase.resolving:
        return widget.loadingBuilder?.call(context) ?? const LoadingScreen();
      case _BootstrapPhase.failed:
        return LoadingScreen(
          message: 'Could not verify account state.',
          detail: _error?.toString(),
          onRetry: () {
            setState(_setResolving);
            _startBootstrap();
          },
        );
      case _BootstrapPhase.resolved:
        final decision = _decision;
        if (decision == null) {
          return widget.loadingBuilder?.call(context) ?? const LoadingScreen();
        }
        return _buildDestination(context, decision);
    }
  }

  Widget _buildDestination(
    BuildContext context,
    _BootstrapDecision decision,
  ) {
    switch (decision.destination) {
      case _BootstrapDestination.welcome:
        return widget.welcomePageBuilder?.call(context) ??
            const WelcomeScreen();
      case _BootstrapDestination.map:
        return widget.mapPageBuilder?.call(context) ?? const MapPage();
      case _BootstrapDestination.onboarding:
        final step = decision.onboardingStep ?? OnboardingData.stepUsername;
        final data = decision.onboardingData ?? OnboardingData();
        return _buildOnboardingStep(step, data);
    }
  }

  Widget _buildOnboardingStep(String step, OnboardingData data) {
    final injectedBuilder = widget.onboardingStepBuilder;
    if (injectedBuilder != null) return injectedBuilder(step, data);

    switch (step) {
      case OnboardingData.stepUsername:
        return NameUsernameScreen(data: data);
      case OnboardingData.stepDemographics:
        return DemographicsScreen(data: data);
      case OnboardingData.stepVibe:
        return VibeTagsScreen(data: data);
      case OnboardingData.stepBio:
        return BioScreen(data: data);
      case OnboardingData.stepPhoto:
      default:
        return AvatarUploadScreen(data: data);
    }
  }
}

class _BootstrapDecision {
  const _BootstrapDecision(
    this.destination, {
    this.onboardingStep,
    this.onboardingData,
  });

  final _BootstrapDestination destination;
  final String? onboardingStep;
  final OnboardingData? onboardingData;
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({
    super.key,
    this.message,
    this.detail,
    this.onRetry,
  });

  final String? message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final detail = this.detail;

    return Scaffold(
      backgroundColor: YanegiColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(YanegiSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'image assest/logofin.png.jpeg',
                  width: 88,
                  height: 88,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: YanegiSpacing.md),
                const Text(
                  'Yanegi',
                  style: TextStyle(
                    color: YanegiColors.textPrimary,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: YanegiSpacing.lg),
                if (message == null) ...[
                  const CircularProgressIndicator(
                    color: YanegiColors.primary,
                    strokeWidth: 2.5,
                  ),
                ] else ...[
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white70,
                    size: 34,
                  ),
                  const SizedBox(height: YanegiSpacing.sm),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: YanegiColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: YanegiSpacing.xs),
                    Text(
                      detail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: YanegiColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (onRetry != null) ...[
                    const SizedBox(height: YanegiSpacing.md),
                    ElevatedButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
