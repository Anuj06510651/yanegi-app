// ignore_for_file: depend_on_referenced_packages

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yanegi/chat/data/firebase_chat_repository.dart';
import 'package:yanegi/chat/models/chat_models.dart';
import 'package:yanegi/services/event_service.dart';

Future<void> _seedChat(FirebaseFirestore firestore, String chatId) async {
  await firestore.collection('users').doc('u1').set({
    'name': 'User One',
    'username': 'userone',
  });
  await firestore.collection('users').doc('u2').set({
    'name': 'User Two',
    'username': 'usertwo',
  });

  await firestore.collection('chats').doc(chatId).set({
    'chatId': chatId,
    'type': 'dm',
    'participantIds': ['u1', 'u2'],
    'createdBy': 'u1',
    'isActive': true,
    'lastMessage': '',
    'lastMessageAt': FieldValue.serverTimestamp(),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

FirebaseChatRepository _buildRepository({
  required FirebaseFirestore firestore,
  required FirebaseAuth auth,
  required bool Function() failWrites,
  bool persistOutbox = false,
}) {
  return FirebaseChatRepository(
    firestore: firestore,
    auth: auth,
    persistOutbox: persistOutbox,
    blockCheckOverride: (_, __) async => false,
    eventService: EventService(
      firestore: firestore,
      auth: auth,
      blockCheckOverride: (_, __) async => false,
    ),
    batchCommitOverride: (batch) async {
      if (failWrites()) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'offline',
        );
      }
      await batch.commit();
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // EventService (constructed by these tests) transitively touches
  // FirebaseFirestore.instance via its default MediaStorageService, which needs
  // a Firebase app to exist. Mock the core platform so construction succeeds.
  // Test-only; does not affect production behavior.
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  group('FirebaseChatRepository reliability', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u1', email: 'u1@test.dev'),
      );
    });

    test('send offline queues message as failed/pending and flush sends later',
        () async {
      await _seedChat(firestore, 'chat_a');

      var shouldFailWrite = true;
      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => shouldFailWrite,
      );

      final statuses = <MessageStatus>[];
      final sub = repo.watchMessages('chat_a').listen((messages) {
        ChatMessage? msg;
        for (final candidate in messages) {
          if (candidate.clientMessageId == 'cm_offline_1') {
            msg = candidate;
            break;
          }
        }
        if (msg != null) {
          statuses.add(msg.status);
        }
      });
      addTearDown(sub.cancel);

      final queued = await repo.sendMessage(
        chatId: 'chat_a',
        text: 'hello offline',
        clientMessageId: 'cm_offline_1',
      );
      expect(queued, true);

      await expectLater(
        repo.watchMessages('chat_a').firstWhere((messages) {
          return messages.any((m) =>
              m.clientMessageId == 'cm_offline_1' &&
              m.status == MessageStatus.failed);
        }),
        completion(isA<List<ChatMessage>>()),
      );
      expect(statuses.contains(MessageStatus.failed), true);

      final missingDoc = await firestore
          .collection('chats')
          .doc('chat_a')
          .collection('messages')
          .doc('cm_offline_1')
          .get();
      expect(missingDoc.exists, false);

      shouldFailWrite = false;
      await repo.flushPendingMessages(chatId: 'chat_a');
      await expectLater(
        repo.watchMessages('chat_a').firstWhere((messages) {
          return messages.any((m) =>
              m.clientMessageId == 'cm_offline_1' &&
              m.status == MessageStatus.sent);
        }),
        completion(isA<List<ChatMessage>>()),
      );

      final deliveredDoc = await firestore
          .collection('chats')
          .doc('chat_a')
          .collection('messages')
          .doc('cm_offline_1')
          .get();
      expect(deliveredDoc.exists, true);
      expect(statuses.contains(MessageStatus.sent), true);
    });

    test('duplicate send with same clientMessageId is prevented', () async {
      await _seedChat(firestore, 'chat_b');

      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => false,
      );

      await repo.sendMessage(
        chatId: 'chat_b',
        text: 'first',
        clientMessageId: 'cm_dup_1',
      );
      await repo.sendMessage(
        chatId: 'chat_b',
        text: 'first duplicate try',
        clientMessageId: 'cm_dup_1',
      );

      await expectLater(
        repo.watchMessages('chat_b').firstWhere((messages) {
          return messages.any((m) =>
              m.clientMessageId == 'cm_dup_1' &&
              m.status == MessageStatus.sent);
        }),
        completion(isA<List<ChatMessage>>()),
      );

      final docs = await firestore
          .collection('chats')
          .doc('chat_b')
          .collection('messages')
          .where('clientMessageId', isEqualTo: 'cm_dup_1')
          .get();
      expect(docs.docs.length, 1);
    });

    test('retry failed message reuses same clientMessageId', () async {
      await _seedChat(firestore, 'chat_c');

      var shouldFailWrite = true;
      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => shouldFailWrite,
      );

      await repo.sendMessage(
        chatId: 'chat_c',
        text: 'retry me',
        clientMessageId: 'cm_retry_1',
      );

      shouldFailWrite = false;
      final retried = await repo.retryMessage(
        chatId: 'chat_c',
        clientMessageId: 'cm_retry_1',
      );
      expect(retried, true);

      await expectLater(
        repo.watchMessages('chat_c').firstWhere((messages) {
          return messages.any((m) =>
              m.clientMessageId == 'cm_retry_1' &&
              m.status == MessageStatus.sent);
        }),
        completion(isA<List<ChatMessage>>()),
      );

      final sentDoc = await firestore
          .collection('chats')
          .doc('chat_c')
          .collection('messages')
          .doc('cm_retry_1')
          .get();
      expect(sentDoc.exists, true);
      expect(sentDoc.data()?['clientMessageId'], 'cm_retry_1');
    });

    test('no message loss after reconnect flush for multiple queued messages',
        () async {
      await _seedChat(firestore, 'chat_d');

      var shouldFailWrite = true;
      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => shouldFailWrite,
      );

      for (var i = 0; i < 3; i++) {
        await repo.sendMessage(
          chatId: 'chat_d',
          text: 'msg $i',
          clientMessageId: 'cm_loss_$i',
        );
      }

      shouldFailWrite = false;
      await repo.flushPendingMessages(chatId: 'chat_d');
      QuerySnapshot<Map<String, dynamic>> all = await firestore
          .collection('chats')
          .doc('chat_d')
          .collection('messages')
          .get();

      var attempts = 0;
      while (all.docs.length < 3 && attempts < 20) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await repo.flushPendingMessages(chatId: 'chat_d');
        all = await firestore
            .collection('chats')
            .doc('chat_d')
            .collection('messages')
            .get();
        attempts++;
      }

      final clientIds = all.docs
          .map((d) => (d.data()['clientMessageId'] ?? '').toString())
          .toSet();

      expect(clientIds.contains('cm_loss_0'), true);
      expect(clientIds.contains('cm_loss_1'), true);
      expect(clientIds.contains('cm_loss_2'), true);
      expect(all.docs.length, 3);
    });

    test('typing writes to chats/{chatId}/typing/{userId}', () async {
      await _seedChat(firestore, 'chat_typing');
      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => false,
      );

      await repo.setTyping(chatId: 'chat_typing', isTyping: true);

      final typingDoc = await firestore
          .collection('chats')
          .doc('chat_typing')
          .collection('typing')
          .doc('u1')
          .get();
      expect(typingDoc.exists, true);
      expect(typingDoc.data()?['isTyping'], true);

      final chatDoc =
          await firestore.collection('chats').doc('chat_typing').get();
      final typingMap = (chatDoc.data()?['typing'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      final meTyping = (typingMap['u1'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};
      expect(meTyping['isTyping'], true);
    });

    test('markMessagesDelivered updates per-user chat_meta delivery cursor',
        () async {
      await _seedChat(firestore, 'chat_delivery');

      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => false,
      );

      await repo.markMessagesDelivered(
        chatId: 'chat_delivery',
        messageIds: const ['msg_delivery_1'],
      );

      final updated = await firestore
          .collection('chat_meta')
          .doc('chat_delivery')
          .collection('members')
          .doc('u1')
          .get();

      final data = updated.data() ?? const <String, dynamic>{};
      expect(data['lastDeliveredAt'], isA<Timestamp>());
      expect(data['lastSeenAt'], isNull);
    });

    test('markMessagesSeen updates per-user seen + delivered cursors',
        () async {
      await _seedChat(firestore, 'chat_seen');

      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => false,
      );

      await repo.markMessagesSeen(
        chatId: 'chat_seen',
        messageIds: const ['msg_seen_1'],
      );

      final updated = await firestore
          .collection('chat_meta')
          .doc('chat_seen')
          .collection('members')
          .doc('u1')
          .get();

      final data = updated.data() ?? const <String, dynamic>{};
      expect(data['lastDeliveredAt'], isA<Timestamp>());
      expect(data['lastSeenAt'], isA<Timestamp>());
    });

    test(
        'open chat after 100 incoming messages writes single member cursor doc',
        () async {
      await _seedChat(firestore, 'chat_bulk_seen');

      for (var i = 0; i < 100; i++) {
        await firestore
            .collection('chats')
            .doc('chat_bulk_seen')
            .collection('messages')
            .doc('msg_bulk_$i')
            .set({
          'messageId': 'msg_bulk_$i',
          'clientMessageId': 'msg_bulk_$i',
          'chatId': 'chat_bulk_seen',
          'senderId': 'u2',
          'text': 'incoming $i',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => false,
      );

      await repo.markChatRead(chatId: 'chat_bulk_seen');

      final memberCursorDocs = await firestore
          .collection('chat_meta')
          .doc('chat_bulk_seen')
          .collection('members')
          .get();
      expect(memberCursorDocs.docs.length, 1);
      expect(memberCursorDocs.docs.first.id, 'u1');
    });

    test('watchMessages does not duplicate local and remote message entries',
        () async {
      await _seedChat(firestore, 'chat_merge_unique');

      var shouldFailWrite = true;
      final repo = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => shouldFailWrite,
      );

      await repo.sendMessage(
        chatId: 'chat_merge_unique',
        text: 'dedupe-check',
        clientMessageId: 'cm_merge_1',
      );

      shouldFailWrite = false;
      await repo.flushPendingMessages(chatId: 'chat_merge_unique');

      final merged = await repo.watchMessages('chat_merge_unique').firstWhere(
            (messages) => messages.any(
              (m) =>
                  m.clientMessageId == 'cm_merge_1' &&
                  m.status == MessageStatus.sent,
            ),
          );

      final duplicateCount =
          merged.where((m) => m.clientMessageId == 'cm_merge_1').length;
      expect(duplicateCount, 1);
    });

    test('pending outbox message is restored after repository restart',
        () async {
      await _seedChat(firestore, 'chat_persisted_outbox');

      var shouldFailWrite = true;
      final repoA = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => shouldFailWrite,
        persistOutbox: true,
      );

      await repoA.sendMessage(
        chatId: 'chat_persisted_outbox',
        text: 'survive restart',
        clientMessageId: 'cm_persist_1',
      );

      await expectLater(
        repoA.watchMessages('chat_persisted_outbox').firstWhere((messages) {
          return messages.any((m) =>
              m.clientMessageId == 'cm_persist_1' &&
              m.status == MessageStatus.failed);
        }),
        completion(isA<List<ChatMessage>>()),
      );

      shouldFailWrite = false;
      final repoB = _buildRepository(
        firestore: firestore,
        auth: auth,
        failWrites: () => false,
        persistOutbox: true,
      );

      await expectLater(
        repoB.watchMessages('chat_persisted_outbox').firstWhere((messages) {
          return messages.any((m) => m.clientMessageId == 'cm_persist_1');
        }),
        completion(isA<List<ChatMessage>>()),
      );

      await repoB.flushPendingMessages(chatId: 'chat_persisted_outbox');
      await expectLater(
        repoB.watchMessages('chat_persisted_outbox').firstWhere((messages) {
          return messages.any((m) =>
              m.clientMessageId == 'cm_persist_1' &&
              m.status == MessageStatus.sent);
        }),
        completion(isA<List<ChatMessage>>()),
      );

      final sentDoc = await firestore
          .collection('chats')
          .doc('chat_persisted_outbox')
          .collection('messages')
          .doc('cm_persist_1')
          .get();
      expect(sentDoc.exists, true);
    });
  });
}
