import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Owner-only "Saved Events" store.
///
/// Saved events live in a **private** subcollection: `users/{uid}/savedEvents/{eventId}`.
/// Only the owner reads or writes this path — saved events are NEVER exposed on
/// any other user's profile. We store only a pointer (`eventId` + `savedAt`); the
/// event itself is always re-fetched from the canonical `events/{eventId}` doc so
/// the saved list reflects current event data (and silently drops deleted events).
///
/// Backward compatibility: this is a NEW private subcollection under the user's
/// own doc. It does not touch any existing field or collection. Firestore rules
/// must allow the owner read/write on `users/{uid}/savedEvents/**`
/// (the common `match /users/{uid}/{document=**}` owner rule already covers this).
class SavedEventsService {
  SavedEventsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> _savedCol(String uid) =>
      _firestore.collection('users').doc(uid).collection('savedEvents');

  /// Live "is this event saved by me" flag for the current user.
  Stream<bool> isSavedStream(String eventId) {
    final uid = _uid;
    if (uid.isEmpty || eventId.trim().isEmpty) {
      return Stream<bool>.value(false);
    }
    return _savedCol(uid)
        .doc(eventId)
        .snapshots()
        .map((snap) => snap.exists)
        .handleError((_) {});
  }

  Future<bool> isSaved(String eventId) async {
    final uid = _uid;
    if (uid.isEmpty || eventId.trim().isEmpty) return false;
    try {
      final snap = await _savedCol(uid).doc(eventId).get();
      return snap.exists;
    } catch (e) {
      debugPrint('SavedEventsService.isSaved failed: $e');
      return false;
    }
  }

  /// Saves an event for the current user. Idempotent.
  Future<bool> saveEvent(String eventId) async {
    final uid = _uid;
    if (uid.isEmpty || eventId.trim().isEmpty) return false;
    try {
      await _savedCol(uid).doc(eventId).set(<String, dynamic>{
        'eventId': eventId,
        'savedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('SavedEventsService.saveEvent failed: $e');
      return false;
    }
  }

  /// Removes an event from the current user's saved list. Idempotent.
  Future<bool> unsaveEvent(String eventId) async {
    final uid = _uid;
    if (uid.isEmpty || eventId.trim().isEmpty) return false;
    try {
      await _savedCol(uid).doc(eventId).delete();
      return true;
    } catch (e) {
      debugPrint('SavedEventsService.unsaveEvent failed: $e');
      return false;
    }
  }

  /// Toggles saved state. Returns the new state (`true` = now saved).
  Future<bool> toggleSaved(String eventId) async {
    final saved = await isSaved(eventId);
    if (saved) {
      await unsaveEvent(eventId);
      return false;
    }
    await saveEvent(eventId);
    return true;
  }

  /// Live ordered list of the current user's saved event IDs (most recent first).
  Stream<List<String>> savedEventIdsStream() {
    final uid = _uid;
    if (uid.isEmpty) return Stream<List<String>>.value(const <String>[]);
    return _savedCol(uid)
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toList(growable: false))
        .handleError((_) {});
  }

  Future<List<String>> getSavedEventIds() async {
    final uid = _uid;
    if (uid.isEmpty) return const <String>[];
    try {
      final snap =
          await _savedCol(uid).orderBy('savedAt', descending: true).get();
      return snap.docs.map((d) => d.id).toList(growable: false);
    } catch (e) {
      debugPrint('SavedEventsService.getSavedEventIds failed: $e');
      return const <String>[];
    }
  }
}
