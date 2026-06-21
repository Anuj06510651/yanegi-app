import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_models.dart';
import '../models/outbox_message.dart';
import '../models/poll_model.dart';
import 'chat_repository.dart';
import '../../services/block_service.dart';
import '../../services/chat_peer_cache.dart';
import '../../services/event_service.dart';
import '../../services/friend_service.dart';
import '../../services/notification_service.dart';
import '../../services/notification_types.dart';

class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    BlockService? blockService,
    EventService? eventService,
    FriendService? friendService,
    NotificationService? notificationService,
    Uuid? uuid,
    bool persistOutbox = true,
    Future<void> Function(WriteBatch batch)? batchCommitOverride,
    Future<bool> Function(String userA, String userB)? blockCheckOverride,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _blockService = blockService,
        _eventService = eventService ??
            EventService(
              firestore: firestore,
              auth: auth,
              notificationService: notificationService,
            ),
        _friendService = friendService ??
            FriendService(
              firestore: firestore,
              auth: auth,
              blockService: blockService,
              notificationService: notificationService,
            ),
        _notificationService =
            notificationService ?? NotificationService(firestore: firestore),
        _uuid = uuid ?? const Uuid(),
        _persistOutbox = persistOutbox,
        _batchCommitOverride = batchCommitOverride,
        _blockCheckOverride = blockCheckOverride;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final BlockService? _blockService;
  final EventService _eventService;
  final FriendService _friendService;
  final NotificationService _notificationService;
  static const Duration _discoverCacheTtl = Duration(minutes: 3);
  static const double _nearbyThresholdKm = 5.0;
  static const Duration _outboxRetryTick = Duration(seconds: 4);
  static const Duration _outboxSentRetention = Duration(seconds: 25);
  static const Duration _retryMaxDelay = Duration(seconds: 45);
  static const String _outboxStoragePrefix = 'chat_outbox_v1:';
  static const String _outboxHiveBoxName = 'chat_outbox_v1';
  static Future<Box<String>>? _outboxBoxFuture;
  static final Map<String, String> _outboxMemoryFallback = <String, String>{};
  final Map<String, Stream<List<ChatMessage>>> _messageStreams =
      <String, Stream<List<ChatMessage>>>{};
  // Last-known remote message tail per chatId. Seeds the multi-stream's
  // first emit on reopen so a returning user sees the previous tail
  // *immediately* instead of flashing the "Start conversation" empty
  // state while Firestore re-establishes its listener.
  final Map<String, List<ChatMessage>> _lastRemoteMessagesByChat =
      <String, List<ChatMessage>>{};
  // Last-known group list per uid. Used as the warm-replay seed on
  // `watchGroups()` so the Groups tab paints instantly with the previous
  // result while the live Firestore listener re-establishes in the
  // background. Cleared on sign-out.
  final Map<String, List<ChatGroup>> _lastGroupsByUid =
      <String, List<ChatGroup>>{};

  final Uuid _uuid;
  final bool _persistOutbox;
  final Future<void> Function(WriteBatch batch)? _batchCommitOverride;
  final Future<bool> Function(String userA, String userB)? _blockCheckOverride;
  DateTime? _discoverCacheAt;
  List<DiscoverPerson> _discoverCache = const [];
  final Map<String, Map<String, _OutboxMessage>> _outboxByChat =
      <String, Map<String, _OutboxMessage>>{};
  final Map<String, StreamController<void>> _outboxSignalByChat =
      <String, StreamController<void>>{};
  Timer? _outboxRetryTimer;
  StreamSubscription<void>? _syncSubscription;
  final Map<String, Future<void>> _hydratingOutboxByChat =
      <String, Future<void>>{};

  String get _currentUid => _auth.currentUser?.uid ?? 'unknown_user';

  // Cached app-profile display name for the signed-in user. Read once on
  // demand from `users/{uid}.name` so outgoing messages never fall back to
  // `FirebaseAuth.currentUser.displayName` (which would leak the Google
  // account display name). Invalidated on sign-out alongside other caches.
  String? _cachedSelfName;
  String? _cachedSelfNameForUid;

  Future<String> _resolveSelfDisplayName() async {
    final uid = _currentUid;
    if (uid == 'unknown_user') return 'You';
    if (_cachedSelfNameForUid == uid &&
        _cachedSelfName != null &&
        _cachedSelfName!.trim().isNotEmpty) {
      return _cachedSelfName!;
    }
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? const <String, dynamic>{};
      final name = (data['name'] ?? data['username'] ?? '').toString().trim();
      final resolved = name.isEmpty ? 'You' : name;
      _cachedSelfName = resolved;
      _cachedSelfNameForUid = uid;
      return resolved;
    } catch (_) {
      return 'You';
    }
  }

  Future<void> _commitBatch(WriteBatch batch) async {
    final override = _batchCommitOverride;
    if (override != null) {
      await override(batch);
      return;
    }
    await batch.commit();
  }

  Future<bool> _isBlockedEitherWay(String userA, String userB) async {
    if (_blockCheckOverride != null) {
      return _blockCheckOverride(userA, userB);
    }
    return (_blockService ?? BlockService()).isBlockedEitherWay(userA, userB);
  }

  String _newClientMessageId() => _uuid.v4();

  String _deterministicDmChatId(String userId1, String userId2) {
    final sorted = <String>[userId1.trim(), userId2.trim()]..sort();
    final encoded = base64Url
        .encode(utf8.encode('${sorted[0]}|${sorted[1]}'))
        .replaceAll('=', '');
    return 'dm_$encoded';
  }

  Map<String, _OutboxMessage> _outboxForChat(String chatId) {
    return _outboxByChat.putIfAbsent(chatId, () => <String, _OutboxMessage>{});
  }

  StreamController<void> _outboxSignalController(String chatId) {
    return _outboxSignalByChat.putIfAbsent(
      chatId,
      () => StreamController<void>.broadcast(),
    );
  }

  String _outboxStorageKey(String chatId) => '$_outboxStoragePrefix$chatId';

  DocumentReference<Map<String, dynamic>> _chatMetaMemberRef({
    required String chatId,
    required String userId,
  }) {
    return _firestore
        .collection('chat_meta')
        .doc(chatId)
        .collection('members')
        .doc(userId);
  }

  Future<void> _touchDeliveryCursor({
    required String chatId,
    required bool markSeen,
  }) async {
    if (chatId.trim().isEmpty || _currentUid == 'unknown_user') return;

    final payload = <String, dynamic>{
      'lastDeliveredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (markSeen) {
      payload['lastSeenAt'] = FieldValue.serverTimestamp();
    }

    await _chatMetaMemberRef(chatId: chatId, userId: _currentUid).set(
      payload,
      SetOptions(merge: true),
    );
  }

  Future<Box<String>?> _getOutboxBox() async {
    if (!_persistOutbox) return null;

    try {
      final boxFuture = _outboxBoxFuture ??= () async {
        await Hive.initFlutter();
        return Hive.openBox<String>(_outboxHiveBoxName);
      }();
      return await boxFuture;
    } catch (_) {
      return null;
    }
  }

  String _statusToStorage(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return 'sending';
      case MessageStatus.sent:
        return 'sent';
      case MessageStatus.failed:
        return 'failed';
    }
  }

  MessageStatus _statusFromStorage(String raw) {
    switch (raw) {
      case 'failed':
        return MessageStatus.failed;
      case 'sent':
        return MessageStatus.sent;
      default:
        return MessageStatus.sending;
    }
  }

  Map<String, dynamic> _serializeOutboxItem(_OutboxMessage item) {
    return OutboxMessage(
      localId: item.clientMessageId,
      chatId: item.chatId,
      text: item.text,
      senderId: item.senderId,
      senderName: item.senderName,
      eventId: item.eventId,
      participantIds: item.participantIds,
      createdAt: item.createdAt,
      status: _statusToStorage(item.status),
      lastUpdatedAt: item.lastUpdatedAt,
      nextAttemptAt: item.nextAttemptAt,
      retryCount: item.retryCount,
      failureReason: item.failureReason,
      inFlight: item.inFlight,
      replyToMessageId: item.replyToMessageId,
      replyToPreviewText: item.replyToPreviewText,
      replyToSenderName: item.replyToSenderName,
    ).toMap();
  }

  _OutboxMessage? _deserializeOutboxItem(
    String chatId,
    Map<String, dynamic> data,
  ) {
    final normalized = Map<String, dynamic>.from(data);
    if (!normalized.containsKey('localId') &&
        normalized.containsKey('clientMessageId')) {
      normalized['localId'] = normalized['clientMessageId'];
    }

    final parsed = OutboxMessage.fromMap(normalized);
    final clientMessageId = parsed.localId.trim();
    final text = parsed.text;
    final senderId = parsed.senderId.trim();

    if (clientMessageId.isEmpty || text.trim().isEmpty || senderId.isEmpty) {
      return null;
    }

    return _OutboxMessage(
      chatId: chatId,
      clientMessageId: clientMessageId,
      text: text,
      senderId: senderId,
      senderName: parsed.senderName,
      eventId: parsed.eventId,
      participantIds: parsed.participantIds,
      createdAt: parsed.createdAt,
      lastUpdatedAt: parsed.lastUpdatedAt,
      nextAttemptAt: parsed.nextAttemptAt,
      status: _statusFromStorage(parsed.status),
      retryCount: parsed.retryCount,
      failureReason: parsed.failureReason,
      inFlight: false,
      replyToMessageId: parsed.replyToMessageId,
      replyToPreviewText: parsed.replyToPreviewText,
      replyToSenderName: parsed.replyToSenderName,
    );
  }

  Future<void> _persistOutboxForChat(String chatId) async {
    if (!_persistOutbox || chatId.trim().isEmpty) return;

    try {
      final box = await _getOutboxBox();
      final outbox = _outboxByChat[chatId];
      if (outbox == null || outbox.isEmpty) {
        final key = _outboxStorageKey(chatId);
        if (box != null) {
          await box.delete(key);
        } else {
          _outboxMemoryFallback.remove(key);
        }
        return;
      }

      final persistable = outbox.values
          .where((item) => item.status != MessageStatus.sent)
          .map(_serializeOutboxItem)
          .toList(growable: false);

      if (persistable.isEmpty) {
        final key = _outboxStorageKey(chatId);
        if (box != null) {
          await box.delete(key);
        } else {
          _outboxMemoryFallback.remove(key);
        }
        return;
      }

      final encoded = jsonEncode(persistable);
      final key = _outboxStorageKey(chatId);
      if (box != null) {
        await box.put(key, encoded);
      } else {
        _outboxMemoryFallback[key] = encoded;
      }
    } catch (_) {
      // Non-fatal persistence failure should not break chat flow.
    }
  }

  Future<void> _hydrateOutboxForChat(String chatId) {
    if (!_persistOutbox || chatId.trim().isEmpty) {
      return Future<void>.value();
    }

    final existing = _hydratingOutboxByChat[chatId];
    if (existing != null) return existing;

    final hydration = () async {
      try {
        final box = await _getOutboxBox();
        final key = _outboxStorageKey(chatId);
        final encoded = box != null ? box.get(key) : _outboxMemoryFallback[key];
        if (encoded == null || encoded.trim().isEmpty) return;

        final decoded = jsonDecode(encoded);
        if (decoded is! List) return;

        final outbox = _outboxForChat(chatId);
        var added = false;

        for (final raw in decoded) {
          if (raw is! Map) continue;
          final item = _deserializeOutboxItem(
            chatId,
            Map<String, dynamic>.from(raw.cast<dynamic, dynamic>()),
          );
          if (item == null || item.status == MessageStatus.sent) continue;
          if (outbox.containsKey(item.clientMessageId)) continue;
          outbox[item.clientMessageId] = item;
          added = true;
        }

        if (added) {
          _ensureOutboxPump();
          _emitOutboxSignal(chatId);
        }
      } catch (_) {
        // Ignore malformed persistence payloads.
      } finally {
        _hydratingOutboxByChat.remove(chatId);
      }
    }();

    _hydratingOutboxByChat[chatId] = hydration;
    return hydration;
  }

  void _emitOutboxSignal(String chatId) {
    final controller = _outboxSignalByChat[chatId];
    if (controller == null || controller.isClosed) return;
    controller.add(null);
  }

  void _ensureOutboxPump() {
    _outboxRetryTimer ??= Timer.periodic(
      _outboxRetryTick,
      (_) {
        flushPendingMessages();
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _syncSubscription?.cancel();
    _outboxRetryTimer?.cancel();

    for (final controller in _outboxSignalByChat.values) {
      await controller.close();
    }

    _outboxSignalByChat.clear();
    _messageStreams.clear();
    _lastRemoteMessagesByChat.clear();
    _lastGroupsByUid.clear();
    _cachedSelfName = null;
    _cachedSelfNameForUid = null;
  }

  bool _isRetryableError(Object error) {
    if (error is FirebaseException) {
      return error.code == 'unavailable' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'aborted' ||
          error.code == 'cancelled' ||
          error.code == 'internal' ||
          error.code == 'network-request-failed';
    }

    final raw = error.toString().toLowerCase();
    return raw.contains('network') ||
        raw.contains('timed out') ||
        raw.contains('unavailable') ||
        raw.contains('offline');
  }

  Duration _retryBackoff(int retryCount) {
    final seconds = math.min(1 << retryCount, _retryMaxDelay.inSeconds);
    return Duration(seconds: seconds);
  }

  ChatMessage _outboxToChatMessage(_OutboxMessage item) {
    return ChatMessage(
      id: item.clientMessageId,
      chatId: item.chatId,
      clientMessageId: item.clientMessageId,
      senderId: item.senderId,
      senderName: item.senderName,
      text: item.text,
      sentAt: item.createdAt,
      isRead: true,
      status: item.status,
      retryCount: item.retryCount,
      failureReason:
          item.failureReason.trim().isEmpty ? null : item.failureReason,
      replyToMessageId: item.replyToMessageId,
      replyToPreviewText: item.replyToPreviewText,
      replyToSenderName: item.replyToSenderName,
    );
  }

  List<ChatMessage> _mergeRemoteAndOutbox(
    String chatId,
    List<ChatMessage> remote,
  ) {
    final mergedByClientId = <String, ChatMessage>{};

    for (final message in remote) {
      final key = message.clientMessageId.trim().isEmpty
          ? message.id
          : message.clientMessageId;
      mergedByClientId[key] = message.copyWith(status: MessageStatus.sent);
    }

    final outbox = _outboxByChat[chatId];
    if (outbox != null) {
      final now = DateTime.now();
      final staleSent = <String>[];

      for (final entry in outbox.entries) {
        final key = entry.key;
        final item = entry.value;
        final remoteMessage = mergedByClientId[key];

        if (remoteMessage != null) {
          if (item.status == MessageStatus.sent) {
            final age = now.difference(item.lastUpdatedAt);
            if (age >= _outboxSentRetention) {
              staleSent.add(key);
            }
          }
          continue;
        }

        mergedByClientId[key] = _outboxToChatMessage(item);
      }

      for (final key in staleSent) {
        outbox.remove(key);
      }

      if (staleSent.isNotEmpty) {
        unawaited(_persistOutboxForChat(chatId));
        _emitOutboxSignal(chatId);
      }
    }

    final merged = mergedByClientId.values.toList()
      ..sort((a, b) {
        final byTime = a.sentAt.compareTo(b.sentAt);
        if (byTime != 0) return byTime;
        return a.clientMessageId.compareTo(b.clientMessageId);
      });
    return merged;
  }

  List<String> _toStringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const <String>[];
  }

  String _normalizeEventAvatar(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';

    final lower = value.toLowerCase();
    // Remote URLs are not valid Flutter asset paths — strip them.
    // Local asset paths (e.g. "image assest/soccer-ball.png") are preserved
    // so EventCategoryAvatar can render them via Image.asset.
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return '';
    }

    return value;
  }

  bool _containsUid(dynamic raw, String uid) {
    return _toStringList(raw).contains(uid);
  }

  bool _isUserTyping(Map<String, dynamic> chatData, String userId) {
    if (userId.trim().isEmpty) return false;

    final typingRaw = chatData['typing'];
    if (typingRaw is! Map) return false;
    final typingMap = Map<String, dynamic>.from(typingRaw);
    final userTyping = typingMap[userId];
    if (userTyping is! Map) return false;
    final payload = Map<String, dynamic>.from(userTyping);
    if (payload['isTyping'] != true) return false;

    final updatedAt = payload['updatedAt'];
    final updatedAtDate = updatedAt is Timestamp
        ? updatedAt.toDate()
        : (updatedAt is DateTime ? updatedAt : null);
    if (updatedAtDate == null) return true;

    return DateTime.now().difference(updatedAtDate).inSeconds <= 8;
  }

  Future<void> _createNotification({
    required String receiverId,
    required String type,
    required String message,
    bool persistActivity = true,
    String? eventId,
    String? chatId,
    String? dedupeKey,
    Duration dedupeWindow = const Duration(minutes: 1),
  }) async {
    if (_currentUid == 'unknown_user' || receiverId == _currentUid) return;
    if (!persistActivity) return;

    final key = dedupeKey ??
        '$type:$_currentUid:$receiverId:${eventId ?? ''}:${chatId ?? ''}:$message';

    final me = await _firestore.collection('users').doc(_currentUid).get();
    final meData = me.data() ?? {};
    String eventBannerUrl = '';
    if (eventId != null && eventId.trim().isNotEmpty) {
      try {
        final eventDoc =
            await _firestore.collection('events').doc(eventId).get();
        final eventData = eventDoc.data() ?? const <String, dynamic>{};
        eventBannerUrl =
            (eventData['bannerUrl'] ?? eventData['bannerImagePath'] ?? '')
                .toString();
      } catch (e, stack) {
        eventBannerUrl = '';
        debugPrint('Event banner lookup failed for chat notification: $e');
        debugPrintStack(stackTrace: stack);
      }
    }

    await _notificationService.sendWithRetry(
      () => _notificationService.sendNotification(
        userId: receiverId,
        type: type,
        senderId: _currentUid,
        senderName:
            (meData['name'] ?? meData['username'] ?? 'Someone').toString(),
        senderAvatar: (meData['avatarUrl'] ??
                meData['avatar_url'] ??
                meData['avatarEmoji'] ??
                '')
            .toString(),
        eventId: eventId,
        message: message,
        title: message,
        body: message,
        chatId: chatId,
        dedupeKey: key,
        dedupeWindow: dedupeWindow,
        eventBannerUrl: eventBannerUrl,
      ),
      userId: receiverId,
      type: type,
      senderId: _currentUid,
      metadata: <String, dynamic>{
        if (eventId != null) 'eventId': eventId,
        if (chatId != null) 'chatId': chatId,
        'dedupeKey': key,
      },
    );
  }

  @override
  Stream<List<ChatConversation>> watchDirectMessages() {
    if (_currentUid == 'unknown_user') return Stream.value([]);

    assert(() {
      debugPrint('CHAT QUERY READ: watchDirectMessages uid=$_currentUid');
      return true;
    }());
    // Per-subscription peer-user cache. Every chat-doc snapshot (typing,
    // lastMessage, unreadCount) previously re-fetched every peer's
    // `users/{uid}` doc — an N+1 storm that fired on every keystroke.
    // Cache keyed by uid; entries refreshed every 60 s.
    final userCache = <String, _CachedUserDoc>{};
    return _firestore
        .collection('chats')
        .where('participantIds', arrayContains: _currentUid)
        .where('type', isEqualTo: 'dm')
        .snapshots(
          includeMetadataChanges: false,
        )
        .asyncMap((snapshot) async {
      try {
        assert(() {
          debugPrint(
              'CHAT QUERY READ: watchDirectMessages received ${snapshot.docs.length} docs');
          return true;
        }());
        if (snapshot.docs.isEmpty) return [];

        List<ChatConversation> chats = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (_containsUid(data['deletedFor'], _currentUid)) continue;

          final List participants = data['participantIds'] ?? [];
          final otherUserId = participants.firstWhere((id) => id != _currentUid,
              orElse: () => null);

          if (otherUserId == null) continue;

          final isPinned = _containsUid(data['pinnedBy'], _currentUid);
          final isMuted = _containsUid(data['mutedBy'], _currentUid);

          // Fetch other user data (cached for 60 s to absorb typing storms).
          final otherUid = otherUserId.toString();
          final cached = userCache[otherUid];
          Map<String, dynamic> userData;
          if (cached != null &&
              DateTime.now().difference(cached.at).inSeconds < 60) {
            userData = cached.data;
          } else {
            // Check persistent Hive cache first so cold-start renders
            // immediately with the correct avatar/name, without waiting
            // for a Firestore round-trip.
            final hiveData = ChatPeerCache.load(otherUid);
            if (hiveData != null) {
              userData = hiveData;
              // Mark in-memory cache with epoch-0 so the NEXT snapshot
              // emission (60 s later) triggers a fresh Firestore fetch.
              userCache[otherUid] = _CachedUserDoc(
                  hiveData, DateTime.fromMillisecondsSinceEpoch(0));
              // Background refresh so the Hive entry stays up to date.
              _firestore.collection('users').doc(otherUid).get().then((doc) {
                if (doc.exists) {
                  final fresh = doc.data() ?? <String, dynamic>{};
                  userCache[otherUid] = _CachedUserDoc(fresh, DateTime.now());
                  ChatPeerCache.save(otherUid, fresh);
                }
              }).catchError((_) {});
            } else {
              final userDoc =
                  await _firestore.collection('users').doc(otherUid).get();
              userData = userDoc.data() ?? <String, dynamic>{};
              userCache[otherUid] = _CachedUserDoc(userData, DateTime.now());
              ChatPeerCache.save(otherUid, userData);
            }
          }

          final unreadCountRaw = data['unreadCount']?[_currentUid];
          final unreadCount = unreadCountRaw is int
              ? unreadCountRaw
              : int.tryParse('$unreadCountRaw') ?? 0;

          chats.add(ChatConversation(
            id: doc.id,
            name: userData['name'] ?? userData['username'] ?? 'User',
            avatarEmoji: userData['avatarEmoji'] ?? '💬',
            avatarUrl: _extractAvatarUrl(userData),
            lastMessage: data['lastMessage'] ?? '',
            lastMessageSenderId:
                (data['lastMessageSenderId'] ?? data['senderId'] ?? '')
                    .toString(),
            lastMessageSenderName:
                (data['lastMessageSenderName'] ?? '').toString(),
            updatedAt: (data['lastMessageAt'] as Timestamp?)?.toDate() ??
                (data['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.now(),
            unreadCount: isMuted ? 0 : unreadCount,
            isActiveNow: userData['isOnline'] ?? false,
            isTyping: _isUserTyping(data, otherUserId.toString()),
            isPinned: isPinned,
            isMuted: isMuted,
            isDeleted: false,
            otherUserId: otherUid,
          ));
        }
        chats.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        return chats;
      } catch (e) {
        debugPrint('CHAT QUERY READ: watchDirectMessages processing error: $e');
        return [];
      }
    }).transform(StreamTransformer.fromHandlers(
      handleError: (error, stack, sink) {
        debugPrint(
            'CHAT QUERY PERMISSION FAILURE: watchDirectMessages error=$error');
        debugPrint('$stack');
        sink.add([]);
      },
    ));
  }

  @override
  Stream<List<ChatGroup>> watchGroups() async* {
    if (_currentUid == 'unknown_user') {
      yield const <ChatGroup>[];
      return;
    }

    // Warm-replay: synchronously emit the previous group list (if any) so
    // the Groups tab paints immediately on reopen while the Firestore
    // listener re-establishes in the background. Mirrors the message
    // warm-replay pattern (`_lastRemoteMessagesByChat`).
    final cachedSeed = _lastGroupsByUid[_currentUid];
    if (cachedSeed != null) {
      yield cachedSeed;
    }

    yield* _watchGroupsLive();
  }

  Stream<List<ChatGroup>> _watchGroupsLive() {
    assert(() {
      debugPrint('CHAT QUERY READ: watchGroups uid=$_currentUid');
      return true;
    }());
    // Per-subscription event-doc cache (60 s TTL). Prevents an N+1 event
    // re-fetch on every chat-doc change (typing, lastMessage, etc.).
    final eventCache = <String, _CachedEventDoc>{};
    return _firestore
        .collection('chats')
        .where('participantIds', arrayContains: _currentUid)
        .where('type', isEqualTo: 'group')
        .snapshots(
          includeMetadataChanges: false,
        )
        .asyncMap((snapshot) async {
      try {
        assert(() {
          debugPrint(
              'CHAT QUERY READ: watchGroups received ${snapshot.docs.length} docs');
          return true;
        }());
        if (snapshot.docs.isEmpty) {
          _lastGroupsByUid[_currentUid] = const <ChatGroup>[];
          return const <ChatGroup>[];
        }

        // Visible chat docs (drop docs the user has deleted-for-self).
        final visibleDocs = snapshot.docs.where((doc) {
          final data = doc.data();
          return !_containsUid(data['deletedFor'], _currentUid);
        }).toList(growable: false);

        // Parallelize event-doc fetches.
        //
        // Previously this loop awaited each `events/{eventId}.get()`
        // sequentially before the next iteration. With N event groups
        // that was N serial round-trips before the first emission —
        // typically 800–1500 ms cold, which is the dominant cause of
        // the Groups-tab 3-4 s spinner.
        //
        // Parallel `Future.wait` collapses that to ~one round-trip
        // regardless of N. The per-subscription `eventCache` still
        // dedupes repeated fetches for the same eventId within the
        // 60 s TTL on subsequent snapshot emissions.
        final fetchFutures =
            <Future<MapEntry<String, Map<String, dynamic>?>>>[];
        final fetchedIds = <String>{};
        for (final doc in visibleDocs) {
          final eventId = (doc.data()['eventId'] ?? '').toString();
          if (eventId.isEmpty) continue;
          final cached = eventCache[eventId];
          if (cached != null &&
              DateTime.now().difference(cached.at).inSeconds < 60) {
            continue;
          }
          if (!fetchedIds.add(eventId)) continue;
          fetchFutures.add(_firestore
              .collection('events')
              .doc(eventId)
              .get()
              .then<MapEntry<String, Map<String, dynamic>?>>(
                (snap) => MapEntry(eventId, snap.data()),
              )
              .catchError((Object e) {
            if (e is FirebaseException) {
              debugPrint(
                'CHAT QUERY READ: event doc fetch failed for eventId=$eventId '
                'code=${e.code} — falling back to chat-doc fields',
              );
            } else {
              debugPrint(
                'CHAT QUERY READ: event doc fetch failed for eventId=$eventId '
                'error=$e — falling back to chat-doc fields',
              );
            }
            return MapEntry<String, Map<String, dynamic>?>(eventId, null);
          }));
        }

        if (fetchFutures.isNotEmpty) {
          final results = await Future.wait(fetchFutures);
          final now = DateTime.now();
          for (final entry in results) {
            eventCache[entry.key] = _CachedEventDoc(entry.value, now);
          }
        }

        final groups = <ChatGroup>[];
        for (final doc in visibleDocs) {
          final data = doc.data();
          final eventId = data['eventId'];
          final eventIdStr = (eventId ?? '').toString();
          final isPinned = _containsUid(data['pinnedBy'], _currentUid);
          final isMuted = _containsUid(data['mutedBy'], _currentUid);

          String eventName = data['name'] ?? 'Group Chat';
          List<String> emojis = [];
          DateTime? endsAt;
          String hostId = (data['hostId'] ?? '').toString();
          var isActive = data['isActive'] != false;
          String bannerUrl =
              (data['eventBannerUrl'] ?? data['bannerUrl'] ?? '').toString();
          String eventAvatar =
              _normalizeEventAvatar(data['eventAvatar'] ?? data['avatarEmoji']);

          if (eventIdStr.isNotEmpty) {
            final cached = eventCache[eventIdStr];
            final eventData = cached?.data;
            if (eventData != null) {
              hostId = (eventData['hostId'] ?? eventData['host_id'] ?? hostId)
                  .toString();
              isActive = isActive && (eventData['isActive'] != false);
              final eventStatus =
                  (eventData['status'] ?? 'active').toString().toLowerCase();
              if (eventStatus != 'active') {
                isActive = false;
              }
              final rawEndAt = eventData['endAt'];
              final endAt = rawEndAt is Timestamp
                  ? rawEndAt.toDate()
                  : (rawEndAt is DateTime ? rawEndAt : null);
              if (endAt != null &&
                  endAt.toUtc().isBefore(DateTime.now().toUtc())) {
                isActive = false;
              }
              eventName = eventData['title'] ?? eventData['label'] ?? eventName;
              bannerUrl = (eventData['bannerUrl'] ??
                      eventData['bannerImageUrl'] ??
                      eventData['coverImageUrl'] ??
                      eventData['imageUrl'] ??
                      '')
                  .toString();
              endsAt = _toDateTime(eventData['endsAt'] ??
                  eventData['endAt'] ??
                  eventData['endTime'] ??
                  eventData['eventEndsAt']);
              eventAvatar = _normalizeEventAvatar(
                eventData['eventAvatar'] ??
                    eventData['hostAvatarEmoji'] ??
                    eventData['avatarEmoji'],
              );
              if (eventData['hostAvatarEmoji'] != null) {
                emojis.add(eventData['hostAvatarEmoji']);
              }
            }
          }

          groups.add(ChatGroup(
            id: doc.id,
            name: eventName,
            eventId: eventIdStr,
            hostId: hostId,
            bannerUrl: bannerUrl,
            eventBannerUrl: bannerUrl,
            eventAvatar: eventAvatar,
            lastMessage: data['lastMessage'] ?? '',
            lastMessageSenderId:
                (data['lastMessageSenderId'] ?? data['senderId'] ?? '')
                    .toString(),
            lastMessageSenderName:
                (data['lastMessageSenderName'] ?? '').toString(),
            memberCount: (data['participantIds'] as List?)?.length ?? 0,
            isEventGroup: eventIdStr.trim().isNotEmpty,
            isActive: isActive,
            isPinned: isPinned,
            isMuted: isMuted,
            isDeleted: false,
            updatedAt: (data['lastMessageAt'] as Timestamp?)?.toDate() ??
                (data['updatedAt'] as Timestamp?)?.toDate() ??
                DateTime.now(),
            avatarEmojis: emojis.isEmpty ? ['🏟'] : emojis,
            eventEndsAt: endsAt,
          ));
        }
        groups.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        // Warm-replay cache write — next subscription paints instantly.
        _lastGroupsByUid[_currentUid] = List<ChatGroup>.unmodifiable(groups);
        return groups;
      } catch (e) {
        debugPrint('CHAT QUERY READ: watchGroups processing error: $e');
        return [];
      }
    }).transform(StreamTransformer.fromHandlers(
      handleError: (error, stack, sink) {
        debugPrint('CHAT QUERY PERMISSION FAILURE: watchGroups error=$error');
        debugPrint('$stack');
        sink.add([]);
      },
    ));
  }

  @override
  Stream<List<ActivityItem>> watchActivity() {
    return Stream.value([]);
  }

  // --- DISCOVER PEOPLE LOGIC ---
  @override
  Stream<List<DiscoverPerson>> watchDiscoverPeople() async* {
    if (_currentUid == 'unknown_user') {
      yield [];
      return;
    }

    final now = DateTime.now();
    if (_discoverCacheAt != null &&
        now.difference(_discoverCacheAt!) < _discoverCacheTtl &&
        _discoverCache.isNotEmpty) {
      yield _reshuffleDiscover(_discoverCache);
    }

    try {
      final fresh = await _computeDiscoverPeople();
      _discoverCache = fresh;
      _discoverCacheAt = DateTime.now();
      yield _reshuffleDiscover(fresh);
    } catch (_) {
      if (_discoverCache.isNotEmpty) {
        yield _reshuffleDiscover(_discoverCache);
      } else {
        yield [];
      }
    }

    // No realtime discover listener.
// Manual refresh + cache only.
  }

  List<DiscoverPerson> _reshuffleDiscover(List<DiscoverPerson> input) {
    if (input.length <= 1) return List<DiscoverPerson>.unmodifiable(input);
    final shuffled = List<DiscoverPerson>.from(input);
    shuffled.shuffle(math.Random(DateTime.now().microsecondsSinceEpoch));
    return List<DiscoverPerson>.unmodifiable(shuffled);
  }

  Future<List<DiscoverPerson>> _computeDiscoverPeople() async {
    final meDoc = await _firestore.collection('users').doc(_currentUid).get();
    final meData = meDoc.data() ?? {};

    final myLocation = _parseLocation(meData['location']);
    final myJoinedEvents =
        Set<String>.from(meData['joinedEvents'] ?? const <String>[]);

    // Vibe matching — core of Feature 13.
    final myVibes = Set<String>.from(
      (meData['vibes'] as List<dynamic>? ?? [])
          .map((v) => v.toString().toLowerCase()),
    );

    final blockedByMe = Set<String>.from(
      meData['blockedUsers'] ?? meData['blockedList'] ?? const <String>[],
    );

    Set<String> myFriendIds;
    try {
      myFriendIds = await _fetchFriendIds();
    } catch (_) {
      myFriendIds = <String>{};
    }
    // friends/{uid}/list is the canonical source — do not merge stale user-doc array.
    final myFriendAvatarMap = await _fetchUserAvatarMap(myFriendIds);

    Set<String> activeRequestPeerIds;
    try {
      activeRequestPeerIds = await _fetchActiveFriendRequestPeerIds();
    } catch (_) {
      activeRequestPeerIds = <String>{};
    }

    final usersSnapshot = await _firestore.collection('users').limit(80).get();
    final scored = <_ScoredDiscover>[];
    final includedIds = <String>{};

    for (final doc in usersSnapshot.docs) {
      final userId = doc.id;
      final data = doc.data();

      if (userId == _currentUid) continue;
      if (!_isProfileVisible(data)) continue;
      if (myFriendIds.contains(userId)) continue;
      if (activeRequestPeerIds.contains(userId)) continue;
      if (blockedByMe.contains(userId)) continue;

      final blockedByThem = Set<String>.from(
        data['blockedUsers'] ?? data['blockedList'] ?? const <String>[],
      );
      if (blockedByThem.contains(_currentUid)) continue;

      final theirLocation = _parseLocation(data['location']);
      final distanceKm = myLocation != null && theirLocation != null
          ? _haversineKm(myLocation, theirLocation)
          : null;

      final theirFriends =
          Set<String>.from(data['friendsList'] ?? const <String>[]);
      final mutualFriendIds = myFriendIds.intersection(theirFriends);
      final mutualFriends = myFriendIds.intersection(theirFriends).length;
      final mutualFriendAvatarUrls = mutualFriendIds
          .map((id) => myFriendAvatarMap[id] ?? '')
          .where((url) => url.trim().isNotEmpty)
          .take(3)
          .toList();

      final theirJoinedEvents =
          Set<String>.from(data['joinedEvents'] ?? const <String>[]);
      final sameEvents = myJoinedEvents.intersection(theirJoinedEvents).length;

      final recentlyActive = _isRecentlyActive(data);
      final nearby = distanceKm != null && distanceKm <= _nearbyThresholdKm;

      const relationStatus = FriendRelationStatus.add;

      // Vibe matching (Feature 13 core signal).
      final theirVibes = Set<String>.from(
        (data['vibes'] as List<dynamic>? ?? [])
            .map((v) => v.toString().toLowerCase()),
      );
      final commonVibeSet = myVibes.intersection(theirVibes);
      final commonVibes = commonVibeSet.toList();
      // Cap vibe bonus at 3 matches (105pts max) so a power-user doesn't crowd out everyone.
      final vibeBonus = commonVibeSet.length.clamp(0, 3) * 35;

      var score = 0;

      score += vibeBonus; // 0–105: shared interests

      if (mutualFriends > 0) {
        score += 50;
      }

      if (sameEvents > 0) {
        score += 40;
      }

      if (nearby) {
        score += 30;
      }

      if (recentlyActive) {
        score += 20;
      } else {
        score += 10;
      }

      final detailParts = <String>[];

      if (commonVibes.isNotEmpty) {
        // Show up to 2 common vibes in the detail line.
        final vibeDisplay = commonVibes.take(2).map((v) {
          final capitalized =
              v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);
          return capitalized;
        }).join(' · ');
        detailParts.add('Into $vibeDisplay');
      }
      if (mutualFriends > 0) {
        detailParts.add(
            '$mutualFriends mutual friend${mutualFriends == 1 ? '' : 's'}');
      }
      if (sameEvents > 0) {
        detailParts.add(
            'Seen at $sameEvents shared event${sameEvents == 1 ? '' : 's'}');
      }
      if (distanceKm != null) {
        detailParts.add(distanceKm < 1
            ? '${(distanceKm * 1000).round()}m away'
            : '${distanceKm.toStringAsFixed(1)}km away');
      }

      final detail =
          detailParts.isEmpty ? 'Suggested for you' : detailParts.join(' • ');

      // Label priority: Vibe Match > Mutual Friends > Same Event > Nearby > Suggested
      final suggestionLabel = commonVibes.isNotEmpty
          ? 'Vibe Match'
          : mutualFriends > 0
              ? 'Mutual Friends'
              : sameEvents > 0
                  ? 'Same Events'
                  : nearby
                      ? 'Nearby you'
                      : 'Suggested';

      scored.add(
        _ScoredDiscover(
          score: score,
          person: DiscoverPerson(
            id: userId,
            name: _extractDisplayName(data),
            username: _extractUsername(data),
            avatarEmoji: (data['avatarEmoji'] ?? '👤').toString(),
            avatarUrl: _extractAvatarUrl(data),
            detail: detail,
            suggestionLabel: suggestionLabel,
            isNearby: nearby,
            mutualFriendAvatarUrls: mutualFriendAvatarUrls,
            seenAtSameEvent: sameEvents > 0,
            mutualFriendsCount: mutualFriends,
            commonVibes: commonVibes,
            distanceKm: distanceKm,
            relationStatus: relationStatus,
          ),
        ),
      );
      includedIds.add(userId);
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.person.name.compareTo(b.person.name);
    });

    final top = scored.take(20).map((e) => e.person).toList();
    if (top.length >= 20) return top;

    return _fillDiscoverFallback(
      base: top,
      alreadyIncludedIds: includedIds,
      blockedByMe: blockedByMe,
      myFriendIds: myFriendIds,
      activeRequestPeerIds: activeRequestPeerIds,
    );
  }

  Future<List<DiscoverPerson>> _fillDiscoverFallback({
    required List<DiscoverPerson> base,
    required Set<String> alreadyIncludedIds,
    required Set<String> blockedByMe,
    required Set<String> myFriendIds,
    required Set<String> activeRequestPeerIds,
  }) async {
    if (base.length >= 20) return base;

    final fallbackSnapshot =
        await _firestore.collection('users').limit(120).get();
    final candidates = fallbackSnapshot.docs.toList()..shuffle(math.Random());
    final filled = <DiscoverPerson>[...base];

    for (final doc in candidates) {
      if (filled.length >= 20) break;

      final userId = doc.id;
      final data = doc.data();

      if (userId == _currentUid) continue;
      if (!_isProfileVisible(data)) continue;
      if (myFriendIds.contains(userId)) continue;
      if (activeRequestPeerIds.contains(userId)) continue;
      if (blockedByMe.contains(userId)) continue;
      if (alreadyIncludedIds.contains(userId)) continue;

      final blockedByThem = Set<String>.from(
        data['blockedUsers'] ?? data['blockedList'] ?? const <String>[],
      );
      if (blockedByThem.contains(_currentUid)) continue;

      filled.add(
        DiscoverPerson(
          id: userId,
          name: _extractDisplayName(data),
          username: _extractUsername(data),
          avatarEmoji: (data['avatarEmoji'] ?? '👤').toString(),
          avatarUrl: _extractAvatarUrl(data),
          detail: 'Suggested for you',
          suggestionLabel: 'Suggested',
          relationStatus: FriendRelationStatus.add,
        ),
      );
      alreadyIncludedIds.add(userId);
    }

    // Last-resort tier: if we still have fewer than 5 cards, relax visibility
    // filter to include users who may not have completed their profile yet.
    // This guarantees the page is never empty even in very small user bases.
    if (filled.length < 5) {
      try {
        final lastResortSnap =
            await _firestore.collection('users').limit(200).get();
        for (final doc in lastResortSnap.docs) {
          if (filled.length >= 8) break;
          final userId = doc.id;
          final data = doc.data();
          if (userId == _currentUid) continue;
          if (myFriendIds.contains(userId)) continue;
          if (blockedByMe.contains(userId)) continue;
          if (alreadyIncludedIds.contains(userId)) continue;
          final blockedByThem = Set<String>.from(
            data['blockedUsers'] ?? data['blockedList'] ?? const <String>[],
          );
          if (blockedByThem.contains(_currentUid)) continue;

          final name = _extractDisplayName(data);
          if (name.trim().isEmpty) continue; // skip completely empty accounts

          filled.add(
            DiscoverPerson(
              id: userId,
              name: name,
              username: _extractUsername(data),
              avatarEmoji: (data['avatarEmoji'] ?? '👤').toString(),
              avatarUrl: _extractAvatarUrl(data),
              detail: 'New to Yanegi',
              suggestionLabel: 'New',
              relationStatus: FriendRelationStatus.add,
            ),
          );
          alreadyIncludedIds.add(userId);
        }
      } catch (_) {}
    }

    return filled;
  }

  bool _isRecentlyActive(Map<String, dynamic> data) {
    final lastActive = _toDateTime(
      data['lastActiveAt'] ??
          data['lastSeenAt'] ??
          data['updatedAt'] ??
          data['lastLoginAt'],
    );
    if (lastActive == null) return false;
    return DateTime.now().difference(lastActive).inHours <= 72;
  }

  Future<Map<String, String>> _fetchUserAvatarMap(Set<String> userIds) async {
    final ids = userIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) return const <String, String>{};

    final avatarMap = <String, String>{};
    const chunkSize = 10;

    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = math.min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      final snapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final avatarUrl = _extractAvatarUrl(data);
        if (avatarUrl.isNotEmpty) {
          avatarMap[doc.id] = avatarUrl;
        }
      }
    }

    return avatarMap;
  }

  Future<Set<String>> _fetchFriendIds() async {
    final snap = await _firestore
        .collection('friends')
        .doc(_currentUid)
        .collection('list')
        .get();
    return snap.docs
        .map((doc) => doc.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  Future<Set<String>> _fetchActiveFriendRequestPeerIds() async {
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> queryByStatuses({
      required String field,
    }) async {
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final status in const ['pending', 'active']) {
        final snap = await _firestore
            .collection('friend_requests')
            .where(field, isEqualTo: _currentUid)
            .where('status', isEqualTo: status)
            .get();
        docs.addAll(snap.docs);
      }
      return docs;
    }

    final fromDocs = await queryByStatuses(field: 'fromUser');
    final toDocs = await queryByStatuses(field: 'toUser');
    final senderDocs = await queryByStatuses(field: 'senderId');
    final receiverDocs = await queryByStatuses(field: 'receiverId');

    final peerIds = <String>{
      ...fromDocs.map((d) => (d.data()['toUser'] ?? '').toString()),
      ...toDocs.map((d) => (d.data()['fromUser'] ?? '').toString()),
      ...senderDocs.map((d) => (d.data()['receiverId'] ?? '').toString()),
      ...receiverDocs.map((d) => (d.data()['senderId'] ?? '').toString()),
    };

    peerIds.removeWhere((id) => id.trim().isEmpty || id == _currentUid);
    return peerIds;
  }

  LatLng? _parseLocation(dynamic raw) {
    if (raw is GeoPoint) {
      return LatLng(raw.latitude, raw.longitude);
    }
    if (raw is Map) {
      final lat = (raw['lat'] ?? raw['latitude']) as num?;
      final lng = (raw['lng'] ?? raw['longitude']) as num?;
      if (lat != null && lng != null) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  DateTime? _toDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  double _haversineKm(LatLng from, LatLng to) {
    final dLat = _degToRad(to.latitude - from.latitude);
    final dLon = _degToRad(to.longitude - from.longitude);
    final lat1 = _degToRad(from.latitude);
    final lat2 = _degToRad(to.latitude);

    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        (math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return 6371.0 * c;
  }

  double _degToRad(double value) => value * 0.017453292519943295;

  /// Per-chat throttle for `prewarmCursor`. 30 s window so rapid back-and-tap
  /// flows don't re-fetch the same doc; the Firestore SDK cache holds the
  /// doc fresh longer than that anyway.
  final Map<String, DateTime> _cursorPrewarmAt = <String, DateTime>{};
  static const Duration _cursorPrewarmTtl = Duration(seconds: 30);

  @override
  void prewarmCursor(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return;
    if (_currentUid == 'unknown_user') return;
    final last = _cursorPrewarmAt[id];
    if (last != null && DateTime.now().difference(last) < _cursorPrewarmTtl) {
      return;
    }
    _cursorPrewarmAt[id] = DateTime.now();
    // Fire-and-forget. A failure is harmless — the thread's `.snapshots()`
    // will fall back to a network read on first emission; we just clear the
    // throttle so a future tap can retry the prewarm.
    unawaited(() async {
      try {
        await _firestore
            .collection('chat_meta')
            .doc(id)
            .collection('members')
            .doc(_currentUid)
            .get();
      } catch (_) {
        _cursorPrewarmAt.remove(id);
      }
    }());
  }

  @override
  List<ChatMessage> lastKnownMessages(String chatId) {
    // Snapshot of the warm-replay cache. Returned as an unmodifiable list so
    // accidental consumer mutation can't corrupt the next subscriber's seed.
    final cached = _lastRemoteMessagesByChat[chatId];
    if (cached == null || cached.isEmpty) return const <ChatMessage>[];
    return List<ChatMessage>.unmodifiable(
        _mergeRemoteAndOutbox(chatId, cached));
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId) {
    if (chatId.trim().isEmpty) return Stream.value([]);
    if (_messageStreams.containsKey(chatId)) {
      return _messageStreams[chatId]!;
    }

    unawaited(_hydrateOutboxForChat(chatId));

    final remoteStream = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(40)
        .snapshots(
          includeMetadataChanges: false,
        );

    final stream = Stream<List<ChatMessage>>.multi((controller) {
      // Seed from the last-known tail so the very first emission on a
      // reopen contains real messages instead of an empty list. This is
      // what makes a second open feel instant (Instagram-style) instead
      // of flashing an empty state while Firestore re-listens.
      List<ChatMessage> remoteMessages =
          _lastRemoteMessagesByChat[chatId] ?? const <ChatMessage>[];

      void emit() {
        _lastRemoteMessagesByChat[chatId] = remoteMessages;
        controller.add(_mergeRemoteAndOutbox(chatId, remoteMessages));
      }

      final remoteSub = remoteStream.listen((snapshot) {
        remoteMessages = snapshot.docs.map((doc) {
          final data = doc.data();
          final senderId = (data['senderId'] ?? '').toString();
          final senderNameRaw = (data['senderName'] ?? '').toString();
          final resolvedSenderName =
              senderId == _currentUid ? 'You' : senderNameRaw.trim();
          final clientMessageId =
              (data['clientMessageId'] ?? data['messageId'] ?? doc.id)
                  .toString()
                  .trim();
          final rawReplyId = (data['replyToMessageId'] ?? '').toString().trim();
          return ChatMessage(
            id: doc.id,
            chatId: chatId,
            clientMessageId: clientMessageId,
            senderId: senderId,
            senderName: resolvedSenderName,
            senderAvatar: (data['senderAvatar'] ?? '').toString(),
            text: (data['text'] ?? '').toString(),
            sentAt:
                (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            isRead: senderId == _currentUid,
            status: MessageStatus.sent,
            retryCount: 0,
            replyToMessageId: rawReplyId.isEmpty ? null : rawReplyId,
            replyToPreviewText: (data['replyToPreviewText'] ?? '').toString(),
            replyToSenderName: (data['replyToSenderName'] ?? '').toString(),
            reactions: ChatMessage.parseReactions(data['reactions']),
            isDeleted: data['isDeleted'] == true,
            isEdited: data['isEdited'] == true,
            editedAt: data['editedAt'] is Timestamp
                ? (data['editedAt'] as Timestamp).toDate()
                : null,
            type: (data['type'] ?? 'text').toString(),
            poll: data['poll'] is Map
                ? PollData.fromMap(
                    Map<String, dynamic>.from(data['poll'] as Map))
                : null,
            metadata: data['metadata'] is Map
                ? Map<String, dynamic>.from(data['metadata'] as Map)
                : const {},
          );
        }).toList();

        emit();
      }, onError: controller.addError);

      final outboxSub = _outboxSignalController(chatId).stream.listen((_) {
        emit();
      }, onError: controller.addError);

      emit();

      controller.onCancel = () async {
        await remoteSub.cancel();
        await outboxSub.cancel();
      };
    });

    final broadcastStream = stream.asBroadcastStream();

    _messageStreams[chatId] = broadcastStream;

    return broadcastStream;
  }

  @override
  Future<bool> sendMessage({
    required String chatId,
    required String text,
    String? clientMessageId,
    String? replyToMessageId,
    String? replyToPreviewText,
    String? replyToSenderName,
  }) async {
    if (chatId.trim().isEmpty) {
      throw ArgumentError('chatId cannot be empty');
    }

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      throw ArgumentError('message text cannot be empty');
    }

    if (_currentUid == 'unknown_user') {
      throw StateError('User not authenticated');
    }

    final resolvedClientMessageId =
        (clientMessageId ?? _newClientMessageId()).trim();
    if (resolvedClientMessageId.isEmpty) {
      throw StateError('clientMessageId cannot be empty');
    }

    // Strict lifecycle gate before enqueue: never pollute outbox for ended chats.
    // Both docs are kept warm in the Firestore SDK's local cache by the active
    // listeners in ChatThreadScreen (_chatDocStream / _eventStream), so reading
    // from cache is instant (~0 ms) and avoids 500–1500 ms network round-trips.
    // Falls back to network automatically if the cache is cold (e.g. first open).
    try {
      final chatRef = _firestore.collection('chats').doc(chatId);
      DocumentSnapshot<Map<String, dynamic>> chatDoc;
      try {
        chatDoc = await chatRef.get(const GetOptions(source: Source.cache));
      } on FirebaseException {
        chatDoc = await chatRef.get();
      }
      if (!chatDoc.exists) return false;

      final chatData = chatDoc.data() ?? const <String, dynamic>{};
      final isChatActive = chatData['isActive'] != false;
      if (!isChatActive) return false;

      final participants =
          List<String>.from(chatData['participantIds'] ?? const <String>[]);
      if (!participants.contains(_currentUid)) return false;

      final eventId = (chatData['eventId'] ?? '').toString().trim();
      if (eventId.isNotEmpty) {
        final eventRef = _firestore.collection('events').doc(eventId);
        DocumentSnapshot<Map<String, dynamic>> eventDoc;
        try {
          eventDoc = await eventRef.get(const GetOptions(source: Source.cache));
        } on FirebaseException {
          eventDoc = await eventRef.get();
        }
        if (!eventDoc.exists) return false;

        final eventData = eventDoc.data() ?? const <String, dynamic>{};
        final status =
            (eventData['status'] ?? 'active').toString().toLowerCase();
        final isEventActive = status == EventService.statusActive;

        final rawEndAt = eventData['endAt'];
        final endAt = rawEndAt is Timestamp
            ? rawEndAt.toDate()
            : (rawEndAt is DateTime ? rawEndAt : null);
        final endedByTime =
            endAt != null && !DateTime.now().toUtc().isBefore(endAt.toUtc());

        if (!isEventActive || endedByTime) {
          return false;
        }
      }
    } catch (_) {
      // If lifecycle cannot be verified, do not enqueue.
      return false;
    }

    await _hydrateOutboxForChat(chatId);

    final outbox = _outboxForChat(chatId);
    final existingLocal = outbox[resolvedClientMessageId];
    if (existingLocal != null) {
      existingLocal.nextAttemptAt = DateTime.now();
      existingLocal.lastUpdatedAt = DateTime.now();
      _ensureOutboxPump();
      _emitOutboxSignal(chatId);
      unawaited(_attemptOutboxSend(existingLocal));
      return true;
    }

    // Resolve senderName from the user's Yanegi profile (users/{uid}.name).
    // Never fall back to FirebaseAuth.displayName — that would broadcast the
    // user's Google account name into group chat message metadata.
    final senderName = await _resolveSelfDisplayName();
    final now = DateTime.now();

    final outboxItem = _OutboxMessage(
      chatId: chatId,
      clientMessageId: resolvedClientMessageId,
      text: trimmedText,
      senderId: _currentUid,
      senderName: senderName,
      eventId: null,
      participantIds: const <String>[],
      status: MessageStatus.sending,
      retryCount: 0,
      createdAt: now,
      lastUpdatedAt: now,
      nextAttemptAt: now,
      replyToMessageId: replyToMessageId,
      replyToPreviewText: replyToPreviewText ?? '',
      replyToSenderName: replyToSenderName ?? '',
    );

    // Local-first: persist to durable outbox before any network path.
    outbox[resolvedClientMessageId] = outboxItem;
    await _persistOutboxForChat(chatId);
    _ensureOutboxPump();
    _emitOutboxSignal(chatId);

    // Non-blocking network attempt.
    unawaited(_attemptOutboxSend(outboxItem));
    return true;
  }

  Future<void> _attemptOutboxSend(_OutboxMessage item) async {
    if (item.inFlight) return;
    if (_currentUid == 'unknown_user') return;
    if (DateTime.now().isBefore(item.nextAttemptAt)) return;

    item.inFlight = true;
    item.status = MessageStatus.sending;
    item.failureReason = '';
    item.lastUpdatedAt = DateTime.now();
    _emitOutboxSignal(item.chatId);

    try {
      final chatRef = _firestore.collection('chats').doc(item.chatId);
      DocumentSnapshot<Map<String, dynamic>> chatDoc;
      try {
        chatDoc = await chatRef.get(const GetOptions(source: Source.cache));
      } on FirebaseException {
        chatDoc = await chatRef.get();
      }
      if (!chatDoc.exists) {
        throw StateError('Chat not found');
      }

      final chatData = chatDoc.data() ?? const <String, dynamic>{};
      final participants =
          List<String>.from(chatData['participantIds'] ?? const <String>[]);
      if (!participants.contains(_currentUid)) {
        throw StateError('Only participants can send messages');
      }
      if ((chatData['type'] ?? '').toString() == 'dm') {
        for (final participantId in participants) {
          if (participantId == _currentUid) continue;
          if (await _isBlockedEitherWay(_currentUid, participantId)) {
            throw StateError('Message blocked by relationship settings');
          }
        }
      }

      final remoteMessage = await _findRemoteMessageByClientMessageId(
        chatId: item.chatId,
        clientMessageId: item.clientMessageId,
      );
      if (remoteMessage != null) {
        final outbox = _outboxByChat[item.chatId];
        outbox?.remove(item.clientMessageId);
        await _persistOutboxForChat(item.chatId);
        _emitOutboxSignal(item.chatId);
        return;
      }

      final msgRef = chatRef.collection('messages').doc(item.clientMessageId);
      final batch = _firestore.batch();
      batch.set(msgRef, {
        'messageId': item.clientMessageId,
        'chatId': item.chatId,
        'senderId': item.senderId,
        'senderName': item.senderName,
        'text': item.text,
        'clientMessageId': item.clientMessageId,
        'createdAt': FieldValue.serverTimestamp(),
        if (item.replyToMessageId != null) ...{
          'replyToMessageId': item.replyToMessageId,
          'replyToPreviewText': item.replyToPreviewText,
          'replyToSenderName': item.replyToSenderName,
        },
      });

      final unreadUpdates = <String, dynamic>{
        'unreadCount.${item.senderId}': 0,
      };
      for (final participantId in participants) {
        if (participantId == item.senderId) continue;
        unreadUpdates['unreadCount.$participantId'] = FieldValue.increment(1);
      }

      batch.update(chatRef, {
        'lastMessage': item.text,
        'lastMessageSenderId': item.senderId,
        'lastMessageSenderName': item.senderName,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'typing.${item.senderId}': {
          'isTyping': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        ...unreadUpdates,
      });

      await _commitBatch(batch);

      final outbox = _outboxByChat[item.chatId];
      outbox?.remove(item.clientMessageId);
      await _persistOutboxForChat(item.chatId);
      _emitOutboxSignal(item.chatId);

      try {
        final clippedText = item.text.length > 80
            ? '${item.text.substring(0, 80)}…'
            : item.text;
        final mutedBy = _toStringList(chatData['mutedBy']);
        for (final participantId in participants) {
          if (participantId == item.senderId) continue;
          if (mutedBy.contains(participantId)) continue;
          await _createNotification(
            receiverId: participantId,
            type: NotificationType.chatMessage,
            message: (chatData['type'] ?? '') == 'group'
                ? 'sent a message in your group: "$clippedText"'
                : 'sent you a message: "$clippedText"',
            persistActivity: true,
            chatId: item.chatId,
            eventId: item.eventId,
            dedupeKey:
                'msg:${item.chatId}:$participantId:${item.clientMessageId}',
            dedupeWindow: const Duration(seconds: 30),
          );
        }
      } catch (e, stack) {
        // Non-critical; keep message sent.
        debugPrint('Message sent, but notification fan-out failed: $e');
        debugPrintStack(stackTrace: stack);
      }
    } catch (error) {
      final remoteMessage = await _findRemoteMessageByClientMessageId(
        chatId: item.chatId,
        clientMessageId: item.clientMessageId,
      );
      if (remoteMessage != null) {
        item.status = MessageStatus.sent;
        item.failureReason = '';
        item.lastUpdatedAt = DateTime.now();
        item.nextAttemptAt = DateTime.now();
      } else {
        final retryable = _isRetryableError(error);
        item.status = MessageStatus.failed;
        item.retryCount = item.retryCount + 1;
        item.failureReason = error.toString();
        item.lastUpdatedAt = DateTime.now();
        item.nextAttemptAt = retryable
            ? DateTime.now().add(_retryBackoff(item.retryCount))
            : DateTime.now().add(_retryBackoff(item.retryCount + 1));
      }
      unawaited(_persistOutboxForChat(item.chatId));
      _emitOutboxSignal(item.chatId);
    } finally {
      item.inFlight = false;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?>
      _findRemoteMessageByClientMessageId({
    required String chatId,
    required String clientMessageId,
  }) async {
    final direct = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(clientMessageId)
        .get();
    if (direct.exists) {
      return direct;
    }

    final query = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('clientMessageId', isEqualTo: clientMessageId)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return query.docs.first;
  }

  @override
  Future<bool> retryMessage({
    required String chatId,
    required String clientMessageId,
  }) async {
    await _hydrateOutboxForChat(chatId);
    final item = _outboxByChat[chatId]?[clientMessageId];
    if (item == null) return false;

    item.status = MessageStatus.sending;
    item.failureReason = '';
    item.nextAttemptAt = DateTime.now();
    item.lastUpdatedAt = DateTime.now();
    unawaited(_persistOutboxForChat(chatId));
    _emitOutboxSignal(chatId);
    await _attemptOutboxSend(item);
    return true;
  }

  @override
  Future<void> flushPendingMessages({String? chatId}) async {
    final now = DateTime.now();
    final forceImmediate = chatId != null;
    final targets = <_OutboxMessage>[];

    if (chatId != null) {
      final outbox = _outboxByChat[chatId];
      if (outbox != null) {
        targets.addAll(outbox.values.where((item) {
          return item.status != MessageStatus.sent &&
              !item.inFlight &&
              (forceImmediate || !now.isBefore(item.nextAttemptAt));
        }));
      }
    } else {
      for (final outbox in _outboxByChat.values) {
        targets.addAll(outbox.values.where((item) {
          return item.status != MessageStatus.sent &&
              !item.inFlight &&
              !now.isBefore(item.nextAttemptAt);
        }));
      }
    }

    for (final item in targets) {
      await _attemptOutboxSend(item);
    }
  }

  @override
  Future<void> setTyping(
      {required String chatId, required bool isTyping}) async {
    if (chatId.trim().isEmpty || _currentUid == 'unknown_user') return;
    // Single source of truth for typing is the chat doc's `typing` map.
    // The legacy `chats/{chatId}/typing/{uid}` subcollection is no longer
    // read anywhere — dropping that write halves typing-related writes.
    final chatRef = _firestore.collection('chats').doc(chatId);
    await chatRef.update({
      'typing.$_currentUid': {
        'isTyping': isTyping,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> markMessagesDelivered({
    required String chatId,
    required Iterable<String> messageIds,
  }) async {
    if (chatId.trim().isEmpty || _currentUid == 'unknown_user') return;
    await _touchDeliveryCursor(chatId: chatId, markSeen: false);
  }

  @override
  Future<void> markMessagesSeen({
    required String chatId,
    required Iterable<String> messageIds,
  }) async {
    if (chatId.trim().isEmpty || _currentUid == 'unknown_user') return;
    await _touchDeliveryCursor(chatId: chatId, markSeen: true);
  }

  @override
  Future<void> markChatRead({required String chatId}) async {
    if (chatId.trim().isEmpty || _currentUid == 'unknown_user') return;

    final chatRef = _firestore.collection('chats').doc(chatId);

    await chatRef.update({
      'unreadCount.$_currentUid': 0,
      'typing.$_currentUid': {
        'isTyping': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    });

    await _touchDeliveryCursor(chatId: chatId, markSeen: true);
  }

  @override
  Future<void> performDmAction(
      {required String chatId, required DmSwipeAction action}) async {
    if (chatId.trim().isEmpty || _currentUid == 'unknown_user') return;

    final chatRef = _firestore.collection('chats').doc(chatId);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(chatRef);
      if (!snap.exists) return;

      final data = snap.data() ?? const <String, dynamic>{};
      if ((data['type'] ?? '').toString() != 'dm') return;

      final participants =
          List<String>.from(data['participantIds'] ?? const <String>[]);
      if (!participants.contains(_currentUid)) return;

      final pinnedBy = _toStringList(data['pinnedBy']);
      final mutedBy = _toStringList(data['mutedBy']);

      switch (action) {
        case DmSwipeAction.pin:
          txn.update(chatRef, {
            if (pinnedBy.contains(_currentUid))
              'pinnedBy': FieldValue.arrayRemove([_currentUid])
            else
              'pinnedBy': FieldValue.arrayUnion([_currentUid]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          break;
        case DmSwipeAction.mute:
          txn.update(chatRef, {
            if (mutedBy.contains(_currentUid))
              'mutedBy': FieldValue.arrayRemove([_currentUid])
            else
              'mutedBy': FieldValue.arrayUnion([_currentUid]),
            if (!mutedBy.contains(_currentUid)) 'unreadCount.$_currentUid': 0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          break;
        case DmSwipeAction.delete:
          txn.update(chatRef, {
            'deletedFor': FieldValue.arrayUnion([_currentUid]),
            'unreadCount.$_currentUid': 0,
            'typing.$_currentUid': {
              'isTyping': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
          break;
      }
    });
  }

  @override
  Future<void> performGroupAction(
      {required String chatId, required DmSwipeAction action}) async {
    if (chatId.trim().isEmpty || _currentUid == 'unknown_user') return;

    final chatRef = _firestore.collection('chats').doc(chatId);
    final memberRef = chatRef.collection('chat_members').doc(_currentUid);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(chatRef);
      if (!snap.exists) return;

      final data = snap.data() ?? const <String, dynamic>{};
      if ((data['type'] ?? '').toString() != 'group') return;

      final participants =
          List<String>.from(data['participantIds'] ?? const <String>[]);
      if (!participants.contains(_currentUid)) return;

      final pinnedBy = _toStringList(data['pinnedBy']);
      final mutedBy = _toStringList(data['mutedBy']);

      switch (action) {
        case DmSwipeAction.pin:
          txn.update(chatRef, {
            if (pinnedBy.contains(_currentUid))
              'pinnedBy': FieldValue.arrayRemove([_currentUid])
            else
              'pinnedBy': FieldValue.arrayUnion([_currentUid]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          break;
        case DmSwipeAction.mute:
          txn.update(chatRef, {
            if (mutedBy.contains(_currentUid))
              'mutedBy': FieldValue.arrayRemove([_currentUid])
            else
              'mutedBy': FieldValue.arrayUnion([_currentUid]),
            if (!mutedBy.contains(_currentUid)) 'unreadCount.$_currentUid': 0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          break;
        case DmSwipeAction.delete:
          txn.update(chatRef, {
            'deletedFor': FieldValue.arrayUnion([_currentUid]),
            'unreadCount.$_currentUid': 0,
            'typing.$_currentUid': {
              'isTyping': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            'updatedAt': FieldValue.serverTimestamp(),
          });
          txn.set(
            memberRef,
            {
              'userId': _currentUid,
              'chatId': chatId,
              'isDeleted': true,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          break;
      }
    });
  }

  @override
  Future<void> undoDeleteChat({required String chatId}) async {
    final id = chatId.trim();
    if (id.isEmpty || _currentUid == 'unknown_user') return;
    try {
      await _firestore.collection('chats').doc(id).update({
        'deletedFor': FieldValue.arrayRemove([_currentUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('undoDeleteChat failed for $id: $e');
    }
  }

  @override
  Future<void> leaveGroupChat({
    required String chatId,
    required String eventId,
  }) async {
    if (chatId.trim().isEmpty || eventId.trim().isEmpty) return;
    if (_currentUid == 'unknown_user') return;

    await _eventService.removeUserFromEventAndChat(
      eventId: eventId,
      userId: _currentUid,
    );

    final chatRef = _firestore.collection('chats').doc(chatId);
    final memberRef = chatRef.collection('chat_members').doc(_currentUid);
    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(chatRef);
      if (!snap.exists) return;

      txn.update(chatRef, {
        'deletedFor': FieldValue.arrayUnion([_currentUid]),
        'unreadCount.$_currentUid': 0,
        'typing.$_currentUid': {
          'isTyping': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
      txn.set(
        memberRef,
        {
          'userId': _currentUid,
          'chatId': chatId,
          'isDeleted': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Future<void> respondToActivity(
      {required String activityId, required bool accepted}) async {}

  @override
  Future<void> sendFriendRequest({required String userId}) async {
    try {
      if (_currentUid == 'unknown_user') return;
      if (await _isBlockedEitherWay(_currentUid, userId)) return;

      final sent = await _friendService.createFriendRequest(
        senderId: _currentUid,
        receiverId: userId,
      );
      if (!sent) return;
      _discoverCacheAt = null;
    } catch (e, stack) {
      debugPrint('Send friend request failed: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  @override
  Future<String> createOrGetDM(String userId1, String userId2) async {
    try {
      final normalizedUser1 = userId1.trim();
      final normalizedUser2 = userId2.trim();
      if (normalizedUser1.isEmpty ||
          normalizedUser2.isEmpty ||
          normalizedUser1 == normalizedUser2) {
        return '';
      }
      final isBlocked =
          await _isBlockedEitherWay(normalizedUser1, normalizedUser2);
      if (isBlocked) {
        return '';
      }

      final chatId = _deterministicDmChatId(normalizedUser1, normalizedUser2);
      final chatDocRef = _firestore.collection('chats').doc(chatId);
      final sortedParticipants = <String>[normalizedUser1, normalizedUser2]
        ..sort();

      await _firestore.runTransaction((txn) async {
        final existing = await txn.get(chatDocRef);
        if (existing.exists) {
          final data = existing.data() ?? const <String, dynamic>{};
          final participants =
              List<String>.from(data['participantIds'] ?? const <String>[]);
          if (!participants.contains(normalizedUser1) ||
              !participants.contains(normalizedUser2)) {
            throw StateError('DM chat participant mismatch.');
          }
          if (data['isActive'] == false) {
            txn.set(
              chatDocRef,
              {
                'isActive': true,
                'deletedFor': FieldValue.arrayRemove(
                  [normalizedUser1, normalizedUser2],
                ),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
          return;
        }

        txn.set(chatDocRef, {
          'chatId': chatId,
          'type': 'dm',
          'participantIds': sortedParticipants,
          'createdBy': normalizedUser1,
          'isActive': true,
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'unreadCount': {
            normalizedUser1: 0,
            normalizedUser2: 0,
          },
        });
      });
      return chatId;
    } catch (e) {
      debugPrint('Create/get DM failed: $e');
      return '';
    }
  }

  @override
  Future<List<DiscoverPerson>> searchUsers(String query) async {
    try {
      if (query.isEmpty) return [];

      // Simple text search for users (inexact prefix search for Firebase to save reads)
      // Since it requires a specific string match logic from prompt: "toLowerCase().contains(query)"
      // To save Firebase quota but implement accurately, fetch matching subset or fetch all and filter
      final snapshot = await _firestore.collection('users').limit(40).get();
      final lowercaseQuery = query.toLowerCase();

      return snapshot.docs.where((doc) {
        if (doc.id == _currentUid) return false;
        final data = doc.data();
        if (!_isProfileVisible(data)) return false;
        final name = (data['name'] ?? '').toString().toLowerCase();
        final uname = (data['username'] ?? '').toString().toLowerCase();
        return name.contains(lowercaseQuery) || uname.contains(lowercaseQuery);
      }).map((doc) {
        final data = doc.data();
        final username = _extractUsername(data);
        return DiscoverPerson(
          id: doc.id,
          name: _extractDisplayName(data),
          username: username,
          detail: username.isEmpty ? 'Suggested for you' : '@$username',
          avatarEmoji: (data['avatarEmoji'] ?? '👤').toString(),
          avatarUrl: _extractAvatarUrl(data),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  String _extractDisplayName(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final username = _extractUsername(data);
    if (username.isNotEmpty) return username;
    return 'User';
  }

  String _extractUsername(Map<String, dynamic> data) {
    final raw = (data['username'] ?? data['userName'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (raw.isEmpty) return '';
    return raw.startsWith('@') ? raw.substring(1) : raw;
  }

  String _extractAvatarUrl(Map<String, dynamic> data) {
    final raw = (data['avatarUrl'] ??
            data['photoUrl'] ??
            data['profileImageUrl'] ??
            data['avatar_url'] ??
            '')
        .toString()
        .trim();
    return _sanitizeAvatarUrl(raw);
  }

  String _sanitizeAvatarUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return '';

    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? '').toLowerCase();
    if (host.contains('googleusercontent.com') || host.contains('ggpht.com')) {
      return '';
    }

    return url;
  }

  bool _isProfileVisible(Map<String, dynamic> data) {
    final raw = data['profileVisibility'];
    if (raw is bool) return raw;
    return true;
  }

  @override
  Stream<int> watchTotalUnreadCount() {
    final uid = _currentUid;
    if (uid == 'unknown_user') return Stream.value(0);

    return _firestore
        .collection('chats')
        .where('participantIds', arrayContains: uid)
        .snapshots(includeMetadataChanges: false)
        .map((snapshot) {
      var total = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (_containsUid(data['deletedFor'], uid)) continue;
        if (_containsUid(data['mutedBy'], uid)) continue;
        final raw = data['unreadCount'];
        if (raw is Map) {
          final perUser = raw[uid];
          if (perUser is int) total += perUser;
        }
      }
      return total;
    }).handleError((_) => 0);
  }

  @override
  Future<void> pinMessage({
    required String chatId,
    required String messageId,
    required String previewText,
  }) async {
    if (chatId.trim().isEmpty || messageId.trim().isEmpty) return;
    if (_currentUid == 'unknown_user') return;
    final preview = previewText.trim();
    await _firestore.collection('chats').doc(chatId).update({
      'pinnedMessageId': messageId,
      'pinnedMessageText':
          preview.length > 120 ? '${preview.substring(0, 120)}…' : preview,
      'pinnedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> unpinMessage({required String chatId}) async {
    if (chatId.trim().isEmpty) return;
    if (_currentUid == 'unknown_user') return;
    await _firestore.collection('chats').doc(chatId).update({
      'pinnedMessageId': FieldValue.delete(),
      'pinnedMessageText': FieldValue.delete(),
      'pinnedAt': FieldValue.delete(),
    });
  }

  @override
  Future<void> sendShareCard({
    required String chatId,
    required String type,
    required Map<String, dynamic> metadata,
  }) async {
    final uid = _currentUid;
    if (uid == 'unknown_user') return;
    if (chatId.trim().isEmpty) return;
    if (type != 'event_card' && type != 'profile_card') return;

    final selfName = await _resolveSelfDisplayName();
    final messageId = _uuid.v4();

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .set({
      'messageId': messageId,
      'clientMessageId': messageId,
      'chatId': chatId,
      'senderId': uid,
      'senderName': selfName,
      'senderAvatar': '',
      'type': type,
      'text': '',
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
      'reactions': <String, dynamic>{},
    });
  }

  @override
  Future<void> createPoll({
    required String chatId,
    required String question,
    required List<String> options,
    bool allowMultipleVotes = false,
  }) async {
    final uid = _currentUid;
    if (uid == 'unknown_user') return;
    final q = question.trim();
    final opts =
        options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
    if (chatId.trim().isEmpty || q.isEmpty || opts.length < 2) return;

    final selfName = await _resolveSelfDisplayName();
    final messageId = _uuid.v4();

    final pollOptions = List.generate(
        opts.length,
        (i) => {
              'id': 'opt$i',
              'text': opts[i],
              'voterIds': <String>[],
            });

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .set({
      'messageId': messageId,
      'clientMessageId': messageId,
      'chatId': chatId,
      'senderId': uid,
      'senderName': selfName,
      'senderAvatar': '',
      'type': 'poll',
      'text': '',
      'poll': {
        'question': q,
        'options': pollOptions,
        'allowMultipleVotes': allowMultipleVotes,
        'createdBy': uid,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'reactions': <String, dynamic>{},
    });
  }

  @override
  Future<void> votePoll({
    required String chatId,
    required String messageId,
    required String optionId,
  }) async {
    final uid = _currentUid;
    if (uid == 'unknown_user') return;
    if (chatId.trim().isEmpty ||
        messageId.trim().isEmpty ||
        optionId.trim().isEmpty) {
      return;
    }

    final msgRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(msgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (data['type'] != 'poll') return;

      final pollMap = data['poll'];
      if (pollMap is! Map) return;
      final allowMultiple = pollMap['allowMultipleVotes'] == true;
      final rawOptions = pollMap['options'];
      if (rawOptions is! List) return;

      final options = rawOptions
          .whereType<Map>()
          .map((o) => Map<String, dynamic>.from(o))
          .toList();

      final targetIdx = options.indexWhere((o) => o['id'] == optionId);
      if (targetIdx == -1) return;

      final targetVoters =
          List<String>.from(options[targetIdx]['voterIds'] ?? []);
      final alreadyVoted = targetVoters.contains(uid);

      if (alreadyVoted) {
        targetVoters.remove(uid);
      } else {
        if (!allowMultiple) {
          // Remove vote from every other option first.
          for (var i = 0; i < options.length; i++) {
            if (i == targetIdx) continue;
            final v = List<String>.from(options[i]['voterIds'] ?? []);
            v.remove(uid);
            options[i]['voterIds'] = v;
          }
        }
        targetVoters.add(uid);
      }
      options[targetIdx]['voterIds'] = targetVoters;

      txn.update(msgRef, {'poll.options': options});
    });
  }

  @override
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final trimmed = newText.trim();
    if (chatId.trim().isEmpty || messageId.trim().isEmpty || trimmed.isEmpty) {
      return;
    }
    if (_currentUid == 'unknown_user') return;

    final msgRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(msgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      // Guard: only the original sender may edit.
      if (data['senderId'] != _currentUid) return;
      // Guard: cannot edit a deleted message.
      if (data['isDeleted'] == true) return;

      txn.update(msgRef, {
        'text': trimmed,
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    if (chatId.trim().isEmpty || messageId.trim().isEmpty) return;
    if (_currentUid == 'unknown_user') return;

    final msgRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(msgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      if (data['senderId'] != _currentUid) return;
      if (data['isDeleted'] == true) return;

      txn.update(msgRef, {'isDeleted': true});
    });
  }

  @override
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    if (chatId.trim().isEmpty ||
        messageId.trim().isEmpty ||
        emoji.trim().isEmpty) return;
    final uid = _currentUid;
    if (uid == 'unknown_user') return;

    final msgRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(msgRef);
      if (!snap.exists) return;

      final data = snap.data() ?? const <String, dynamic>{};
      final parsed = ChatMessage.parseReactions(data['reactions']);
      final users = List<String>.from(parsed[emoji] ?? []);

      if (users.contains(uid)) {
        users.remove(uid);
      } else {
        users.add(uid);
      }

      if (users.isEmpty) {
        // Remove the emoji key entirely rather than leaving an empty array.
        txn.update(msgRef, {'reactions.$emoji': FieldValue.delete()});
      } else {
        txn.update(msgRef, {'reactions.$emoji': users});
      }
    });
  }
}

class _CachedUserDoc {
  _CachedUserDoc(this.data, this.at);
  final Map<String, dynamic> data;
  final DateTime at;
}

class _CachedEventDoc {
  _CachedEventDoc(this.data, this.at);
  final Map<String, dynamic>? data;
  final DateTime at;
}

class _ScoredDiscover {
  final int score;
  final DiscoverPerson person;

  _ScoredDiscover({
    required this.score,
    required this.person,
  });
}

class _OutboxMessage {
  _OutboxMessage({
    required this.chatId,
    required this.clientMessageId,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.participantIds,
    required this.createdAt,
    required this.lastUpdatedAt,
    required this.nextAttemptAt,
    this.eventId,
    this.status = MessageStatus.sending,
    this.retryCount = 0,
    this.failureReason = '',
    this.inFlight = false,
    this.replyToMessageId,
    this.replyToPreviewText = '',
    this.replyToSenderName = '',
  });

  final String chatId;
  final String clientMessageId;
  final String text;
  final String senderId;
  final String senderName;
  final String? eventId;
  final List<String> participantIds;
  final DateTime createdAt;
  DateTime lastUpdatedAt;
  DateTime nextAttemptAt;
  MessageStatus status;
  int retryCount;
  String failureReason;
  bool inFlight;
  final String? replyToMessageId;
  final String replyToPreviewText;
  final String replyToSenderName;
}
