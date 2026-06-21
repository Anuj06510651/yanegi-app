import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/pending_upload.dart';

enum UploadQueueState { queued, uploading, retrying, failed, success }

class UploadStatusEvent {
  const UploadStatusEvent({
    required this.upload,
    required this.state,
    this.downloadUrl,
    this.error,
  });

  final PendingUpload upload;
  final UploadQueueState state;
  final String? downloadUrl;
  final String? error;
}

class ReliableUploadQueueService {
  ReliableUploadQueueService();

  static const String _prefsKey = 'media_upload_queue_v1';
  static const Duration _workerInterval = Duration(seconds: 3);
  static const int _maxInputSizeBytes = 10 * 1024 * 1024; // 10 MB pre-compression
  static const String _cacheControl = 'public,max-age=31536000';
  static const int _maxRetries = 5;

  static final Uuid _uuid = const Uuid();
  static final Map<String, PendingUpload> _uploadQueue =
      <String, PendingUpload>{};
  static final Map<String, String> _lastHashByStoragePath = <String, String>{};
  static final Map<String, String> _lastUrlByStoragePath = <String, String>{};
  static final Map<String, String> _sourceHashByUploadId = <String, String>{};
  static final Set<String> _loadedMemoPaths = <String>{};
  static final Map<String, UploadQueueState> _states =
      <String, UploadQueueState>{};
  static final Map<String, Future<void> Function(String)> _onSuccessById =
      <String, Future<void> Function(String)>{};
  static final Map<String, Completer<String>> _completerById =
      <String, Completer<String>>{};
  static final Set<String> _inFlight = <String>{};

  static final StreamController<UploadStatusEvent> _statusController =
      StreamController<UploadStatusEvent>.broadcast();

  static Timer? _worker;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static bool _networkAvailable = true;
  static bool _processing = false;
  static bool _bootstrapped = false;

  Stream<UploadStatusEvent> get uploadStatusStream => _statusController.stream;

  UploadQueueState? stateForStoragePath(String storagePath) {
    final normalized = _normalizeStoragePath(storagePath);
    for (final upload in _uploadQueue.values) {
      if (upload.storagePath == normalized) {
        return _states[upload.id] ?? UploadQueueState.queued;
      }
    }
    return null;
  }

  Future<String> enqueueUpload(
    File file,
    String storagePath, {
    required String type,
    Future<void> Function(String url)? onUploadSuccess,
  }) async {
    await _ensureBootstrapped();

    if (!file.existsSync()) {
      throw StateError('File not found at path: ${file.path}');
    }

    if (file.lengthSync() > _maxInputSizeBytes) {
      throw Exception('Image too large. Please select smaller image.');
    }

    final normalized = _normalizeStoragePath(storagePath);
    await _loadUploadMemoForPath(normalized);
    final sourceHash = await generateFileHash(file);
    final existingUrl = _existingUrlForHash(
      storagePath: normalized,
      hash: sourceHash,
    );

    if (existingUrl != null) {
      final cachedUpload = PendingUpload(
        id: _uuid.v4(),
        filePath: file.path,
        storagePath: normalized,
        type: type,
        retryCount: 0,
        nextRetryAt: DateTime.now(),
      );
      _emit(cachedUpload, UploadQueueState.success, downloadUrl: existingUrl);
      if (onUploadSuccess != null) {
        await onUploadSuccess(existingUrl);
      }
      return cachedUpload.id;
    }

    final preparedFile = await compressImage(file, type);

    final duplicate = _findDuplicate(preparedFile.path, normalized);
    if (duplicate != null) {
      if (onUploadSuccess != null) {
        _onSuccessById[duplicate.id] = onUploadSuccess;
      }
      _startWorker();
      return duplicate.id;
    }

    final upload = PendingUpload(
      id: _uuid.v4(),
      filePath: preparedFile.path,
      storagePath: normalized,
      type: type,
      retryCount: 0,
      nextRetryAt: DateTime.now(),
    );
    _sourceHashByUploadId[upload.id] = sourceHash;

    _uploadQueue[upload.id] = upload;
    _states[upload.id] = UploadQueueState.queued;
    _emit(upload, UploadQueueState.queued);

    if (onUploadSuccess != null) {
      _onSuccessById[upload.id] = onUploadSuccess;
    }

    await _persistQueue();
    _startWorker();
    return upload.id;
  }

  Future<String> enqueueAndWait(
    File file,
    String storagePath, {
    required String type,
  }) async {
    await _ensureBootstrapped();
    if (!file.existsSync()) {
      throw StateError('File not found at path: ${file.path}');
    }

    if (file.lengthSync() > _maxInputSizeBytes) {
      throw Exception('Image too large. Please select smaller image.');
    }

    final normalized = _normalizeStoragePath(storagePath);
    await _loadUploadMemoForPath(normalized);
    final sourceHash = await generateFileHash(file);
    final existingUrl = _existingUrlForHash(
      storagePath: normalized,
      hash: sourceHash,
    );
    if (existingUrl != null) {
      return existingUrl;
    }

    final uploadId = await enqueueUpload(
      file,
      storagePath,
      type: type,
    );

    final existing = _completerById[uploadId];
    if (existing != null) return existing.future;

    final completer = Completer<String>();
    _completerById[uploadId] = completer;
    _startWorker();
    return completer.future;
  }

  Future<void> retryNowByStoragePath(String storagePath) async {
    await _ensureBootstrapped();

    final normalized = _normalizeStoragePath(storagePath);
    for (final upload in _uploadQueue.values) {
      if (upload.storagePath == normalized) {
        upload.nextRetryAt = DateTime.now();
        _states[upload.id] = UploadQueueState.retrying;
        _emit(upload, UploadQueueState.retrying);
      }
    }

    await _persistQueue();
    _startWorker();
  }

  PendingUpload? _findDuplicate(String filePath, String storagePath) {
    for (final upload in _uploadQueue.values) {
      if (upload.filePath == filePath) return upload;
      if (upload.storagePath == storagePath && upload.filePath == filePath) {
        return upload;
      }
    }
    return null;
  }

  Future<void> _ensureBootstrapped() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    await _restoreQueue();
    await _setupConnectivity();
    _startWorker();
  }

  Future<void> _setupConnectivity() async {
    final connectivity = Connectivity();
    _networkAvailable =
        _isOnlineFromResults(await connectivity.checkConnectivity());

    await _connectivitySub?.cancel();
    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      _networkAvailable = _isOnlineFromResults(results);
      if (_networkAvailable) {
        _startWorker();
      }
    });
  }

  bool _isOnlineFromResults(List<ConnectivityResult> results) {
    for (final item in results) {
      if (item != ConnectivityResult.none) return true;
    }
    return false;
  }

  Future<void> _restoreQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      for (final item in decoded) {
        if (item is! Map) continue;
        final upload = PendingUpload.fromJson(item.cast<String, dynamic>());
        if (upload.id.trim().isEmpty ||
            upload.filePath.trim().isEmpty ||
            upload.storagePath.trim().isEmpty) {
          continue;
        }
        _uploadQueue[upload.id] = upload;
        _states[upload.id] = UploadQueueState.queued;
      }
    } catch (_) {
      // Ignore corrupt queue data.
    }
  }

  Future<void> _persistQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _uploadQueue.values.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }

  String _hashPrefKey(String storagePath) => 'upload_hash_$storagePath';

  String _urlPrefKey(String storagePath) => 'upload_url_$storagePath';

  Future<void> _loadUploadMemoForPath(String storagePath) async {
    if (_loadedMemoPaths.contains(storagePath)) return;

    final prefs = await SharedPreferences.getInstance();
    final hash = (prefs.getString(_hashPrefKey(storagePath)) ?? '').trim();
    final url = (prefs.getString(_urlPrefKey(storagePath)) ?? '').trim();
    if (hash.isNotEmpty) {
      _lastHashByStoragePath[storagePath] = hash;
    }
    if (url.isNotEmpty) {
      _lastUrlByStoragePath[storagePath] = url;
    }
    _loadedMemoPaths.add(storagePath);
  }

  Future<void> _storeUploadMemo({
    required String storagePath,
    required String hash,
    required String url,
  }) async {
    _lastHashByStoragePath[storagePath] = hash;
    _lastUrlByStoragePath[storagePath] = url;
    _loadedMemoPaths.add(storagePath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashPrefKey(storagePath), hash);
    await prefs.setString(_urlPrefKey(storagePath), url);
  }

  String? _existingUrlForHash({
    required String storagePath,
    required String hash,
  }) {
    final previousHash = _lastHashByStoragePath[storagePath];
    final previousUrl = (_lastUrlByStoragePath[storagePath] ?? '').trim();
    if (previousHash == hash && previousUrl.isNotEmpty) {
      return previousUrl;
    }
    return null;
  }

  void _startWorker() {
    _worker ??= Timer.periodic(_workerInterval, (_) {
      unawaited(_processQueue());
    });
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    try {
      if (!_networkAvailable) return;

      final now = DateTime.now();
      final uploads = _uploadQueue.values.toList(growable: false);

      for (final upload in uploads) {
        if (now.isBefore(upload.nextRetryAt)) continue;
        if (_inFlight.contains(upload.id)) continue;

        _inFlight.add(upload.id);
        try {
          await _processSingle(upload);
        } finally {
          _inFlight.remove(upload.id);
        }
      }
    } finally {
      _processing = false;
      await _persistQueue();
    }
  }

  Future<void> _processSingle(PendingUpload upload) async {
    final pending = _uploadQueue[upload.id];
    if (pending == null) return;

    final startState = pending.retryCount > 0
        ? UploadQueueState.retrying
        : UploadQueueState.uploading;
    _states[pending.id] = startState;
    _emit(pending, startState);

    try {
      final ref = FirebaseStorage.instance.ref(pending.storagePath);
      await ref.putFile(
        File(pending.filePath),
        SettableMetadata(
          cacheControl: _cacheControl,
          contentType: 'image/jpeg',
        ),
      );
      final url = await ref.getDownloadURL();

      final sourceHash = _sourceHashByUploadId[pending.id] ??
          await generateFileHash(File(pending.filePath));
      await _storeUploadMemo(
        storagePath: pending.storagePath,
        hash: sourceHash,
        url: url,
      );

      final onSuccess = _onSuccessById[pending.id];
      if (onSuccess != null) {
        await onSuccess(url);
      }

      _uploadQueue.remove(pending.id);
      _states[pending.id] = UploadQueueState.success;
      _emit(pending, UploadQueueState.success, downloadUrl: url);

      final completer = _completerById.remove(pending.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(url);
      }

      _onSuccessById.remove(pending.id);
      _states.remove(pending.id);
      _sourceHashByUploadId.remove(pending.id);
    } catch (e) {
      pending.retryCount++;

      // Exponential backoff: 5s, 15s, 30s, 60s, 120s — capped at 120s.
      final delaySec = [5, 15, 30, 60, 120]
          .elementAtOrNull(pending.retryCount - 1) ?? 120;
      pending.nextRetryAt = DateTime.now().add(Duration(seconds: delaySec));

      final isPermanentFailure = pending.retryCount >= _maxRetries;
      final state = isPermanentFailure
          ? UploadQueueState.failed
          : UploadQueueState.retrying;
      _states[pending.id] = state;
      _emit(pending, state, error: e.toString());

      debugPrint(
        '[upload] ${isPermanentFailure ? 'FAILED' : 'retry ${pending.retryCount}/$_maxRetries'}'
        ' storagePath=${pending.storagePath} error=$e'
        '${isPermanentFailure ? '' : ' nextRetryIn=${delaySec}s'}',
      );

      if (isPermanentFailure) {
        // Complete any waiting caller with the error so they don't hang forever.
        final completer = _completerById.remove(pending.id);
        if (completer != null && !completer.isCompleted) {
          completer.completeError(e, StackTrace.current);
        }
        _onSuccessById.remove(pending.id);
        _sourceHashByUploadId.remove(pending.id);
        _states.remove(pending.id);
      }
    }
  }

  String _normalizeStoragePath(String storagePath) {
    var normalized =
        storagePath.startsWith('/') ? storagePath.substring(1) : storagePath;
    final lastSlash = normalized.lastIndexOf('/');
    final fileName =
        lastSlash == -1 ? normalized : normalized.substring(lastSlash + 1);
    if (fileName.isEmpty) return normalized;

    final dot = fileName.lastIndexOf('.');
    if (dot == -1) {
      return '$normalized.jpg';
    }

    final ext = fileName.substring(dot + 1).toLowerCase();
    if (ext == 'jpg') return normalized;

    final withoutExt =
        normalized.substring(0, normalized.length - ext.length - 1);
    return '$withoutExt.jpg';
  }

  Future<String> generateFileHash(File file) async {
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
  }

  Future<File> compressImage(File file, String type) async {
    int quality;
    int maxWidth;

    if (type == 'profile') {
      quality = 70;
      maxWidth = 512;
    } else if (type == 'event_thumb') {
      quality = 50;
      maxWidth = 300;
    } else {
      quality = 70;
      maxWidth = 1280;
    }

    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        '${file.path}_compressed.jpg',
        quality: quality,
        minWidth: maxWidth,
        minHeight: maxWidth,
        format: CompressFormat.jpeg,
        keepExif: false,
      );

      if (result == null) return file;
      return File(result.path);
    } catch (_) {
      return file;
    }
  }

  void _emit(
    PendingUpload upload,
    UploadQueueState state, {
    String? downloadUrl,
    String? error,
  }) {
    if (_statusController.isClosed) return;
    _statusController.add(
      UploadStatusEvent(
        upload: upload,
        state: state,
        downloadUrl: downloadUrl,
        error: error,
      ),
    );
  }
}
