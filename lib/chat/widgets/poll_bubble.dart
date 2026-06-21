import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../models/poll_model.dart';

/// Renders a poll message in the chat thread.
///
/// Shows animated progress bars, highlights the current user's vote,
/// and calls [onVote] when the user taps an option.
class PollBubble extends StatelessWidget {
  const PollBubble({
    super.key,
    required this.message,
    required this.currentUserId,
    required this.isMine,
    required this.onVote,
    required this.senderName,
  });

  final ChatMessage message;
  final String currentUserId;
  final bool isMine;
  final void Function(String optionId) onVote;
  final String senderName;

  PollData get poll => message.poll!;

  @override
  Widget build(BuildContext context) {
    final total = poll.totalVotes;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * 0.82;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 220),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: isMine
                ? Theme.of(context).colorScheme.primary.withAlpha(220)
                : const Color(0xFF1E2636),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isMine
                  ? Colors.white.withAlpha(30)
                  : const Color(0xFF7C7AFF).withAlpha(60),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.bar_chart_rounded,
                      size: 16,
                      color: isMine
                          ? Colors.white.withAlpha(200)
                          : const Color(0xFF7C7AFF)),
                  const SizedBox(width: 6),
                  Text(
                    'Poll',
                    style: TextStyle(
                      color: isMine
                          ? Colors.white.withAlpha(200)
                          : const Color(0xFF7C7AFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  if (!isMine) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· $senderName',
                      style: TextStyle(
                        color: Colors.white.withAlpha(100),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Question
              Text(
                poll.question,
                style: TextStyle(
                  color: isMine ? Colors.white : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),

              // Options
              for (final option in poll.options)
                _PollOption(
                  option: option,
                  total: total,
                  currentUserId: currentUserId,
                  isMine: isMine,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onVote(option.id);
                  },
                ),

              const SizedBox(height: 6),

              // Footer
              Text(
                total == 0
                    ? 'No votes yet'
                    : '$total ${total == 1 ? 'vote' : 'votes'}${poll.allowMultipleVotes ? ' · Multiple allowed' : ''}',
                style: TextStyle(
                  color: isMine
                      ? Colors.white.withAlpha(130)
                      : Colors.white.withAlpha(100),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.option,
    required this.total,
    required this.currentUserId,
    required this.isMine,
    required this.onTap,
  });

  final PollOption option;
  final int total;
  final String currentUserId;
  final bool isMine;
  final VoidCallback onTap;

  bool get _voted => option.hasVoted(currentUserId);
  double get _percent => total == 0 ? 0 : option.voterIds.length / total;

  @override
  Widget build(BuildContext context) {
    final accent = _voted
        ? const Color(0xFF22E7A2)
        : (isMine ? Colors.white : const Color(0xFF7C7AFF));
    final trackColor = isMine
        ? Colors.white.withAlpha(_voted ? 50 : 25)
        : Colors.white.withAlpha(_voted ? 30 : 15);

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label row
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _voted ? accent : Colors.transparent,
                    border: Border.all(
                      color: _voted ? accent : Colors.white.withAlpha(80),
                      width: 1.5,
                    ),
                  ),
                  child: _voted
                      ? const Icon(Icons.check_rounded,
                          size: 11, color: Colors.black)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.text,
                    style: TextStyle(
                      color: Colors.white.withAlpha(_voted ? 255 : 200),
                      fontSize: 13,
                      fontWeight:
                          _voted ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  total == 0
                      ? '0%'
                      : '${(_percent * 100).round()}%',
                  style: TextStyle(
                    color: _voted
                        ? accent
                        : Colors.white.withAlpha(130),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(
                children: [
                  Container(height: 4, color: trackColor),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    widthFactor: _percent,
                    child: Container(height: 4, color: accent),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
