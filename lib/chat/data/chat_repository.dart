import '../models/chat_models.dart';

abstract class ChatRepository {
  Stream<List<ChatConversation>> watchDirectMessages();
  Stream<List<ChatGroup>> watchGroups();
  Stream<List<ActivityItem>> watchActivity();
  Stream<List<DiscoverPerson>> watchDiscoverPeople();
  Stream<List<ChatMessage>> watchMessages(String chatId);

  /// Synchronous read of the last-known message tail for [chatId] — used to
  /// seed `StreamBuilder.initialData` on chat open so the first frame paints
  /// real messages instead of a spinner. Returns an empty list when no
  /// previous tail has been cached this session.
  List<ChatMessage> lastKnownMessages(String chatId);

  /// Fire-and-forget cache warm for the self read-receipt cursor doc
  /// (`chat_meta/{chatId}/members/{currentUid}`). Called from the chat list
  /// onTap a few hundred milliseconds before the chat thread mounts so the
  /// thread's cursor `.snapshots()` first emission is a cache hit instead
  /// of a fresh network roundtrip. No-op on duplicate calls within a
  /// short window so rapid tap-back-tap doesn't double-fetch.
  void prewarmCursor(String chatId);

  Future<bool> sendMessage({
    required String chatId,
    required String text,
    String? clientMessageId,
    String? replyToMessageId,
    String? replyToPreviewText,
    String? replyToSenderName,
  });
  Future<bool> retryMessage({
    required String chatId,
    required String clientMessageId,
  });
  Future<void> flushPendingMessages({String? chatId});
  Future<void> setTyping({required String chatId, required bool isTyping});
  Future<void> markChatRead({required String chatId});
  Future<void> markMessagesDelivered({
    required String chatId,
    required Iterable<String> messageIds,
  });
  Future<void> markMessagesSeen({
    required String chatId,
    required Iterable<String> messageIds,
  });

  Future<void> performDmAction({
    required String chatId,
    required DmSwipeAction action,
  });

  Future<void> performGroupAction({
    required String chatId,
    required DmSwipeAction action,
  });

  /// Reverses a soft-delete by removing the current user from `deletedFor`.
  /// Called when the user taps UNDO within the 3-second window.
  Future<void> undoDeleteChat({required String chatId});

  Future<void> leaveGroupChat({
    required String chatId,
    required String eventId,
  });

  Future<void> respondToActivity({
    required String activityId,
    required bool accepted,
  });

  Future<void> sendFriendRequest({required String userId});

  /// Adds or removes [emoji] reaction by the current user on [messageId].
  /// Toggle semantics: if the user already reacted with this emoji it is
  /// removed; otherwise it is added.  Cleans up the Firestore field entirely
  /// when the last reactor is removed so we never persist empty arrays.
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  });

  /// Replaces [messageId]'s text with [newText] and sets `isEdited = true`.
  /// Only the original sender may call this. Noop on outbox/deleted messages.
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  });

  /// Sends an event or profile share card into [chatId].
  Future<void> sendShareCard({
    required String chatId,
    required String type,
    required Map<String, dynamic> metadata,
  });

  /// Creates a poll message in [chatId].
  Future<void> createPoll({
    required String chatId,
    required String question,
    required List<String> options,
    bool allowMultipleVotes = false,
  });

  /// Toggles the current user's vote for [optionId] in a poll message.
  Future<void> votePoll({
    required String chatId,
    required String messageId,
    required String optionId,
  });

  /// Soft-deletes [messageId] by setting `isDeleted = true`.
  /// The doc is kept so reply threads stay coherent; the text is cleared.
  /// Only the original sender may call this.
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  });

  /// Pins [messageId] in a group chat, storing a short preview for the banner.
  Future<void> pinMessage({
    required String chatId,
    required String messageId,
    required String previewText,
  });

  /// Clears the pinned message from the group chat.
  Future<void> unpinMessage({required String chatId});

  /// One lightweight Firestore query that sums `unreadCount[uid]` across all
  /// chats the current user participates in (both DMs and groups). Emits 0
  /// when there are no unread messages. Used for the bottom-nav badge.
  Stream<int> watchTotalUnreadCount();

  // New Methods to Fix DM and Search
  Future<String> createOrGetDM(String userId1, String userId2);
  Future<List<DiscoverPerson>> searchUsers(String query);

  /// Releases resources held by this repository instance — cancels
  /// subscriptions, clears caches, and closes stream controllers. Call this
  /// via [ref.onDispose] in the Riverpod provider so cleanup runs whenever
  /// the provider is invalidated (e.g. on sign-out).
  Future<void> dispose();
}
