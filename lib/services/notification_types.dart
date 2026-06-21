class NotificationType {
  static const friendRequest = 'friend_request';
  static const friendAccept = 'friend_accept';

  static const eventRequest = 'event_request';
  static const eventAccept = 'event_accept';
  static const eventReject = 'event_reject';
  static const eventCreated = 'event_created';

  static const chatMessage = 'chat_message';

  static const mention = 'mention';

  static const friendJoinedEvent = 'friend_joined_event';

  static const waitlistSpotAvailable = 'waitlist_spot_available';

  static const postEventRecap = 'post_event_recap';
  static const shoutout = 'shoutout';

  static const eventReminder = 'event_reminder';

  static const weeklyDigest = 'weekly_digest';
}

String normalizeType(String type) {
  switch (type.trim().toLowerCase()) {
    case 'friend_accepted':
      return NotificationType.friendAccept;

    case 'event_join_accepted':
      return NotificationType.eventAccept;

    case 'event_join_request':
      return NotificationType.eventRequest;

    // Additional legacy compatibility aliases.
    case 'event_accepted':
      return NotificationType.eventAccept;
    case 'event_rejected':
    case 'event_join_declined':
      return NotificationType.eventReject;
    case 'event_created_by_friend':
    case 'nearby_event':
      return NotificationType.eventCreated;
    case 'dm_message':
    case 'group_message':
    case 'chat':
      return NotificationType.chatMessage;

    default:
      return type.trim().toLowerCase();
  }
}
