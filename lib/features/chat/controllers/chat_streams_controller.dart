// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/chat/chat_thread_screen.dart';

extension _ChatStreamsController on _ChatThreadScreenState {
  List<String> _safeParticipantIds(dynamic raw) {
    if (raw is Iterable) {
      return raw.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream(String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _presenceDocStream(
    String userId,
  ) {
    return FirebaseFirestore.instance
        .collection('user_presence')
        .doc(userId)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _memberCursorDocStream(
    String chatId,
    String userId,
  ) {
    return FirebaseFirestore.instance
        .collection('chat_meta')
        .doc(chatId)
        .collection('members')
        .doc(userId)
        .snapshots();
  }

  void _ensureEventStream(String eventId) {
    final normalizedEventId = eventId.trim();
    if (normalizedEventId.isEmpty) return;
    if (_eventStream != null && _eventStreamEventId == normalizedEventId) {
      return;
    }

    _eventStreamEventId = normalizedEventId;
    _eventStream = FirebaseFirestore.instance
        .collection('events')
        .doc(normalizedEventId)
        .snapshots();
  }

  void _ensureDmStreams(String otherUserId) {
    final normalizedOtherUserId = otherUserId.trim();
    if (normalizedOtherUserId.isEmpty) return;
    if (_peerUserId == normalizedOtherUserId &&
        _otherUserStream != null &&
        _peerCursorStream != null) {
      return;
    }

    _peerUserId = normalizedOtherUserId;
    _otherUserStream = _userStream(normalizedOtherUserId);
    _peerPresenceStream = _presenceDocStream(normalizedOtherUserId);
    _peerCursorStream = _memberCursorDocStream(
      widget.chatId,
      normalizedOtherUserId,
    );
  }

  Future<bool> _ensureBlockedFuture(
    String currentUserId,
    String otherUserId,
  ) {
    final normalizedOtherUserId = otherUserId.trim();
    final normalizedCurrentUserId = currentUserId.trim();
    final key = '$normalizedCurrentUserId|$normalizedOtherUserId';
    if (_blockedFuture != null && _blockedFutureKey == key) {
      return _blockedFuture!;
    }

    _blockedFutureKey = key;
    _blockedFuture = _blockService.isBlockedEitherWay(
      normalizedCurrentUserId,
      normalizedOtherUserId,
    );
    return _blockedFuture!;
  }
}
