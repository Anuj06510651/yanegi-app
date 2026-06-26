import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/yanegi_theme.dart';
import '../models/admin_attention_item.dart';
import '../models/admin_growth_stats.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';

class DashboardHomeScreen extends ConsumerWidget {
  const DashboardHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: 'NEEDS ATTENTION',
            onRefresh: () {
              ref.invalidate(adminAttentionProvider);
              ref.invalidate(adminGrowthStatsProvider);
            },
          ),
          const SizedBox(height: 14),
          _AttentionSection(),
          const SizedBox(height: 32),
          const _SectionHeader(title: 'GROWTH METRICS'),
          const SizedBox(height: 14),
          _GrowthSection(),
          const SizedBox(height: 32),
          const _SectionHeader(title: 'COMMUNITY HEALTH'),
          const SizedBox(height: 14),
          _HealthSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onRefresh;

  const _SectionHeader({required this.title, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: YanegiColors.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Container(height: 1, color: const Color(0xFF1A1A1A))),
        if (onRefresh != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: onRefresh,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.refresh_rounded,
                  size: 14, color: YanegiColors.textTertiary),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Needs Attention ───────────────────────────────────────────────────────────

class _AttentionSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminAttentionProvider);

    return async.when(
      loading: () => const _AttentionSkeleton(),
      error: (e, _) => AdminErrorState(message: e.toString()),
      data: (items) {
        if (items.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: YanegiColors.accentSuccess.withAlpha(20),
              borderRadius: BorderRadius.circular(YanegiRadius.sm),
              border: Border.all(color: YanegiColors.accentSuccess.withAlpha(60)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 16, color: YanegiColors.accentSuccess),
                SizedBox(width: 8),
                Text(
                  'All clear — no items need attention right now.',
                  style: TextStyle(
                      fontSize: 13, color: YanegiColors.accentSuccess),
                ),
              ],
            ),
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((item) => _AttentionCard(item: item)).toList(),
        );
      },
    );
  }
}

class _AttentionCard extends ConsumerWidget {
  final AdminAttentionItem item;

  const _AttentionCard({required this.item});

  Color get _severityColor {
    switch (item.severity) {
      case AttentionSeverity.critical:
        return const Color(0xFFEF4444);
      case AttentionSeverity.warning:
        return const Color(0xFFF59E0B);
      case AttentionSeverity.info:
        return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _severityColor;
    return GestureDetector(
      onTap: () =>
          ref.read(adminRouteProvider.notifier).state = item.route,
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(YanegiRadius.md),
          border: Border(
            left: BorderSide(color: color, width: 3),
            top: BorderSide(color: color.withAlpha(50)),
            right: BorderSide(color: color.withAlpha(50)),
            bottom: BorderSide(color: color.withAlpha(50)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    style: const TextStyle(
                        fontSize: 12, color: YanegiColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${item.count}',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionSkeleton extends StatelessWidget {
  const _AttentionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: AdminSkeletonBox(height: 72)),
        const SizedBox(width: 12),
        Expanded(child: AdminSkeletonBox(height: 72)),
      ],
    );
  }
}

// ── Growth Metrics ────────────────────────────────────────────────────────────

class _GrowthSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminGrowthStatsProvider);

    return async.when(
      loading: () => const AdminSkeletonStatGrid(),
      error: (e, _) => AdminErrorState(message: e.toString()),
      data: (s) => _GrowthGrid(stats: s),
    );
  }
}

class _GrowthGrid extends StatelessWidget {
  final AdminGrowthStats stats;

  const _GrowthGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final growthRate = stats.totalUsers > 0
        ? '${(stats.usersThisWeek / stats.totalUsers * 100).toStringAsFixed(1)}%'
        : '—';
    final reportRate = stats.usersThisWeek > 0
        ? '${(stats.reportsThisWeek / stats.usersThisWeek * 100).toStringAsFixed(1)}%'
        : '—';

    final metrics = [
      _MetricData('TOTAL USERS', '${stats.totalUsers}', 'on platform',
          YanegiColors.primary),
      _MetricData(
          'NEW TODAY', '${stats.usersToday}', 'registered', YanegiColors.accentSuccess),
      _MetricData('NEW THIS WEEK', '${stats.usersThisWeek}', '+users',
          YanegiColors.accentSuccess),
      _MetricData(
          'ACTIVE 24H', '${stats.activeUsers24h}', 'last seen', YanegiColors.primary),
      _MetricData(
          'EVENTS TODAY', '${stats.eventsToday}', 'created', const Color(0xFF818CF8)),
      _MetricData('EVENTS THIS WEEK', '${stats.eventsThisWeek}', 'created',
          const Color(0xFF818CF8)),
      _MetricData(
          'LIVE EVENTS', '${stats.activeEvents}', 'happening now', YanegiColors.accentSuccess),
      _MetricData(
          'COMMUNITIES', '${stats.communities}', 'total', const Color(0xFFFB923C)),
      _MetricData(
          'PENDING REPORTS',
          '${stats.reportsPending}',
          'need review',
          stats.reportsPending > 0
              ? const Color(0xFFEF4444)
              : YanegiColors.textTertiary),
      _MetricData('REPORTS THIS WEEK', '${stats.reportsThisWeek}', 'submitted',
          stats.reportsThisWeek > 0
              ? const Color(0xFFF59E0B)
              : YanegiColors.textTertiary),
      _MetricData('GROWTH RATE', growthRate, 'week / total', YanegiColors.primary),
      _MetricData('REPORT RATE', reportRate, 'reports / new users',
          stats.reportsThisWeek > 0
              ? const Color(0xFFEF4444)
              : YanegiColors.textTertiary),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 100,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, i) => _MetricCard(data: metrics[i]),
    );
  }
}

class _MetricData {
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  const _MetricData(this.title, this.value, this.subtitle, this.color);
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard({required this.data});

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
          Text(
            data.title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textTertiary,
              letterSpacing: 0.6,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            data.value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: data.color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.subtitle,
            style: const TextStyle(
                fontSize: 11, color: YanegiColors.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Community Health ──────────────────────────────────────────────────────────

class _HealthSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminGrowthStatsProvider);
    return async.when(
      loading: () => AdminSkeletonBox(height: 80),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        final reportRate = s.usersThisWeek > 0
            ? '${(s.reportsThisWeek / s.usersThisWeek * 100).toStringAsFixed(1)}%'
            : '—';
        final launchDate = DateTime(2024, 1, 1);
        final platformAge =
            DateTime.now().difference(launchDate).inDays;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _HealthTile(
                icon: Icons.event_rounded,
                label: 'Live Events',
                value: '${s.activeEvents}'),
            _HealthTile(
                icon: Icons.flag_rounded,
                label: 'Pending Reports',
                value: '${s.reportsPending}',
                valueColor: s.reportsPending > 0
                    ? const Color(0xFFEF4444)
                    : null),
            _HealthTile(
                icon: Icons.report_rounded,
                label: 'Reports This Week',
                value: '${s.reportsThisWeek}'),
            _HealthTile(
                icon: Icons.percent_rounded,
                label: 'Report Rate',
                value: reportRate),
            _HealthTile(
                icon: Icons.calendar_month_rounded,
                label: 'Platform Age',
                value: '${platformAge}d'),
          ],
        );
      },
    );
  }
}

class _HealthTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _HealthTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.md),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: YanegiColors.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 11, color: YanegiColors.textTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: valueColor ?? YanegiColors.textPrimary,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
