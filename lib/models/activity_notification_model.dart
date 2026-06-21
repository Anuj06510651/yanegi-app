import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_types.dart';

class ActivityNotification {
  final String id;
  final String receiverId;
  final String type;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String eventBannerUrl;
  final String? eventId;
  final String? chatId;
  final String title;
  final String? message;
  final String? dedupeKey;
  final String actionStatus;
  final bool isRead;
  final DateTime createdAt;

  ActivityNotification({
    required this.id,
    required this.receiverId,
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    this.eventBannerUrl = '',
    this.eventId,
    this.chatId,
    required this.title,
    this.message,
    this.dedupeKey,
    this.actionStatus = '',
    required this.isRead,
    required this.createdAt,
  });

  String get userId => receiverId;

  factory ActivityNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ActivityNotification(
      id: doc.id,
      receiverId: (data['receiverId'] ?? data['userId'] ?? '').toString(),
      type: normalizeType((data['type'] ?? '').toString()),
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderAvatar: data['senderAvatar'] ?? '',
      eventBannerUrl: (data['eventBannerUrl'] ?? '').toString(),
      eventId: data['eventId'],
      chatId: data['chatId'],
      title: (data['title'] ?? data['message'] ?? '').toString(),
      message: (data['message'] ?? data['body'])?.toString(),
      dedupeKey: data['dedupeKey']?.toString(),
      actionStatus: (data['actionStatus'] ??
              ((data['type'] ?? '').toString() == 'friend_request'
                  ? 'pending'
                  : ''))
          .toString(),
      isRead: data['read'] == true || data['isRead'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory ActivityNotification.fromMap(
    Map<String, dynamic> data, {
    String id = '',
  }) {
    return ActivityNotification(
      id: id,
      receiverId: (data['receiverId'] ?? data['userId'] ?? '').toString(),
      type: normalizeType((data['type'] ?? '').toString()),
      senderId: (data['senderId'] ?? '').toString(),
      senderName: (data['senderName'] ?? '').toString(),
      senderAvatar: (data['senderAvatar'] ?? '').toString(),
      eventBannerUrl: (data['eventBannerUrl'] ?? '').toString(),
      eventId: data['eventId']?.toString(),
      chatId: data['chatId']?.toString(),
      title: (data['title'] ?? data['message'] ?? '').toString(),
      message: (data['message'] ?? data['body'])?.toString(),
      dedupeKey: data['dedupeKey']?.toString(),
      actionStatus: (data['actionStatus'] ??
              ((data['type'] ?? '').toString() == 'friend_request'
                  ? 'pending'
                  : ''))
          .toString(),
      isRead: data['read'] == true || data['isRead'] == true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'receiverId': receiverId,
      'userId': receiverId,
      'type': type,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      if (eventBannerUrl.trim().isNotEmpty) 'eventBannerUrl': eventBannerUrl,
      if (eventId != null) 'eventId': eventId,
      if (chatId != null) 'chatId': chatId,
      'title': title,
      if (message != null) 'body': message,
      if (message != null) 'message': message,
      if (dedupeKey != null) 'dedupeKey': dedupeKey,
      if (actionStatus.isNotEmpty) 'actionStatus': actionStatus,
      'read': isRead,
      'isRead': isRead,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
