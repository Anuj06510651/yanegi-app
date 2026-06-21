import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase configuration for the DEVELOPMENT project (`yanegi-dev`).
///
/// Only reached when the app is built with `--dart-define=APP_ENV=dev`
/// (see [AppEnvironment]). Production is unaffected by anything in this file.
///
/// Android values come from the dev `google-services.json`
/// (com.yanegi.app.dev). Web/iOS use placeholder appIds because the dev
/// project is currently Android-only; configure them via `flutterfire
/// configure --project=yanegi-dev` before running dev on those platforms.
class DevFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'DevFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCvPuytQwKklxClC5itwuTCSbDACezWi4E',
    appId: '1:437216733779:android:7cb53d057115746c5334a6',
    messagingSenderId: '437216733779',
    projectId: 'yanegi-dev',
    storageBucket: 'yanegi-dev.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCvPuytQwKklxClC5itwuTCSbDACezWi4E',
    appId: '1:437216733779:web:placeholder',
    messagingSenderId: '437216733779',
    projectId: 'yanegi-dev',
    authDomain: 'yanegi-dev.firebaseapp.com',
    storageBucket: 'yanegi-dev.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCvPuytQwKklxClC5itwuTCSbDACezWi4E',
    appId: '1:437216733779:ios:placeholder',
    messagingSenderId: '437216733779',
    projectId: 'yanegi-dev',
    storageBucket: 'yanegi-dev.firebasestorage.app',
    iosBundleId: 'com.yanegi.app.dev',
  );

  static const FirebaseOptions macos = ios;
}
