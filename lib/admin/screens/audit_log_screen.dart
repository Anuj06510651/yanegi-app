import 'package:flutter/material.dart';

import '../../theme/yanegi_theme.dart';

class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});

  static const _examples = [
    ('Just now', 'admin@yanegi.com', 'Viewed report', 'Report #xyz789'),
    ('2m ago', 'admin@yanegi.com', 'Opened event detail', 'Event #def456'),
    ('1h ago', 'admin@yanegi.com', 'Searched users', 'query: "anuj"'),
    ('3h ago', 'admin@yanegi.com', 'Viewed user profile', 'User #abc123'),
    ('Yesterday', 'admin@yanegi.com', 'Refreshed dashboard', '—'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Audit Log',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Track every admin action on the platform',
            style: TextStyle(fontSize: 13, color: YanegiColors.textTertiary),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: YanegiColors.primary.withAlpha(18),
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              border: Border.all(color: YanegiColors.primary.withAlpha(60)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: YanegiColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Audit logging will be enabled in the next admin release. '
                    'Every action taken by admins will appear here automatically.',
                    style: TextStyle(
                        fontSize: 13, color: YanegiColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const _SectionLabel('PLANNED LOG STRUCTURE'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: YanegiColors.surface,
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              border: Border.all(color: Colors.white.withAlpha(8)),
            ),
            child: Column(
              children: [
                _buildHeader(),
                const Divider(height: 1, color: Color(0xFF1A1A1A)),
                ..._examples.map(
                  (e) => Opacity(
                    opacity: 0.45,
                    child: _buildRow(e.$1, e.$2, e.$3, e.$4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Rows above are examples only and do not represent real data.',
            style: TextStyle(fontSize: 11, color: YanegiColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: YanegiColors.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _ColHeader('TIME')),
          Expanded(flex: 3, child: _ColHeader('ADMIN')),
          Expanded(flex: 3, child: _ColHeader('ACTION')),
          Expanded(flex: 3, child: _ColHeader('TARGET')),
        ],
      ),
    );
  }

  Widget _buildRow(
      String time, String admin, String action, String target) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(time,
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textTertiary)),
          ),
          Expanded(
            flex: 3,
            child: Text(admin,
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textSecondary)),
          ),
          Expanded(
            flex: 3,
            child: Text(action,
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textPrimary)),
          ),
          Expanded(
            flex: 3,
            child: Text(target,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: YanegiColors.textTertiary)),
          ),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

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
