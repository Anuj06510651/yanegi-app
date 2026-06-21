import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Sliding-window rate limiter backed by Firestore so limits persist across
/// app restarts and devices for the same user.
///
/// Each rate-limit "bucket" lives at:
///   `user_quotas/{uid}/buckets/{action}`
///
/// Document fields:
///   - `events`: List<Timestamp>    — recorded event times within window
///   - `updatedAt`: serverTimestamp — for debugging only
///
/// Important: this is a CLIENT-SIDE limiter — it stops well-behaved clients
/// from exceeding configured quotas and provides UI hooks ("please wait"
/// messages). It does NOT replace server-side enforcement against malicious
/// users; Firestore rules + Cloud Functions are the authoritative line of
/// defense (see CLAUDE.md "Rate Limit Spec").
///
/// Limits are defined centrally in [RateLimitSpec]. Each spec defines a window
/// AND a max-events count; the action is denied if [events] within the window
/// >= max.
class RateLimitSpec {
  const RateLimitSpec({
    required this.action,
    required this.window,
    required this.maxEvents,
  });

  /// Logical key (e.g. `friend_request_hour`). Must be unique per limit.
  final String action;
  final Duration window;
  final int maxEvents;

  /// Human-friendly reason shown to the UI when blocked.
  String get blockedMessage =>
      'You’re doing that a little too quickly. Please wait a moment and try again.';
}

class RateLimitResult {
  const RateLimitResult({
    required this.allowed,
    required this.remaining,
    required this.retryAfter,
  });

  final bool allowed;
  final int remaining;
  final Duration retryAfter;
}

class RateLimiterService {
  RateLimiterService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // ─── Canonical action specs ───────────────────────────────────────────────
  // Aligned with CLAUDE.md "Rate Limit Spec". Change here = change everywhere.

  static const friendRequestPerHour = RateLimitSpec(
    action: 'friend_request_hour',
    window: Duration(hours: 1),
    maxEvents: 30,
  );
  static const friendRequestPerDay = RateLimitSpec(
    action: 'friend_request_day',
    window: Duration(days: 1),
    maxEvents: 100,
  );

  static const eventJoinPerHour = RateLimitSpec(
    action: 'event_join_hour',
    window: Duration(hours: 1),
    maxEvents: 50,
  );

  static const eventCreatePerDay = RateLimitSpec(
    action: 'event_create_day',
    window: Duration(days: 1),
    maxEvents: 10,
  );

  static const dmCreatePerDay = RateLimitSpec(
    action: 'dm_create_day',
    window: Duration(days: 1),
    maxEvents: 50,
  );

  static const profileUpdatePerDay = RateLimitSpec(
    action: 'profile_update_day',
    window: Duration(days: 1),
    maxEvents: 30,
  );

  static const photoUploadPerDay = RateLimitSpec(
    action: 'photo_upload_day',
    window: Duration(days: 1),
    maxEvents: 20,
  );

  static const bannerUploadPerDay = RateLimitSpec(
    action: 'banner_upload_day',
    window: Duration(days: 1),
    maxEvents: 10,
  );

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Returns `true` if the action is currently allowed for the signed-in user.
  /// Does NOT record the event — callers should call [record] after the action
  /// commits, so failed actions don't burn quota.
  ///
  /// On network/permission failure this conservatively returns `allowed: true`
  /// so a transient Firestore outage never blocks the user. Server-side
  /// enforcement (rules + Cloud Functions) remains authoritative.
  Future<RateLimitResult> check(RateLimitSpec spec) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return const RateLimitResult(
        allowed: false,
        remaining: 0,
        retryAfter: Duration.zero,
      );
    }
    try {
      final ref = _bucketRef(uid, spec);
      final snap = await ref.get();
      final now = DateTime.now();
      final cutoff = now.subtract(spec.window);
      final raw = (snap.data()?['events'] as List?) ?? const [];
      final times = _withinWindow(raw, cutoff);
      final remaining = (spec.maxEvents - times.length).clamp(0, spec.maxEvents);

      if (times.length >= spec.maxEvents) {
        final oldest = times.first;
        final retryAfter = oldest.add(spec.window).difference(now);
        return RateLimitResult(
          allowed: false,
          remaining: 0,
          retryAfter:
              retryAfter.isNegative ? Duration.zero : retryAfter,
        );
      }
      return RateLimitResult(
        allowed: true,
        remaining: remaining,
        retryAfter: Duration.zero,
      );
    } catch (e) {
      // Fail open — never strand the user behind a transient Firestore error.
      // Server-side rules still enforce abuse limits where wired.
      debugPrint('RateLimiter.check fail-open (${spec.action}): $e');
      return RateLimitResult(
        allowed: true,
        remaining: spec.maxEvents,
        retryAfter: Duration.zero,
      );
    }
  }

  /// Records an event for [spec]. Should be called immediately AFTER the
  /// guarded action succeeds (or, for actions whose result the server
  /// determines, immediately after the request is dispatched).
  Future<void> record(RateLimitSpec spec) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final ref = _bucketRef(uid, spec);
      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(ref);
        final now = DateTime.now();
        final cutoff = now.subtract(spec.window);
        final raw = (snap.data()?['events'] as List?) ?? const [];
        final trimmed = _withinWindow(raw, cutoff)
          ..add(now);
        // Cap the array to avoid runaway growth on hot actions.
        final capped = trimmed.length > spec.maxEvents + 10
            ? trimmed.sublist(trimmed.length - spec.maxEvents - 10)
            : trimmed;
        txn.set(
          ref,
          {
            'events': capped.map((d) => Timestamp.fromDate(d)).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      // Non-fatal: a quota write failure must never break the user-visible
      // action that just succeeded. Logged for observability only.
      debugPrint('RateLimiter.record failed (${spec.action}): $e');
    }
  }

  /// Convenience: check + record in one call when the action is best-effort
  /// (e.g. analytics-like events) and the caller doesn't need to react to a
  /// block decision. Returns whether the action was allowed.
  Future<bool> tryConsume(RateLimitSpec spec) async {
    final result = await check(spec);
    if (!result.allowed) return false;
    await record(spec);
    return true;
  }

  // ─── Internals ────────────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _bucketRef(
    String uid,
    RateLimitSpec spec,
  ) {
    return _firestore
        .collection('user_quotas')
        .doc(uid)
        .collection('buckets')
        .doc(spec.action);
  }

  List<DateTime> _withinWindow(List<dynamic> raw, DateTime cutoff) {
    final out = <DateTime>[];
    for (final v in raw) {
      DateTime? dt;
      if (v is Timestamp) {
        dt = v.toDate();
      } else if (v is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(v);
      }
      if (dt != null && dt.isAfter(cutoff)) out.add(dt);
    }
    out.sort();
    return out;
  }
}
