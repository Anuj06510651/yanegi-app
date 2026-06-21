// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/chat/chat_thread_screen.dart';

extension _ChatDeliveryController on _ChatThreadScreenState {
  DateTime? _asDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  DateTime? _maxDateTime(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  DateTime? _effectiveSelfDeliveredAt(DateTime? streamValue) {
    return _maxDateTime(streamValue, _optimisticLastDeliveredAt);
  }

  DateTime? _effectiveSelfSeenAt(DateTime? streamValue) {
    return _maxDateTime(streamValue, _optimisticLastSeenAt);
  }

  String _formatMessageTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  String _formatLastSeen(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    final bottom = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        bottom,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(bottom);
    }
  }

  bool _isNearBottom({double threshold = 120}) {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) <= threshold;
  }

  void _onMessagesUpdated(List<ChatMessage> messages) {
    if (messages.isEmpty) return;

    final newestId = messages.last.id;
    final hasNewMessage = newestId != _lastRenderedMessageId ||
        messages.length != _lastRenderedMessageCount;
    final shouldAutoScroll = !_didInitialAutoScroll || _isNearBottom();

    _lastRenderedMessageId = newestId;
    _lastRenderedMessageCount = messages.length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      unawaited(_markChatRead());

      if (!shouldAutoScroll || !hasNewMessage) return;
      if (!_scrollController.hasClients) return;

      _scrollToBottom(animated: _didInitialAutoScroll);
      _didInitialAutoScroll = true;
    });
  }

  Future<void> _markChatRead() async {
    if (_isMarkingRead) return;
    _isMarkingRead = true;
    try {
      await ref
          .read(chatRepositoryProvider)
          .markChatRead(chatId: widget.chatId);
      final now = DateTime.now().toUtc();
      _optimisticLastDeliveredAt = now;
      _optimisticLastSeenAt = now;
    } catch (_) {
      // keep silent
    } finally {
      _isMarkingRead = false;
    }
  }

  bool _isOtherUserTyping(
    Map<String, dynamic> chatData,
    String otherUserId,
  ) {
    if (otherUserId.trim().isEmpty) return false;
    final typingRaw = chatData['typing'];
    if (typingRaw is! Map) return false;
    final typingMap = Map<String, dynamic>.from(typingRaw);
    final entry = typingMap[otherUserId];
    if (entry is! Map) return false;
    final payload = Map<String, dynamic>.from(entry);
    if (payload['isTyping'] != true) return false;
    final updatedAt = payload['updatedAt'];
    final updated = updatedAt is Timestamp
        ? updatedAt.toDate()
        : (updatedAt is DateTime ? updatedAt : null);
    if (updated == null) return true;
    return DateTime.now().difference(updated).inSeconds <= 8;
  }

  bool _isEventActive(Map<String, dynamic> eventData) {
    if (eventData.isEmpty) return true;

    final status = (eventData['status'] ?? EventService.statusActive)
        .toString()
        .toLowerCase();
    if (status != EventService.statusActive) return false;
    if (eventData['isActive'] == false) return false;

    final rawEndAt = eventData['endAt'];
    final endAt = rawEndAt is Timestamp
        ? rawEndAt.toDate()
        : (rawEndAt is DateTime ? rawEndAt : null);
    if (endAt == null) return true;

    return DateTime.now().toUtc().isBefore(endAt.toUtc());
  }

  Future<void> _setTyping(bool isTyping) async {
    if (widget.chatId.trim().isEmpty) return;
    try {
      await ref
          .read(chatRepositoryProvider)
          .setTyping(chatId: widget.chatId, isTyping: isTyping);
    } catch (_) {
      // ignore typing failures
    }
  }

  DateTime? _latestIncomingMessageTime(
    List<ChatMessage> messages,
    String currentUserId,
  ) {
    DateTime? latest;
    for (final message in messages) {
      if (message.senderId == currentUserId) continue;
      latest = _maxDateTime(latest, message.sentAt);
    }
    return latest;
  }

  Future<void> _syncDeliveryAndSeen(
    List<ChatMessage> messages,
    String currentUserId, {
    required DateTime? selfLastDeliveredAt,
    required DateTime? selfLastSeenAt,
  }) async {
    if (widget.chatId.trim().isEmpty || messages.isEmpty) return;

    final latestIncomingAt =
        _latestIncomingMessageTime(messages, currentUserId);
    if (latestIncomingAt == null) return;

    // Step 1 — Delivery: fires immediately when the recipient's app loads the
    // chat. This gives the sender the grey double-tick (delivered) state.
    final needsDeliveryWrite = selfLastDeliveredAt == null ||
        selfLastDeliveredAt.toUtc().isBefore(latestIncomingAt.toUtc());
    if (needsDeliveryWrite && !_isAckingDelivered) {
      _isAckingDelivered = true;
      try {
        await ref.read(chatRepositoryProvider).markMessagesDelivered(
          chatId: widget.chatId,
          messageIds: const <String>[],
        );
        _optimisticLastDeliveredAt = DateTime.now().toUtc();
      } catch (_) {
        // Keep silent for real-time cursor update failures.
      } finally {
        _isAckingDelivered = false;
      }
    }

    if (!_isNearBottom(threshold: 220)) {
      _seenMarkTimer?.cancel();
      return;
    }

    // Step 2 — Seen: debounced by 1.5 s after delivery so the sender sees the
    // grey double-tick briefly before it upgrades to the blue seen state.
    // This makes the three-state flow (✓ → ✓✓ grey → ✓✓ blue) visible.
    final needsSeenWrite = selfLastSeenAt == null ||
        selfLastSeenAt.toUtc().isBefore(latestIncomingAt.toUtc());
    if (needsSeenWrite && !_isAckingSeen) {
      _seenMarkTimer?.cancel();
      _seenMarkTimer = Timer(const Duration(milliseconds: 1500), () async {
        if (!mounted) return;
        if (_isAckingSeen) return;
        _isAckingSeen = true;
        try {
          await ref.read(chatRepositoryProvider).markMessagesSeen(
            chatId: widget.chatId,
            messageIds: const <String>[],
          );
          final now = DateTime.now().toUtc();
          _optimisticLastDeliveredAt = now;
          _optimisticLastSeenAt = now;
        } catch (_) {
          // Keep silent for real-time cursor update failures.
        } finally {
          _isAckingSeen = false;
        }
      });
    }
  }

  void _onComposerTextChanged(String value, bool canSend) {
    if (!canSend) return;

    final hasText = value.trim().isNotEmpty;
    if (hasText && !_typingActive) {
      _typingActive = true;
      unawaited(_setTyping(true));
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (_typingActive) {
        _typingActive = false;
        unawaited(_setTyping(false));
      }
    });

    // @mention detection — only meaningful in group chats.
    if (widget.isGroup) {
      _detectMentionQuery(value);
    } else {
      _clearMentionSuggestions();
    }
  }

  MessageDeliveryStatus _deliveryStatusFromCursor({
    required ChatMessage message,
    required DateTime? lastDeliveredAt,
    required DateTime? lastSeenAt,
  }) {
    final createdAtUtc = message.sentAt.toUtc();
    if (lastSeenAt != null && !createdAtUtc.isAfter(lastSeenAt.toUtc())) {
      return MessageDeliveryStatus.seen;
    }
    if (lastDeliveredAt != null &&
        !createdAtUtc.isAfter(lastDeliveredAt.toUtc())) {
      return MessageDeliveryStatus.delivered;
    }
    return MessageDeliveryStatus.sent;
  }

  String _statusLabel({
    required ChatMessage message,
    required DateTime? peerLastDeliveredAt,
    required DateTime? peerLastSeenAt,
  }) {
    if (message.status == MessageStatus.sending) return '⏳';
    if (message.status == MessageStatus.failed) return '⚠';

    final status = _deliveryStatusFromCursor(
      message: message,
      lastDeliveredAt: peerLastDeliveredAt,
      lastSeenAt: peerLastSeenAt,
    );
    if (status == MessageDeliveryStatus.sent) return '✓';
    return '✓✓';
  }

  Color _statusColor({
    required ChatMessage message,
    required DateTime? peerLastDeliveredAt,
    required DateTime? peerLastSeenAt,
  }) {
    if (message.status == MessageStatus.failed) {
      return Colors.redAccent.withAlpha(210);
    }
    if (message.status == MessageStatus.sending) {
      return Colors.white.withAlpha(150);
    }

    final status = _deliveryStatusFromCursor(
      message: message,
      lastDeliveredAt: peerLastDeliveredAt,
      lastSeenAt: peerLastSeenAt,
    );
    if (status == MessageDeliveryStatus.seen) {
      return const Color(0xFF6CC8FF);
    }
    return Colors.white.withAlpha(120);
  }

  /// Renders the per-burst delivery status row:
  ///   own messages  → [tick icon] [time]
  ///   others' msgs  → [time]
  ///
  /// Icons:
  ///   clock         = sending (optimistic, not yet on server)
  ///   single grey ✓ = sent (reached server, peer not yet delivered)
  ///   double grey ✓ = delivered (peer device received it)
  ///   double blue ✓ = seen (peer has read it)
  ///   red warning   = failed to send
  Widget _buildDeliveryStatusWidget({
    required ChatMessage message,
    required bool isMine,
    required DateTime? peerLastDeliveredAt,
    required DateTime? peerLastSeenAt,
    String peerDisplayName = '',
  }) {
    final timeStr = _formatMessageTime(message.sentAt);
    final timeStyle = TextStyle(
      color: Colors.white.withAlpha(120),
      fontSize: 11,
    );

    if (!isMine) {
      return Text(timeStr, style: timeStyle);
    }

    // ── Sending ──────────────────────────────────────────────────────────────
    if (message.status == MessageStatus.sending) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded,
              size: 11, color: Colors.white.withAlpha(120)),
          const SizedBox(width: 3),
          Text(timeStr, style: timeStyle),
        ],
      );
    }

    // ── Failed ───────────────────────────────────────────────────────────────
    if (message.status == MessageStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 11, color: Colors.redAccent.withAlpha(210)),
          const SizedBox(width: 3),
          Text(timeStr, style: timeStyle),
        ],
      );
    }

    // ── Delivery status ───────────────────────────────────────────────────────
    final deliveryStatus = _deliveryStatusFromCursor(
      message: message,
      lastDeliveredAt: peerLastDeliveredAt,
      lastSeenAt: peerLastSeenAt,
    );

    switch (deliveryStatus) {
      case MessageDeliveryStatus.seen:
        // Initial bubble: always renders regardless of DP or network.
        // Color is deterministic from the peer's name — same name = same color.
        // Only shown in DMs (group chats use "Seen by N" below the burst).
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SeenInitialBubble(name: peerDisplayName),
            const SizedBox(width: 4),
            Text(timeStr, style: timeStyle),
          ],
        );

      case MessageDeliveryStatus.delivered:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all_rounded,
                size: 14, color: Colors.white.withAlpha(160)),
            const SizedBox(width: 3),
            Text(timeStr, style: timeStyle),
          ],
        );

      case MessageDeliveryStatus.sent:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_rounded,
                size: 14, color: Colors.white.withAlpha(120)),
            const SizedBox(width: 3),
            Text(timeStr, style: timeStyle),
          ],
        );
    }
  }

  /// Single status row for the last own-message burst in a group chat.
  ///
  /// Replaces both `_buildDeliveryStatusWidget` and the old separate
  /// `_buildGroupSeenBy` so there is never a stacked tick-then-seen-label.
  ///
  /// States:
  ///   ⏱ time          — sending (optimistic)
  ///   ⚠ time           — failed
  ///   ✓  time          — sent, nobody has read it yet
  ///   "Seen by N"      — at least one member read it (NO tick, time omitted
  ///                      to keep the row uncluttered)
  ///   "Seen by all"    — every other participant has read it
  Widget _buildGroupStatusRow({
    required ChatMessage lastMsg,
    required List<String> participants,
    required String currentUserId,
  }) {
    final timeStr = _formatMessageTime(lastMsg.sentAt);
    final timeStyle = TextStyle(color: Colors.white.withAlpha(120), fontSize: 11);

    // Sending / failed states don't need a Firestore read.
    if (lastMsg.status == MessageStatus.sending) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.access_time_rounded, size: 11, color: Colors.white.withAlpha(120)),
        const SizedBox(width: 3),
        Text(timeStr, style: timeStyle),
      ]);
    }
    if (lastMsg.status == MessageStatus.failed) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 11, color: Colors.redAccent.withAlpha(210)),
        const SizedBox(width: 3),
        Text(timeStr, style: timeStyle),
      ]);
    }

    final stream = _groupMembersMetaStream;
    if (stream == null) {
      // No stream yet — show plain sent tick.
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.done_rounded, size: 14, color: Colors.white.withAlpha(120)),
        const SizedBox(width: 3),
        Text(timeStr, style: timeStyle),
      ]);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final msgSentAt = lastMsg.sentAt.toUtc();
        var seenCount = 0;

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            if (doc.id == currentUserId) continue;
            final raw = doc.data()['lastSeenAt'];
            final seenAt = raw is Timestamp ? raw.toDate().toUtc() : null;
            if (seenAt != null && !seenAt.isBefore(msgSentAt)) seenCount++;
          }
        }

        // ── Not yet seen by anyone → single grey tick + time ─────────────────
        if (seenCount == 0) {
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.done_rounded, size: 14, color: Colors.white.withAlpha(120)),
            const SizedBox(width: 3),
            Text(timeStr, style: timeStyle),
          ]);
        }

        // ── Seen by at least one person → label only, no tick, no time ───────
        final othersCount = (participants.length - 1).clamp(0, 9999);
        final label = othersCount > 0 && seenCount >= othersCount
            ? 'Seen by all'
            : 'Seen by $seenCount';

        return Text(
          label,
          style: TextStyle(
            color: const Color(0xFF6CC8FF).withAlpha(200),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }
}
