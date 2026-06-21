// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/chat/chat_thread_screen.dart';

extension _ChatMessageActionsController on _ChatThreadScreenState {
  Widget _buildReplyBlock({
    required String senderName,
    required String previewText,
    required VoidCallback? onTap,
    required bool isMine,
  }) {
    final borderColor =
        isMine ? Colors.white.withAlpha(160) : YanegiColors.primary;
    final nameColor =
        isMine ? Colors.white.withAlpha(220) : YanegiColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: borderColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName.isNotEmpty ? senderName : 'Unknown',
              style: TextStyle(
                color: nameColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              previewText.length > 80
                  ? '${previewText.substring(0, 80)}…'
                  : previewText,
              style:
                  TextStyle(color: Colors.white.withAlpha(170), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _jumpToMessage(String messageId) {
    final key = _messageKeys[messageId];
    if (key == null || key.currentContext == null) return;
    Scrollable.ensureVisible(
      key.currentContext!,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.3,
    ).then((_) {
      if (!mounted) return;
      setState(() => _highlightedMessageId = messageId);
      _highlightClearTimer?.cancel();
      _highlightClearTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _highlightedMessageId = null);
      });
    });
  }

  Widget _buildSenderAvatar(ChatMessage message) {
    return AppUserAvatar(photoUrl: message.senderAvatar, radius: 11);
  }

  /// Renders every message in a [burst] back-to-back with tight spacing,
  /// supporting long-press reactions, swipe-to-reply, reply-block display,
  /// reaction pills, and jump highlight.
  List<Widget> _buildBurstBubbles({
    required ChatMessageBurstRow burst,
    required bool isMine,
    required Color outgoingBubbleColor,
    required Color outgoingTextColor,
    required String currentUserId,
    String? pinnedMessageId,
    bool canSend = true,
  }) {
    final widgets = <Widget>[];
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.72;
    final normalColor = isMine ? outgoingBubbleColor : const Color(0xFF171D2A);
    final highlightColor = isMine
        ? Color.lerp(outgoingBubbleColor, Colors.white, 0.22)!
        : const Color(0xFF243040);

    for (var i = 0; i < burst.messages.length; i++) {
      final msg = burst.messages[i];
      final isLast = i == burst.messages.length - 1;
      final msgKey = _messageKeys.putIfAbsent(msg.id, () => GlobalKey());
      final isHighlighted = _highlightedMessageId == msg.id;

      // Poll messages — standalone bubble, no burst grouping.
      if (msg.isPoll) {
        widgets.add(
          Padding(
            key: msgKey,
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMine && widget.isGroup)
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      burst.senderName,
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                PollBubble(
                  message: msg,
                  currentUserId: currentUserId,
                  isMine: isMine,
                  senderName: burst.senderName,
                  onVote: (optionId) => _votePoll(msg.id, optionId),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Share card messages — standalone bubble, no burst grouping.
      if (msg.isShareCard) {
        widgets.add(
          Padding(
            key: msgKey,
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMine && widget.isGroup)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      burst.senderName,
                      style: TextStyle(
                        color: Colors.white.withAlpha(150),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ShareCardBubble(message: msg, isMine: isMine),
              ],
            ),
          ),
        );
        continue;
      }

      final isDeleted = msg.isDeleted;

      // Deleted messages: show a minimal placeholder, no interactions.
      if (isDeleted) {
        widgets.add(
          Padding(
            key: msgKey,
            padding: EdgeInsets.only(bottom: isLast ? 0 : 2),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: normalColor.withAlpha(120),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.white.withAlpha(18), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block_rounded,
                        size: 14, color: Colors.white.withAlpha(80)),
                    const SizedBox(width: 6),
                    Text(
                      'Message deleted',
                      style: TextStyle(
                        color: Colors.white.withAlpha(120),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        continue;
      }

      final bubble = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: GestureDetector(
          onLongPress: () => _showMessageActions(msg, pinnedMessageId: pinnedMessageId),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isHighlighted ? highlightColor : normalColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.hasReply)
                  _buildReplyBlock(
                    senderName: msg.replyToSenderName,
                    previewText: msg.replyToPreviewText,
                    onTap: msg.replyToMessageId != null
                        ? () => _jumpToMessage(msg.replyToMessageId!)
                        : null,
                    isMine: isMine,
                  ),
                Text(
                  msg.text,
                  style: TextStyle(
                    color: isMine ? outgoingTextColor : Colors.white,
                  ),
                ),
                // "edited" badge
                if (msg.isEdited)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'edited',
                      style: TextStyle(
                        color: (isMine ? outgoingTextColor : Colors.white)
                            .withAlpha(100),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      final isPinnedMsg = pinnedMessageId != null && msg.id == pinnedMessageId;

      widgets.add(
        Padding(
          key: msgKey,
          padding: EdgeInsets.only(bottom: isLast ? 0 : 2),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPinnedMsg)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.push_pin_rounded,
                          size: 11,
                          color: const Color(0xFF7C7AFF).withAlpha(200)),
                      const SizedBox(width: 3),
                      Text(
                        'Pinned',
                        style: TextStyle(
                          color: const Color(0xFF7C7AFF).withAlpha(200),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              _SwipeToReplyRow(
                onReply:
                    canSend ? () => setState(() => _replyingTo = msg) : null,
                child: bubble,
              ),
              if (msg.hasReactions)
                ReactionRow(
                  reactions: msg.reactions,
                  currentUserId: currentUserId,
                  isMine: isMine,
                  onToggle: (emoji) => _toggleReaction(msg.id, emoji),
                  onShowDetails: (emoji) => showReactionDetails(
                    context: context,
                    reactions: msg.reactions,
                    currentUserId: currentUserId,
                    onRemoveReaction: (e) => _toggleReaction(msg.id, e),
                    initialEmoji: emoji,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final nearBottom = (pos.maxScrollExtent - pos.pixels) <= 150;
    if (nearBottom != _headerVisible) {
      setState(() => _headerVisible = nearBottom);
    }
  }

  Future<void> _sendMessage({required bool canSend}) async {
    if (_isSending) return;

    // If in edit mode, submit edit instead of sending a new message.
    if (_editingMessage != null) {
      final text = _textController.text.trim();
      if (text.isNotEmpty) await _submitEdit(text);
      return;
    }

    if (!canSend) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This ${EventLabel.of(widget.eventId ?? '')} has ended',
            ),
          ),
        );
      }
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty || widget.chatId.trim().isEmpty) return;

    final replyTo = _replyingTo;
    setState(() {
      _isSending = true;
      _replyingTo = null;
    });

    var success = false;
    try {
      final previewText = replyTo != null
          ? (replyTo.text.length > 80
              ? replyTo.text.substring(0, 80)
              : replyTo.text)
          : null;
      success = await ref.read(chatRepositoryProvider).sendMessage(
            chatId: widget.chatId,
            text: text,
            replyToMessageId: replyTo?.id,
            replyToPreviewText: previewText,
            replyToSenderName: replyTo?.senderName,
          );
    } catch (_) {
      success = false;
    }

    try {
      if (!success) {
        return;
      }

      if (!mounted) return;

      _textController.clear();
      _clearMentionSuggestions();
      if (_typingActive) {
        _typingActive = false;
        unawaited(_setTyping(false));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Fire mention notifications fire-and-forget — never block the UI.
      unawaited(_dispatchMentionNotifications(text));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _dismissReactionPicker() {
    if (_reactionPickerOverlay == null) return;
    _reactionPickerOverlay!.remove();
    _reactionPickerOverlay = null;
  }

  void _showMessageActions(
    ChatMessage message, {
    String? pinnedMessageId,
  }) {
    if (message.status != MessageStatus.sent) return;
    if (message.isDeleted) return;

    final currentUserId = ref.read(currentUserIdProvider);
    HapticFeedback.mediumImpact();
    showMessageActionsSheet(
      context: context,
      message: message,
      currentUserId: currentUserId,
      isGroup: widget.isGroup,
      onReact: (emoji) => _toggleReaction(message.id, emoji),
      onReply: () => setState(() => _replyingTo = message),
      onCopy: () {
        Clipboard.setData(ClipboardData(text: message.text));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copied to clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      onEdit: () => _startEdit(message),
      onDelete: () => _confirmDelete(message),
      onMoreEmojis: () => _showFullEmojiPicker(message),
      currentPinnedMessageId: pinnedMessageId,
      onPin: () => _pinMessage(message),
      onUnpin: () => _unpinMessage(),
    );
  }

  Future<void> _pinMessage(ChatMessage message) async {
    final preview = message.isPoll
        ? '📊 ${message.poll?.question ?? ''}'
        : message.text;
    try {
      await ref.read(chatRepositoryProvider).pinMessage(
            chatId: widget.chatId,
            messageId: message.id,
            previewText: preview,
          );
    } catch (e) {
      assert(() {
        debugPrint('[ChatThread] pinMessage error: $e');
        return true;
      }());
    }
  }

  Future<void> _unpinMessage() async {
    try {
      await ref
          .read(chatRepositoryProvider)
          .unpinMessage(chatId: widget.chatId);
    } catch (e) {
      assert(() {
        debugPrint('[ChatThread] unpinMessage error: $e');
        return true;
      }());
    }
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
    });
    _textController.text = message.text;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: message.text.length),
    );
  }

  void _cancelEdit() {
    setState(() => _editingMessage = null);
    _textController.clear();
  }

  Future<void> _confirmDelete(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101726),
        title: const Text('Delete message?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This message will be removed for everyone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(chatRepositoryProvider).deleteMessage(
            chatId: widget.chatId,
            messageId: message.id,
          );
    } catch (e) {
      assert(() {
        debugPrint('[ChatThread] deleteMessage error: $e');
        return true;
      }());
    }
  }

  void _showFullEmojiPicker(ChatMessage message) {
    final currentUserId = ref.read(currentUserIdProvider);
    final currentUserReactions = message.reactions.entries
        .where((e) => e.value.contains(currentUserId))
        .map((e) => e.key)
        .toSet();
    showFullEmojiPicker(
      context: context,
      currentUserReactions: currentUserReactions,
      onEmojiSelected: (emoji) => _toggleReaction(message.id, emoji),
    );
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    if (messageId.trim().isEmpty || emoji.trim().isEmpty) return;
    try {
      await ref.read(chatRepositoryProvider).toggleReaction(
            chatId: widget.chatId,
            messageId: messageId,
            emoji: emoji,
          );
    } catch (e, stack) {
      assert(() {
        debugPrint('[ChatThread] toggleReaction error: $e');
        debugPrintStack(stackTrace: stack);
        return true;
      }());
    }
  }

  Future<void> _submitEdit(String newText) async {
    final editing = _editingMessage;
    if (editing == null) return;
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;
    setState(() => _editingMessage = null);
    _textController.clear();
    try {
      await ref.read(chatRepositoryProvider).editMessage(
            chatId: widget.chatId,
            messageId: editing.id,
            newText: trimmed,
          );
    } catch (e) {
      assert(() {
        debugPrint('[ChatThread] editMessage error: $e');
        return true;
      }());
    }
  }

  void _openCreatePoll() {
    showCreatePollSheet(
      context: context,
      onCreate: (question, options, allowMultiple) async {
        try {
          await ref.read(chatRepositoryProvider).createPoll(
                chatId: widget.chatId,
                question: question,
                options: options,
                allowMultipleVotes: allowMultiple,
              );
        } catch (e) {
          assert(() {
            debugPrint('[ChatThread] createPoll error: $e');
            return true;
          }());
        }
      },
    );
  }

  Future<void> _votePoll(String messageId, String optionId) async {
    try {
      await ref.read(chatRepositoryProvider).votePoll(
            chatId: widget.chatId,
            messageId: messageId,
            optionId: optionId,
          );
    } catch (e) {
      assert(() {
        debugPrint('[ChatThread] votePoll error: $e');
        return true;
      }());
    }
  }

  Future<void> _retryMessage(ChatMessage message) async {
    if (message.status != MessageStatus.failed) return;

    try {
      final retried = await ref.read(chatRepositoryProvider).retryMessage(
            chatId: widget.chatId,
            clientMessageId: message.clientMessageId,
          );
      if (!retried) return;
    } catch (_) {
      // Keep silent: per-message failed status and retry affordance are visible.
      return;
    }
  }

  Future<void> _openEventDetailsFromHeader({
    required String eventId,
  }) async {
    if (!widget.isGroup) return;
    if (!mounted) return;
    final trimmedEventId = eventId.trim();
    if (trimmedEventId.isEmpty) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Event details are not available yet.')),
      );
      return;
    }

    // Tap on group header now opens Event Details directly (no intermediate
    // modal). Guards against missing eventId and unmounted state so the tap
    // can never crash the chat thread, even if the chat doc raced or the
    // event was deleted in another tab.
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: trimmedEventId),
        ),
      );
    } catch (e, stack) {
      debugPrint('ChatThreadScreen._openEventDetailsFromHeader: $e');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open event details.')),
      );
    }
  }
}
