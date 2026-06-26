import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../theme/yanegi_theme.dart';
import '../models/admin_report.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';
import 'user_detail_screen.dart';

enum _ReportPriority { high, medium, low }

_ReportPriority _computePriority(AdminReport report) {
  final r = report.reason.toLowerCase();
  const highTerms = [
    'harassment', 'violence', 'threats', 'sexual', 'abuse', 'explicit', 'assault'
  ];
  const medTerms = [
    'spam', 'fake', 'impersonation', 'scam', 'fraud', 'misinformation'
  ];
  if (highTerms.any(r.contains)) return _ReportPriority.high;
  if (medTerms.any(r.contains)) return _ReportPriority.medium;
  return _ReportPriority.low;
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: ReportStatus.values.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(adminReportsFilterProvider.notifier).state =
            ReportStatus.values[_tabController.index];
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: YanegiColors.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: YanegiColors.primary,
            unselectedLabelColor: YanegiColors.textSecondary,
            indicatorColor: YanegiColors.primary,
            indicatorWeight: 2,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Resolved'),
              Tab(text: 'Dismissed'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: ReportStatus.values
                .map((status) => _ReportTable(status: status))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ReportTable extends ConsumerWidget {
  final ReportStatus status;

  const _ReportTable({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(adminReportsProvider(status));

    return reportsAsync.when(
      loading: () => const AdminSkeletonList(itemCount: 8),
      error: (e, _) => AdminErrorState(message: e.toString()),
      data: (reports) {
        if (reports.isEmpty) {
          return AdminEmptyState(
            message: 'No ${status.name} reports',
            icon: status == ReportStatus.pending
                ? Icons.check_circle_outline_rounded
                : Icons.inbox_rounded,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                '${reports.length} ${status.name} report${reports.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textTertiary),
              ),
            ),
            _buildHeaders(),
            const Divider(height: 1, color: Color(0xFF1A1A1A)),
            Expanded(
              child: ListView.separated(
                itemCount: reports.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFF111111)),
                itemBuilder: (context, i) => _ReportRow(
                  report: reports[i],
                  onTapReporter: reports[i].reporterId.isNotEmpty
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => UserDetailScreen(
                                uid: reports[i].reporterId),
                          ))
                      : null,
                  onTapReported: reports[i].reportedUserId.isNotEmpty
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => UserDetailScreen(
                                uid: reports[i].reportedUserId),
                          ))
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaders() {
    return Container(
      color: YanegiColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 1, child: _ColHeader('PRIORITY')),
          Expanded(flex: 3, child: _ColHeader('REASON')),
          Expanded(flex: 3, child: _ColHeader('DESCRIPTION')),
          Expanded(flex: 2, child: _ColHeader('REPORTER')),
          Expanded(flex: 2, child: _ColHeader('REPORTED USER')),
          Expanded(flex: 2, child: _ColHeader('DATE')),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final AdminReport report;
  final VoidCallback? onTapReporter;
  final VoidCallback? onTapReported;

  const _ReportRow({
    required this.report,
    this.onTapReporter,
    this.onTapReported,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = report.createdAt != null
        ? DateFormat('d MMM yyyy').format(report.createdAt!)
        : '—';

    final reason = report.reason.isNotEmpty
        ? report.reason
              .replaceAll('_', ' ')
              .split(' ')
              .map((w) => w.isEmpty
                  ? ''
                  : '${w[0].toUpperCase()}${w.substring(1)}')
              .join(' ')
        : '—';

    final priority = _computePriority(report);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Priority badge
          Expanded(flex: 1, child: _PriorityBadge(priority: priority)),
          // Reason
          Expanded(
            flex: 3,
            child: Text(
              reason,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: YanegiColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          // Description
          Expanded(
            flex: 3,
            child: Text(
              report.description.isNotEmpty ? report.description : '—',
              style: const TextStyle(
                fontSize: 12,
                color: YanegiColors.textSecondary,
                height: 1.4,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          // Reporter
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: onTapReporter,
              child: Text(
                report.reporterName.isNotEmpty
                    ? report.reporterName
                    : report.reporterId.isNotEmpty
                        ? '${report.reporterId.substring(0, 8)}...'
                        : '—',
                style: TextStyle(
                  fontSize: 13,
                  color: onTapReporter != null
                      ? YanegiColors.primary
                      : YanegiColors.textSecondary,
                  decoration: onTapReporter != null
                      ? TextDecoration.underline
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Reported user
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: onTapReported,
              child: Text(
                report.reportedUserName.isNotEmpty
                    ? report.reportedUserName
                    : report.reportedUserId.isNotEmpty
                        ? '${report.reportedUserId.substring(0, 8)}...'
                        : '—',
                style: TextStyle(
                  fontSize: 13,
                  color: onTapReported != null
                      ? YanegiColors.primary
                      : YanegiColors.textSecondary,
                  decoration: onTapReported != null
                      ? TextDecoration.underline
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Date
          Expanded(
            flex: 2,
            child: Text(
              dateStr,
              style: const TextStyle(
                  fontSize: 12, color: YanegiColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final _ReportPriority priority;

  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (priority) {
      case _ReportPriority.high:
        color = const Color(0xFFEF4444);
        label = 'HIGH';
      case _ReportPriority.medium:
        color = const Color(0xFFF59E0B);
        label = 'MED';
      case _ReportPriority.low:
        color = YanegiColors.textTertiary;
        label = 'LOW';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color,
            letterSpacing: 0.5),
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: YanegiColors.textTertiary,
        letterSpacing: 0.6,
      ),
    );
  }
}
