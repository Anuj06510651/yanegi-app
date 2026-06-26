import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../theme/yanegi_theme.dart';

/// A single shimmer-animated placeholder box.
class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: YanegiColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Shimmer wrapper used by all skeleton widgets.
class _Shimmer extends StatelessWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: YanegiColors.surfaceElevated,
      highlightColor: const Color(0xFF2A2A2A),
      child: child,
    );
  }
}

/// Grid of 7 shimmer stat card skeletons (mirrors DashboardHomeScreen grid).
class AdminSkeletonStatGrid extends StatelessWidget {
  const AdminSkeletonStatGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          mainAxisExtent: 140,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 7,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: YanegiColors.surfaceElevated,
            borderRadius: BorderRadius.circular(YanegiRadius.lg),
          ),
        ),
      ),
    );
  }
}

/// A list of shimmer rows used on Users/Events screens.
class AdminSkeletonList extends StatelessWidget {
  final int itemCount;

  const AdminSkeletonList({super.key, this.itemCount = 10});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Row(
          children: [
            const _ShimmerBox(width: 40, height: 40, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerBox(width: MediaQuery.of(context).size.width * 0.25, height: 14),
                  const SizedBox(height: 6),
                  _ShimmerBox(width: MediaQuery.of(context).size.width * 0.15, height: 11),
                ],
              ),
            ),
            const _ShimmerBox(width: 80, height: 11),
          ],
        ),
      ),
    );
  }
}


/// A single shimmer box for inline use in any screen.
class AdminSkeletonBox extends StatelessWidget {
  final double height;
  final double? width;

  const AdminSkeletonBox({super.key, required this.height, this.width});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: YanegiColors.surfaceElevated,
          borderRadius: BorderRadius.circular(YanegiRadius.md),
        ),
      ),
    );
  }
}

/// A full-page shimmer for detail screens (header + rows).
class AdminSkeletonDetail extends StatelessWidget {
  const AdminSkeletonDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _ShimmerBox(width: 72, height: 72, radius: 36),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _ShimmerBox(width: 180, height: 18),
                    SizedBox(height: 8),
                    _ShimmerBox(width: 120, height: 13),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
            ...List.generate(
              6,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: _ShimmerBox(width: double.infinity, height: 48),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
