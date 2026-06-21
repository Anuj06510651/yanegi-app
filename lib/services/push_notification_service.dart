import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import '../screens/chat/chat_thread_screen.dart';
import '../screens/event_detail_screen.dart';
import '../screens/event_recap_screen.dart';
import '../screens/profile_social_screen.dart';
import 'notification_types.dart';

@immutable
class PushDebugSnapshot {
  const PushDebugSnapshot({
    required this.token,
    required this.authorizationStatus,
    required this.notificationsEnabled,
    required this.lastEventSource,
    required this.lastPayload,
    required this.lastUpdatedAt,
    required this.lastError,
  });

  final String token;
  final String authorizationStatus;
  final bool notificationsEnabled;
  final String lastEventSource;
  final Map<String, dynamic> lastPayload;
  final DateTime? lastUpdatedAt;
  final String lastError;

  factory PushDebugSnapshot.empty() => const PushDebugSnapshot(
        token: '',
        authorizationStatus: 'unknown',
        notificationsEnabled: false,
        lastEventSource: '',
        lastPayload: <String, dynamic>{},
        lastUpdatedAt: null,
        lastError: '',
      );

  PushDebugSnapshot copyWith({
    String? token,
    String? authorizationStatus,
    bool? notificationsEnabled,
    String? lastEventSource,
    Map<String, dynamic>? lastPayload,
    DateTime? lastUpdatedAt,
    String? lastError,
  }) {
    return PushDebugSnapshot(
      token: token ?? this.token,
      authorizationStatus: authorizationStatus ?? this.authorizationStatus,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      lastEventSource: lastEventSource ?? this.lastEventSource,
      lastPayload: lastPayload ?? this.lastPayload,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Background isolate handler for FCM data/notification payloads.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase may already be initialized in isolate.
  }
}

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FlutterLocalNotificationsPlugin? localNotifications,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FlutterLocalNotificationsPlugin _localNotifications;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  StreamSubscription<User?>? _authStateSub;

  bool _initialized = false;
  GlobalKey<NavigatorState>? _navigatorKey;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'yanegi_activity',
    'Yanegi Activity Notifications',
    description: 'Foreground activity notifications for Yanegi.',
    importance: Importance.high,
  );

  static final ValueNotifier<PushDebugSnapshot> debugSnapshotNotifier =
      ValueNotifier<PushDebugSnapshot>(PushDebugSnapshot.empty());

  PushDebugSnapshot get debugSnapshot => debugSnapshotNotifier.value;

  Future<void> initialize({
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_initialized) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    await _initializeLocalNotifications();

    final permissionSettings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    _recordDebugSnapshot(
      authorizationStatus: permissionSettings.authorizationStatus.name,
      notificationsEnabled: permissionSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          permissionSettings.authorizationStatus ==
              AuthorizationStatus.provisional,
      lastEventSource: 'permission_request',
    );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _syncCurrentToken();

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
      unawaited(_updateUserToken(newToken));
    });

    _authStateSub = _auth.authStateChanges().listen((user) {
      if (user == null) return;
      unawaited(_syncCurrentToken());
    });

    _onMessageSub = FirebaseMessaging.onMessage.listen((message) {
      _recordDebugSnapshot(
        lastEventSource: 'foreground_message',
        lastPayload: _composeDebugPayload(message),
      );
      unawaited(_showForegroundNotification(message));
    });

    _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _recordDebugSnapshot(
        lastEventSource: 'opened_from_background',
        lastPayload: _composeDebugPayload(msg),
      );
      _handleNavigation(msg.data);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _recordDebugSnapshot(
        lastEventSource: 'opened_from_terminated',
        lastPayload: _composeDebugPayload(initialMessage),
      );
      _handleNavigation(initialMessage.data);
    }

    await refreshDebugSnapshot();
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _onMessageSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    await _authStateSub?.cancel();
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.trim().isEmpty) return;

        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map) return;
          final map =
              Map<String, dynamic>.from(decoded.cast<String, dynamic>());
          _recordDebugSnapshot(
            lastEventSource: 'local_notification_tap',
            lastPayload: map,
          );
          _handleNavigation(map);
        } catch (e) {
          _recordDebugSnapshot(
            lastEventSource: 'local_notification_tap',
            lastError: 'Local payload decode failed: $e',
          );
          debugPrint('Local notification payload decode failed: $e');
        }
      },
    );

    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
  }

  Future<void> _syncCurrentToken() async {
    final token = await _messaging.getToken();
    await _updateUserToken(token);

    _recordDebugSnapshot(
      token: (token ?? '').trim(),
      lastEventSource: 'token_sync',
    );
  }

  Future<void> _updateUserToken(String? token) async {
    final normalized = (token ?? '').trim();
    if (normalized.isEmpty) return;

    final uid = _auth.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) return;

    debugPrint('USER WRITE START: PushNotificationService _updateUserToken');
    debugPrint('USER WRITE UID: $uid');
    debugPrint('USER WRITE PAYLOAD: {fcmToken, fcmTokenUpdatedAt, updatedAt, updated_at}');

    try {
      await _firestore.collection('users').doc(uid).set({
        'fcmToken': normalized,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('USER WRITE SUCCESS: PushNotificationService _updateUserToken');
    } catch (e) {
      debugPrint('USER WRITE FAILED: PushNotificationService _updateUserToken: $e');
    }

    _recordDebugSnapshot(
      token: normalized,
      lastEventSource: 'token_persisted',
    );
  }

  Future<PushDebugSnapshot> refreshDebugSnapshot() async {
    final settings = await _messaging.getNotificationSettings();
    final token = (await _messaging.getToken())?.trim() ?? '';

    _recordDebugSnapshot(
      token: token,
      authorizationStatus: settings.authorizationStatus.name,
      notificationsEnabled:
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional,
      lastEventSource: 'manual_refresh',
    );
    return debugSnapshotNotifier.value;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final data = _stringifyMap(message.data);

    final title =
        (message.notification?.title ?? data['senderName'] ?? 'New Activity')
            .trim();
    final body =
        (message.notification?.body ?? data['message'] ?? data['type'] ?? '')
            .trim();

    if (title.isEmpty && body.isEmpty) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title.isEmpty ? 'New Activity' : title,
      body.isEmpty ? null : body,
      details,
      payload: jsonEncode(data),
    );
  }

  Map<String, dynamic> _stringifyMap(Map<String, dynamic> data) {
    final normalized = <String, dynamic>{};
    data.forEach((key, value) {
      if (value == null) {
        normalized[key] = '';
      } else {
        normalized[key] = value.toString();
      }
    });
    return normalized;
  }

  Map<String, dynamic> _composeDebugPayload(RemoteMessage message) {
    final data = _stringifyMap(message.data);
    final title = (message.notification?.title ?? '').trim();
    final body = (message.notification?.body ?? '').trim();
    if (title.isNotEmpty) {
      data['notificationTitle'] = title;
    }
    if (body.isNotEmpty) {
      data['notificationBody'] = body;
    }
    return data;
  }

  void _recordDebugSnapshot({
    String? token,
    String? authorizationStatus,
    bool? notificationsEnabled,
    String? lastEventSource,
    Map<String, dynamic>? lastPayload,
    String? lastError,
  }) {
    final current = debugSnapshotNotifier.value;
    debugSnapshotNotifier.value = current.copyWith(
      token: token,
      authorizationStatus: authorizationStatus,
      notificationsEnabled: notificationsEnabled,
      lastEventSource: lastEventSource,
      lastPayload: lastPayload,
      lastError: lastError,
      lastUpdatedAt: DateTime.now(),
    );
  }

  void _handleNavigation(Map<String, dynamic> rawData) {
    final navigatorState = _navigatorKey?.currentState;
    if (navigatorState == null) return;

    final data = _stringifyMap(rawData);
    final type = normalizeType((data['type'] ?? '').toString());

    // Re-engagement taps: go to an event detail if eventId was included,
    // otherwise just surface the app (user lands on the home/explore screen).
    if (type == 're_engagement') {
      final eventId = (data['eventId'] ?? '').toString().trim();
      if (eventId.isNotEmpty) {
        navigatorState.push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(eventId: eventId),
          ),
        );
      }
      // No eventId → app opens to wherever the user last was (home screen).
      return;
    }

    if (type == NotificationType.friendRequest ||
        type == NotificationType.friendAccept) {
      final profileUserId = (data['senderId'] ?? '').toString().trim();
      if (profileUserId.isEmpty) return;
      navigatorState.push(
        MaterialPageRoute(
          builder: (_) => SocialProfileScreen(profileUserId: profileUserId),
        ),
      );
      return;
    }

    if (type == NotificationType.eventRequest ||
        type == NotificationType.eventAccept ||
        type == NotificationType.eventReject ||
        type == NotificationType.eventCreated) {
      final eventId = (data['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) return;
      navigatorState.push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: eventId),
        ),
      );
      return;
    }

    if (type == NotificationType.eventReminder) {
      final eventId = (data['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) return;
      navigatorState.push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: eventId),
        ),
      );
      return;
    }

    if (type == NotificationType.postEventRecap) {
      final eventId    = (data['eventId'] ?? '').toString().trim();
      final eventTitle = (data['eventTitle'] ?? '').toString().trim();
      if (eventId.isEmpty) return;
      navigatorState.push(MaterialPageRoute(
        builder: (_) => EventRecapScreen(
          eventId: eventId,
          eventTitle: eventTitle.isNotEmpty ? eventTitle : 'Your Event',
        ),
      ));
      return;
    }

    if (type == NotificationType.shoutout) {
      final profileUserId = (data['senderId'] ?? '').toString().trim();
      if (profileUserId.isEmpty) return;
      navigatorState.push(MaterialPageRoute(
        builder: (_) => SocialProfileScreen(profileUserId: profileUserId),
      ));
      return;
    }

    if (type == NotificationType.waitlistSpotAvailable) {
      final eventId = (data['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) return;
      navigatorState.push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: eventId),
        ),
      );
      return;
    }

    if (type == NotificationType.friendJoinedEvent) {
      final eventId = (data['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) return;
      navigatorState.push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: eventId),
        ),
      );
      return;
    }

    if (type == NotificationType.mention) {
      final chatId = (data['chatId'] ?? '').toString().trim();
      if (chatId.isEmpty) return;
      final isGroup = chatId.startsWith('grp_');
      navigatorState.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            chatId: chatId,
            title: isGroup ? 'Group Chat' : 'Chat',
            isGroup: isGroup,
          ),
        ),
      );
      return;
    }

    if (type == NotificationType.chatMessage) {
      final chatId = (data['chatId'] ?? '').toString().trim();
      if (chatId.isEmpty) return;
      final senderName = (data['senderName'] ?? 'Chat').toString().trim();
      final isGroupFlag =
          (data['isGroup'] ?? '').toString().trim().toLowerCase() == 'true';
      final isGroup = isGroupFlag || chatId.startsWith('grp_');
      navigatorState.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            chatId: chatId,
            title: isGroup ? 'Group Chat' : senderName,
            isGroup: isGroup,
          ),
        ),
      );
    }

    // Weekly digest: open the top event if one was included, otherwise just
    // surface the app (user lands on explore/home screen naturally).
    if (type == NotificationType.weeklyDigest) {
      final topEventId = (data['topEventId'] ?? '').toString().trim();
      if (topEventId.isNotEmpty) {
        navigatorState.push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(eventId: topEventId),
          ),
        );
      }
      // No topEventId → app opens to home screen.
      return;
    }
  }
}
