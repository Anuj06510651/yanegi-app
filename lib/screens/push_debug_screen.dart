import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/push_notification_service.dart';
import '../theme/yanegi_theme.dart';

class PushDebugScreen extends StatefulWidget {
  const PushDebugScreen({super.key});

  @override
  State<PushDebugScreen> createState() => _PushDebugScreenState();
}

class _PushDebugScreenState extends State<PushDebugScreen> {
  final PushNotificationService _pushService = PushNotificationService();
  bool _isRefreshing = false;

  ColorScheme get _scheme => Theme.of(context).colorScheme;
  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => _scheme.surface;
  Color get _textPrimary => _scheme.onSurface;
  Color get _textSecondary => _scheme.onSurface.withOpacity(0.68);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _pushService.refreshDebugSnapshot();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.trim().isEmpty) {
      _toast('$label is empty.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value));
    _toast('$label copied.');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          'Push Debug (QA)',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: YanegiTypeScale.h2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isRefreshing ? null : _refresh,
            icon: _isRefreshing
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _textPrimary,
                    ),
                  )
                : Icon(Icons.refresh, color: _textPrimary),
          ),
        ],
      ),
      body: ValueListenableBuilder<PushDebugSnapshot>(
        valueListenable: PushNotificationService.debugSnapshotNotifier,
        builder: (context, snapshot, _) {
          final payloadPretty =
              const JsonEncoder.withIndent('  ').convert(snapshot.lastPayload);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              _card(
                title: 'Permission',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Status', snapshot.authorizationStatus),
                    const SizedBox(height: 8),
                    _row('Enabled', snapshot.notificationsEnabled.toString()),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _card(
                title: 'FCM Token',
                trailing: TextButton(
                  onPressed: () => _copy('FCM token', snapshot.token),
                  child: const Text('Copy'),
                ),
                child: SelectableText(
                  snapshot.token.trim().isEmpty
                      ? 'No token available yet.'
                      : snapshot.token,
                  style: TextStyle(color: _textPrimary, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 14),
              _card(
                title: 'Last Event',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(
                        'Source',
                        snapshot.lastEventSource.isEmpty
                            ? '-'
                            : snapshot.lastEventSource),
                    const SizedBox(height: 8),
                    _row(
                      'Updated',
                      snapshot.lastUpdatedAt == null
                          ? '-'
                          : snapshot.lastUpdatedAt.toString(),
                    ),
                    if (snapshot.lastError.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        snapshot.lastError,
                        style: TextStyle(color: Colors.red.shade300),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _card(
                title: 'Last Payload',
                trailing: TextButton(
                  onPressed: () => _copy('Payload', payloadPretty),
                  child: const Text('Copy'),
                ),
                child: SelectableText(
                  snapshot.lastPayload.isEmpty ? '{}' : payloadPretty,
                  style: TextStyle(color: _textPrimary, fontSize: 12.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _textSecondary.withOpacity(0.18)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: YanegiTypeScale.body,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            '$label:',
            style: TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
