import 'package:flutter/material.dart';

import '../../theme/yanegi_theme.dart';

/// Centered empty state shown when a list or query returns no results.
class AdminEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const AdminEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: YanegiColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: YanegiColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
