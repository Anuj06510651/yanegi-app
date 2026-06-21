import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'notification_types.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String _dedupeNotificationId({
    required String userId,
    required String dedupeKey,
  }) {
    final raw = '$userId|$dedupeKey';
    final encoded = base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
    if (encoded.length <= 1200) {
      return 'dedupe_$encoded';
    }

    var hash = 2166136261;
    for (final codeUnit in raw.codeUnits) {
      hash = hash ^ codeUnit;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return 'dedupe_${hash.toRadixString(16)}';
  }

  // Backoff schedule for transient failures: immediate, +2s, +5s, +10s.
  // Anything classified as non-retryable (permission-denied, validation, auth)
  // short-circuits without burning the schedule. See CLAUDE.md "Retry Spec".
  static const List<Duration> _retryDelays = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  static bool _isRetryable(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
        case 'unauthenticated':
        case 'invalid-argument':
        case 'failed-precondition':
        case 'not-found':
        case 'already-exists':
        case 'out-of-range':
          return false;
        case 'unavailable':
        case 'deadline-exceeded':
        case 'resource-exhausted':
        case 'aborted':
        case 'internal':
        case 'cancelled':
        case 'unknown':
          return true;
      }
    }
    return true;
  }

  Future<bool> sendWithRetry(
    Future<void> Function() fn, {
    String? userId,
    String? type,
    String? senderId,
    Map<String, dynamic>? metadata,
  }) async {
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 0; attempt < _retryDelays.length; attempt++) {
      final delay = _retryDelays[attempt];
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      try {
        await fn();
        return true;
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;
        debugPrint(
            'Notification failed (attempt ${attempt + 1}/${_retryDelays.length}): $e');
        if (!_isRetryable(e)) {
          debugPrint(
              'Notification not retryable (${e is FirebaseException ? e.code : e.runtimeType}) — aborting retry');
          break;
        }
      }
    }

    debugPrint('Notification permanently failed');
    await _logNotificationFailure(
      userId: userId,
      type: type,
      senderId: senderId,
      error: lastError,
      stackTrace: lastStack,
      retries: _retryDelays.length,
      metadata: metadata,
    );
    return false;
  }

  Future<void> _logNotificationFailure({
    String? userId,
    String? type,
    String? senderId,
    Object? error,
    StackTrace? stackTrace,
    required int retries,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _firestore.collection('notification_failures').add({
        'userId': (userId ?? '').trim(),
        'type': (type ?? '').trim(),
        'senderId': (senderId ?? '').trim(),
        'error': error?.toString() ?? 'unknown_error',
        'stackTrace': stackTrace?.toString() ?? '',
        'retries': retries,
        'time': Timestamp.now(),
        'createdAt': FieldValue.serverTimestamp(),
        if (metadata != null) 'metadata': metadata,
      });
    } catch (e, stack) {
      debugPrint('Failed to write notification_failures log: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> sendNotification({
    required String userId,
    required String type,
    required String senderId,
    String? senderName,
    String? senderAvatar,
    String? eventId,
    String? message,
    String? title,
    String? body,
    String? chatId,
    String? dedupeKey,
    Duration dedupeWindow = const Duration(minutes: 2),
    String? actionStatus,
    String? eventBannerUrl,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedSenderId = senderId.trim();
    final normalizedType = normalizeType(type);
    if (normalizedUserId.isEmpty || normalizedSenderId.isEmpty) return;
    if (normalizedUserId == normalizedSenderId) return;

    final normalizedMessage = (message ?? '').trim();
    final normalizedTitle = (title ?? normalizedMessage).trim();
    final normalizedBody = (body ?? normalizedMessage).trim();
    final normalizedDedupeKey = (dedupeKey ?? '').trim();

    final data = <String, dynamic>{
      'userId': normalizedUserId,
      'receiverId': normalizedUserId,
      'type': normalizedType,
      'senderId': normalizedSenderId,
      'senderName': (senderName ?? '').trim(),
      'senderAvatar': (senderAvatar ?? '').trim(),
      'eventId': (eventId ?? '').trim(),
      'chatId': chatId,
      'message': normalizedMessage,
      'title': normalizedTitle,
      'body': normalizedBody,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
      'isRead': false,
    };

    if (normalizedDedupeKey.isNotEmpty) {
      data['dedupeKey'] = normalizedDedupeKey;
    }

    final normalizedActionStatus = (actionStatus ?? '').trim();
    if (normalizedActionStatus.isNotEmpty) {
      data['actionStatus'] = normalizedActionStatus;
    }

    final normalizedBannerUrl = (eventBannerUrl ?? '').trim();
    if (normalizedBannerUrl.isNotEmpty) {
      data['eventBannerUrl'] = normalizedBannerUrl;
    }

    final notifications = _firestore.collection('notifications');
    if (normalizedDedupeKey.isEmpty) {
      await notifications.add(data);
      return;
    }

    final dedupeRef = notifications.doc(
      _dedupeNotificationId(
        userId: normalizedUserId,
        dedupeKey: normalizedDedupeKey,
      ),
    );

    await _firestore.runTransaction((txn) async {
      final existing = await txn.get(dedupeRef);
      if (existing.exists) {
        final existingData = existing.data() ?? const <String, dynamic>{};
        final createdAt = existingData['createdAt'];
        if (createdAt is Timestamp &&
            DateTime.now().difference(createdAt.toDate()) < dedupeWindow) {
          return;
        }
      }

      txn.set(dedupeRef, data);
    });
  }
}
