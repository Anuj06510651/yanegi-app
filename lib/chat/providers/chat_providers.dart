import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/chat_repository.dart';
import '../data/firebase_chat_repository.dart';
import '../models/chat_models.dart';
import '../../services/friend_service.dart';

final currentUserIdProvider = Provider<String>(
  (_) => FirebaseAuth.instance.currentUser?.uid ?? 'unknown_user',
);

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = FirebaseChatRepository();
  // Dispose the repository when the provider is invalidated (sign-out).
  // This cancels outbox timers, sync subscriptions, and clears all caches
  // so a subsequent sign-in always starts with a clean slate.
  ref.onDispose(() => repo.dispose());
  return repo;
});

final dmListProvider = StreamProvider<List<ChatConversation>>((ref) {
  return ref.watch(chatRepositoryProvider).watchDirectMessages();
});

final groupListProvider = StreamProvider<List<ChatGroup>>((ref) {
  return ref.watch(chatRepositoryProvider).watchGroups();
});

final activityListProvider = StreamProvider<List<ActivityItem>>((ref) {
  return ref.watch(chatRepositoryProvider).watchActivity();
});

final discoverPeopleProvider = StreamProvider<List<DiscoverPerson>>((ref) {
  return ref.watch(chatRepositoryProvider).watchDiscoverPeople();
});

final discoverFriendshipStateProvider =
    StreamProvider.family<FriendRelationStatus, String>((ref, targetUid) {
  final currentUid = ref.watch(currentUserIdProvider).trim();
  final otherUid = targetUid.trim();

  if (currentUid.isEmpty ||
      currentUid == 'unknown_user' ||
      otherUid.isEmpty ||
      otherUid == currentUid) {
    return Stream.value(FriendRelationStatus.add);
  }

  final friendService = FriendService();
  return friendService.friendStateStream(currentUid, otherUid).map((state) {
    switch (state) {
      case FriendRelationshipState.friend:
        return FriendRelationStatus.friends;
      case FriendRelationshipState.requestSent:
      case FriendRelationshipState.requestReceived:
        return FriendRelationStatus.requested;
      case FriendRelationshipState.notFriend:
        return FriendRelationStatus.add;
    }
  });
});

final messageListProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  chatId,
) {
  return ref.watch(chatRepositoryProvider).watchMessages(chatId);
});
