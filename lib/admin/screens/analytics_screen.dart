import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/yanegi_theme.dart';
import '../models/admin_daily_stat.dart';
import '../models/admin_growth_stats.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';
import '../widgets/analytics_bar_chart.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(adminAnalyticsProvider);
    final growthAsync = ref.watch(adminGrowthStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('ACTIVITY CHARTS (LAST 14 DAYS)'),
          const SizedBox(height: 16),
          analyticsAsync.when(
            loading: () => const AdminSkeletonStatGrid(),
            error: (e, _) => AdminErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(adminAnalyticsProvider),
            ),
            data: (data) => _ChartsGrid(data: data),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('USER FUNNEL'),
          const SizedBox(height: 16),
          growthAsync.when(
            loading: () => const AdminSkeletonBox(height: 200),
            error: (_, __) => const SizedBox.shrink(),
            data: (s) => _UserFunnelCard(stats: s),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('PROFILE COMPLETION FUNNEL'),
          const SizedBox(height: 16),
          growthAsync.when(
            loading: () => const AdminSkeletonBox(height: 180),
            error: (_, __) => const SizedBox.shrink(),
            data: (s) => _ProfileFunnelCard(stats: s),
          ),
          const SizedBox(height: 24),
          _buildNote(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
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
      ],
    );
  }

  Widget _buildNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: YanegiColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: YanegiColors.textTertiary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Funnel steps marked "—" require additional Firestore fields or '
              'analytics events. Charts require lastSeen, createdAt, and events.createdAt fields.',
              style:
                  TextStyle(fontSize: 12, color: YanegiColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Charts ────────────────────────────────────────────────────────────────────

class _ChartsGrid extends StatelessWidget {
  final AdminAnalyticsData data;

  const _ChartsGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 800;
      if (wide) {
        return Column(
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _ChartCard(
                  label: 'Daily New Users',
                  data: data.newUsers,
                  barColor: YanegiColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ChartCard(
                  label: 'Daily Active Users',
                  data: data.activeUsers,
                  barColor: YanegiColors.accentSuccess,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _ChartCard(
                  label: 'Events Created Per Day',
                  data: data.newEvents,
                  barColor: const Color(0xFF818CF8),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ChartCard(
                  label: 'Communities Created Per Day',
                  data: data.newCommunities,
                  barColor: const Color(0xFFFB923C),
                ),
              ),
            ]),
          ],
        );
      }
      return Column(
        children: [
          _ChartCard(label: 'Daily New Users', data: data.newUsers, barColor: YanegiColors.primary),
          const SizedBox(height: 16),
          _ChartCard(label: 'Daily Active Users', data: data.activeUsers, barColor: YanegiColors.accentSuccess),
          const SizedBox(height: 16),
          _ChartCard(label: 'Events Created Per Day', data: data.newEvents, barColor: const Color(0xFF818CF8)),
          const SizedBox(height: 16),
          _ChartCard(label: 'Communities Created Per Day', data: data.newCommunities, barColor: const Color(0xFFFB923C)),
        ],
      );
    });
  }
}

class _ChartCard extends StatelessWidget {
  final String label;
  final List<AdminDailyStat> data;
  final Color barColor;

  const _ChartCard({
    required this.label,
    required this.data,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.lg),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: data.isEmpty
          ? SizedBox(
              height: 220,
              child: AdminEmptyState(
                message: 'No data for "$label"',
                icon: Icons.bar_chart_rounded,
              ),
            )
          : AdminBarChart(data: data, label: label, barColor: barColor),
    );
  }
}

// ── User Funnel ───────────────────────────────────────────────────────────────

class _UserFunnelCard extends StatelessWidget {
  final AdminGrowthStats stats;

  const _UserFunnelCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.totalUsers;
    final steps = [
      _FunnelStep('Account Created', total, total),
      _FunnelStep('Completed Profile', null, total),
      _FunnelStep('Created First Event', null, total),
      _FunnelStep('Joined First Event', null, total),
      _FunnelStep('Attended an Event', null, total),
      _FunnelStep('Returned After 7 Days', null, total),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.lg),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.map((s) => _FunnelStepRow(step: s)).toList(),
      ),
    );
  }
}

class _ProfileFunnelCard extends StatelessWidget {
  final AdminGrowthStats stats;

  const _ProfileFunnelCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.totalUsers;
    final steps = [
      _FunnelStep('Registered', total, total),
      _FunnelStep('Added Photo', null, total),
      _FunnelStep('Added Bio', null, total),
      _FunnelStep('Added Interests', null, total),
      _FunnelStep('Added Date of Birth', null, total),
      _FunnelStep('Completed Profile', null, total),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.lg),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.map((s) => _FunnelStepRow(step: s)).toList(),
      ),
    );
  }
}

class _FunnelStep {
  final String label;
  final int? count;
  final int topCount;

  const _FunnelStep(this.label, this.count, this.topCount);

  double get ratio {
    if (count == null || topCount == 0) return 0.0;
    return count! / topCount;
  }

  String get pctText {
    if (count == null) return '—';
    if (topCount == 0) return '0%';
    return '${(count! / topCount * 100).toStringAsFixed(0)}%';
  }
}

class _FunnelStepRow extends StatelessWidget {
  final _FunnelStep step;

  const _FunnelStepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  step.label,
                  style: const TextStyle(
                      fontSize: 13, color: YanegiColors.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                step.count != null ? '${step.count}' : '—',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: YanegiColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  step.pctText,
                  style: const TextStyle(
                      fontSize: 12, color: YanegiColors.textTertiary),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, constraints) {
            final fillWidth = step.count != null
                ? constraints.maxWidth * step.ratio
                : 0.0;
            return Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: YanegiColors.surfaceElevated,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 6,
                  width: fillWidth.clamp(0, constraints.maxWidth),
                  decoration: BoxDecoration(
                    color: step.count != null
                        ? YanegiColors.primary.withAlpha(200)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
