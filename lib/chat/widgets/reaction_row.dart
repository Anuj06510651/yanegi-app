import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Horizontal wrap of reaction pills displayed beneath a message bubble.
///
/// Each pill shows the emoji + reactor count. The current user's reactions
/// are visually highlighted. Tapping a pill calls [onToggle] (toggle the
/// reaction). Long-pressing calls [onShowDetails] which opens the
/// who-reacted bottom sheet (only meaningful in group chats).
class ReactionRow extends StatelessWidget {
  const ReactionRow({
    super.key,
    required this.reactions,
    required this.currentUserId,
    required this.isMine,
    required this.onToggle,
    this.onShowDetails,
  });

  /// Map of emoji → list of user IDs from [ChatMessage.reactions].
  final Map<String, List<String>> reactions;
  final String currentUserId;

  /// True when this message was sent by the current user (affects alignment).
  final bool isMine;

  /// Called when the user taps a reaction pill to add or remove their reaction.
  final void Function(String emoji) onToggle;

  /// Called when the user long-presses a reaction pill to see who reacted.
  /// Pass null to disable the who-reacted affordance (e.g. in DMs when
  /// the caller prefers a simpler UX).
  final void Function(String emoji)? onShowDetails;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // Sort: emojis the current user reacted to appear first, then by count.
    final sorted = reactions.entries.toList()
      ..sort((a, b) {
        final aMine = a.value.contains(currentUserId) ? 0 : 1;
        final bMine = b.value.contains(currentUserId) ? 0 : 1;
        if (aMine != bMine) return aMine - bMine;
        return b.value.length.compareTo(a.value.length);
      });

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
          children: [
            for (final entry in sorted)
              _ReactionPill(
                emoji: entry.key,
                count: entry.value.length,
                isActive: entry.value.contains(currentUserId),
                onTap: () => onToggle(entry.key),
                onLongPress: onShowDetails != null
                    ? () => onShowDetails!(entry.key)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.emoji,
    required this.count,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
  });

  final String emoji;
  final int count;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF7C7AFF).withAlpha(38)
              : Colors.white.withAlpha(18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF7C7AFF).withAlpha(180)
                : Colors.white.withAlpha(30),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF7C7AFF)
                      : Colors.white.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
