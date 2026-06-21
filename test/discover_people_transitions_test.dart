// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';

import 'package:yanegi/chat/data/chat_repository.dart';
import 'package:yanegi/chat/models/chat_models.dart';
import 'package:yanegi/chat/providers/chat_providers.dart';
import 'package:yanegi/screens/chat/chat_hub_screen.dart';

/// Minimal no-op stub satisfying the full [ChatRepository] interface.
/// Only [watchDiscoverPeople] is overridden by subclasses in this test file.
class _StubChatRepository implements ChatRepository {
  @override
  Stream<List<ChatConversation>> watchDirectMessages() => const Stream.empty();
  @override
  Stream<List<ChatGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<ActivityItem>> watchActivity() => const Stream.empty();
  @override
  Stream<List<DiscoverPerson>> watchDiscoverPeople() => const Stream.empty();
  @override
  Stream<List<ChatMessage>> watchMessages(String chatId) =>
      const Stream.empty();
  @override
  List<ChatMessage> lastKnownMessages(String chatId) => const [];
  @override
  void prewarmCursor(String chatId) {}
  @override
  Future<bool> sendMessage({
    required String chatId,
    required String text,
    String? clientMessageId,
    String? replyToMessageId,
    String? replyToPreviewText,
    String? replyToSenderName,
  }) async =>
      false;
  @override
  Future<bool> retryMessage({
    required String chatId,
    required String clientMessageId,
  }) async =>
      false;
  @override
  Future<void> flushPendingMessages({String? chatId}) async {}
  @override
  Future<void> setTyping({
    required String chatId,
    required bool isTyping,
  }) async {}
  @override
  Future<void> markChatRead({required String chatId}) async {}
  @override
  Future<void> markMessagesDelivered({
    required String chatId,
    required Iterable<String> messageIds,
  }) async {}
  @override
  Future<void> markMessagesSeen({
    required String chatId,
    required Iterable<String> messageIds,
  }) async {}
  @override
  Future<void> performDmAction({
    required String chatId,
    required DmSwipeAction action,
  }) async {}
  @override
  Future<void> performGroupAction({
    required String chatId,
    required DmSwipeAction action,
  }) async {}
  @override
  Future<void> undoDeleteChat({required String chatId}) async {}
  @override
  Future<void> leaveGroupChat({
    required String chatId,
    required String eventId,
  }) async {}
  @override
  Future<void> respondToActivity({
    required String activityId,
    required bool accepted,
  }) async {}
  @override
  Future<void> sendFriendRequest({required String userId}) async {}
  @override
  Future<void> sendShareCard({
    required String chatId,
    required String type,
    required Map<String, dynamic> metadata,
  }) async {}
  @override
  Future<String> createOrGetDM(String userId1, String userId2) async => '';
  @override
  Future<List<DiscoverPerson>> searchUsers(String query) async => const [];
  @override
  Stream<int> watchTotalUnreadCount() => Stream<int>.value(0);
  @override
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {}
  @override
  Future<void> pinMessage({
    required String chatId,
    required String messageId,
    required String previewText,
  }) async {}
  @override
  Future<void> unpinMessage({required String chatId}) async {}
  @override
  Future<void> createPoll({
    required String chatId,
    required String question,
    required List<String> options,
    bool allowMultipleVotes = false,
  }) async {}
  @override
  Future<void> votePoll({
    required String chatId,
    required String messageId,
    required String optionId,
  }) async {}
  @override
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {}
  @override
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {}
  @override
  Future<void> dispose() async {}
}

class _ControllableChatRepository extends _StubChatRepository {
  _ControllableChatRepository({List<DiscoverPerson>? initialPeople})
      : _currentPeople = List<DiscoverPerson>.unmodifiable(
          initialPeople ?? const <DiscoverPerson>[],
        );

  final StreamController<List<DiscoverPerson>> _discoverController =
      StreamController<List<DiscoverPerson>>.broadcast();
  List<DiscoverPerson> _currentPeople;

  @override
  Stream<List<DiscoverPerson>> watchDiscoverPeople() async* {
    yield _currentPeople;
    yield* _discoverController.stream;
  }

  void emitDiscover(List<DiscoverPerson> people) {
    _currentPeople = List<DiscoverPerson>.unmodifiable(people);
    _discoverController.add(_currentPeople);
  }

  Future<void> disposeHarness() async {
    await _discoverController.close();
  }
}

DiscoverPerson _person({
  required String id,
  required String name,
}) {
  return DiscoverPerson(
    id: id,
    name: name,
    username: name.toLowerCase(),
    avatarEmoji: '🙂',
    detail: 'Suggested for you',
  );
}

Future<void> _openDiscoverTab(WidgetTester tester) async {
  await tester.tap(find.text('Discover People'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('Discover button transitions Add -> Requested -> Friends -> Add',
      (tester) async {
    final person = _person(id: 'usr_test_1', name: 'Rhea Test');
    final repo = _ControllableChatRepository(initialPeople: <DiscoverPerson>[]);

    final relationControllers =
        <String, StreamController<FriendRelationStatus>>{};

    StreamController<FriendRelationStatus> relationControllerFor(String uid) {
      return relationControllers.putIfAbsent(
        uid,
        () => StreamController<FriendRelationStatus>.broadcast(),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me_test_uid'),
          chatRepositoryProvider.overrideWithValue(repo),
          discoverFriendshipStateProvider.overrideWith((ref, targetUid) {
            return relationControllerFor(targetUid).stream;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatHubScreen(),
          ),
        ),
      ),
    );

    await _openDiscoverTab(tester);

    repo.emitDiscover(<DiscoverPerson>[person]);
    await tester.pumpAndSettle();

    expect(find.text('Rhea Test'), findsOneWidget);
    expect(find.text('Add Friend'), findsOneWidget);

    relationControllerFor(person.id).add(FriendRelationStatus.requested);
    await tester.pumpAndSettle();
    expect(find.text('Requested'), findsOneWidget);

    relationControllerFor(person.id).add(FriendRelationStatus.friends);
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsOneWidget);

    relationControllerFor(person.id).add(FriendRelationStatus.add);
    await tester.pumpAndSettle();
    expect(find.text('Add Friend'), findsOneWidget);

    for (final controller in relationControllers.values) {
      await controller.close();
    }
    await repo.disposeHarness();
  });

  testWidgets('Rejected/deleted request user reappears as Add Friend',
      (tester) async {
    final person = _person(id: 'usr_test_2', name: 'Ishaan Test');
    final repo = _ControllableChatRepository(initialPeople: <DiscoverPerson>[]);

    final relationControllers =
        <String, StreamController<FriendRelationStatus>>{};

    StreamController<FriendRelationStatus> relationControllerFor(String uid) {
      return relationControllers.putIfAbsent(
        uid,
        () => StreamController<FriendRelationStatus>.broadcast(),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('me_test_uid'),
          chatRepositoryProvider.overrideWithValue(repo),
          discoverFriendshipStateProvider.overrideWith((ref, targetUid) {
            return relationControllerFor(targetUid).stream;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ChatHubScreen(),
          ),
        ),
      ),
    );

    await _openDiscoverTab(tester);

    repo.emitDiscover(<DiscoverPerson>[person]);
    await tester.pumpAndSettle();
    expect(find.text('Ishaan Test'), findsOneWidget);
    expect(find.text('Add Friend'), findsOneWidget);

    relationControllerFor(person.id).add(FriendRelationStatus.requested);
    await tester.pumpAndSettle();
    expect(find.text('Requested'), findsOneWidget);

    // Simulate feed exclusion while request is active.
    repo.emitDiscover(const <DiscoverPerson>[]);
    await tester.pumpAndSettle();
    expect(find.text('Ishaan Test'), findsNothing);

    // Rejection/deletion: relationship stream returns to add.
    relationControllerFor(person.id).add(FriendRelationStatus.add);

    // Person should reappear in discover feed and show Add Friend again.
    repo.emitDiscover(<DiscoverPerson>[person]);
    await tester.pumpAndSettle();
    expect(find.text('Ishaan Test'), findsOneWidget);
    expect(find.text('Add Friend'), findsOneWidget);

    for (final controller in relationControllers.values) {
      await controller.close();
    }
    await repo.disposeHarness();
  });
}
