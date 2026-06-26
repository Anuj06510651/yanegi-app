import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/event_model.dart';
import '../../models/user_profile.dart';
import '../models/admin_daily_stat.dart';
import '../models/admin_report.dart';
import '../models/admin_stats.dart';
import '../models/admin_attention_item.dart';
import '../models/admin_routes.dart';
export '../models/admin_routes.dart';
import '../models/admin_growth_stats.dart';
import '../models/admin_user_detail.dart';

import '../services/admin_firestore_service.dart';

// ── Navigation ────────────────────────────────────────────────────────────────

// AdminRoute is defined in admin_routes.dart and re-exported via admin_attention_item.dart

final adminRouteProvider = StateProvider<AdminRoute>(
  (ref) => AdminRoute.dashboard,
);

// ── Authentication ────────────────────────────────────────────────────────────

/// Raw Firebase auth state. Emits null when signed out.
final adminAuthStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

/// Checks the `admins/{uid}` Firestore document. Automatically re-runs
/// whenever the auth state changes (because it watches adminAuthStateProvider).
final adminVerificationProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(adminAuthStateProvider).valueOrNull;
  if (user == null) return false;
  return ref.read(adminFirestoreServiceProvider).isAdmin(user.uid);
});

// ── Service ───────────────────────────────────────────────────────────────────

final adminFirestoreServiceProvider = Provider<AdminFirestoreService>(
  (ref) => AdminFirestoreService(),
);

// ── Dashboard stats ───────────────────────────────────────────────────────────

final adminStatsProvider = FutureProvider<AdminStats>(
  (ref) => ref.read(adminFirestoreServiceProvider).fetchDashboardStats(),
);

// ── Users ─────────────────────────────────────────────────────────────────────

final adminUserSearchProvider = StateProvider<String>((ref) => '');

final adminUsersProvider =
    StreamProvider.family<List<UserProfile>, String>((ref, query) {
  return ref.read(adminFirestoreServiceProvider).watchUsers(query: query);
});

// ── Events ────────────────────────────────────────────────────────────────────

final adminEventSearchProvider = StateProvider<String>((ref) => '');

final adminEventsProvider =
    StreamProvider.family<List<EventModel>, String>((ref, query) {
  return ref.read(adminFirestoreServiceProvider).watchEvents(query: query);
});

// ── Reports ───────────────────────────────────────────────────────────────────

final adminReportsFilterProvider = StateProvider<ReportStatus>(
  (ref) => ReportStatus.pending,
);

final adminReportsProvider =
    StreamProvider.family<List<AdminReport>, ReportStatus>((ref, status) {
  return ref.read(adminFirestoreServiceProvider).watchReports(status: status);
});

// ── Analytics ─────────────────────────────────────────────────────────────────

final adminAnalyticsProvider = FutureProvider<AdminAnalyticsData>(
  (ref) => ref.read(adminFirestoreServiceProvider).fetchAnalytics(),
);

// ── Growth stats ──────────────────────────────────────────────────────────────

final adminGrowthStatsProvider = FutureProvider<AdminGrowthStats>(
  (ref) => ref.read(adminFirestoreServiceProvider).fetchGrowthStats(),
);

// ── Attention items ───────────────────────────────────────────────────────────

final adminAttentionProvider = FutureProvider<List<AdminAttentionItem>>(
  (ref) => ref.read(adminFirestoreServiceProvider).fetchAttentionItems(),
);

// ── Location analytics ────────────────────────────────────────────────────────

final adminLocationProvider = FutureProvider<Map<String, int>>(
  (ref) => ref.read(adminFirestoreServiceProvider).fetchLocationSummary(),
);

// ── Top hosts ─────────────────────────────────────────────────────────────────

final adminTopHostsProvider = FutureProvider<List<Map<String, dynamic>>>(
  (ref) => ref.read(adminFirestoreServiceProvider).fetchTopHosts(10),
);

// ── Admin users (AdminUserDetail) ─────────────────────────────────────────────

final adminUserSortProvider = StateProvider<String>((ref) => 'newest');

final adminAdminUsersProvider = StreamProvider.family<
    List<AdminUserDetail>, (String, String)>((ref, params) {
  final (query, sortBy) = params;
  return ref
      .read(adminFirestoreServiceProvider)
      .watchAdminUsers(query: query, sortBy: sortBy);
});

// ── Global search ─────────────────────────────────────────────────────────────

final adminGlobalSearchProvider = StateProvider<String>((ref) => '');

final adminGlobalSearchResultsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, query) {
  return ref.read(adminFirestoreServiceProvider).searchAll(query);
});

// ── Host profile lookup (used by events table) ────────────────────────────────

final adminHostProfileProvider =
    FutureProvider.family<UserProfile?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  return ref.read(adminFirestoreServiceProvider).fetchUser(uid);
});
