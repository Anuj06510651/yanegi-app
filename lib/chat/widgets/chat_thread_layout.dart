import 'package:flutter/material.dart';

import '../models/chat_models.dart';

/// One row in the chat thread list. Either a date divider or a "burst" of
/// consecutive messages from the same sender within a short time window.
///
/// Building this list once per message-stream tick and feeding it to
/// `ListView.builder` keeps grouping/divider logic out of the bubble widget
/// and lets us memoize per-row rendering without any backend changes.
sealed class ChatThreadRow {
  const ChatThreadRow();

  /// Stable identity used by `ValueKey` so the framework can recycle widgets
  /// across rebuilds without resurrecting offscreen subtrees.
  String get rowKey;
}

class ChatDateDividerRow extends ChatThreadRow {
  const ChatDateDividerRow(this.label, this.day);
  final String label;
  final DateTime day;

  @override
  String get rowKey => 'date_${day.year}_${day.month}_${day.day}';
}

class ChatMessageBurstRow extends ChatThreadRow {
  const ChatMessageBurstRow({
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.messages,
    required this.firstAt,
    required this.lastAt,
  });

  final String senderId;
  final String senderName;
  final String senderAvatar;
  final List<ChatMessage> messages;
  final DateTime firstAt;
  final DateTime lastAt;

  bool isMine(String currentUserId) => senderId == currentUserId;

  @override
  String get rowKey => 'burst_${messages.first.id}_${messages.length}';
}

/// Build the row list for a sorted (ascending-by-time) list of [messages].
///
/// Grouping rules:
///   - consecutive messages from the same `senderId`
///   - within [burstWindow] (default 5 min) of the previous message
///     in the burst → folded into the same burst.
/// Date dividers:
///   - inserted between any two rows whose calendar day differs
///   - and at the very top of the list.
List<ChatThreadRow> buildChatThreadRows(
  List<ChatMessage> messages, {
  Duration burstWindow = const Duration(minutes: 5),
  DateTime Function()? now,
}) {
  if (messages.isEmpty) return const [];
  final today = (now ?? DateTime.now).call();

  final rows = <ChatThreadRow>[];
  DateTime? currentDay;
  List<ChatMessage>? currentBurst;
  String? currentSenderId;
  DateTime? lastMessageAt;

  void flushBurst() {
    if (currentBurst == null || currentBurst!.isEmpty) return;
    final first = currentBurst!.first;
    final last = currentBurst!.last;
    rows.add(ChatMessageBurstRow(
      senderId: first.senderId,
      senderName: first.senderName,
      senderAvatar: first.senderAvatar,
      messages: List.unmodifiable(currentBurst!),
      firstAt: first.sentAt,
      lastAt: last.sentAt,
    ));
    currentBurst = null;
    currentSenderId = null;
    lastMessageAt = null;
  }

  for (final msg in messages) {
    final msgDay = DateTime(msg.sentAt.year, msg.sentAt.month, msg.sentAt.day);
    if (currentDay == null || !_isSameDay(currentDay, msgDay)) {
      flushBurst();
      rows.add(ChatDateDividerRow(_dividerLabel(msgDay, today: today), msgDay));
      currentDay = msgDay;
    }

    final breaksBurst = currentSenderId == null ||
        currentSenderId != msg.senderId ||
        lastMessageAt == null ||
        msg.sentAt.difference(lastMessageAt!) > burstWindow ||
        msg.replyToMessageId != null ||
        msg.isPoll; // polls are always standalone

    if (breaksBurst) {
      flushBurst();
      currentBurst = <ChatMessage>[msg];
      currentSenderId = msg.senderId;
    } else {
      currentBurst!.add(msg);
    }
    lastMessageAt = msg.sentAt;
  }

  flushBurst();
  return rows;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dividerLabel(DateTime day, {required DateTime today}) {
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 0 && diff < 7) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[day.weekday - 1];
  }
  // Same-year compact format, otherwise include year.
  if (day.year == today.year) {
    return '${_monthShort(day.month)} ${day.day}';
  }
  return '${_monthShort(day.month)} ${day.day}, ${day.year}';
}

String _monthShort(int m) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return names[m - 1];
}

/// Floating, glass-style divider used between two days of messages.
class ChatDateDivider extends StatelessWidget {
  const ChatDateDivider({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withAlpha(28)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(180),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
