import 'package:flutter/material.dart';

import '../../config/app_environment.dart';
import '../../theme/yanegi_theme.dart';

class ReleaseDashboardScreen extends StatelessWidget {
  const ReleaseDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDev = AppEnvironment.isDev;
    final projectId = isDev ? 'yanegi-dev' : 'yanegi-684f9';
    final env = isDev ? 'Development' : 'Production';
    final envColor = isDev
        ? const Color(0xFFFFC615)
        : const Color(0xFF3B82F6);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Release Dashboard',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'App version, environment, and platform status',
            style: TextStyle(fontSize: 13, color: YanegiColors.textTertiary),
          ),
          const SizedBox(height: 24),
          // Environment card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: envColor.withAlpha(18),
              borderRadius: BorderRadius.circular(YanegiRadius.lg),
              border: Border.all(color: envColor.withAlpha(60)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: envColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isDev ? 'DEV' : 'PROD',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: envColor,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$env Environment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: envColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Firebase project: $projectId',
                        style: const TextStyle(
                            fontSize: 12, color: YanegiColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSection('APP VERSION', [
            _buildRow('Current Version', '1.0.5+15'),
            _buildRow('Environment', env),
            _buildRow('Firebase Project', projectId),
            _buildRow('Platform', 'Flutter (Web/Android/iOS)'),
          ]),
          const SizedBox(height: 20),
          _buildSection('FIREBASE STATUS', [
            _buildStatusRow('Firestore', true),
            _buildStatusRow('Authentication', true),
            _buildStatusRow('Storage', null),
            _buildStatusRow('Functions', null),
          ]),
          const SizedBox(height: 20),
          _buildSection('APP DISTRIBUTION', [
            _buildRow('Android Users', '—'),
            _buildRow('iOS Users', '—'),
            _buildRow('Web Users', '—'),
          ]),
          const SizedBox(height: 20),
          _buildSection('STABILITY', [
            _buildRow('Crash Rate', '—'),
            _buildRow('ANR Rate', '—'),
          ]),
          const SizedBox(height: 12),
          const Text(
            'Connect Firebase Crashlytics to track crash and ANR rates.',
            style: TextStyle(fontSize: 11, color: YanegiColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: YanegiColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: YanegiColors.surface,
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(color: Colors.white.withAlpha(8)),
          ),
          child: Column(
            children: rows
                .asMap()
                .entries
                .map((e) => Column(children: [
                      e.value,
                      if (e.key < rows.length - 1)
                        const Divider(
                            height: 1,
                            color: Color(0xFF1A1A1A),
                            indent: 16,
                            endIndent: 16),
                    ]))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: YanegiColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: YanegiColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, bool? connected) {
    final color = connected == null
        ? YanegiColors.textTertiary
        : connected
            ? YanegiColors.accentSuccess
            : const Color(0xFFEF4444);
    final text = connected == null ? '—' : (connected ? 'Connected' : 'Error');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: YanegiColors.textSecondary),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (connected != null)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
