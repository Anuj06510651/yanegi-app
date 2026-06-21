import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import 'package:yanegi/firebase_options.dart';
import 'package:yanegi/firebase_options_dev.dart';

/// Central switch between the Development and Production environments.
///
/// The active environment is chosen at COMPILE TIME via the `APP_ENV`
/// dart-define. It defaults to `prod`, so any build that forgets the define
/// stays safely pinned to the live production project (`yanegi-684f9`).
///
/// Dev builds are produced with:
///   flutter run --flavor dev --dart-define=APP_ENV=dev
///
/// The Android applicationId suffix (`.dev`) is what makes Gradle pick the
/// matching `google-services.json`; `APP_ENV` is what makes Dart pick the
/// matching `FirebaseOptions` and web endpoints. The two must always agree —
/// the documented build commands keep them in sync.
class AppEnvironment {
  const AppEnvironment._();

  static const String _env =
      String.fromEnvironment('APP_ENV', defaultValue: 'prod');

  static bool get isDev => _env == 'dev';
  static bool get isProd => !isDev;

  /// Human-readable environment name (`dev` | `prod`).
  static String get name => isDev ? 'dev' : 'prod';

  /// Firebase configuration for the active environment.
  static FirebaseOptions get firebaseOptions => isDev
      ? DevFirebaseOptions.currentPlatform
      : DefaultFirebaseOptions.currentPlatform;

  /// Hosting base URL used for share links, deep links and OG previews.
  static String get webBaseUrl =>
      isDev ? 'https://yanegi-dev.web.app' : 'https://yanegi-684f9.web.app';
}
