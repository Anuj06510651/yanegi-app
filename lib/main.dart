import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/chat_peer_cache.dart';
import 'services/explore_cache_service.dart';
import 'services/local_profile_cache.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:yanegi/theme/yanegi_theme.dart';
import 'package:yanegi/onboarding/auth_bootstrapper.dart';

import 'package:yanegi/services/app_theme_service.dart';
import 'package:yanegi/services/user_presence_service.dart';
import 'package:yanegi/services/push_notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_links/app_links.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yanegi/config/app_environment.dart';
import 'screens/event_detail_screen.dart';
import 'screens/profile_social_screen.dart';

void main() {
  runZonedGuarded(() async {
    debugPrint("BOOT 1: App Started");

    WidgetsFlutterBinding.ensureInitialized();

    await Hive.initFlutter();
    await Future.wait([
      LocalProfileCache.init(),
      ExploreCacheService.init(),
      ChatPeerCache.init(),
    ]);

    debugPrint("BOOT 2: Firebase Init Start");

    await Firebase.initializeApp(
      options: AppEnvironment.firebaseOptions,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    debugPrint("BOOT 3: Firebase Init Complete");

    // Fresh-install guard: Firebase Auth tokens live in the Android Keystore
    // and can survive uninstall on some OEM devices / backup-restore scenarios.
    // On the very first launch after an install, force sign-out so the user
    // always lands on the Welcome screen rather than being silently restored.
    await _clearAuthOnFreshInstall();

    // 🔥 Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);

      // Network errors (offline / DNS failure / tile load) are non-fatal.
      if (_isNetworkError(details.exception)) {
        FirebaseCrashlytics.instance.recordError(
          details.exception,
          details.stack,
          fatal: false,
        );
      } else {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }

      debugPrint('🔥 FlutterError: ${details.exceptionAsString()}');

      if (details.stack != null) {
        debugPrintStack(stackTrace: details.stack);
      }
    };

    // 🔥 Widget build errors
    ErrorWidget.builder = (FlutterErrorDetails details) {
      FlutterError.presentError(details);

      FirebaseCrashlytics.instance.recordFlutterFatalError(details);

      final error = details.exception;
      final stackTrace = details.stack;

      debugPrint('🔥 UI Build Error: $error');

      if (stackTrace != null) {
        debugPrintStack(stackTrace: stackTrace);
      }

      return const Material(
        color: Colors.black,
        child: Center(
          child: Text(
            'Something went wrong',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    };

    // 🔥 Async / platform errors
    PlatformDispatcher.instance.onError = (
      Object error,
      StackTrace stack,
    ) {
      final isNetwork = _isNetworkError(error);
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: !isNetwork,
      );

      debugPrint('🔥 PlatformDispatcher uncaught error: $error');
      debugPrintStack(stackTrace: stack);

      return true;
    };

    // Firebase Messaging background handler
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
    }

    debugPrint('🔥 PROJECT ID: ${Firebase.app().options.projectId}');
    debugPrint('🔥 AUTH DOMAIN: ${Firebase.app().options.authDomain}');
    debugPrint(
      '🔥 API KEY EXISTS: ${Firebase.app().options.apiKey.isNotEmpty}',
    );

    // 🔥 Theme loading
    debugPrint("BOOT 4: Theme Loading Start");

    try {
      await AppThemeService.instance.loadThemePreference();

      debugPrint("BOOT 4: Theme Loaded");
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st);

      debugPrint('🔥 Theme preference load failed: $e');
      debugPrintStack(stackTrace: st);
    }

    // System UI
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: YanegiColors.background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    debugPrint("BOOT 5: Auth restore delegated to AuthBootstrapper");

    debugPrint("BOOT 6: Routing");

    debugPrint('🚀 Starting YanegiApp...');

    runApp(
      const ProviderScope(
        child: YanegiApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    final isNetwork = _isNetworkError(error);
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      fatal: !isNetwork,
    );

    debugPrint('🔥 runZonedGuarded uncaught zone error: $error');
    debugPrintStack(stackTrace: stack);
  });
}

/// Clears persisted Firebase Auth / Google Sign-In tokens on a fresh install.
///
/// Firebase Auth tokens live in the Android Keystore and can survive app
/// uninstall on certain OEM devices or when Google Backup/Restore is enabled.
/// SharedPreferences data does NOT survive a clean uninstall, so we use the
/// absence of the marker key as a reliable "first launch after install" signal.
Future<void> _clearAuthOnFreshInstall() async {
  try {
    const markerKey = 'yanegi_installed_v2';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(markerKey) == true) return; // normal warm-start

    debugPrint('BOOT: fresh install detected — clearing persisted auth tokens');
    await Future.wait([
      FirebaseAuth.instance.signOut().catchError((_) async {}),
      GoogleSignIn().signOut().catchError((_) async => null),
    ]);

    // Wipe all Hive profile caches so the previous user's profile data is gone.
    // (The boxes are already open at this point.)
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) LocalProfileCache.clear(currentUid);

    await prefs.setBool(markerKey, true);
    debugPrint('BOOT: fresh install auth clear complete');
  } catch (e) {
    debugPrint('BOOT: fresh install auth clear failed (non-fatal): $e');
  }
}

/// Returns true for transient network errors that should not be fatal crashes.
/// These include offline/DNS failures and tile-load socket resets.
bool _isNetworkError(Object error) {
  if (error is SocketException) return true;
  // http.ClientException (map tiles, Storage image loads) carries the message.
  final msg = error.toString();
  return msg.contains('SocketException') ||
      msg.contains('ClientException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Software caused connection abort') ||
      msg.contains('Connection refused') ||
      msg.contains('Network is unreachable');
}

class YanegiApp extends StatelessWidget {
  const YanegiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _YanegiAppShell();
  }
}

class _YanegiAppShell extends StatefulWidget {
  const _YanegiAppShell();

  @override
  State<_YanegiAppShell> createState() => _YanegiAppShellState();
}

class _YanegiAppShellState extends State<_YanegiAppShell>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<Uri>? _deepLinkSub;

  late final UserPresenceService _presenceService;

  PushNotificationService? _pushNotificationService;

  @override
  void initState() {
    super.initState();

    debugPrint("BOOT SHELL: initState");

    WidgetsBinding.instance.addObserver(this);

    _presenceService = UserPresenceService();

    /// 🔥 Delay heavy services until first frame render
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint("BOOT POST FRAME: starting delayed services");

      // 🔥 Delayed Presence Service
      try {
        debugPrint("BOOT PRESENCE: delayed start");

        await _presenceService.start();

        debugPrint("BOOT PRESENCE: started");
      } catch (e, st) {
        FirebaseCrashlytics.instance.recordError(e, st);

        debugPrint("BOOT PRESENCE ERROR: $e");
      }

      // 🔥 Delayed Push Initialization
      try {
        debugPrint("BOOT PUSH: delayed initialization start");

        Firebase.app();

        final service = PushNotificationService();

        _pushNotificationService = service;

        await service.initialize(
          navigatorKey: _navigatorKey,
        );

        debugPrint("BOOT PUSH: delayed initialization complete");
      } catch (e, st) {
        FirebaseCrashlytics.instance.recordError(e, st);

        debugPrint("BOOT PUSH ERROR: $e");
      }

      // Deep link handling via app_links (handles both cold-start and foreground).
      try {
        final appLinks = AppLinks();

        // Cold-start link (app launched from a link while not running)
        final initialUri = await appLinks.getInitialLink();
        if (initialUri != null) {
          _handleDeepLink(initialUri);
        }

        // Foreground / background links
        _deepLinkSub = appLinks.uriLinkStream.listen(
          _handleDeepLink,
          onError: (e) => debugPrint('Deep link stream error: $e'),
        );

        debugPrint("BOOT DEEP LINK: wired up");
      } catch (e, st) {
        FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
        debugPrint("BOOT DEEP LINK ERROR: $e");
      }
    });
    try {
      Firebase.app();

      _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        debugPrint(
          "BOOT AUTH STATE: ${user != null ? "SIGNED IN" : "SIGNED OUT"}",
        );

        if (user != null) {
          FirebaseCrashlytics.instance.setUserIdentifier(user.uid);
        }

        unawaited(
          AppThemeService.instance.loadThemePreference(),
        );
      });
    } catch (e, st) {
      FirebaseCrashlytics.instance.recordError(e, st);

      debugPrint('🔥 Theme auth sync skipped: $e');
    }
  }

  void _handleDeepLink(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 2) return;

    final type = segments[0];   // 'event' or 'profile'
    final id   = Uri.decodeComponent(segments[1]).trim();
    if (id.isEmpty) return;

    final nav = _navigatorKey.currentState;
    if (nav == null) return;

    if (type == 'event') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: id),
        ),
      );
    } else if (type == 'profile') {
      nav.push(
        MaterialPageRoute(
          builder: (_) => SocialProfileScreen(profileUserId: id),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("APP LIFECYCLE: $state");
  }

  @override
  void dispose() {
    debugPrint("BOOT SHELL: dispose");

    WidgetsBinding.instance.removeObserver(this);

    _authStateSub?.cancel();
    _deepLinkSub?.cancel();

    final pushService = _pushNotificationService;

    if (pushService != null) {
      unawaited(pushService.dispose());
    }

    unawaited(_presenceService.stop());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeService.instance.themeModeListenable,
      builder: (context, mode, _) {
        debugPrint("BOOT UI: Building MaterialApp");

        return MaterialApp(
          title: 'Yanegi',
          debugShowCheckedModeBanner: false,
          theme: YanegiTheme.light,
          darkTheme: YanegiTheme.dark,
          themeMode: mode,
          navigatorKey: _navigatorKey,
          home: const AuthBootstrapper(),
        );
      },
    );
  }
}
