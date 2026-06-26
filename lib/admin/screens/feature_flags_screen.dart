import 'package:flutter/material.dart';

import '../../theme/yanegi_theme.dart';

class FeatureFlagsScreen extends StatelessWidget {
  const FeatureFlagsScreen({super.key});

  static const _flags = [
    ('Gallery', 'Allow users to upload gallery photos to their profile'),
    ('Attendance Confirmation', 'Enable hosts to mark attendees after events end'),
    ('Profile Verification', 'Show a verified badge on eligible user profiles'),
    ('Communities', 'Enable community creation and discovery'),
    ('AI Moderation', 'Automatically flag potentially harmful content for review'),
    ('Push Notifications', 'Enable FCM push notifications across the platform'),
    ('Event Waitlist', 'Allow users to join a waitlist for full events'),
    ('Event Recap', 'Post-event shoutout and recap flow'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Feature Flags',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: YanegiColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Control platform features without deploying code',
            style: TextStyle(fontSize: 13, color: YanegiColors.textTertiary),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withAlpha(18),
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withAlpha(60)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Color(0xFFF59E0B)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These flags are display-only. Backend implementation is required '
                    'before any flag can take effect.',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFFF59E0B)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: YanegiColors.surface,
              borderRadius: BorderRadius.circular(YanegiRadius.lg),
              border: Border.all(color: Colors.white.withAlpha(8)),
            ),
            child: Column(
              children: _flags.asMap().entries.map((entry) {
                final flag = entry.value;
                final isLast = entry.key == _flags.length - 1;
                return Column(
                  children: [
                    SwitchListTile.adaptive(
                      title: Text(
                        flag.$1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: YanegiColors.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        flag.$2,
                        style: const TextStyle(
                            fontSize: 12,
                            color: YanegiColors.textTertiary),
                      ),
                      value: false,
                      onChanged: null,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    ),
                    if (!isLast)
                      const Divider(
                          height: 1,
                          color: Color(0xFF1A1A1A),
                          indent: 20,
                          endIndent: 20),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
