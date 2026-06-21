import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../chat/models/chat_models.dart';
import '../../chat/widgets/ice_breaker_prompts.dart';
import '../../utils/event_label.dart';
import '../../chat/providers/chat_providers.dart';
import '../../chat/widgets/chat_thread_layout.dart';
import '../../chat/widgets/create_poll_sheet.dart';
import '../../chat/widgets/message_actions_sheet.dart';
import '../../chat/widgets/poll_bubble.dart';
import '../../chat/widgets/share_card_bubble.dart';
import '../../widgets/share_to_chat_sheet.dart';
import '../../chat/widgets/message_reaction_picker.dart';
import '../../chat/widgets/reaction_details_sheet.dart';
import '../../chat/widgets/reaction_row.dart';
import '../../services/activity_notification_service.dart';
import '../../services/block_service.dart';
import '../../services/event_service.dart';
import '../../services/notification_types.dart';
import '../../theme/yanegi_theme.dart';
import '../../utils/error_handler.dart';
import '../../widgets/app_avatars.dart';
import '../../widgets/chat_doodle_background.dart';
import '../event_detail_screen.dart';
import '../profile_social_screen.dart';

part '../../features/chat/controllers/chat_streams_controller.dart';
part '../../features/chat/controllers/chat_delivery_controller.dart';
part '../../features/chat/controllers/chat_mention_controller.dart';
part '../../features/chat/controllers/chat_message_actions_controller.dart';
part '../../features/chat/widgets/pinned_banner.dart';
part '../../features/chat/widgets/group_info_modal.dart';
part '../../features/chat/widgets/swipe_to_reply_row.dart';
part '../../features/chat/widgets/seen_initial_bubble.dart';
part '../../features/chat/widgets/alumni_share_button.dart';

class ChatThreadScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String title;
  final bool isGroup;

  /// Pre-known peer uid (for DMs) — when supplied, the peer/cursor streams
  /// attach in `initState` instead of waiting for the chat-doc snapshot.
  final String? peerUserId;

  /// Pre-known event id (for event group chats) — when supplied, the event
  /// stream and command-center header are attached in `initState` so the
  /// header paints on the first frame instead of waiting for the chat doc.
  final String? eventId;

  const ChatThreadScreen({
    super.key,
    required this.chatId,
    required this.title,
    this.isGroup = false,
    this.peerUserId,
    this.eventId,
  });

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final BlockService _blockService = BlockService();
  late final Stream<List<ChatMessage>> _messagesStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _eventStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _selfCursorStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _peerCursorStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _otherUserStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _peerPresenceStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _groupMembersMetaStream;
  Future<bool>? _blockedFuture;
  String? _eventStreamEventId;
  String? _peerUserId;
  String? _blockedFutureKey;

  /// Comparator used by [_chatDocStableStream] to suppress emissions that
  /// only flip transient fields (typing map, lastMessage*, unreadCount,
  /// updatedAt timestamps). Returns `true` when the next snapshot is
  /// structurally equivalent for the body's purposes — body uses only
  /// `isActive`, `eventId`, `participantIds`, `deletedFor`, and the chat
  /// metadata that controls swipe actions.
  static bool _isChatDocStableEqual(
    DocumentSnapshot<Map<String, dynamic>> a,
    DocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final dataA = a.data() ?? const <String, dynamic>{};
    final dataB = b.data() ?? const <String, dynamic>{};
    if ((dataA['isActive'] ?? true) != (dataB['isActive'] ?? true))
      return false;
    if ((dataA['eventId'] ?? '') != (dataB['eventId'] ?? '')) return false;
    if (!_listEquals(dataA['participantIds'], dataB['participantIds'])) {
      return false;
    }
    if (!_listEquals(dataA['deletedFor'], dataB['deletedFor'])) return false;
    if (!_listEquals(dataA['pinnedBy'], dataB['pinnedBy'])) return false;
    if (!_listEquals(dataA['mutedBy'], dataB['mutedBy'])) return false;
    if ((dataA['pinnedMessageId'] ?? '') != (dataB['pinnedMessageId'] ?? ''))
      return false;
    if ((dataA['pinnedMessageText'] ?? '') != (dataB['pinnedMessageText'] ?? ''))
      return false;
    return true;
  }

  static bool _listEquals(dynamic a, dynamic b) {
    final la = a is Iterable ? a.toList(growable: false) : const [];
    final lb = b is Iterable ? b.toList(growable: false) : const [];
    if (la.length != lb.length) return false;
    for (var i = 0; i < la.length; i++) {
      if (la[i] != lb[i]) return false;
    }
    return true;
  }

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatDocStream;

  /// Distinct projection of the chat doc that ignores transient fields the
  /// body never reads (typing map, lastMessage*, unreadCount, updatedAt).
  /// Without this, every keystroke from any participant flips the typing
  /// timestamp on the chat doc and forces the entire body widget tree
  /// (FutureBuilder + Column + AnimatedSize + ListView wrappers) to rebuild
  /// — a constant background cost during active conversations.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
      _chatDocStableStream;

  bool _isSending = false;
  bool _typingActive = false;

  // @mention autocomplete
  final Map<String, String> _participantNames = {}; // uid → display name
  List<MapEntry<String, String>> _mentionSuggestions = [];
  int _mentionAnchorIndex = -1;
  Set<String> _participantsLoaded = {};
  bool _isMarkingRead = false;
  bool _didInitialAutoScroll = false;
  bool _headerVisible = true;
  String? _lastRenderedMessageId;
  int _lastRenderedMessageCount = 0;
  Timer? _typingDebounce;
  // Debounce seen-mark by 1.5 s so the grey double-tick (delivered) is
  // visible to the sender before upgrading to the blue (seen) state.
  Timer? _seenMarkTimer;
  bool _isAckingDelivered = false;
  bool _isAckingSeen = false;
  DateTime? _optimisticLastDeliveredAt;
  DateTime? _optimisticLastSeenAt;

  // Reply state
  ChatMessage? _replyingTo;
  String? _highlightedMessageId;
  Timer? _highlightClearTimer;
  final Map<String, GlobalKey> _messageKeys = {};

  // Reaction picker overlay
  OverlayEntry? _reactionPickerOverlay;

  // Edit mode — non-null while the user is editing a sent message
  ChatMessage? _editingMessage;

  // Row-cache — avoids re-running O(n) buildChatThreadRows on every setState
  // that isn't caused by a new message (scroll threshold, reply toggle, send state).
  List<ChatMessage>? _lastMessages;
  List<ChatThreadRow> _cachedRows = const [];

  /// Synchronously-readable warm-replay seed captured in `initState`. Fed to
  /// `StreamBuilder<List<ChatMessage>>.initialData` so the message list paints
  /// real messages on the first frame instead of a spinner.
  late final List<ChatMessage> _initialMessageSeed;

  // ── Seen-by (group chats) ────────────────────────────────────────────────────

  // ── @Mention autocomplete ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final repo = ref.read(chatRepositoryProvider);
    _chatDocStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots();
    _chatDocStableStream = _chatDocStream.distinct(_isChatDocStableEqual);
    _messagesStream = repo.watchMessages(widget.chatId);
    // Synchronous read of the warm-replay cache — this is what eliminates the
    // spinner flash on chat reopen. The list is `const []` on first-ever open
    // for a chat (cold start, no cache), which is fine — the StreamBuilder
    // renders an empty state for a frame and then pops in messages.
    _initialMessageSeed = repo.lastKnownMessages(widget.chatId);
    final currentUserId = ref.read(currentUserIdProvider);
    _selfCursorStream = _memberCursorDocStream(widget.chatId, currentUserId);

    // Pre-attach event / peer streams synchronously when the caller already
    // knows the IDs (the chat hub does — it ships ChatGroup.eventId and the
    // DM-list pre-resolves the peer uid). This way the EventCommandCenter
    // header and the DM subtitle paint on the first frame instead of waiting
    // for the chat-doc snapshot to round-trip.
    final preEventId = widget.eventId?.trim() ?? '';
    if (preEventId.isNotEmpty) {
      _ensureEventStream(preEventId);
    }
    final prePeerUid = widget.peerUserId?.trim() ?? '';
    if (!widget.isGroup && prePeerUid.isNotEmpty) {
      _ensureDmStreams(prePeerUid);
    }

    if (widget.isGroup) {
      _groupMembersMetaStream = FirebaseFirestore.instance
          .collection('chat_meta')
          .doc(widget.chatId)
          .collection('members')
          .snapshots();
    }
    _scrollController.addListener(_onScroll);
    _scrollController.addListener(_dismissReactionPicker);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markChatRead();
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _seenMarkTimer?.cancel();
    _highlightClearTimer?.cancel();
    if (_typingActive) {
      unawaited(_setTyping(false));
    }
    _reactionPickerOverlay?.remove();
    _reactionPickerOverlay = null;
    _blockedFuture = null;
    _eventStream = null;
    _selfCursorStream = null;
    _peerCursorStream = null;
    _otherUserStream = null;
    _peerPresenceStream = null;
    _groupMembersMetaStream = null;
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Message action helpers ───────────────────────────────────────────────────

  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugPrint(
        '[ChatThreadScreen] build(chatId: ${widget.chatId}, isGroup: ${widget.isGroup})',
      );
      return true;
    }());

    if (widget.chatId.trim().isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF090D15),
        body: Center(
          child: Text(
            'Chat not available',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF090D15),
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1420),
        titleSpacing: 0,
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _chatDocStream,
          builder: (context, chatSnapshot) {
            if (chatSnapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 17)),
                  Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              );
            }
            final chatData =
                chatSnapshot.data?.data() ?? const <String, dynamic>{};
            final participants =
                _safeParticipantIds(chatData['participantIds']);
            final eventId = (chatData['eventId'] ?? '').toString().trim();
            final otherUserId = !widget.isGroup
                ? participants.firstWhere(
                    (id) => id != currentUserId,
                    orElse: () => '',
                  )
                : '';

            if (eventId.isNotEmpty) {
              _ensureEventStream(eventId);
            }

            if (!widget.isGroup && otherUserId.isNotEmpty) {
              _ensureDmStreams(otherUserId);
            }

            if (widget.isGroup) {
              Widget buildGroupTitle({required bool eventEnded}) {
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openEventDetailsFromHeader(eventId: eventId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(fontSize: 17)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${participants.length} members',
                              style: TextStyle(
                                color: Colors.white.withAlpha(150),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            if (eventEnded) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(22),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(45),
                                  ),
                                ),
                                child: Text(
                                  '${EventLabel.capitalized(eventId)} Ended',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (eventId.isEmpty) {
                return buildGroupTitle(eventEnded: false);
              }

              final eventStream = _eventStream;
              if (eventStream == null) {
                return buildGroupTitle(eventEnded: false);
              }

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: eventStream,
                builder: (context, eventSnapshot) {
                  final eventData =
                      eventSnapshot.data?.data() ?? const <String, dynamic>{};
                  final eventEnded = !_isEventActive(eventData);
                  return buildGroupTitle(eventEnded: eventEnded);
                },
              );
            }

            final chatMapTyping = _isOtherUserTyping(chatData, otherUserId);
            if (otherUserId.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 17)),
                  Text(
                    chatMapTyping ? 'Typing…' : 'Offline',
                    style: TextStyle(
                      color: chatMapTyping
                          ? const Color(0xFF22E7A2)
                          : Colors.white.withAlpha(150),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              );
            }

            final otherUserStream = _otherUserStream;
            if (otherUserStream == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 17)),
                  Text(
                    chatMapTyping ? 'Typing…' : 'Offline',
                    style: TextStyle(
                      color: chatMapTyping
                          ? const Color(0xFF22E7A2)
                          : Colors.white.withAlpha(150),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: otherUserStream,
              builder: (context, userSnapshot) {
                // Profile data (name, avatar) — from users/{uid}.
                // Presence data (isOnline, lastSeen) — from user_presence/{uid}
                // via a separate nested StreamBuilder so typing-storm rebuilds
                // on the chat doc don't re-subscribe to the presence collection.
                Widget buildPresenceSubtitle({
                  required bool isOnline,
                  required DateTime? lastSeen,
                }) {
                  final isTyping = chatMapTyping;
                  final showGreenDot = (isOnline || isTyping);
                  final label = isTyping
                      ? 'Typing…'
                      : isOnline
                          ? 'Online'
                          : lastSeen != null
                              ? 'Last seen ${_formatLastSeen(lastSeen)}'
                              : 'Offline';

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showGreenDot) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22E7A2),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: showGreenDot
                              ? const Color(0xFF22E7A2)
                              : Colors.white.withAlpha(150),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  );
                }

                final presenceStream = _peerPresenceStream;
                if (presenceStream == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(fontSize: 17)),
                      buildPresenceSubtitle(
                          isOnline: false, lastSeen: null),
                    ],
                  );
                }

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: presenceStream,
                  builder: (context, presenceSnapshot) {
                    final pd = presenceSnapshot.data?.data() ??
                        const <String, dynamic>{};
                    final isOnline = pd['isOnline'] == true;
                    final lastSeenRaw = pd['lastSeen'];
                    final lastSeen = lastSeenRaw is Timestamp
                        ? lastSeenRaw.toDate()
                        : (lastSeenRaw is DateTime ? lastSeenRaw : null);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: const TextStyle(fontSize: 17)),
                        buildPresenceSubtitle(
                            isOnline: isOnline, lastSeen: lastSeen),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      body: Stack(
        children: [
          const ChatDoodleBackground(),
          AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _chatDocStableStream,
          builder: (context, chatSnapshot) {
            if (chatSnapshot.hasError) {
              return const Center(
                child: Text(
                  'Something went wrong',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }
            final chatData =
                chatSnapshot.data?.data() ?? const <String, dynamic>{};
            final isChatActive = chatData['isActive'] != false;
            final eventId = (chatData['eventId'] ?? '').toString().trim();
            final participants =
                _safeParticipantIds(chatData['participantIds']);
            // Load participant names for @mention autocomplete whenever
            // the participant list changes (group chats only).
            if (widget.isGroup) {
              final participantSet = participants.toSet();
              if (participantSet != _participantsLoaded) {
                _participantsLoaded = participantSet;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _loadParticipantNames(participants);
                });
              }
            }

            final baseCanSend =
                !widget.isGroup || participants.contains(currentUserId);
            final otherUserId = !widget.isGroup
                ? participants.firstWhere(
                    (id) => id != currentUserId,
                    orElse: () => '',
                  )
                : '';

            Widget buildChatBody({
              required bool isEventChatActive,
              required DateTime? selfLastDeliveredAt,
              required DateTime? selfLastSeenAt,
              required DateTime? peerLastDeliveredAt,
              required DateTime? peerLastSeenAt,
            }) {
              final blockedFuture = _ensureBlockedFuture(
                currentUserId,
                otherUserId,
              );

              return FutureBuilder<bool>(
                future: (!widget.isGroup && otherUserId.isNotEmpty)
                    ? blockedFuture
                    : Future.value(false),
                builder: (context, blockSnapshot) {
                  final isBlocked = blockSnapshot.data ?? false;
                  final canSend = baseCanSend &&
                      !isBlocked &&
                      isChatActive &&
                      isEventChatActive;

                  final endedByLifecycle = !isChatActive || !isEventChatActive;
                  final disabledHint = endedByLifecycle
                      ? 'This ${EventLabel.of(eventId)} has ended'
                      : isBlocked
                          ? 'Messaging unavailable for this user'
                          : 'Only participants can send messages';

                  // Extract pin data from the chat doc.
                  final rawPinnedId =
                      (chatData['pinnedMessageId'] ?? '').toString().trim();
                  final pinnedId =
                      rawPinnedId.isEmpty ? null : rawPinnedId;
                  final pinnedText =
                      (chatData['pinnedMessageText'] ?? '').toString().trim();

                  return Column(
                    children: [
                      // Pinned message banner.
                      if (pinnedId != null)
                        _PinnedBanner(
                          text: pinnedText.isEmpty ? 'Pinned message' : pinnedText,
                          onTap: () => _jumpToMessage(pinnedId),
                          onDismiss: _unpinMessage,
                        ),

                      // Note: the persistent EventCommandCenter location strip
                      // was removed from the chat body. Location + Open in
                      // Maps now live on the Event Details screen, reached by
                      // tapping the group title in the AppBar.
                      Expanded(
                        child: StreamBuilder<List<ChatMessage>>(
                          stream: _messagesStream,
                          initialData: _initialMessageSeed,
                          builder: (context, messagesSnapshot) {
                            // No spinner: with `initialData` seeded from the
                            // warm-replay cache we always have a list to render.
                            // For cold-start chats (empty seed), the empty-state
                            // branch below shows "Start conversation" instead of
                            // a spinner — same as WhatsApp / Telegram do.

                            if (messagesSnapshot.hasError) {
                              return Center(
                                child: Text(
                                  'Could not load messages',
                                  style: TextStyle(
                                      color: Colors.white.withAlpha(160)),
                                ),
                              );
                            }

                            // Stream still connecting AND no cached seed —
                            // show a spinner so the user never sees a false
                            // "Start conversation" on a chat that has messages.
                            final isWaiting = messagesSnapshot.connectionState ==
                                ConnectionState.waiting;
                            if (isWaiting && _initialMessageSeed.isEmpty) {
                              return const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              );
                            }

                            final messages =
                                messagesSnapshot.data ?? <ChatMessage>[];

                            // Only recompute rows and notify scroll logic when
                            // the message list actually changed — not on every
                            // parent setState (scroll, reply toggle, typing).
                            if (!identical(messages, _lastMessages)) {
                              _lastMessages = messages;
                              _cachedRows = buildChatThreadRows(messages);
                              // Prune GlobalKeys for messages no longer in
                              // the viewport window, bounding GC pressure.
                              final liveIds = messages.map((m) => m.id).toSet();
                              _messageKeys.removeWhere(
                                  (id, _) => !liveIds.contains(id));
                              _onMessagesUpdated(messages);
                            }
                            unawaited(_syncDeliveryAndSeen(
                              messages,
                              currentUserId,
                              selfLastDeliveredAt: selfLastDeliveredAt,
                              selfLastSeenAt: selfLastSeenAt,
                            ));

                            if (messages.isEmpty) {
                              // Show ice-breaker prompts on empty DMs.
                              // Group chats and self-chats keep the plain label.
                              final peer = _peerUserId ?? '';
                              if (!widget.isGroup && peer.isNotEmpty) {
                                return IceBreakerPrompts(
                                  currentUserId: currentUserId,
                                  peerUserId: peer,
                                  peerName: widget.title,
                                  onPromptSelected: (text) {
                                    _textController.text = text;
                                    // Move cursor to end of filled text.
                                    _textController.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(
                                          offset: text.length),
                                    );
                                    // Trigger typing indicator so the peer
                                    // sees the current user is composing.
                                    _onComposerTextChanged(text, true);
                                  },
                                );
                              }
                              return Center(
                                child: Text(
                                  'Start conversation',
                                  style: TextStyle(
                                      color: Colors.white.withAlpha(150)),
                                ),
                              );
                            }

                            final rows = _cachedRows;

                            // Identify the last burst sent by the current user
                            // so we can show "Seen by N" only under it.
                            String? lastOwnBurstKey;
                            if (widget.isGroup) {
                              for (final row in rows.reversed) {
                                if (row is ChatMessageBurstRow &&
                                    row.isMine(currentUserId)) {
                                  lastOwnBurstKey = row.rowKey;
                                  break;
                                }
                              }
                            }

                            return ListView.builder(
                              controller: _scrollController,
                              reverse: false,
                              padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                              cacheExtent: 800,
                              addAutomaticKeepAlives: false,
                              addRepaintBoundaries: true,
                              itemCount: rows.length,
                              itemBuilder: (context, rowIndex) {
                                final row = rows[rowIndex];
                                if (row is ChatDateDividerRow) {
                                  return ChatDateDivider(
                                    key: ValueKey(row.rowKey),
                                    label: row.label,
                                  );
                                }
                                final burst = row as ChatMessageBurstRow;
                                final isMine = burst.isMine(currentUserId);
                                final outgoingBubbleColor =
                                    Theme.of(context).colorScheme.primary;
                                final outgoingTextColor =
                                    Theme.of(context).colorScheme.onPrimary;
                                final lastMsg = burst.messages.last;
                                return Padding(
                                  key: ValueKey(burst.rowKey),
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: isMine
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    children: [
                                      // Avatar on left for all incoming messages
                                      if (!isMine) ...[
                                        AppUserAvatar(
                                          photoUrl: burst.senderAvatar,
                                          radius: 16,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: isMine
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                        if (!isMine && widget.isGroup)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 2,
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              burst.senderName,
                                              style: TextStyle(
                                                color: Colors.white.withAlpha(150),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ..._buildBurstBubbles(
                                          burst: burst,
                                          isMine: isMine,
                                          outgoingBubbleColor:
                                              outgoingBubbleColor,
                                          outgoingTextColor: outgoingTextColor,
                                          canSend: canSend,
                                          currentUserId: currentUserId,
                                          pinnedMessageId: (chatData['pinnedMessageId'] ?? '').toString().trim().isEmpty
                                              ? null
                                              : chatData['pinnedMessageId'].toString(),
                                        ),
                                        const SizedBox(height: 2),
                                        // Group chats: single combined row —
                                        // shows ✓+time when unseen, "Seen by N"
                                        // (no tick) when anyone has read it.
                                        // DMs: classic 3-state tick row.
                                        if (widget.isGroup && isMine && burst.rowKey == lastOwnBurstKey)
                                          _buildGroupStatusRow(
                                            lastMsg: lastMsg,
                                            participants: participants,
                                            currentUserId: currentUserId,
                                          )
                                        else if (!widget.isGroup)
                                          _buildDeliveryStatusWidget(
                                            message: lastMsg,
                                            isMine: isMine,
                                            peerLastDeliveredAt: peerLastDeliveredAt,
                                            peerLastSeenAt: peerLastSeenAt,
                                            peerDisplayName: widget.title,
                                          )
                                        else
                                          // Group burst that isn't the last own
                                          // burst: show plain time, no tick.
                                          Text(
                                            _formatMessageTime(lastMsg.sentAt),
                                            style: TextStyle(
                                              color: Colors.white.withAlpha(120),
                                              fontSize: 11,
                                            ),
                                          ),
                                        if (isMine &&
                                            lastMsg.status ==
                                                MessageStatus.failed)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: InkWell(
                                              onTap: () =>
                                                  _retryMessage(lastMsg),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent
                                                      .withAlpha(26),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: Colors.redAccent
                                                        .withAlpha(120),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'Retry',
                                                  style: TextStyle(
                                                    color: Colors.redAccent,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          ],
                                        ),
                                      ),
                                      // Spacer for outgoing (mirrors avatar width)
                                      if (isMine) const SizedBox(width: 40),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1420),
                          border: Border(
                            top: BorderSide(color: Colors.white.withAlpha(12)),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Opacity(
                            opacity: endedByLifecycle ? 0.72 : 1,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (endedByLifecycle)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        left: 12, right: 12, bottom: 8),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.celebration_rounded,
                                          size: 13,
                                          color: Colors.white54,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'This ${EventLabel.of(eventId)} has ended · Alumni chat',
                                            style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12),
                                          ),
                                        ),
                                        // Share event into this alumni chat
                                        if (eventId.isNotEmpty)
                                          _AlumniShareButton(
                                            eventId: eventId,
                                            chatId: widget.chatId,
                                          ),
                                      ],
                                    ),
                                  ),
                                // Edit mode banner
                                if (_editingMessage != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF171D2A),
                                      borderRadius: BorderRadius.circular(10),
                                      border: const Border(
                                        left: BorderSide(
                                            color: Color(0xFF22E7A2),
                                            width: 3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.edit_rounded,
                                            size: 14,
                                            color: Color(0xFF22E7A2)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text(
                                                'Editing message',
                                                style: TextStyle(
                                                  color: Color(0xFF22E7A2),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _editingMessage!.text.length > 80
                                                    ? '${_editingMessage!.text.substring(0, 80)}…'
                                                    : _editingMessage!.text,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withAlpha(170),
                                                  fontSize: 12,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: _cancelEdit,
                                          child: Icon(Icons.close_rounded,
                                              size: 18,
                                              color:
                                                  Colors.white.withAlpha(150)),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_replyingTo != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF171D2A),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border(
                                        left: BorderSide(
                                            color: YanegiColors.primary,
                                            width: 3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Replying to ${_replyingTo!.senderName.isNotEmpty ? _replyingTo!.senderName : "Unknown"}',
                                                style: TextStyle(
                                                  color: YanegiColors.primary,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _replyingTo!.text.length > 80
                                                    ? '${_replyingTo!.text.substring(0, 80)}…'
                                                    : _replyingTo!.text,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withAlpha(170),
                                                  fontSize: 12,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () => setState(
                                              () => _replyingTo = null),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: Colors.white.withAlpha(150),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                // @mention autocomplete chips
                                _buildMentionSuggestionsBar(),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Attachments coming soon.'),
                                          ),
                                        );
                                      },
                                      icon: Icon(
                                        Icons.attach_file_rounded,
                                        color: Colors.white.withAlpha(190),
                                      ),
                                    ),
                                    // Poll button — group chats only
                                    if (widget.isGroup && canSend)
                                      IconButton(
                                        tooltip: 'Create poll',
                                        onPressed: _openCreatePoll,
                                        icon: Icon(
                                          Icons.bar_chart_rounded,
                                          color: Colors.white.withAlpha(190),
                                        ),
                                      ),
                                    Expanded(
                                      child: TextField(
                                        controller: _textController,
                                        enabled: canSend && !_isSending,
                                        onChanged: (value) =>
                                            _onComposerTextChanged(
                                                value, canSend),
                                        onSubmitted: (_) =>
                                            _sendMessage(canSend: canSend),
                                        decoration: InputDecoration(
                                          hintText: canSend
                                              ? 'Message...'
                                              : disabledHint,
                                          hintStyle: TextStyle(
                                            color: Colors.white.withAlpha(110),
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFF171D2A),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(24),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                        ),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: canSend && !_isSending
                                          ? () => _sendMessage(canSend: canSend)
                                          : null,
                                      child: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: canSend
                                              ? YanegiColors.primary
                                              : Colors.grey,
                                          shape: BoxShape.circle,
                                        ),
                                        child: _isSending
                                            ? const Padding(
                                                padding: EdgeInsets.all(11),
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(
                                                    Colors.white,
                                                  ),
                                                ),
                                              )
                                            : Icon(
                                                _editingMessage != null
                                                    ? Icons.check_rounded
                                                    : Icons.send_rounded,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }

            final selfCursorStream = _selfCursorStream;
            if (selfCursorStream == null) {
              return buildChatBody(
                isEventChatActive: eventId.isEmpty ? true : false,
                selfLastDeliveredAt: null,
                selfLastSeenAt: null,
                peerLastDeliveredAt: null,
                peerLastSeenAt: null,
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: selfCursorStream,
              builder: (context, selfCursorSnapshot) {
                final selfCursorData = selfCursorSnapshot.data?.data() ??
                    const <String, dynamic>{};
                final selfLastDeliveredAt = _effectiveSelfDeliveredAt(
                    _asDateTime(selfCursorData['lastDeliveredAt']));
                final selfLastSeenAt = _effectiveSelfSeenAt(
                    _asDateTime(selfCursorData['lastSeenAt']));

                Widget buildWithPeerCursor({required bool isEventChatActive}) {
                  if (!widget.isGroup && otherUserId.trim().isNotEmpty) {
                    final peerCursorStream = _peerCursorStream;
                    if (peerCursorStream == null) {
                      return buildChatBody(
                        isEventChatActive: isEventChatActive,
                        selfLastDeliveredAt: selfLastDeliveredAt,
                        selfLastSeenAt: selfLastSeenAt,
                        peerLastDeliveredAt: null,
                        peerLastSeenAt: null,
                      );
                    }

                    return StreamBuilder<
                        DocumentSnapshot<Map<String, dynamic>>>(
                      stream: peerCursorStream,
                      builder: (context, peerCursorSnapshot) {
                        final peerCursorData =
                            peerCursorSnapshot.data?.data() ??
                                const <String, dynamic>{};
                        return buildChatBody(
                          isEventChatActive: isEventChatActive,
                          selfLastDeliveredAt: selfLastDeliveredAt,
                          selfLastSeenAt: selfLastSeenAt,
                          peerLastDeliveredAt:
                              _asDateTime(peerCursorData['lastDeliveredAt']),
                          peerLastSeenAt:
                              _asDateTime(peerCursorData['lastSeenAt']),
                        );
                      },
                    );
                  }

                  return buildChatBody(
                    isEventChatActive: isEventChatActive,
                    selfLastDeliveredAt: selfLastDeliveredAt,
                    selfLastSeenAt: selfLastSeenAt,
                    peerLastDeliveredAt: null,
                    peerLastSeenAt: null,
                  );
                }

                if (eventId.isEmpty) {
                  return buildWithPeerCursor(isEventChatActive: true);
                }

                final eventStream = _eventStream;

                if (eventStream == null) {
                  return buildWithPeerCursor(
                    isEventChatActive: true,
                  );
                }

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _eventStream,
                  builder: (context, eventSnapshot) {
                    final eventData =
                        eventSnapshot.data?.data() ?? const <String, dynamic>{};

                    final isEventChatActive = _isEventActive(eventData);

                    return buildWithPeerCursor(
                      isEventChatActive: isEventChatActive,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pinned message banner shown below the AppBar in group chats.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────

/// Seen-state indicator for DM read receipts.
///
/// Renders a 16×16 circle with the peer's first initial on a deterministic
/// background color + a teal ring. Never makes a network request, never fails,
/// always looks the same regardless of whether the peer has a profile photo.
///
/// Edge cases:
///   • Empty name     → shows "?" on a neutral grey background
///   • Non-ASCII name → takes the first Unicode grapheme (e.g. "李" → "李")
///   • Group chat     → never instantiated (group uses "Seen by N" text)

/// Share button shown in the alumni bar of ended event group chats.
/// Fetches the event title from Firestore once, then opens the share sheet.
