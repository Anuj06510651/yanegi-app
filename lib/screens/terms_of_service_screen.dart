import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatefulWidget {
  const TermsOfServiceScreen({super.key});

  @override
  State<TermsOfServiceScreen> createState() => _TermsOfServiceScreenState();
}

class _TermsOfServiceScreenState extends State<TermsOfServiceScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _hasReachedEnd = false;
  bool _isSaving = false;
  bool _alreadyAccepted = false;

  static const List<String> _quickSummary = [
    'We help you discover and join events.',
    'You are in control of your choices and interactions.',
    'Respectful and lawful behavior keeps the community safe.',
  ];

  static const List<_TermsSection> _sections = [
    _TermsSection(
      title: 'Acceptance',
      body:
          'By using Yanegi, you confirm that you are 18+ and accept these Terms of Service. If these terms do not work for you, please avoid using the app.',
    ),
    _TermsSection(
      title: 'User Rules',
      body:
          'Please keep account information accurate and treat others respectfully. Abuse, scams, impersonation, and harmful behavior are not permitted.',
    ),
    _TermsSection(
      title: 'Event Responsibility',
      body:
          'Hosts and attendees are responsible for their own decisions and conduct. It is important to verify event details, venue conditions, and participants before attending.',
    ),
    _TermsSection(
      title: 'Platform Role',
      body:
          'Yanegi helps people discover and connect around events. We do not directly organize or supervise user-created events, and outcomes depend on user actions.',
    ),
    _TermsSection(
      title: 'Liability',
      body:
          'We aim to provide a safe platform, but users are responsible for their own interactions, event choices, and outcomes to the extent allowed by law.',
      warning: 'Use at your own risk',
    ),
    _TermsSection(
      title: 'Termination',
      body:
          'Accounts that violate these terms, community standards, or legal requirements may be restricted or removed. You can stop using Yanegi at any time.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_evaluateScrollProgress);
    _loadAcceptanceStatus();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _evaluateScrollProgress());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_evaluateScrollProgress);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAcceptanceStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _alreadyAccepted = (data['legalAccepted'] ?? false) == true;
      });
    } catch (_) {
      // Keep default value; UI can still continue.
    }
  }

  void _evaluateScrollProgress() {
    if (!mounted || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final canScroll = position.maxScrollExtent > 12;
    final reachedEnd =
        !canScroll || position.pixels >= position.maxScrollExtent - 20;

    if (reachedEnd != _hasReachedEnd) {
      setState(() => _hasReachedEnd = reachedEnd);
    }
  }

  Future<void> _acceptTerms() async {
    if (_isSaving || !_hasReachedEnd || _alreadyAccepted) return;

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _toast('Please sign in first.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'legalAccepted': true,
        'legalAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _alreadyAccepted = true);
      _toast('Terms accepted. Thank you.');
    } catch (_) {
      if (!mounted) return;
      _toast('Could not save your acceptance. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
          'Terms of Service',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
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
                      border:
                          Border.all(color: scheme.primary.withOpacity(0.24)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.warning_amber_rounded,
                              color: scheme.primary, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Yanegi is designed for adults (18+).',
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
                  ..._sections.map((section) {
                    return _TermsSectionCard(section: section);
                  }),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_hasReachedEnd)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Scroll to the bottom to enable acceptance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed:
                        (_hasReachedEnd && !_isSaving && !_alreadyAccepted)
                            ? _acceptTerms
                            : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    child: Text(
                      _isSaving
                          ? 'Saving...'
                          : (_alreadyAccepted ? 'Already Accepted' : 'I Agree'),
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

class _TermsSection {
  final String title;
  final String body;
  final String? warning;

  const _TermsSection({
    required this.title,
    required this.body,
    this.warning,
  });
}

class _TermsSectionCard extends StatelessWidget {
  final _TermsSection section;

  const _TermsSectionCard({required this.section});

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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.24),
                ),
              ),
              child: Text(
                section.warning!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
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
