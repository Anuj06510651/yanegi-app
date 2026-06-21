import 'package:flutter/material.dart';
import '../theme/yanegi_theme.dart';

class NearbyPill extends StatelessWidget {
  final int count;

  const NearbyPill({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: YanegiColors.surface.withAlpha(220),
        border: Border.all(
          color: YanegiColors.accentGreen.withAlpha(100),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: YanegiColors.accentGreen.withAlpha(30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: YanegiColors.accentGreen,
              boxShadow: [
                BoxShadow(
                  color: YanegiColors.accentGreen,
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count+ nearby',
            style: TextStyle(
              color: YanegiColors.accentGreen.withAlpha(240),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
