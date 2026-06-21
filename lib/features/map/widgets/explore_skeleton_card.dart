part of '../../../screens/map_screen.dart';

class _ExploreSkeletonCard extends StatelessWidget {
  const _ExploreSkeletonCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF1F2635),
      highlightColor: const Color(0xFF2D3548),
      period: const Duration(milliseconds: 1100),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2635),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: height * 0.45,
              decoration: BoxDecoration(
                color: const Color(0xFF2D3548),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF2D3548),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 10,
              width: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF2D3548),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
