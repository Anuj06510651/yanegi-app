import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/event_model.dart';
import '../../models/user_profile.dart';
import '../models/admin_daily_stat.dart';
import '../models/admin_report.dart';
import '../models/admin_stats.dart';
import '../models/admin_attention_item.dart';
import '../models/admin_growth_stats.dart';
import '../models/admin_user_detail.dart';


class AdminFirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const int _pageSize = 25;
  static const int _analyticsDays = 14;

  // ── Admin verification ────────────────────────────────────────────────────

  Future<bool> isAdmin(String uid) async {
    try {
      final doc = await _db.collection('admins').doc(uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  // ── Dashboard stats ───────────────────────────────────────────────────────

  Future<AdminStats> fetchDashboardStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final since24h = now.subtract(const Duration(hours: 24));

    int totalUsers = 0;
    int usersToday = 0;
    int activeUsers24h = 0;
    int eventsToday = 0;
    int activeEvents = 0;
    int communities = 0;
    int reportsPending = 0;

    await Future.wait([
      _count(_db.collection('users')).then((v) => totalUsers = v),
      _count(
        _db.collection('users').where(
              'created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
            ),
      ).then((v) => usersToday = v),
      _count(
        _db.collection('users').where(
              'lastSeen',
              isGreaterThanOrEqualTo: Timestamp.fromDate(since24h),
            ),
      ).then((v) => activeUsers24h = v),
      _count(
        _db.collection('events').where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
            ),
      ).then((v) => eventsToday = v),
      _count(
        _db.collection('events').where('isActive', isEqualTo: true),
      ).then((v) => activeEvents = v),
      _count(_db.collection('communities')).then((v) => communities = v),
      _count(
        _db.collection('reports').where('status', isEqualTo: 'pending'),
      ).then((v) => reportsPending = v),
    ]);

    return AdminStats(
      totalUsers: totalUsers,
      usersToday: usersToday,
      activeUsers24h: activeUsers24h,
      eventsToday: eventsToday,
      activeEvents: activeEvents,
      communities: communities,
      reportsPending: reportsPending,
    );
  }

  Future<int> _count(Query query) async {
    try {
      final result = await query.count().get();
      return result.count ?? 0;
    } on FirebaseException {
      return 0;
    }
  }

  // ── User list ─────────────────────────────────────────────────────────────

  Stream<List<UserProfile>> watchUsers({String query = ''}) {
    if (query.length == 28 && !query.contains(' ')) {
      return _db
          .collection('users')
          .doc(query)
          .snapshots()
          .map((doc) => doc.exists ? [UserProfile.fromFirestore(doc)] : []);
    }

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final end = q.substring(0, q.length - 1) +
          String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);
      return _db
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: end)
          .limit(_pageSize)
          .snapshots()
          .map((s) => s.docs.map(UserProfile.fromFirestore).toList());
    }

    return _db
        .collection('users')
        .orderBy('created_at', descending: true)
        .limit(_pageSize)
        .snapshots()
        .map((s) => s.docs.map(UserProfile.fromFirestore).toList());
  }

  Future<UserProfile?> fetchUser(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.exists ? UserProfile.fromFirestore(doc) : null;
    } catch (_) {
      return null;
    }
  }

  // ── Event list ────────────────────────────────────────────────────────────

  Stream<List<EventModel>> watchEvents({String query = ''}) {
    if (query.isNotEmpty) {
      final end = query.substring(0, query.length - 1) +
          String.fromCharCode(query.codeUnitAt(query.length - 1) + 1);
      return _db
          .collection('events')
          .where('title', isGreaterThanOrEqualTo: query)
          .where('title', isLessThan: end)
          .limit(_pageSize)
          .snapshots()
          .map((s) => s.docs.map(_eventFromDoc).toList());
    }

    return _db
        .collection('events')
        .orderBy('startAt', descending: true)
        .limit(_pageSize)
        .snapshots()
        .map((s) => s.docs.map(_eventFromDoc).toList());
  }

  Future<EventModel?> fetchEvent(String id) async {
    try {
      final doc = await _db.collection('events').doc(id).get();
      return doc.exists ? _eventFromDoc(doc) : null;
    } catch (_) {
      return null;
    }
  }

  EventModel _eventFromDoc(DocumentSnapshot doc) =>
      EventModel.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>);

  // ── Reports ───────────────────────────────────────────────────────────────
  // No orderBy — avoids composite index requirement.
  // Results are sorted client-side by createdAt descending.

  Stream<List<AdminReport>> watchReports({required ReportStatus status}) {
    return _db
        .collection('reports')
        .where('status', isEqualTo: status.name)
        .limit(_pageSize)
        .snapshots()
        .map((s) {
          final reports = s.docs.map(AdminReport.fromFirestore).toList();
          reports.sort((a, b) {
            if (a.createdAt == null && b.createdAt == null) return 0;
            if (a.createdAt == null) return 1;
            if (b.createdAt == null) return -1;
            return b.createdAt!.compareTo(a.createdAt!);
          });
          return reports;
        });
  }

  // ── User detail extras ────────────────────────────────────────────────────
  // No orderBy on compound where queries — avoids composite index requirement.

  Future<List<Map<String, dynamic>>> fetchUserJoinedEvents(String uid) async {
    try {
      final snap = await _db
          .collection('events')
          .where('participants', arrayContains: uid)
          .limit(20)
          .get();
      final docs = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      docs.sort((a, b) {
        final aTs = a['startAt'];
        final bTs = b['startAt'];
        if (aTs is! Timestamp || bTs is! Timestamp) return 0;
        return bTs.compareTo(aTs);
      });
      return docs;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchUserHostedEvents(String uid) async {
    try {
      final snap = await _db
          .collection('events')
          .where('hostId', isEqualTo: uid)
          .limit(20)
          .get();
      final docs = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      docs.sort((a, b) {
        final aTs = a['startAt'];
        final bTs = b['startAt'];
        if (aTs is! Timestamp || bTs is! Timestamp) return 0;
        return bTs.compareTo(aTs);
      });
      return docs;
    } catch (_) {
      return [];
    }
  }

  Future<List<AdminReport>> fetchUserReports(String uid) async {
    try {
      final snap = await _db
          .collection('reports')
          .where('reportedUserId', isEqualTo: uid)
          .limit(10)
          .get();
      final reports = snap.docs.map(AdminReport.fromFirestore).toList();
      reports.sort((a, b) {
        if (a.createdAt == null && b.createdAt == null) return 0;
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });
      return reports;
    } catch (_) {
      return [];
    }
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  Future<AdminAnalyticsData> fetchAnalytics() async {
    final since = DateTime.now().subtract(const Duration(days: _analyticsDays));
    final results = await Future.wait([
      _dailyStats(collection: 'users', dateField: 'created_at', since: since),
      _dailyStats(collection: 'users', dateField: 'lastSeen', since: since),
      _dailyStats(collection: 'events', dateField: 'createdAt', since: since),
      _dailyStats(collection: 'communities', dateField: 'createdAt', since: since),
    ]);
    return AdminAnalyticsData(
      newUsers: results[0],
      activeUsers: results[1],
      newEvents: results[2],
      newCommunities: results[3],
    );
  }

  Future<List<AdminDailyStat>> _dailyStats({
    required String collection,
    required String dateField,
    required DateTime since,
  }) async {
    try {
      final snap = await _db
          .collection(collection)
          .where(dateField, isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();

      final Map<String, int> daily = {};
      for (final doc in snap.docs) {
        final ts = doc.data()[dateField];
        if (ts is! Timestamp) continue;
        final d = ts.toDate();
        final key =
            "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
        daily[key] = (daily[key] ?? 0) + 1;
      }

      return daily.entries
          .map((e) => AdminDailyStat(date: DateTime.parse(e.key), count: e.value))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    } on FirebaseException {
      return [];
    }
  }

  // ── Growth stats ──────────────────────────────────────────────────────────

  Future<AdminGrowthStats> fetchGrowthStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1));
    final since24h = now.subtract(const Duration(hours: 24));

    int totalUsers = 0;
    int usersToday = 0;
    int usersThisWeek = 0;
    int activeUsers24h = 0;
    int eventsToday = 0;
    int eventsThisWeek = 0;
    int activeEvents = 0;
    int communities = 0;
    int reportsPending = 0;
    int reportsThisWeek = 0;

    await Future.wait([
      _count(_db.collection('users')).then((v) => totalUsers = v),
      _count(
        _db
            .collection('users')
            .where('created_at',
                isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart)),
      ).then((v) => usersToday = v),
      _count(
        _db
            .collection('users')
            .where('created_at',
                isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart)),
      ).then((v) => usersThisWeek = v),
      _count(
        _db
            .collection('users')
            .where('lastSeen',
                isGreaterThanOrEqualTo: Timestamp.fromDate(since24h)),
      ).then((v) => activeUsers24h = v),
      _count(
        _db
            .collection('events')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart)),
      ).then((v) => eventsToday = v),
      _count(
        _db
            .collection('events')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart)),
      ).then((v) => eventsThisWeek = v),
      _count(
        _db.collection('events').where('isActive', isEqualTo: true),
      ).then((v) => activeEvents = v),
      _count(_db.collection('communities')).then((v) => communities = v),
      _count(
        _db.collection('reports').where('status', isEqualTo: 'pending'),
      ).then((v) => reportsPending = v),
      _count(
        _db
            .collection('reports')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart)),
      ).then((v) => reportsThisWeek = v),
    ]);

    return AdminGrowthStats(
      totalUsers: totalUsers,
      usersToday: usersToday,
      usersThisWeek: usersThisWeek,
      activeUsers24h: activeUsers24h,
      eventsToday: eventsToday,
      eventsThisWeek: eventsThisWeek,
      activeEvents: activeEvents,
      communities: communities,
      reportsPending: reportsPending,
      reportsThisWeek: reportsThisWeek,
    );
  }

  // ── Attention items ───────────────────────────────────────────────────────

  Future<List<AdminAttentionItem>> fetchAttentionItems() async {
    final now = DateTime.now();
    final soonCutoff = now.add(const Duration(hours: 1));
    final items = <AdminAttentionItem>[];

    final results = await Future.wait([
      _count(
        _db.collection('reports').where('status', isEqualTo: 'pending'),
      ),
      _db
          .collection('events')
          .where('startAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(now))
          .where('startAt',
              isLessThanOrEqualTo: Timestamp.fromDate(soonCutoff))
          .limit(20)
          .get()
          .then((s) => s.size)
          .catchError((_) => 0),
      _count(
        _db.collection('users').where('hasCompleted', isEqualTo: false),
      ),
    ]);

    final pendingReports = results[0];
    final eventsStartingSoon = results[1];
    final incompleteUsers = results[2];

    if (pendingReports > 0) {
      items.add(AdminAttentionItem(
        severity: pendingReports >= 5
            ? AttentionSeverity.critical
            : AttentionSeverity.warning,
        category: AttentionCategory.moderation,
        title: 'Pending Reports',
        body: '$pendingReports report${pendingReports == 1 ? '' : 's'} awaiting review.',
        count: pendingReports,
        route: AdminRoute.reports,
        icon: Icons.flag_rounded,
      ));
    }

    if (eventsStartingSoon > 0) {
      items.add(AdminAttentionItem(
        severity: AttentionSeverity.info,
        category: AttentionCategory.events,
        title: 'Events Starting Soon',
        body: '$eventsStartingSoon event${eventsStartingSoon == 1 ? '' : 's'} starting within the next hour.',
        count: eventsStartingSoon,
        route: AdminRoute.events,
        icon: Icons.schedule_rounded,
      ));
    }

    if (incompleteUsers > 0) {
      items.add(AdminAttentionItem(
        severity: AttentionSeverity.info,
        category: AttentionCategory.users,
        title: 'Incomplete Onboarding',
        body: '$incompleteUsers user${incompleteUsers == 1 ? '' : 's'} have not completed onboarding.',
        count: incompleteUsers,
        route: AdminRoute.users,
        icon: Icons.person_off_rounded,
      ));
    }

    return items;
  }

  // ── Location summary ──────────────────────────────────────────────────────

  Future<Map<String, int>> fetchLocationSummary() async {
    try {
      final snap = await _db
          .collection('events')
          .where('isActive', isEqualTo: true)
          .limit(200)
          .get();

      final Map<String, int> cityCount = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final raw =
            (data['locationName'] ?? data['location'] ?? '').toString();
        if (raw.isEmpty) continue;
        final city = raw.split(',').first.trim();
        if (city.isNotEmpty) {
          cityCount[city] = (cityCount[city] ?? 0) + 1;
        }
      }

      final sorted = Map.fromEntries(
        cityCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
      );
      return sorted;
    } catch (_) {
      return {};
    }
  }

  // ── Top hosts ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchTopHosts(int limit) async {
    try {
      final snap = await _db
          .collection('events')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      final Map<String, Map<String, dynamic>> hosts = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final hostId = (data['hostId'] ?? '').toString();
        if (hostId.isEmpty) continue;
        if (hosts.containsKey(hostId)) {
          hosts[hostId]!['eventCount'] =
              (hosts[hostId]!['eventCount'] as int) + 1;
        } else {
          hosts[hostId] = {
            'uid': hostId,
            'name': (data['hostName'] ?? data['hostUsername'] ?? 'Unknown')
                .toString(),
            'eventCount': 1,
          };
        }
      }

      final sorted = hosts.values.toList()
        ..sort(
          (a, b) =>
              (b['eventCount'] as int).compareTo(a['eventCount'] as int),
        );
      return sorted.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Admin user list (AdminUserDetail) ─────────────────────────────────────

  Stream<List<AdminUserDetail>> watchAdminUsers({
    String query = '',
    String sortBy = 'newest',
  }) {
    if (query.length == 28 && !query.contains(' ')) {
      return _db
          .collection('users')
          .doc(query)
          .snapshots()
          .map((doc) =>
              doc.exists ? [AdminUserDetail.fromFirestore(doc)] : []);
    }

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final end = q.substring(0, q.length - 1) +
          String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);
      return _db
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: end)
          .limit(_pageSize)
          .snapshots()
          .map((s) => s.docs.map(AdminUserDetail.fromFirestore).toList());
    }

    final orderField = 'created_at';
    final descending = sortBy != 'oldest';

    return _db
        .collection('users')
        .orderBy(orderField, descending: descending)
        .limit(_pageSize)
        .snapshots()
        .map((s) => s.docs.map(AdminUserDetail.fromFirestore).toList());
  }

  // ── Global search ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchAll(String query) async {
    if (query.length < 2) return [];

    final q = query.toLowerCase();
    final end = q.substring(0, q.length - 1) +
        String.fromCharCode(q.codeUnitAt(q.length - 1) + 1);

    final results = await Future.wait([
      _db
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: end)
          .limit(10)
          .get()
          .then((s) => s.docs.map((doc) {
                final data = doc.data();
                return <String, dynamic>{
                  'type': 'user',
                  'id': doc.id,
                  'title': (data['name'] ?? data['username'] ?? '').toString(),
                  'subtitle':
                      '@${(data['username'] ?? '').toString()}',
                  'avatarUrl':
                      (data['photoUrl'] ?? data['avatarUrl'] ?? '').toString(),
                };
              }).toList())
          .catchError((_) => <Map<String, dynamic>>[]),
      _db
          .collection('events')
          .where('title', isGreaterThanOrEqualTo: query)
          .where('title', isLessThan:
              query.substring(0, query.length - 1) +
                  String.fromCharCode(
                      query.codeUnitAt(query.length - 1) + 1))
          .limit(10)
          .get()
          .then((s) => s.docs.map((doc) {
                final data = doc.data();
                return <String, dynamic>{
                  'type': 'event',
                  'id': doc.id,
                  'title': (data['title'] ?? '').toString(),
                  'subtitle':
                      (data['locationName'] ?? data['location'] ?? '')
                          .toString(),
                  'avatarUrl':
                      (data['bannerUrl'] ?? '').toString(),
                };
              }).toList())
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);

    return [...results[0], ...results[1]];
  }

}
