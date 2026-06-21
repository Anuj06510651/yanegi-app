import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference get _chats => _firestore.collection('chats');

  // Get active user chats
  Stream<QuerySnapshot> getUserChats() {
    final uid = _auth.currentUser?.uid;
    return _chats
        .where('participantIds', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  // Get messages for a specific chat
  Stream<QuerySnapshot> getChatMessages(String chatId) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Send a message
  Future<void> sendMessage(
    String chatId,
    String text, {
    String? clientMessageId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      print('TESTING [ERROR]: Cannot send message. No authenticated user.');
      return;
    }

    final normalizedText = text.trim();
    if (normalizedText.isEmpty) return;

    final resolvedClientMessageId = (clientMessageId ?? _uuid.v4()).trim();
    if (resolvedClientMessageId.isEmpty) return;

    final existing = await _chats
        .doc(chatId)
        .collection('messages')
        .where('clientMessageId', isEqualTo: resolvedClientMessageId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      print(
          'TESTING [CHAT]: Skipping duplicate send for clientMessageId=$resolvedClientMessageId');
      return;
    }

    final batch = _firestore.batch();

    final messageRef =
        _chats.doc(chatId).collection('messages').doc(resolvedClientMessageId);
    batch.set(messageRef, {
      'messageId': resolvedClientMessageId,
      'chatId': chatId,
      'senderId': uid,
      'text': normalizedText,
      'clientMessageId': resolvedClientMessageId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final chatRef = _chats.doc(chatId);
    batch.update(chatRef, {
      'lastMessage': normalizedText,
      'lastMessageSenderId': uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
      print(
          'TESTING [CHAT]: Successfully sent message to chat: $chatId | text: $normalizedText');
    } catch (e) {
      print(
          'TESTING [ERROR]: Message send failed for chat: $chatId with error: $e');
    }
  }
}
