import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yanegi/auth/screens/auth_landing_page.dart';
import 'package:yanegi/theme/yanegi_theme.dart';

/// Central gate for guest (anonymous) users.
///
/// Guests are signed in anonymously so they can browse the map and view events,
/// but actions that touch other people — joining an event, opening someone's
/// profile, messaging — require upgrading to a real account. Call
/// [ensureSignedIn] at the start of any such action: it returns `true` when the
/// user already has a real account, or shows a sign-in prompt and returns
/// `false` so the caller aborts.
class GuestGate {
  GuestGate._();

  /// A guest is anyone with no Firebase user or an anonymous user.
  static bool get isGuest {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous;
  }

  /// Returns `true` if the action may proceed (real account). Otherwise shows a
  /// sign-in prompt and returns `false`.
  static Future<bool> ensureSignedIn(
    BuildContext context, {
    String title = 'Sign in to continue',
    String message =
        'Create a free account to join events and connect with people.',
  }) async {
    if (!isGuest) return true;
    await promptSignIn(context, title: title, message: message);
    return false;
  }

  /// Shows the sign-in prompt sheet. Theme-aware (Light/Dark).
  static Future<void> promptSignIn(
    BuildContext context, {
    String title = 'Sign in to continue',
    String message =
        'Create a free account to join events and connect with people.',
  }) {
    final scheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Icon(Icons.lock_outline_rounded, color: scheme.primary, size: 36),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AuthLandingPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YanegiRadius.md),
                      ),
                    ),
                    child: const Text(
                      'Sign in / Create account',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(
                    'Not now',
                    style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
