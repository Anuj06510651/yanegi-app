import 'package:flutter/material.dart';

import 'poll_model.dart';

enum ActivityType { friendRequest, eventInvite, groupInvite, joinApproval }

enum DmSwipeAction { pin, mute, delete }

class ChatConversation {
  final String id;
  final String name;
  final String avatarEmoji;
  final String avatarUrl;
  final String lastMessage;
  final String lastMessageSenderId;
  final String lastMessageSenderName;
  final DateTime updatedAt;
  final int unreadCount;
  final bool isActiveNow;
  final bool isTyping;
  final bool isPinned;
  final bool isMuted;
  final bool isDeleted;
  /// Peer uid resolved at list-load time so `ChatThreadScreen` can attach
  /// peer/cursor streams in `initState` without waiting on the chat-doc
  /// snapshot. Empty when the list row was built before the peer could be
  /// resolved (unusual — `watchDirectMessages` always sets it).
  final String otherUserId;

  const ChatConversation({
    required this.id,
    required this.name,
    required this.avatarEmoji,
    this.avatarUrl = '',
    required this.lastMessage,
    this.lastMessageSenderId = '',
    this.lastMessageSenderName = '',
    required this.updatedAt,
    required this.unreadCount,
    required this.isActiveNow,
    required this.isTyping,
    this.isPinned = false,
    this.isMuted = false,
    this.isDeleted = false,
    this.otherUserId = '',
  });

  ChatConversation copyWith({
    String? id,
    String? name,
    String? avatarEmoji,
    String? avatarUrl,
    String? lastMessage,
    String? lastMessageSenderId,
    String? lastMessageSenderName,
    DateTime? updatedAt,
    int? unreadCount,
    bool? isActiveNow,
    bool? isTyping,
    bool? isPinned,
    bool? isMuted,
    bool? isDeleted,
    String? otherUserId,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageSenderName:
          lastMessageSenderName ?? this.lastMessageSenderName,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isActiveNow: isActiveNow ?? this.isActiveNow,
      isTyping: isTyping ?? this.isTyping,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isDeleted: isDeleted ?? this.isDeleted,
      otherUserId: otherUserId ?? this.otherUserId,
    );
  }
}

class ChatGroup {
  final String id;
  final String name;
  final String eventId;
  final String hostId;
  final String bannerUrl;
  final String eventBannerUrl;
  final String eventAvatar;
  final String lastMessage;
  final String lastMessageSenderId;
  final String lastMessageSenderName;
  final int memberCount;
  final bool isEventGroup;
  final bool isActive;
  final bool isPinned;
  final bool isMuted;
  final bool isDeleted;
  final DateTime updatedAt;
  final DateTime? eventEndsAt;
  final List<String> avatarEmojis;

  const ChatGroup({
    required this.id,
    required this.name,
    this.eventId = '',
    this.hostId = '',
    this.bannerUrl = '',
    this.eventBannerUrl = '',
    this.eventAvatar = '',
    required this.lastMessage,
    this.lastMessageSenderId = '',
    this.lastMessageSenderName = '',
    required this.memberCount,
    required this.isEventGroup,
    this.isActive = true,
    this.isPinned = false,
    this.isMuted = false,
    this.isDeleted = false,
    required this.updatedAt,
    required this.avatarEmojis,
    this.eventEndsAt,
  });

  ChatGroup copyWith({
    String? id,
    String? name,
    String? eventId,
    String? hostId,
    String? bannerUrl,
    String? eventBannerUrl,
    String? eventAvatar,
    String? lastMessage,
    String? lastMessageSenderId,
    String? lastMessageSenderName,
    int? memberCount,
    bool? isEventGroup,
    bool? isActive,
    bool? isPinned,
    bool? isMuted,
    bool? isDeleted,
    DateTime? updatedAt,
    DateTime? eventEndsAt,
    List<String>? avatarEmojis,
  }) {
    return ChatGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      eventId: eventId ?? this.eventId,
      hostId: hostId ?? this.hostId,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      eventBannerUrl: eventBannerUrl ?? this.eventBannerUrl,
      eventAvatar: eventAvatar ?? this.eventAvatar,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageSenderName:
          lastMessageSenderName ?? this.lastMessageSenderName,
      memberCount: memberCount ?? this.memberCount,
      isEventGroup: isEventGroup ?? this.isEventGroup,
      isActive: isActive ?? this.isActive,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isDeleted: isDeleted ?? this.isDeleted,
      updatedAt: updatedAt ?? this.updatedAt,
      eventEndsAt: eventEndsAt ?? this.eventEndsAt,
      avatarEmojis: avatarEmojis ?? this.avatarEmojis,
    );
  }

  String get resolvedBannerUrl {
    final fromEventField = eventBannerUrl.trim();
    if (fromEventField.isNotEmpty) return fromEventField;
    return bannerUrl.trim();
  }

  String get resolvedEventAvatar {
    final fromEventField = eventAvatar.trim();
    if (fromEventField.isNotEmpty) return fromEventField;
    return avatarEmojis.isNotEmpty ? avatarEmojis.first : '';
  }

  bool get isExpiredEventGroup {
    if (!isEventGroup || eventEndsAt == null) return false;
    return DateTime.now().isAfter(eventEndsAt!);
  }
}

class ActivityItem {
  final String id;
  final ActivityType type;
  final String title;
  final String subtitle;
  final String avatarEmoji;
  final DateTime createdAt;

  const ActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.avatarEmoji,
    required this.createdAt,
  });

  String get typeLabel {
    switch (type) {
      case ActivityType.friendRequest:
        return 'Friend Request';
      case ActivityType.eventInvite:
        return 'Event Invite';
      case ActivityType.groupInvite:
        return 'Group Invite';
      case ActivityType.joinApproval:
        return 'Join Approval';
    }
  }
}

class DiscoverPerson {
  final String id;
  final String name;
  final String username;
  final String avatarEmoji;
  final String detail;
  final String? suggestionLabel;
  final bool isNearby;
  final List<String> mutualFriendAvatarUrls;
  final bool seenAtSameEvent;
  final String? avatarUrl;
  final int mutualFriendsCount;
  final List<String> commonVibes;
  final double? distanceKm;
  final FriendRelationStatus relationStatus;

  const DiscoverPerson({
    required this.id,
    required this.name,
    this.username = '',
    required this.avatarEmoji,
    required this.detail,
    this.suggestionLabel,
    this.isNearby = false,
    this.mutualFriendAvatarUrls = const [],
    this.seenAtSameEvent = false,
    this.avatarUrl,
    this.mutualFriendsCount = 0,
    this.commonVibes = const [],
    this.distanceKm,
    this.relationStatus = FriendRelationStatus.add,
  });
}

enum FriendRelationStatus { add, requested, friends }

enum MessageStatus { sending, sent, failed }

enum MessageDeliveryStatus { sent, delivered, seen }

class ChatMessage {
  final String id;
  final String chatId;
  final String clientMessageId;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String text;
  final DateTime sentAt;
  final bool isRead;
  final MessageStatus status;
  final int retryCount;
  final String? failureReason;
  final String? replyToMessageId;
  final String replyToPreviewText;
  final String replyToSenderName;
  // emoji → list of user IDs who reacted
  final Map<String, List<String>> reactions;
  final bool isDeleted;
  final bool isEdited;
  final DateTime? editedAt;
  // 'text' (default), 'poll', 'event_card', or 'profile_card'
  final String type;
  final PollData? poll;
  final Map<String, dynamic> metadata;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.clientMessageId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar = '',
    required this.text,
    required this.sentAt,
    required this.isRead,
    this.status = MessageStatus.sent,
    this.retryCount = 0,
    this.failureReason,
    this.replyToMessageId,
    this.replyToPreviewText = '',
    this.replyToSenderName = '',
    this.reactions = const {},
    this.isDeleted = false,
    this.isEdited = false,
    this.editedAt,
    this.type = 'text',
    this.poll,
    this.metadata = const {},
  });

  bool get isPoll => type == 'poll' && poll != null;
  bool get isShareCard => type == 'event_card' || type == 'profile_card';

  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? clientMessageId,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? text,
    DateTime? sentAt,
    bool? isRead,
    MessageStatus? status,
    int? retryCount,
    String? failureReason,
    String? replyToMessageId,
    String? replyToPreviewText,
    String? replyToSenderName,
    Map<String, List<String>>? reactions,
    bool? isDeleted,
    bool? isEdited,
    DateTime? editedAt,
    String? type,
    PollData? poll,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      text: text ?? this.text,
      sentAt: sentAt ?? this.sentAt,
      isRead: isRead ?? this.isRead,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      failureReason: failureReason ?? this.failureReason,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToPreviewText: replyToPreviewText ?? this.replyToPreviewText,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      reactions: reactions ?? this.reactions,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      type: type ?? this.type,
      poll: poll ?? this.poll,
      metadata: metadata ?? this.metadata,
    );
  }

  bool isMine(String currentUserId) => senderId == currentUserId;

  bool get hasReply =>
      replyToMessageId != null && replyToMessageId!.trim().isNotEmpty;

  bool get hasReactions => reactions.isNotEmpty;

  static Map<String, List<String>> parseReactions(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (key.trim().isEmpty) continue;
      final val = entry.value;
      if (val is Iterable) {
        final users =
            val.whereType<String>().where((s) => s.isNotEmpty).toList();
        if (users.isNotEmpty) out[key] = users;
      }
    }
    return out;
  }
}

String formatCompactTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${dt.day}/${dt.month}';
}

Color activityTypeColor(ActivityType type) {
  switch (type) {
    case ActivityType.friendRequest:
      return const Color(0xFF7C7AFF);
    case ActivityType.eventInvite:
      return const Color(0xFF3B82F6);
    case ActivityType.groupInvite:
      return const Color(0xFF22E7A2);
    case ActivityType.joinApproval:
      return const Color(0xFF64B5F6);
  }
}
