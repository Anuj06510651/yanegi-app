import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/yanegi_theme.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';

class LocationAnalyticsScreen extends ConsumerWidget {
  const LocationAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(adminLocationProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Location Analytics',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Events per city — active events only',
            style: TextStyle(fontSize: 13, color: YanegiColors.textTertiary),
          ),
          const SizedBox(height: 24),
          locationAsync.when(
            loading: () => const AdminSkeletonList(itemCount: 8),
            error: (e, _) => AdminErrorState(message: e.toString()),
            data: (cityMap) {
              if (cityMap.isEmpty) {
                return const AdminEmptyState(
                  message: 'No location data available',
                  icon: Icons.location_off_rounded,
                );
              }
              final sorted = cityMap.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final maxCount = sorted.first.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sorted.length} cities with active events',
                    style: const TextStyle(
                        fontSize: 12, color: YanegiColors.textTertiary),
                  ),
                  const SizedBox(height: 16),
                  ...sorted.map((entry) => _CityRow(
                        city: entry.key,
                        count: entry.value,
                        maxCount: maxCount,
                      )),
                  const SizedBox(height: 20),
                  _buildHeatmapPlaceholder(),
                  const SizedBox(height: 8),
                  const Text(
                    'City is extracted from the first segment of the event location name field.',
                    style: TextStyle(
                        fontSize: 11, color: YanegiColors.textTertiary),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapPlaceholder() {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.lg),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_rounded, size: 32, color: YanegiColors.textTertiary),
          SizedBox(height: 10),
          Text(
            'HEATMAP',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Interactive map visualization — coming soon',
            style: TextStyle(fontSize: 13, color: YanegiColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _CityRow extends StatelessWidget {
  final String city;
  final int count;
  final int maxCount;

  const _CityRow({
    required this.city,
    required this.count,
    required this.maxCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.sm),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              city,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: YanegiColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final fillWidth = maxCount > 0
                  ? constraints.maxWidth * count / maxCount
                  : 0.0;
              return Container(
                height: 8,
                decoration: BoxDecoration(
                  color: YanegiColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 8,
                    width: fillWidth,
                    decoration: BoxDecoration(
                      color: YanegiColors.primary.withAlpha(180),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 16),
          Text(
            '$count event${count == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: YanegiColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
