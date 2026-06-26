import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/user_profile.dart';
import '../../theme/yanegi_theme.dart';
import '../models/admin_report.dart';
import '../screens/event_detail_admin_screen.dart';
import '../services/admin_firestore_service.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';

class UserDetailScreen extends StatefulWidget {
  final String uid;

  const UserDetailScreen({super.key, required this.uid});

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen>
    with SingleTickerProviderStateMixin {
  final _service = AdminFirestoreService();
  late final TabController _tabController;
  late Future<_UserDetailData> _future;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _future = _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_UserDetailData> _load() async {
    final results = await Future.wait([
      _service.fetchUser(widget.uid),
      _service.fetchUserHostedEvents(widget.uid),
      _service.fetchUserJoinedEvents(widget.uid),
      _service.fetchUserReports(widget.uid),
    ]);

    return _UserDetailData(
      profile: results[0] as UserProfile?,
      hostedEvents: results[1] as List<Map<String, dynamic>>,
      joinedEvents: results[2] as List<Map<String, dynamic>>,
      reports: results[3] as List<AdminReport>,
    );
  }

  static int _profileCompletion(UserProfile p) {
    int s = 0;
    if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) s += 20;
    if (p.bio.isNotEmpty) s += 20;
    if (p.name.isNotEmpty) s += 20;
    if (p.vibes.isNotEmpty) s += 20;
    if (p.dob != null) s += 20;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YanegiColors.background,
      appBar: AppBar(
        backgroundColor: YanegiColors.surface,
        foregroundColor: YanegiColors.textPrimary,
        elevation: 0,
        title: Text(
          'User: ${widget.uid}',
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: YanegiColors.primary,
          unselectedLabelColor: YanegiColors.textSecondary,
          indicatorColor: YanegiColors.primary,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Events'),
            Tab(text: 'Reports'),
          ],
        ),
      ),
      body: FutureBuilder<_UserDetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AdminSkeletonDetail();
          }
          if (snap.hasError) {
            return AdminErrorState(message: snap.error.toString());
          }
          final data = snap.data!;
          if (data.profile == null) {
            return const AdminEmptyState(message: 'User not found');
          }
          final completion = _profileCompletion(data.profile!);
          return Column(
            children: [
              _MetricBar(
                profile: data.profile!,
                completion: completion,
                hosted: data.hostedEvents.length,
                joined: data.joinedEvents.length,
                reports: data.reports.length,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ProfileTab(
                        profile: data.profile!, completion: completion),
                    _EventsTab(
                        hosted: data.hostedEvents,
                        joined: data.joinedEvents),
                    _ReportsTab(reports: data.reports),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Metric bar ────────────────────────────────────────────────────────────────

class _MetricBar extends StatelessWidget {
  final UserProfile profile;
  final int completion;
  final int hosted;
  final int joined;
  final int reports;

  const _MetricBar({
    required this.profile,
    required this.completion,
    required this.hosted,
    required this.joined,
    required this.reports,
  });

  @override
  Widget build(BuildContext context) {
    final completionColor = completion >= 80
        ? YanegiColors.accentSuccess
        : completion >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    String lastSeen = '—';

    final metrics = [
      ('PROFILE', '$completion%', completionColor),
      ('JOINED', '$joined', YanegiColors.primary),
      ('HOSTED', '$hosted', YanegiColors.primary),
      ('FRIENDS', '${profile.friendsCount}', YanegiColors.textPrimary),
      ('LAST SEEN', lastSeen, YanegiColors.textTertiary),
      ('MEMBER', profile.createdAt != null
          ? DateFormat('MMM yy').format(profile.createdAt!)
          : '—', YanegiColors.textTertiary),
      ('REPORTS', '$reports',
          reports > 0 ? const Color(0xFFEF4444) : YanegiColors.textTertiary),
    ];

    return Container(
      color: YanegiColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: metrics.map((m) {
            return Container(
              width: 110,
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: YanegiColors.surfaceElevated,
                borderRadius: BorderRadius.circular(YanegiRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.$1,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: YanegiColors.textTertiary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.$2,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: m.$3,
                      height: 1,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Profile tab ───────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final UserProfile profile;
  final int completion;

  const _ProfileTab({required this.profile, required this.completion});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main content
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildSection('IDENTITY', [
                  _row('UID', profile.uid, monospace: true, copyable: true),
                  _row('Name', profile.name.isNotEmpty ? profile.name : '—'),
                  _row('Username', '@${profile.username}'),
                  _row('Bio', profile.bio.isNotEmpty ? profile.bio : '—'),
                  _row('Gender', profile.gender ?? '—'),
                  _row('Date of Birth',
                      profile.dob != null
                          ? DateFormat('d MMMM yyyy').format(profile.dob!)
                          : '—'),
                ]),
                const SizedBox(height: 16),
                _buildSection('ACCOUNT', [
                  _row('Member Since',
                      profile.createdAt != null
                          ? DateFormat('d MMM yyyy, h:mm a')
                              .format(profile.createdAt!)
                          : '—'),
                  _row('Friends', '${profile.friendsCount}'),
                  _row('Events Joined', '${profile.eventsJoined}'),
                  _row('Events Created', '${profile.eventsCreated}'),
                  _row('Blocked Users', '${profile.blockedUsers.length}'),
                ]),
                if (profile.vibes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSection('INTERESTS', [
                    _row('Vibes', profile.vibes.join(', ')),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          // Moderation panel
          Expanded(
            flex: 1,
            child: _ModerationPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: YanegiColors.surfaceElevated,
          backgroundImage: profile.avatarUrl != null
              ? CachedNetworkImageProvider(profile.avatarUrl!,
                  maxWidth: 128, maxHeight: 128)
              : null,
          child: profile.avatarUrl == null
              ? const Icon(Icons.person_rounded,
                  size: 28, color: YanegiColors.textTertiary)
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.name.isNotEmpty ? profile.name : '(no name)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: YanegiColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '@${profile.username}',
                style: const TextStyle(
                    fontSize: 13, color: YanegiColors.textSecondary),
              ),
            ],
          ),
        ),
        _CompletionBadge(completion: completion),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: YanegiColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: YanegiColors.surface,
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(color: Colors.white.withAlpha(8)),
          ),
          child: Column(
            children: rows
                .asMap()
                .entries
                .map((e) => Column(children: [
                      e.value,
                      if (e.key < rows.length - 1)
                        const Divider(
                            height: 1,
                            color: Color(0xFF1A1A1A),
                            indent: 16,
                            endIndent: 16),
                    ]))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value,
      {bool monospace = false, bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: YanegiColors.textPrimary,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: value)),
              child: const Icon(Icons.copy_rounded,
                  size: 13, color: YanegiColors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _CompletionBadge extends StatelessWidget {
  final int completion;

  const _CompletionBadge({required this.completion});

  @override
  Widget build(BuildContext context) {
    final color = completion >= 80
        ? YanegiColors.accentSuccess
        : completion >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$completion% profile',
        style:
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _ModerationPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.md),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MODERATION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Available in next release',
            style:
                TextStyle(fontSize: 11, color: YanegiColors.textTertiary),
          ),
          const SizedBox(height: 16),
          ...[
            ('Warn User', Icons.warning_amber_rounded),
            ('Suspend', Icons.pause_circle_outline_rounded),
            ('Ban', Icons.block_rounded),
            ('Delete Gallery', Icons.photo_library_outlined),
            ('Reset Prompt', Icons.refresh_rounded),
          ].map((action) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Tooltip(
                  message: 'Available in next release',
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(action.$2, size: 14),
                      label: Text(action.$1,
                          style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        foregroundColor: YanegiColors.textTertiary,
                        side: const BorderSide(color: Color(0xFF2A2A2A)),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ── Events tab ────────────────────────────────────────────────────────────────

class _EventsTab extends StatelessWidget {
  final List<Map<String, dynamic>> hosted;
  final List<Map<String, dynamic>> joined;

  const _EventsTab({required this.hosted, required this.joined});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: YanegiColors.primary,
            unselectedLabelColor: YanegiColors.textSecondary,
            indicatorColor: YanegiColors.primary,
            tabs: [Tab(text: 'Hosted'), Tab(text: 'Joined')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _EventTable(events: hosted),
                _EventTable(events: joined),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTable extends StatelessWidget {
  final List<Map<String, dynamic>> events;

  const _EventTable({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const AdminEmptyState(message: 'No events');
    }
    return Column(
      children: [
        Container(
          color: YanegiColors.surface,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: const Row(
            children: [
              Expanded(flex: 3, child: _SmallHeader('TITLE')),
              Expanded(flex: 2, child: _SmallHeader('START')),
              Expanded(flex: 1, child: _SmallHeader('STATUS')),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF1A1A1A)),
        Expanded(
          child: ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Color(0xFF111111)),
            itemBuilder: (context, i) {
              final e = events[i];
              final id = e['id'].toString();
              final title =
                  (e['title'] ?? 'Untitled').toString();
              final startTs = e['startAt'];
              String startStr = '—';
              if (startTs != null) {
                try {
                  final dt = startTs.toDate() as DateTime;
                  startStr =
                      DateFormat('d MMM yyyy').format(dt);
                } catch (_) {}
              }
              final isActive = e['isActive'] == true;
              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EventDetailAdminScreen(eventId: id),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            color: YanegiColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          startStr,
                          style: const TextStyle(
                              fontSize: 12,
                              color: YanegiColors.textSecondary),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isActive
                                    ? YanegiColors.accentSuccess
                                    : YanegiColors.textTertiary)
                                .withAlpha(26),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isActive ? 'Active' : 'Ended',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? YanegiColors.accentSuccess
                                  : YanegiColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SmallHeader extends StatelessWidget {
  final String text;
  const _SmallHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: YanegiColors.textTertiary,
          letterSpacing: 0.6,
        ),
      );
}

// ── Reports tab ───────────────────────────────────────────────────────────────

class _ReportsTab extends StatelessWidget {
  final List<AdminReport> reports;

  const _ReportsTab({required this.reports});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const AdminEmptyState(
        message: 'No reports against this user',
        icon: Icons.verified_user_rounded,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ReportTile(report: reports[i]),
    );
  }
}

enum _ReportPriority { high, medium, low }

_ReportPriority _priority(AdminReport report) {
  final r = report.reason.toLowerCase();
  const highTerms = ['harassment', 'violence', 'threats', 'sexual', 'abuse', 'explicit', 'assault'];
  const medTerms = ['spam', 'fake', 'impersonation', 'scam', 'fraud', 'misinformation'];
  if (highTerms.any(r.contains)) return _ReportPriority.high;
  if (medTerms.any(r.contains)) return _ReportPriority.medium;
  return _ReportPriority.low;
}

class _ReportTile extends StatelessWidget {
  final AdminReport report;

  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = _priority(report);
    Color priorityColor;
    String priorityLabel;
    switch (p) {
      case _ReportPriority.high:
        priorityColor = const Color(0xFFEF4444);
        priorityLabel = 'HIGH';
      case _ReportPriority.medium:
        priorityColor = const Color(0xFFF59E0B);
        priorityLabel = 'MED';
      case _ReportPriority.low:
        priorityColor = YanegiColors.textTertiary;
        priorityLabel = 'LOW';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.sm),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: priorityColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  priorityLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: priorityColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: report.status),
              const Spacer(),
              Text(
                report.createdAt != null
                    ? DateFormat('d MMM yyyy').format(report.createdAt!)
                    : '—',
                style: const TextStyle(
                    fontSize: 11, color: YanegiColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            report.reason,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: YanegiColors.textPrimary,
            ),
          ),
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              report.description,
              style: const TextStyle(
                  fontSize: 12, color: YanegiColors.textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'From: ${report.reporterName.isNotEmpty ? report.reporterName : report.reporterId}',
            style: const TextStyle(
                fontSize: 11, color: YanegiColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ReportStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case ReportStatus.pending:
        color = const Color(0xFFFFC615);
      case ReportStatus.resolved:
        color = YanegiColors.accentSuccess;
      case ReportStatus.dismissed:
        color = YanegiColors.textTertiary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _UserDetailData {
  final UserProfile? profile;
  final List<Map<String, dynamic>> hostedEvents;
  final List<Map<String, dynamic>> joinedEvents;
  final List<AdminReport> reports;

  const _UserDetailData({
    required this.profile,
    required this.hostedEvents,
    required this.joinedEvents,
    required this.reports,
  });
}
