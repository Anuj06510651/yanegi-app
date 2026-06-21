import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import 'message_reaction_picker.dart';

/// Bottom sheet shown on long-press of any message.
///
/// Top half — quick emoji reactions (same 5 + "+" as the overlay picker).
/// Bottom half — contextual actions: Reply, Copy, Edit (own), Delete (own).
///
/// All callbacks are fire-and-forget; the caller owns navigation / state.
void showMessageActionsSheet({
  required BuildContext context,
  required ChatMessage message,
  required String currentUserId,
  required bool isGroup,
  required void Function(String emoji) onReact,
  required VoidCallback onReply,
  required void Function() onCopy,
  required void Function() onEdit,
  required void Function() onDelete,
  required void Function() onMoreEmojis,
  // Pin / unpin (group chats only)
  String? currentPinnedMessageId,
  VoidCallback? onPin,
  VoidCallback? onUnpin,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (_) => _MessageActionsSheet(
      message: message,
      currentUserId: currentUserId,
      isGroup: isGroup,
      onReact: onReact,
      onReply: onReply,
      onCopy: onCopy,
      onEdit: onEdit,
      onDelete: onDelete,
      onMoreEmojis: onMoreEmojis,
      currentPinnedMessageId: currentPinnedMessageId,
      onPin: onPin,
      onUnpin: onUnpin,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _MessageActionsSheet extends StatelessWidget {
  const _MessageActionsSheet({
    required this.message,
    required this.currentUserId,
    required this.isGroup,
    required this.onReact,
    required this.onReply,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
    required this.onMoreEmojis,
    this.currentPinnedMessageId,
    this.onPin,
    this.onUnpin,
  });

  final ChatMessage message;
  final String currentUserId;
  final bool isGroup;
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  final void Function() onCopy;
  final void Function() onEdit;
  final void Function() onDelete;
  final void Function() onMoreEmojis;
  final String? currentPinnedMessageId;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;

  bool get _isCurrentlyPinned => currentPinnedMessageId == message.id;
  bool get _showPin => !message.isDeleted && onPin != null && !_isCurrentlyPinned;
  bool get _showUnpin => _isCurrentlyPinned && onUnpin != null;

  static const _editWindowMinutes = 15;
  static const _deleteWindowMinutes = 60;

  bool get _isMine => message.senderId == currentUserId;

  bool get _canEdit {
    if (!_isMine || message.isDeleted || message.isPoll) return false;
    final age = DateTime.now().difference(message.sentAt);
    return age.inMinutes < _editWindowMinutes;
  }

  bool get _canDelete {
    if (!_isMine || message.isDeleted || message.isPoll) return false;
    final age = DateTime.now().difference(message.sentAt);
    return age.inMinutes < _deleteWindowMinutes;
  }

  /// "12m left" hint shown when within 3 minutes of the window closing.
  String? _editTimeHint() {
    if (!_isMine || message.isDeleted) return null;
    final age = DateTime.now().difference(message.sentAt);
    final remaining = _editWindowMinutes - age.inMinutes;
    if (remaining > 3 || remaining <= 0) return null;
    return '${remaining}m left';
  }

  String? _deleteTimeHint() {
    if (!_isMine || message.isDeleted) return null;
    final age = DateTime.now().difference(message.sentAt);
    final remaining = _deleteWindowMinutes - age.inMinutes;
    if (remaining > 5 || remaining <= 0) return null;
    return '${remaining}m left';
  }

  Set<String> get _myReactions => message.reactions.entries
      .where((e) => e.value.contains(currentUserId))
      .map((e) => e.key)
      .toSet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF151C2A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),

            // ── Quick reactions ───────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in kQuickReactionEmojis)
                    _ReactionButton(
                      emoji: emoji,
                      isActive: _myReactions.contains(emoji),
                      onTap: () {
                        Navigator.of(context).pop();
                        onReact(emoji);
                      },
                    ),
                  _MoreReactionButton(onTap: () {
                    Navigator.of(context).pop();
                    onMoreEmojis();
                  }),
                ],
              ),
            ),

            Divider(color: Colors.white.withAlpha(12), height: 1),

            // ── Action tiles ─────────────────────────────────────────────
            _ActionTile(
              icon: Icons.reply_rounded,
              label: 'Reply',
              onTap: () {
                Navigator.of(context).pop();
                onReply();
              },
            ),
            _ActionTile(
              icon: Icons.copy_rounded,
              label: 'Copy',
              onTap: () {
                Navigator.of(context).pop();
                onCopy();
              },
            ),
            if (_showPin)
              _ActionTile(
                icon: Icons.push_pin_outlined,
                label: 'Pin',
                onTap: () {
                  Navigator.of(context).pop();
                  onPin!();
                },
              ),
            if (_showUnpin)
              _ActionTile(
                icon: Icons.push_pin_rounded,
                label: 'Unpin',
                onTap: () {
                  Navigator.of(context).pop();
                  onUnpin!();
                },
              ),
            if (_canEdit)
              _ActionTile(
                icon: Icons.edit_rounded,
                label: 'Edit',
                hint: _editTimeHint(),
                onTap: () {
                  Navigator.of(context).pop();
                  onEdit();
                },
              ),
            if (_canDelete)
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                hint: _deleteTimeHint(),
                color: Colors.redAccent,
                onTap: () {
                  Navigator.of(context).pop();
                  onDelete();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.emoji,
    required this.isActive,
    required this.onTap,
  });

  final String emoji;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? const Color(0xFF7C7AFF).withAlpha(50)
              : Colors.white.withAlpha(10),
          border: isActive
              ? Border.all(color: const Color(0xFF7C7AFF), width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

class _MoreReactionButton extends StatelessWidget {
  const _MoreReactionButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha(18),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.add_rounded,
            color: Colors.white.withAlpha(200), size: 22),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.hint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  // Optional time-remaining hint shown in amber when close to window closing.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: c.withAlpha(200), size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (hint != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(30),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.amber.withAlpha(100)),
                ),
                child: Text(
                  hint!,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
