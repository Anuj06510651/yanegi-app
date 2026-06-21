import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'rate_limiter_service.dart';
import 'reliable_upload_queue_service.dart';

class MediaStorageService {
  MediaStorageService({RateLimiterService? rateLimiter})
      : _rateLimiter = rateLimiter ?? RateLimiterService();

  final ReliableUploadQueueService _queueService = ReliableUploadQueueService();
  final RateLimiterService _rateLimiter;

  Stream<UploadStatusEvent> get uploadStatusStream =>
      _queueService.uploadStatusStream;

  UploadQueueState? uploadStateForStoragePath(String storagePath) {
    return _queueService.stateForStoragePath(storagePath);
  }

  Future<void> retryUploadByStoragePath(String storagePath) {
    return _queueService.retryNowByStoragePath(storagePath);
  }

  Future<String> uploadProfileImage({
    required String userId,
    required String localFilePath,
    String? oldDownloadUrl,
  }) async {
    await _assertUploadQuota(RateLimiterService.photoUploadPerDay);
    final url = await _queueService.enqueueAndWait(
      File(localFilePath),
      'profile_images/$userId/profile.jpg',
      type: 'profile',
    );
    unawaited(_rateLimiter.record(RateLimiterService.photoUploadPerDay));
    return _appendCacheBuster(url);
  }

  Future<String> enqueueProfileImageUpload({
    required String userId,
    required String localFilePath,
  }) async {
    await _assertUploadQuota(RateLimiterService.photoUploadPerDay);
    final path = await _queueService.enqueueUpload(
      File(localFilePath),
      'profile_images/$userId/profile.jpg',
      type: 'profile',
    );
    unawaited(_rateLimiter.record(RateLimiterService.photoUploadPerDay));
    return path;
  }

  Future<String> uploadBannerImage({
    required String userId,
    required String localFilePath,
    String? oldDownloadUrl,
  }) async {
    await _assertUploadQuota(RateLimiterService.bannerUploadPerDay);
    final url = await _queueService.enqueueAndWait(
      File(localFilePath),
      'banner_images/$userId/banner.jpg',
      type: 'banner',
    );
    unawaited(_rateLimiter.record(RateLimiterService.bannerUploadPerDay));
    return _appendCacheBuster(url);
  }

  Future<String> enqueueBannerImageUpload({
    required String userId,
    required String localFilePath,
  }) async {
    await _assertUploadQuota(RateLimiterService.bannerUploadPerDay);
    final path = await _queueService.enqueueUpload(
      File(localFilePath),
      'banner_images/$userId/banner.jpg',
      type: 'banner',
    );
    unawaited(_rateLimiter.record(RateLimiterService.bannerUploadPerDay));
    return path;
  }

  Future<void> _assertUploadQuota(RateLimitSpec spec) async {
    final result = await _rateLimiter.check(spec);
    if (!result.allowed) {
      throw StateError(
        'You’ve uploaded a lot today. Please try again later.',
      );
    }
  }

  Future<String> uploadEventImage({
    required String eventId,
    required String localFilePath,
  }) async {
    final fullImageUrl = await _queueService.enqueueAndWait(
      File(localFilePath),
      'event_images/$eventId.jpg',
      type: 'event',
    );

    try {
      await _queueService.enqueueAndWait(
        File(localFilePath),
        'event_images/${eventId}_thumb.jpg',
        type: 'event_thumb',
      );
    } catch (_) {
      // best effort thumb upload
    }

    return _appendCacheBuster(fullImageUrl);
  }

  Future<String> uploadImageReliable({
    required String localFilePath,
    required String storagePath,
    String type = 'misc',
  }) async {
    final url = await _queueService.enqueueAndWait(
      File(localFilePath),
      storagePath,
      type: type,
    );
    return _appendCacheBuster(url);
  }

  Future<String> enqueueImageUpload({
    required String localFilePath,
    required String storagePath,
    String type = 'misc',
  }) {
    return _queueService.enqueueUpload(
      File(localFilePath),
      storagePath,
      type: type,
    );
  }

  Future<String?> getEventThumbnailUrl({required String eventId}) async {
    final normalizedId = eventId.trim();
    if (normalizedId.isEmpty) return null;

    for (final storage in _storageCandidates()) {
      try {
        return await storage
            .ref()
            .child('event_images/${normalizedId}_thumb.jpg')
            .getDownloadURL();
      } catch (_) {
        // try next candidate
      }
    }

    return null;
  }

  Future<void> deleteProfileImage({
    required String userId,
    String? oldDownloadUrl,
  }) {
    return _deleteAtPath('profile_images/$userId/profile.jpg');
  }

  Future<void> deleteBannerImage({
    required String userId,
    String? oldDownloadUrl,
  }) {
    return _deleteAtPath('banner_images/$userId/banner.jpg');
  }

  Future<void> _deleteAtPath(String storagePath) async {
    final normalizedPath =
        storagePath.startsWith('/') ? storagePath.substring(1) : storagePath;

    for (final storage in _storageCandidates()) {
      try {
        await storage.ref().child(normalizedPath).delete();
      } on FirebaseException catch (e) {
        if (e.code.toLowerCase().contains('object-not-found')) {
          continue;
        }
      } catch (_) {
        // best effort
      }
    }
  }

  List<FirebaseStorage> _storageCandidates() {
    final configuredBucket =
        (Firebase.app().options.storageBucket ?? '').trim();
    final projectId = Firebase.app().options.projectId.trim();
    final buckets = <String>{};

    if (configuredBucket.isNotEmpty) {
      buckets.add(configuredBucket);

      if (configuredBucket.endsWith('.firebasestorage.app')) {
        buckets.add(
          configuredBucket.replaceAll(
            '.firebasestorage.app',
            '.appspot.com',
          ),
        );
      } else if (configuredBucket.endsWith('.appspot.com')) {
        buckets.add(
          configuredBucket.replaceAll(
            '.appspot.com',
            '.firebasestorage.app',
          ),
        );
      }
    }

    var resolvedProjectId = projectId;
    if (resolvedProjectId.isEmpty && configuredBucket.isNotEmpty) {
      resolvedProjectId = configuredBucket
          .replaceAll('.appspot.com', '')
          .replaceAll('.firebasestorage.app', '')
          .trim();
    }

    if (resolvedProjectId.isNotEmpty) {
      buckets.add('$resolvedProjectId.firebasestorage.app');
      buckets.add('$resolvedProjectId.appspot.com');
    }

    if (buckets.isEmpty) {
      return <FirebaseStorage>[FirebaseStorage.instance];
    }

    return buckets
        .map((bucket) => FirebaseStorage.instanceFor(bucket: bucket))
        .toList();
  }

  String _appendCacheBuster(String url) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return url.contains('?') ? '$url&t=$ts' : '$url?t=$ts';
  }
}
