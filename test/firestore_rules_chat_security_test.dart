import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Firestore chat security rules hardening', () {
    late String rules;

    setUpAll(() async {
      final file = File('firestore.rules');
      rules = await file.readAsString();
    });

    test('chat reads are participant-scoped (User A cannot read User B chat)',
        () {
      expect(rules.contains('match /chats/{chatId}'), true);
      expect(
          rules.contains(
              'allow read: if isChatParticipantFromData(resource.data);'),
          true);
    });

    test('message creation enforces auth sender identity', () {
      expect(
          rules.contains('request.resource.data.senderId == request.auth.uid'),
          true);
      expect(rules.contains('isChatParticipant(chatId)'), true);
      expect(
          rules.contains(
              'request.resource.data.clientMessageId == request.resource.data.messageId'),
          true);
    });

    test('non-participants are denied by default', () {
      expect(rules.contains('match /{document=**} {'), true);
      expect(rules.contains('allow read: if false;'), true);
      expect(rules.contains('allow write: if false;'), true);
    });

    test('notifications cannot be spoofed', () {
      expect(rules.contains('match /notifications/{notificationId}'), true);
      expect(
          rules.contains('request.resource.data.senderId == request.auth.uid'),
          true);
      expect(rules.contains('resource.data.userId == request.auth.uid'), true);
    });

    test('message updates are disabled (cursor tracking only)', () {
      expect(rules.contains('match /messages/{messageId} {'), true);
      expect(rules.contains('allow update: if false;'), true);
      expect(rules.contains('allow delete: if false;'), true);
    });

    test('chat_meta member cursor writes are self-scoped', () {
      expect(
          rules.contains('match /chat_meta/{chatId}/members/{userId} {'), true);
      expect(rules.contains('request.auth.uid == userId'), true);
      expect(rules.contains('lastDeliveredAt'), true);
      expect(rules.contains('lastSeenAt'), true);
    });

    test('typing subcollection is participant-scoped and self-writable', () {
      expect(rules.contains('match /typing/{userId} {'), true);
      expect(rules.contains('allow read: if isChatParticipant(chatId);'), true);
      expect(rules.contains('request.auth.uid == userId'), true);
    });
  });
}
