import 'package:flutter/material.dart';

import '../theme/yanegi_theme.dart';
import 'authentication/admin_auth_guard.dart';

/// Root widget for the standalone Admin Dashboard application.
/// Launched via lib/admin_main.dart — completely separate from the public app.
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yanegi Admin',
      debugShowCheckedModeBanner: false,
      // Admin dashboard is always dark — no theme switching
      theme: YanegiTheme.dark,
      home: const AdminAuthGuard(),
    );
  }
}
