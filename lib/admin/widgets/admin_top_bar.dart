import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/yanegi_theme.dart';
import '../providers/admin_providers.dart';

class AdminTopBar extends ConsumerWidget {
  const AdminTopBar({super.key});

  static const _titles = {
    AdminRoute.dashboard: 'Dashboard',
    AdminRoute.users: 'User Management',
    AdminRoute.events: 'Event Management',
    AdminRoute.reports: 'Reports Center',
    AdminRoute.analytics: 'Analytics',
    AdminRoute.search: 'Global Search',
    AdminRoute.auditLog: 'Audit Log',
    AdminRoute.locationAnalytics: 'Location Analytics',
    AdminRoute.attendance: 'Attendance Dashboard',
    AdminRoute.releases: 'Release Dashboard',
    AdminRoute.featureFlags: 'Feature Flags',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(adminRouteProvider);
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: YanegiColors.surface,
        border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _titles[route] ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: YanegiColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          if (user?.email != null) ...[
            const Icon(Icons.shield_rounded,
                size: 14, color: YanegiColors.accentSuccess),
            const SizedBox(width: 6),
            Text(
              user!.email!,
              style: const TextStyle(
                  fontSize: 12, color: YanegiColors.textSecondary),
            ),
            const SizedBox(width: 16),
            const _SignOutButton(),
          ],
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sign out',
      child: InkWell(
        onTap: () => FirebaseAuth.instance.signOut(),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF2A2A2A)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_rounded,
                  size: 14, color: YanegiColors.textSecondary),
              SizedBox(width: 5),
              Text('Sign out',
                  style: TextStyle(
                      fontSize: 12, color: YanegiColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
