import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
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
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAFa5071HC5_4zvOuhKb_4aWZrLrrfOrs0',
    appId: '1:266662976182:web:placeholder',
    messagingSenderId: '266662976182',
    projectId: 'yanegi-684f9',
    authDomain: 'yanegi-684f9.firebaseapp.com',
    storageBucket: 'yanegi-684f9.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAFa5071HC5_4zvOuhKb_4aWZrLrrfOrs0',
    appId: '1:266662976182:android:40c577760ce4370af8e417',
    messagingSenderId: '266662976182',
    projectId: 'yanegi-684f9',
    storageBucket: 'yanegi-684f9.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAFa5071HC5_4zvOuhKb_4aWZrLrrfOrs0',
    appId: '1:266662976182:ios:placeholder',
    messagingSenderId: '266662976182',
    projectId: 'yanegi-684f9',
    storageBucket: 'yanegi-684f9.firebasestorage.app',
    iosBundleId: 'com.example.yanegi',
  );

  static const FirebaseOptions macos = ios;
}