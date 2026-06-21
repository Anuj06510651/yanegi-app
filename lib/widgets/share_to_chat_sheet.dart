import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/providers/chat_providers.dart';
import '../theme/yanegi_theme.dart';

/// Opens the share-to-chat sheet.
/// [shareType] must be 'event_card' or 'profile_card'.
/// [metadata] carries the card payload (targetId, title, emoji, subtitle).
Future<void> showShareToChatSheet(
  BuildContext context, {
  required String shareType,
  required Map<String, dynamic> metadata,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ShareToChatSheet(
      shareType: shareType,
      metadata: metadata,
    ),
  );
}

class ShareToChatSheet extends ConsumerStatefulWidget {
  const ShareToChatSheet({
    super.key,
    required this.shareType,
    required this.metadata,
  });

  final String shareType;
  final Map<String, dynamic> metadata;

  @override
  ConsumerState<ShareToChatSheet> createState() => _ShareToChatSheetState();
}

class _ShareToChatSheetState extends ConsumerState<ShareToChatSheet> {
  final Set<String> _selected = {};
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final dmAsync = ref.watch(dmListProvider);
    final hasSelection = _selected.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF101726),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Drag handle ─────────────────────────────────────────────
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

              // ── Title ────────────────────────────────────────────────────
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Send to',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── DM list ──────────────────────────────────────────────────
              Expanded(
                child: dmAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => Center(
                    child: Text(
                      'Could not load conversations',
                      style: TextStyle(color: Colors.white.withAlpha(140)),
                    ),
                  ),
                  data: (dms) {
                    final active =
                        dms.where((d) => !d.isDeleted).toList();

                    if (active.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 40,
                                color: Colors.white.withAlpha(60)),
                            const SizedBox(height: 12),
                            Text(
                              'No conversations yet',
                              style: TextStyle(
                                  color: Colors.white.withAlpha(140),
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: active.length,
                      itemBuilder: (_, i) {
                        final dm = active[i];
                        final isSelected = _selected.contains(dm.id);

                        return _DmSelectTile(
                          dm: dm,
                          isSelected: isSelected,
                          onTap: () => setState(() {
                            if (isSelected) {
                              _selected.remove(dm.id);
                            } else {
                              _selected.add(dm.id);
                            }
                          }),
                        );
                      },
                    );
                  },
                ),
              ),

              // ── Fixed bottom send bar ────────────────────────────────────
              AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                offset: hasSelection ? Offset.zero : const Offset(0, 1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: hasSelection ? 1.0 : 0.0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      MediaQuery.of(context).padding.bottom + 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1520),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withAlpha(18),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _sending ? null : _send,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YanegiColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              YanegiColors.primary.withAlpha(120),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Send  (${_selected.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);

    final repo = ref.read(chatRepositoryProvider);
    for (final chatId in _selected) {
      await repo.sendShareCard(
        chatId: chatId,
        type: widget.shareType,
        metadata: widget.metadata,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sent to ${_selected.length} '
          'conversation${_selected.length == 1 ? '' : 's'}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _DmSelectTile extends StatelessWidget {
  const _DmSelectTile({
    required this.dm,
    required this.isSelected,
    required this.onTap,
  });

  final dynamic dm;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = dm.name.isNotEmpty ? dm.name[0].toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF1E2A3A),
              backgroundImage: (dm.avatarUrl as String).isNotEmpty
                  ? NetworkImage(dm.avatarUrl as String)
                  : null,
              child: (dm.avatarUrl as String).isEmpty
                  ? Text(
                      (dm.avatarEmoji as String).isNotEmpty
                          ? dm.avatarEmoji as String
                          : initial,
                      style: const TextStyle(fontSize: 20),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // Name + last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dm.name as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if ((dm.lastMessage as String).isNotEmpty)
                    Text(
                      dm.lastMessage as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withAlpha(110),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Checkbox circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? YanegiColors.primary
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? YanegiColors.primary
                      : Colors.white.withAlpha(70),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
