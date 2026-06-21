import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _contactEmail = 'supportyanegi@gmail.com';

  static const List<_PolicySection> _sections = [
    _PolicySection(
      title: 'Information We Collect',
      body:
          'We collect account basics (such as username, profile details), optional photos you upload, and location-related data needed for event discovery and participation. We may also collect technical diagnostics for reliability and safety.',
      warning:
          'Please avoid sharing sensitive personal details in public profiles or event descriptions.',
    ),
    _PolicySection(
      title: 'How We Use Data',
      body:
          'Data is used to operate app features: account setup, event discovery, notifications, safety checks, support responses, and product improvements. Location is used only to power location-based event functionality.',
    ),
    _PolicySection(
      title: 'Data Sharing',
      body:
          'We do not sell your personal data. Data may be shared only with trusted infrastructure providers needed to run app services (for example, cloud storage/notifications), and only as required to deliver app functionality.',
      warning: 'We do not sell your data to advertisers.',
    ),
    _PolicySection(
      title: 'Data Retention',
      body:
          'We retain data while your account is active and as needed for legal/safety obligations. Some logs may be retained for abuse prevention and reliability. You can request account-related actions via support.',
    ),
    _PolicySection(
      title: 'Your Rights',
      body:
          'You can update profile details, control visibility, and manage notifications from Settings. You can also contact support for account-related privacy requests.',
    ),
    _PolicySection(
      title: 'Security',
      body:
          'We use standard security practices and platform protections to reduce risk of unauthorized access. No system is perfect, but we continuously improve safeguards and monitoring.',
      warning:
          'Help protect your account by using secure device settings and keeping the app updated.',
    ),
    _PolicySection(
      title: 'Contact',
      body:
          'For privacy questions, data concerns, or policy clarification, contact our support team at the email below.',
    ),
  ];

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _contactEmail,
      queryParameters: const {
        'subject': 'Privacy Policy Question - Yanegi App',
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
          'Privacy Policy',
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
                    'Quick Summary',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _summaryBullet(
                    context,
                    'We help you discover events with essential account and location data.',
                  ),
                  _summaryBullet(
                      context, 'You control your data from Settings.'),
                  _summaryBullet(context, 'We do not sell your data.'),
                  _summaryBullet(
                      context, 'Respectful use helps protect everyone.'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ..._sections.map((section) {
              return _PolicySectionCard(
                section: section,
                onContactTap: section.title == 'Contact'
                    ? () => _openEmail(context)
                    : null,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _summaryBullet(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    final textSecondary = scheme.onSurface.withOpacity(0.72);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child:
                Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textSecondary,
                height: 1.35,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySection {
  final String title;
  final String body;
  final String? warning;

  const _PolicySection({
    required this.title,
    required this.body,
    this.warning,
  });
}

class _PolicySectionCard extends StatelessWidget {
  final _PolicySection section;
  final VoidCallback? onContactTap;

  const _PolicySectionCard({
    required this.section,
    this.onContactTap,
  });

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
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: TextStyle(
              color: textSecondary,
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
          if (section.warning != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.warning!,
                    style: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (onContactTap != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onContactTap,
              child: Text(
                PrivacyPolicyScreen._contactEmail,
                style: TextStyle(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
