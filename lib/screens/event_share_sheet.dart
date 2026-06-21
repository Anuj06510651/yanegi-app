import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/yanegi_theme.dart';
import '../utils/error_handler.dart';
import '../utils/event_share_service.dart';
import '../widgets/event_share_card.dart';

/// Opens the event share bottom sheet.
///
/// [onShareInChat] — optional callback fired (after the sheet is dismissed)
/// when the user taps "Share in Chat". Wire up [showShareToChatSheet] here.
Future<void> showEventShareSheet(
  BuildContext context, {
  required EventShareData data,
  VoidCallback? onShareInChat,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EventShareSheet(data: data, onShareInChat: onShareInChat),
  );
}

class EventShareSheet extends StatefulWidget {
  const EventShareSheet({
    super.key,
    required this.data,
    this.onShareInChat,
  });
  final EventShareData data;
  final VoidCallback? onShareInChat;

  @override
  State<EventShareSheet> createState() => _EventShareSheetState();
}

class _EventShareSheetState extends State<EventShareSheet> {
  final _cardKey = GlobalKey();
  bool _sharingCard = false;
  bool _sharingText = false;
  bool _linkCopied = false;

  @override
  Widget build(BuildContext context) {
    final link = EventShareService.deepLink(widget.data.eventId);
    final shareText = EventShareService.generateText(widget.data);

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D1420),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text(
                      'Share Event',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Colors.white.withAlpha(160),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // ── Scrollable body ──────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    MediaQuery.of(context).padding.bottom + 28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card preview
                      Center(
                        child: RepaintBoundary(
                          key: _cardKey,
                          child: EventShareCard(data: widget.data),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // In-app chat share
                      if (widget.onShareInChat != null) ...[
                        _SectionLabel(label: 'SHARE IN YANEGI'),
                        const SizedBox(height: 10),
                        _ActionTile(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Send in Chat',
                          subtitle: 'Share as a card to a direct message',
                          onTap: () {
                            Navigator.pop(context);
                            widget.onShareInChat!();
                          },
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Share as image
                      _SectionLabel(label: 'SHARE AS IMAGE'),
                      const SizedBox(height: 10),
                      _ActionTile(
                        icon: Icons.image_outlined,
                        label: 'Share Card',
                        subtitle: 'WhatsApp · Instagram · Telegram · Discord',
                        loading: _sharingCard,
                        onTap: _shareCard,
                      ),

                      const SizedBox(height: 20),

                      // Share as text
                      _SectionLabel(label: 'SHARE AS TEXT'),
                      const SizedBox(height: 10),
                      _ActionTile(
                        icon: Icons.send_outlined,
                        label: 'Share Link',
                        subtitle: 'X · LinkedIn · Facebook · any platform',
                        loading: _sharingText,
                        onTap: _shareText,
                      ),
                      const SizedBox(height: 12),
                      _ActionTile(
                        icon: _linkCopied
                            ? Icons.check_rounded
                            : Icons.link_rounded,
                        label: _linkCopied ? 'Link Copied' : 'Copy Link',
                        subtitle: link,
                        onTap: _copyLink,
                        accent: _linkCopied
                            ? YanegiColors.accentSuccess
                            : null,
                      ),

                      const SizedBox(height: 24),

                      // Text preview
                      _SectionLabel(label: 'MESSAGE PREVIEW'),
                      const SizedBox(height: 10),
                      _TextPreview(text: shareText),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareCard() async {
    if (_sharingCard) return;
    setState(() => _sharingCard = true);
    try {
      await EventShareService.shareCard(_cardKey, widget.data);
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.eventShareFailed,
        error: e,
        where: 'EventShareSheet._shareCard',
      );
    } finally {
      if (mounted) setState(() => _sharingCard = false);
    }
  }

  Future<void> _shareText() async {
    if (_sharingText) return;
    setState(() => _sharingText = true);
    try {
      await EventShareService.shareText(widget.data);
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.eventShareFailed,
        error: e,
        where: 'EventShareSheet._shareText',
      );
    } finally {
      if (mounted) setState(() => _sharingText = false);
    }
  }

  Future<void> _copyLink() async {
    final link = EventShareService.deepLink(widget.data.eventId);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    setState(() => _linkCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied.'),
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }
}

// ── Internal widgets ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withAlpha(100),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool loading;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? YanegiColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF131D2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withAlpha(18)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: loading
                      ? Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
                          ),
                        )
                      : Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withAlpha(100),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Colors.white.withAlpha(60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withAlpha(160),
          fontSize: 13,
          height: 1.6,
        ),
      ),
    );
  }
}
