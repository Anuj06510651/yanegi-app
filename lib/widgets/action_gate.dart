import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:yanegi/screens/profile_social_screen.dart';
import 'package:yanegi/widgets/guest_gate.dart';

/// Central gate for actions that touch other people. Browsing the app stays
/// open for everyone; only create/join event, friend request/accept and direct
/// message are gated.
///
/// An action may proceed only when the user (a) has a real account — guests are
/// sent to [GuestGate.promptSignIn] — and (b) has a COMPLETE profile:
///   • main profile photo   • About Me (bio)   • at least 3 interests.
///
/// Reads only existing user-doc fields; no schema change. The gate is a UX
/// nudge, not a security boundary (Firestore rules remain the real guard), so
/// it deliberately **fails open** on a network error rather than blocking a
/// legitimate user on a flaky connection.
///
/// Backward compatibility: users with `hasCompletedProfile == true` are always
/// allowed (grandfathered), so no existing or legacy user can be blocked by the
/// stricter field-level definition introduced here.
class ActionGate {
  ActionGate._();

  static Future<bool> ensureCanAct(
    BuildContext context, {
    String message = 'Complete your profile to do this.',
  }) async {
    if (GuestGate.isGuest) {
      await GuestGate.promptSignIn(context);
      return false;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      await GuestGate.promptSignIn(context);
      return false;
    }

    Map<String, dynamic> data;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      data = doc.data() ?? const <String, dynamic>{};
    } catch (_) {
      return true; // fail-open
    }

    // Grandfather clause: anyone who already finished onboarding keeps full
    // access, regardless of current field requirements or legacy document
    // shape. This guarantees no existing/completed user is ever retroactively
    // blocked. The strict field check below therefore only gates users who
    // actually skipped onboarding (hasCompletedProfile != true).
    if (data['hasCompletedProfile'] == true) return true;

    if (isProfileComplete(data)) return true;
    if (context.mounted) {
      await _promptCompleteProfile(context, data, uid, message);
    }
    return false;
  }

  /// Pure predicate. Tolerant of legacy field-name variants for the photo.
  static bool isProfileComplete(Map<String, dynamic> data) {
    return _photoOk(data) && _bioOk(data) && _interestsOk(data);
  }

  static bool _photoOk(Map<String, dynamic> data) =>
      (data['photoUrl'] ??
              data['avatarUrl'] ??
              data['avatar_url'] ??
              data['profileImage'] ??
              data['profile_image'] ??
              '')
          .toString()
          .trim()
          .isNotEmpty;

  static bool _bioOk(Map<String, dynamic> data) =>
      (data['bio'] ?? '').toString().trim().isNotEmpty;

  static bool _interestsOk(Map<String, dynamic> data) {
    final raw = data['vibes'] ?? data['interests'];
    final List<String> items;
    if (raw is List) {
      items = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (raw is String) {
      // Legacy comma-separated storage.
      items = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      items = const <String>[];
    }
    return items.length >= 3;
  }

  static Future<void> _promptCompleteProfile(
    BuildContext context,
    Map<String, dynamic> data,
    String uid,
    String message,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final photoOk = _photoOk(data);
    final bioOk = _bioOk(data);
    final interestsOk = _interestsOk(data);

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget checkRow(bool ok, String label) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    ok
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: ok ? scheme.primary : scheme.onSurface.withOpacity(0.35),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );

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
                Icon(Icons.person_outline_rounded, color: scheme.primary, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Complete your profile',
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
                  ),
                ),
                const SizedBox(height: 18),
                checkRow(photoOk, 'Add a profile photo'),
                checkRow(bioOk, 'Write your About Me'),
                checkRow(interestsOk, 'Pick at least 3 interests'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SocialProfileScreen(profileUserId: uid),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Complete profile',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(
                      'Not now',
                      style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
                    ),
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
