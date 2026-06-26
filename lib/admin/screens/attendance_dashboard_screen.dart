import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/yanegi_theme.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';
import 'user_detail_screen.dart';

class AttendanceDashboardScreen extends ConsumerWidget {
  const AttendanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topHostsAsync = ref.watch(adminTopHostsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attendance Dashboard',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Host rankings, attendance rates, and no-shows',
            style: TextStyle(fontSize: 13, color: YanegiColors.textTertiary),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: YanegiColors.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              border:
                  Border.all(color: YanegiColors.primary.withAlpha(60)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: YanegiColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Attendance tracking requires hosts to confirm attendance after events. '
                    'This feature will be enabled in a future release.',
                    style: TextStyle(
                        fontSize: 13, color: YanegiColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _SectionLabel('ATTENDANCE OVERVIEW'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const [
              _PlaceholderTile(
                  icon: Icons.how_to_reg_rounded,
                  label: 'Avg Attendance Rate',
                  value: '—'),
              _PlaceholderTile(
                  icon: Icons.person_off_rounded,
                  label: 'No-Show Rate',
                  value: '—'),
              _PlaceholderTile(
                  icon: Icons.pending_rounded,
                  label: 'Awaiting Confirmation',
                  value: '—'),
              _PlaceholderTile(
                  icon: Icons.report_problem_rounded,
                  label: 'Disputes',
                  value: '—'),
            ],
          ),
          const SizedBox(height: 28),
          const _SectionLabel('TOP HOSTS BY EVENT COUNT'),
          const SizedBox(height: 12),
          topHostsAsync.when(
            loading: () => const AdminSkeletonList(itemCount: 5),
            error: (e, _) => AdminErrorState(message: e.toString()),
            data: (hosts) {
              if (hosts.isEmpty) {
                return const AdminEmptyState(
                    message: 'No hosts yet',
                    icon: Icons.person_outline_rounded);
              }
              return Container(
                decoration: BoxDecoration(
                  color: YanegiColors.surface,
                  borderRadius: BorderRadius.circular(YanegiRadius.md),
                  border: Border.all(color: Colors.white.withAlpha(8)),
                ),
                child: Column(
                  children: hosts.asMap().entries.map((entry) {
                    final host = entry.value;
                    final rank = entry.key + 1;
                    final isLast = entry.key == hosts.length - 1;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '#$rank',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: YanegiColors.textTertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: YanegiColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(Icons.person_rounded,
                                    size: 18,
                                    color: YanegiColors.textTertiary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (host['name'] ?? 'Unknown')
                                          .toString(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: YanegiColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${host['eventCount']} events hosted',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: YanegiColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => UserDetailScreen(
                                        uid:
                                            host['uid'].toString()),
                                  ),
                                ),
                                child: const Text(
                                  'View Profile',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: YanegiColors.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          const Divider(
                              height: 1,
                              color: Color(0xFF1A1A1A),
                              indent: 16,
                              endIndent: 16),
                      ],
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PlaceholderTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.md),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
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
          ]),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textTertiary,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coming soon',
            style: TextStyle(fontSize: 10, color: YanegiColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: YanegiColors.textTertiary,
          letterSpacing: 0.8,
        ),
      );
}
