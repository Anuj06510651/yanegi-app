import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Production-grade presence service.
///
/// Write policy:
/// - online=true : on resume + heartbeat every 60 s (while foregrounded).
///   Debounced 3 s to absorb the inactive→resumed burst without double-writes.
/// - online=false: written IMMEDIATELY (no debounce) on paused and detached.
///   Bypassing the debounce is critical — on Android the OS can kill the
///   process within the 3-second window, leaving the user stuck as "Online".
/// - detached: now triggers an immediate offline write (was previously skipped).
/// - Heartbeat is paused (timer cancelled) while the app is backgrounded.
///
/// Billing impact vs old service:
/// - Cold start: 2 writes → 1 (auth sub covers it; explicit write removed).
/// - Background cycle: 2 writes → 1 (inactive skipped; only paused writes).
/// - Heartbeat period: 30 s → 60 s.
/// - Offline heartbeat: was writing every 30 s → now suppressed entirely.
class UserPresenceService with WidgetsBindingObserver {
  UserPresenceService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Duration heartbeatInterval = const Duration(seconds: 60),
  })  : _firestoreOverride = firestore,
        _authOverride = auth,
        _heartbeatInterval = heartbeatInterval;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;
  final Duration _heartbeatInterval;

  // Debounce window: collapses rapid lifecycle bursts (inactive → paused,
  // paused → inactive → resumed) into a single Firestore write.
  static const Duration _debounceDuration = Duration(seconds: 3);

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  bool get _canUseDefaultFirebase => Firebase.apps.isNotEmpty;

  Timer? _heartbeatTimer;
  Timer? _debounceTimer;
  StreamSubscription<User?>? _authSub;
  bool _started = false;

  // Tracks the last successfully written state for deduplication.
  bool? _lastWrittenIsOnline;
  DateTime? _lastWriteTime;
  // Tracks the most recently requested state so the debounce fires the
  // correct value after any intermediate state changes during the window.
  bool _pendingIsOnline = true;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (_firestoreOverride == null && !_canUseDefaultFirebase) {
      return;
    }

    WidgetsBinding.instance.addObserver(this);

    // authStateChanges() emits the current user immediately on subscription.
    // This single emission handles the cold-start online write without needing
    // a separate explicit _writePresence call after this block.
    _authSub = _auth.authStateChanges().listen((user) {
      if (user == null) return;
      _scheduleWrite(isOnline: true, reason: 'auth-state');
    });

    _startHeartbeat();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    _cancelHeartbeat();
    _debounceTimer?.cancel();
    _debounceTimer = null;

    await _authSub?.cancel();
    _authSub = null;

    WidgetsBinding.instance.removeObserver(this);

    // Bypass debounce on explicit stop so the offline write is immediate.
    await _writePresenceNow(isOnline: false, bumpLastSeen: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handleLifecycleState(state);
  }

  // Exposed for unit tests.
  void handleLifecycleStateForTest(AppLifecycleState state) =>
      _handleLifecycleState(state);

  void _handleLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Debounced — absorbs the inactive→resumed→inactive burst that fires
        // when the user quickly switches tasks without fully leaving.
        debugPrint('PRESENCE STATE CHANGED: lifecycle=resumed → online=true');
        _startHeartbeat();
        _scheduleWrite(isOnline: true, reason: 'lifecycle-resumed');
        break;

      case AppLifecycleState.paused:
        // User minimised / switched away. Cancel any pending online debounce
        // and write offline IMMEDIATELY — no debounce — because the OS can
        // kill the process within seconds on low-memory Android devices,
        // leaving the user stuck as "Online" if we wait.
        debugPrint('PRESENCE STATE CHANGED: lifecycle=paused → offline (immediate)');
        _cancelHeartbeat();
        _debounceTimer?.cancel();
        _debounceTimer = null;
        unawaited(_writePresenceNow(isOnline: false, bumpLastSeen: true));
        break;

      case AppLifecycleState.detached:
        // Process is being killed (Android back-stack clear, force-stop, OOM).
        // This is the last chance to write — must be immediate and synchronous
        // where possible. Also cancels heartbeat to avoid a timer firing on a
        // dying isolate.
        debugPrint('PRESENCE STATE CHANGED: lifecycle=detached → offline (immediate)');
        _cancelHeartbeat();
        _debounceTimer?.cancel();
        _debounceTimer = null;
        unawaited(_writePresenceNow(isOnline: false, bumpLastSeen: true));
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Transient states — skip writes.
        // inactive: phone call overlay, notification shade, app-switcher enter.
        // hidden: iOS app-switcher screenshot frame.
        // These fire immediately before paused and immediately after resumed;
        // the paused/resumed handlers above own the real state transitions.
        debugPrint('PRESENCE WRITE SKIPPED: transient lifecycle state=$state');
        break;
    }
  }

  /// Requests a write after a debounce window.
  ///
  /// Deduplication: if [isOnline] is unchanged from the last written value and
  /// the write happened recently (< heartbeatInterval − 5 s), skip entirely.
  /// This prevents redundant writes from auth token refreshes and rapid
  /// lifecycle transitions.
  void _scheduleWrite({required bool isOnline, required String reason}) {
    _pendingIsOnline = isOnline;

    // Dedup: same state written recently → no-op.
    if (_lastWrittenIsOnline == isOnline) {
      final lastWrite = _lastWriteTime;
      if (lastWrite != null) {
        final elapsed = DateTime.now().difference(lastWrite);
        if (elapsed < _heartbeatInterval - const Duration(seconds: 5)) {
          debugPrint(
            'PRESENCE WRITE SKIPPED: isOnline=$isOnline unchanged, '
            'last write ${elapsed.inSeconds}s ago — reason=$reason',
          );
          return;
        }
      }
    }

    // Cancel any existing debounce and restart the window.
    if (_debounceTimer != null) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
    }
    debugPrint(
      'PRESENCE TIMER CREATED: debounce ${_debounceDuration.inSeconds}s '
      '— isOnline=$isOnline reason=$reason',
    );
    _debounceTimer = Timer(_debounceDuration, () {
      debugPrint(
        'PRESENCE TIMER DISPOSED: debounce fired → writing isOnline=$_pendingIsOnline',
      );
      _debounceTimer = null;
      unawaited(
        _writePresenceNow(
          isOnline: _pendingIsOnline,
          bumpLastSeen: !_pendingIsOnline,
        ),
      );
    });
  }

  void _startHeartbeat() {
    if (_heartbeatTimer != null) {
      // Timer already running — guard against double-start on rapid resumes.
      return;
    }
    debugPrint(
      'PRESENCE TIMER CREATED: heartbeat every ${_heartbeatInterval.inSeconds}s',
    );
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!_started) return;
      // Suppress heartbeat while offline — no value in rewriting online=false.
      if (!_pendingIsOnline) {
        debugPrint('PRESENCE WRITE SKIPPED: heartbeat suppressed — offline');
        return;
      }
      debugPrint('PRESENCE HEARTBEAT: writing isOnline=true');
      unawaited(_writePresenceNow(isOnline: true, bumpLastSeen: false));
    });
  }

  void _cancelHeartbeat() {
    if (_heartbeatTimer != null) {
      debugPrint('PRESENCE TIMER DISPOSED: heartbeat cancelled');
      _heartbeatTimer!.cancel();
      _heartbeatTimer = null;
    }
  }

  Future<void> _writePresenceNow({
    required bool isOnline,
    required bool bumpLastSeen,
  }) async {
    if (_firestoreOverride == null && !_canUseDefaultFirebase) {
      return;
    }

    final uid = _auth.currentUser?.uid ?? '';
    if (uid.trim().isEmpty) return;

    final payload = <String, dynamic>{
      'isOnline': isOnline,
      'presenceUpdatedAt': FieldValue.serverTimestamp(),
    };

    if (bumpLastSeen) {
      // Single canonical offline timestamp — `lastSeenAt` removed.
      payload['lastSeen'] = FieldValue.serverTimestamp();
    }

    debugPrint('PRESENCE STATE CHANGED: uid=$uid isOnline=$isOnline writing…');

    try {
      await _firestore.collection('user_presence').doc(uid).set(
            payload,
            SetOptions(merge: true),
          );
      _lastWrittenIsOnline = isOnline;
      _lastWriteTime = DateTime.now();
      debugPrint('PRESENCE STATE CHANGED: write success isOnline=$isOnline');
    } catch (e) {
      debugPrint('PRESENCE STATE CHANGED: write failed — $e');
      // Presence is best-effort; never crash UX on write failures.
    }
  }
}
