import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SafetyReportingScreen extends StatelessWidget {
  const SafetyReportingScreen({super.key});

  static const String _safetyEmail = 'supportyanegi@gmail.com';

  static const List<String> _quickSummary = [
    'Your safety is a priority whenever you use Yanegi.',
    'You can report concerns quickly and privately.',
    'In emergencies, contact local authorities first.',
  ];

  static const List<_SafetySection> _sections = [
    _SafetySection(
      title: 'How to Report',
      points: [
        'Open Report a Problem from Settings when something feels unsafe.',
        'Share clear details: what happened, where, and who was involved.',
        'Include screenshots or evidence when available.',
      ],
    ),
    _SafetySection(
      title: 'What You Can Report',
      points: [
        'Harassment, threats, hate speech, or intimidation.',
        'Scams, fraud, suspicious payment requests, or impersonation.',
        'Unsafe or illegal event behavior and repeated policy violations.',
      ],
    ),
    _SafetySection(
      title: 'Response Time',
      points: [
        'Critical safety reports are prioritized as quickly as possible.',
        'Most standard reports are reviewed within 24-72 hours.',
        'You may be contacted if we need additional details.',
      ],
    ),
    _SafetySection(
      title: 'Emergency Info',
      points: [
        'If you are in immediate danger, contact local emergency services first.',
        'Do not wait for an in-app response during urgent incidents.',
        'After you are safe, send details to help us take platform action.',
      ],
    ),
  ];

  Future<void> _openEmail(
    BuildContext context, {
    required String email,
    required String subject,
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': subject,
      },
    );

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app found')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found')),
      );
    }
  }

  void _showReportFuture(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report flow coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final textSecondary = scheme.onSurface.withOpacity(0.72);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        title: Text(
          'Safety & Reporting',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QuickSummaryCard(items: _quickSummary),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.primary.withOpacity(0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.local_police_outlined,
                        color: scheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Call Police (100) if in danger',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: textSecondary.withOpacity(0.22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safety Tips',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _tipRow('Meet in public places'),
                  _tipRow('Share location'),
                  _tipRow('Trust instincts'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ..._sections.map((section) => _SafetySectionCard(section: section)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openEmail(
                      context,
                      email: _safetyEmail,
                      subject: 'Safety Report - Yanegi App',
                    ),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text(_safetyEmail),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showReportFuture(context),
                    icon: const Icon(Icons.report_gmailerrorred_outlined),
                    label: const Text('Report (Future)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipRow(String tip) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.verified_user_outlined,
                size: 16, color: Colors.green),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetySection {
  final String title;
  final List<String> points;

  const _SafetySection({
    required this.title,
    required this.points,
  });
}

class _SafetySectionCard extends StatelessWidget {
  final _SafetySection section;

  const _SafetySectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textSecondary = scheme.onSurface.withOpacity(0.72);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textSecondary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ...section.points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.circle, size: 7, color: Colors.blueGrey),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      point,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickSummaryCard extends StatelessWidget {
  final List<String> items;

  const _QuickSummaryCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textSecondary = scheme.onSurface.withOpacity(0.72);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textSecondary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Summary',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
