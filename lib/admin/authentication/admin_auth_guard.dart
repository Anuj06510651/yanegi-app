import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_providers.dart';
import '../screens/access_denied_screen.dart';
import '../screens/admin_login_screen.dart';
import '../screens/admin_shell.dart';

/// Root guard for the entire admin dashboard.
///
/// State machine:
///   no user            → AdminLoginScreen
///   user + loading     → _AdminLoadingScreen (spinner)
///   user + is admin    → AdminShell
///   user + not admin   → signs out silently → AccessDeniedScreen
///                        (stays until user taps "Try Different Account")
///
/// Security note: admin verification hits Firestore `admins/{uid}` on every
/// auth state change. Actual data access is enforced by Firestore Security
/// Rules — this guard is the UX layer, not the security layer.
class AdminAuthGuard extends ConsumerStatefulWidget {
  const AdminAuthGuard({super.key});

  @override
  ConsumerState<AdminAuthGuard> createState() => _AdminAuthGuardState();
}

class _AdminAuthGuardState extends ConsumerState<AdminAuthGuard> {
  /// Set to true once we confirm the signed-in user is NOT in admins collection.
  /// Stays true until the user explicitly taps "Try Different Account", so
  /// AccessDeniedScreen remains visible even after the async sign-out completes.
  bool _accessDenied = false;

  @override
  Widget build(BuildContext context) {
    // Side-effect listener — runs after build, not during.
    // Fires once when adminVerificationProvider resolves to false.
    ref.listen<AsyncValue<bool>>(adminVerificationProvider, (_, next) {
      next.whenData((isAdmin) {
        if (!isAdmin && mounted) {
          setState(() => _accessDenied = true);
          FirebaseAuth.instance.signOut();
        }
      });
    });

    if (_accessDenied) {
      return AccessDeniedScreen(
        onRetry: () => setState(() => _accessDenied = false),
      );
    }

    final authState = ref.watch(adminAuthStateProvider);
    return authState.when(
      loading: () => const _AdminLoadingScreen(),
      error: (_, __) => const _AdminLoadingScreen(),
      data: (user) {
        if (user == null) return const AdminLoginScreen();

        final verification = ref.watch(adminVerificationProvider);
        return verification.when(
          loading: () => const _AdminLoadingScreen(),
          error: (_, __) => const _AdminLoadingScreen(),
          // If isAdmin is false here, the listener above already set _accessDenied.
          // We show loading briefly while sign-out propagates.
          data: (isAdmin) =>
              isAdmin ? const AdminShell() : const _AdminLoadingScreen(),
        );
      },
    );
  }
}

class _AdminLoadingScreen extends StatelessWidget {
  const _AdminLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF000000),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF3B82F6)),
            SizedBox(height: 16),
            Text(
              'Verifying admin access...',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
