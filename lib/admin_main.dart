import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_app.dart';
import 'config/app_environment.dart';

// Run with:
//   flutter run -t lib/admin_main.dart --flavor prod --dart-define=APP_ENV=prod
//   flutter run -t lib/admin_main.dart --flavor dev  --dart-define=APP_ENV=dev
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: AppEnvironment.firebaseOptions);
  runApp(const ProviderScope(child: AdminApp()));
}
