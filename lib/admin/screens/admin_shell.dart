import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/yanegi_theme.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/admin_top_bar.dart';
import 'analytics_screen.dart';
import 'attendance_dashboard_screen.dart';
import 'audit_log_screen.dart';
import 'dashboard_home_screen.dart';
import 'events_screen.dart';
import 'feature_flags_screen.dart';
import 'global_search_screen.dart';
import 'location_analytics_screen.dart';
import 'release_dashboard_screen.dart';
import 'reports_screen.dart';
import 'users_screen.dart';

/// Root shell of the admin dashboard.
///
/// Screen order MUST match AdminRoute.index in admin_routes.dart:
///   dashboard(0), users(1), events(2), reports(3), analytics(4),
///   search(5), auditLog(6), locationAnalytics(7), attendance(8),
///   releases(9), featureFlags(10)
///
/// We use Stack+Positioned.fill+IgnorePointer+Offstage+TickerMode instead of
/// IndexedStack for two reasons:
///
/// 1. box.dart:2251 (infinite size): IndexedStack passes loose constraints to
///    children. Screens rooted in Column+Expanded need TIGHT height bounds.
///    Positioned.fill provides tight constraints equal to the Stack size.
///
/// 2. mouse_tracker.dart:199 cascade: IndexedStack's Offstage children still
///    register InkWell/Material mouse-hover regions on Flutter Web. Every mouse
///    move fires assertions for all 10 inactive screens.
///    IgnorePointer(ignoring: !active) removes inactive screens from
///    hit-testing completely, silencing the cascade.
///
/// State is fully preserved: Offstage keeps the widget tree alive,
/// TickerMode pauses animations on inactive screens — identical semantics to
/// IndexedStack with no Navigator involvement.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key});

  static const _screens = [
    DashboardHomeScreen(),       // 0 — dashboard
    UsersScreen(),               // 1 — users
    EventsScreen(),              // 2 — events
    ReportsScreen(),             // 3 — reports
    AnalyticsScreen(),           // 4 — analytics
    GlobalSearchScreen(),        // 5 — search
    AuditLogScreen(),            // 6 — auditLog
    LocationAnalyticsScreen(),   // 7 — locationAnalytics
    AttendanceDashboardScreen(), // 8 — attendance
    ReleaseDashboardScreen(),    // 9 — releases
    FeatureFlagsScreen(),        // 10 — featureFlags
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(adminRouteProvider);

    return Scaffold(
      backgroundColor: YanegiColors.background,
      body: Row(
        children: [
          const AdminSidebar(),
          Container(width: 1, color: const Color(0xFF1A1A1A)),
          Expanded(
            child: Column(
              children: [
                const AdminTopBar(),
                Expanded(
                  child: Stack(
                    children: List.generate(_screens.length, (i) {
                      final active = i == route.index;
                      return Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !active,
                          child: Offstage(
                            offstage: !active,
                            child: TickerMode(
                              enabled: active,
                              child: _screens[i],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
