import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Three-way arrival intent for an event participant. Stored on the
/// participant doc as a single string field so it costs ONE write per status
/// change and ZERO new reads beyond what the participants subscription
/// already pays for.
enum ArrivalStatus {
  none,
  onMyWay,
  arrived,
  runningLate,
}

ArrivalStatus parseArrivalStatus(dynamic raw) {
  if (raw is! String) return ArrivalStatus.none;
  switch (raw) {
    case 'on_my_way':
      return ArrivalStatus.onMyWay;
    case 'arrived':
      return ArrivalStatus.arrived;
    case 'running_late':
      return ArrivalStatus.runningLate;
    default:
      return ArrivalStatus.none;
  }
}

String arrivalStatusToWire(ArrivalStatus status) {
  switch (status) {
    case ArrivalStatus.onMyWay:
      return 'on_my_way';
    case ArrivalStatus.arrived:
      return 'arrived';
    case ArrivalStatus.runningLate:
      return 'running_late';
    case ArrivalStatus.none:
      return '';
  }
}

String arrivalStatusEmoji(ArrivalStatus status) {
  switch (status) {
    case ArrivalStatus.onMyWay:
      return '🚶';
    case ArrivalStatus.arrived:
      return '📍';
    case ArrivalStatus.runningLate:
      return '⏳';
    case ArrivalStatus.none:
      return '';
  }
}

String arrivalStatusLabel(ArrivalStatus status) {
  switch (status) {
    case ArrivalStatus.onMyWay:
      return 'On my way';
    case ArrivalStatus.arrived:
      return 'Reached';
    case ArrivalStatus.runningLate:
      return 'Running late';
    case ArrivalStatus.none:
      return '';
  }
}

/// Writes only — reads come from the participants subscription the parent
/// already keeps open. Throttles writes to one per [debounce] (default 10s)
/// per user to prevent spam-tapping from running up write counts.
class ArrivalStatusService {
  ArrivalStatusService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Duration debounce = const Duration(seconds: 10),
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _debounce = debounce;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Duration _debounce;
  final Map<String, DateTime> _lastWriteByEvent = {};

  /// Sets the arrival status for the signed-in user on the given event.
  ///
  /// Writes:
  ///   - `event_participants/{eventId}/users/{uid}` patches `arrivalStatus`
  ///     and `arrivalStatusAt`.
  ///
  /// Returns `true` if the write was actually attempted; `false` if it was
  /// debounced (recent identical write within [_debounce]).
  Future<bool> setStatus({
    required String eventId,
    required ArrivalStatus status,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty || eventId.trim().isEmpty) return false;

    final last = _lastWriteByEvent[eventId];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _debounce) {
      debugPrint(
          'ARRIVAL DEBOUNCED: eventId=$eventId uid=$uid (last=${now.difference(last).inSeconds}s ago)');
      return false;
    }
    _lastWriteByEvent[eventId] = now;

    final ref = _firestore
        .collection('event_participants')
        .doc(eventId)
        .collection('users')
        .doc(uid);

    final wire = arrivalStatusToWire(status);
    try {
      await ref.set(
        {
          'arrivalStatus': wire,
          'arrivalStatusAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('ARRIVAL WRITE: eventId=$eventId uid=$uid status=$wire');
      return true;
    } catch (e, stack) {
      debugPrint('ARRIVAL WRITE FAILED: $e');
      debugPrintStack(stackTrace: stack);
      return false;
    }
  }
}
