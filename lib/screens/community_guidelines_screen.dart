import 'package:flutter/material.dart';

class CommunityGuidelinesScreen extends StatelessWidget {
  const CommunityGuidelinesScreen({super.key});

  static const List<String> _quickSummary = [
    'We want events to feel welcoming and safe for everyone.',
    'You can connect freely while respecting other people’s boundaries.',
    'Clear profiles and honest communication build trust.',
  ];

  static const List<_GuidelineSection> _sections = [
    _GuidelineSection(
      title: 'Event Rules',
      allowed: [
        'Create clear, accurate event details.',
        'Keep venues and activities lawful and safe.',
        'Treat hosts, attendees, and staff respectfully.',
      ],
      notAllowed: [
        'No illegal events.',
        'No dangerous activities that violate local law.',
        'No misleading event details or fake ticket claims.',
      ],
    ),
    _GuidelineSection(
      title: 'Chat Rules',
      allowed: [
        'Use polite, relevant communication.',
        'Report abusive messages instead of escalating.',
      ],
      notAllowed: [
        'No harassment.',
        'No hate speech, threats, or intimidation.',
        'No spam, scams, or repeated unwanted messages.',
      ],
    ),
    _GuidelineSection(
      title: 'Authenticity',
      allowed: [
        'Use your real identity and current profile details.',
        'Share genuine photos and truthful interests.',
      ],
      notAllowed: [
        'No fake profiles.',
        'No impersonation of people, brands, or organizations.',
      ],
    ),
    _GuidelineSection(
      title: 'Privacy Respect',
      allowed: [
        'Respect personal boundaries and consent.',
        'Use shared information only for intended interaction.',
      ],
      notAllowed: [
        'Do not share private user data without permission.',
        'Do not dox, stalk, or pressure users for personal info.',
      ],
    ),
    _GuidelineSection(
      title: 'Consequences',
      allowed: [
        'Appeal politely through support if you think a moderation action is incorrect.',
      ],
      notAllowed: [
        'Violations may lead to warnings, content removal, account suspension, or permanent bans.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        title: Text(
          'Community Guidelines',
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
            _KeyStandardsCard(),
            const SizedBox(height: 14),
            ..._sections
                .map((section) => _GuidelineSectionCard(section: section)),
          ],
        ),
      ),
    );
  }
}

class _GuidelineSection {
  final String title;
  final List<String> allowed;
  final List<String> notAllowed;

  const _GuidelineSection({
    required this.title,
    required this.allowed,
    required this.notAllowed,
  });
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

class _KeyStandardsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textSecondary = scheme.onSurface.withOpacity(0.72);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule_outlined, color: scheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Key Standards',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _highlightItem('No illegal events', textSecondary),
          _highlightItem('No harassment', textSecondary),
          _highlightItem('No fake profiles', textSecondary),
        ],
      ),
    );
  }

  Widget _highlightItem(String text, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.circle, size: 8, color: Colors.blueGrey.shade500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidelineSectionCard extends StatelessWidget {
  final _GuidelineSection section;

  const _GuidelineSectionCard({required this.section});

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
          _label(
            context,
            icon: Icons.check_circle,
            iconColor: Colors.green,
            text: 'Allowed',
          ),
          const SizedBox(height: 6),
          ...section.allowed.map((item) {
            return _bulletRule(
              context,
              icon: Icons.check,
              iconColor: Colors.green,
              text: item,
            );
          }),
          const SizedBox(height: 8),
          _label(
            context,
            icon: Icons.cancel,
            iconColor: Theme.of(context).colorScheme.error,
            text: 'Not allowed',
          ),
          const SizedBox(height: 6),
          ...section.notAllowed.map((item) {
            return _bulletRule(
              context,
              icon: Icons.close,
              iconColor: Theme.of(context).colorScheme.error,
              text: item,
            );
          }),
        ],
      ),
    );
  }

  Widget _label(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _bulletRule(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String text,
  }) {
    final textSecondary =
        Theme.of(context).colorScheme.onSurface.withOpacity(0.72);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: iconColor),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '• $text',
              style: TextStyle(
                color: textSecondary,
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
