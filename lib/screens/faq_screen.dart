import 'package:flutter/material.dart';

class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  static const List<_FaqItem> _items = [
    _FaqItem(
      question: 'What is Yanegi?',
      answer:
          'Yanegi is a social app to discover nearby events, connect with people, and join experiences that match your interests.',
    ),
    _FaqItem(
      question: 'How to join event?',
      answer:
          'Open an event from the feed or map, then tap Join/Request. For private or approval-based events, your request will be reviewed by the host.',
    ),
    _FaqItem(
      question: 'Messaging rules',
      answer:
          'Please keep messages respectful and relevant to community interaction. Harassment, spam, or abusive content can lead to restrictions.',
    ),
    _FaqItem(
      question: 'Profile visibility',
      answer:
          'From Settings, you can control profile visibility and whether your profile appears in event participant lists.',
    ),
    _FaqItem(
      question: 'Notifications',
      answer:
          'You can manage push notifications from Settings. Activity updates still appear in-app based on your account actions.',
    ),
    _FaqItem(
      question: 'Nearby events',
      answer:
          'Nearby event suggestions depend on your location and discovery settings. You can enable/disable nearby activity in Settings anytime.',
    ),
    _FaqItem(
      question: 'Report problem',
      answer:
          'Use Settings > Report a Problem to submit issue details, category, and optional screenshot for faster debugging by our team.',
    ),
    _FaqItem(
      question: 'Contact support',
      answer:
          'Use Settings > Contact Support to open your email app with a pre-filled support request template.',
    ),
    _FaqItem(
      question: 'Data safety',
      answer:
          'We collect only required data to provide app features, improve reliability, and support moderation/safety. You can request account actions from Settings.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final textSecondary = scheme.onSurface.withOpacity(0.68);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        title: Text(
          'FAQ',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: textSecondary.withOpacity(0.22)),
            ),
            child: Text(
              'Find quick answers to common questions.',
              style: TextStyle(color: textSecondary, height: 1.35),
            ),
          ),
          ..._items.map((item) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: textSecondary.withOpacity(0.2)),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  splashFactory: InkRipple.splashFactory,
                ),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  title: Text(
                    item.question,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  iconColor: scheme.primary,
                  collapsedIconColor: textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.answer,
                        style: TextStyle(
                          color: textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}
