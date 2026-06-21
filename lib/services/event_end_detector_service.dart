import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finds events the current user participated in that have recently ended
/// and haven't been recapped yet.
///
/// Returns a list of ended event maps: [{id, title, bannerUrl}]
class EventEndDetectorService {
  static const _shownPrefix = 'recap_shown_';

  Future<List<Map<String, String>>> findEndedUnrecappedEvents() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const [];

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24));

    try {
      // Query events where: user is a participant, event has ended in last 24h
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where('participants', arrayContains: uid)
          .where('status', isEqualTo: 'active')
          .get();

      final result = <Map<String, String>>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        final endRaw = data['endAt'] ?? data['endTime'];
        DateTime? endAt;
        if (endRaw is Timestamp) endAt = endRaw.toDate();

        if (endAt == null) continue;
        // Only show if ended in the last 24 hours
        if (endAt.isAfter(now) || endAt.isBefore(cutoff)) continue;

        final eventId = doc.id;
        final shownKey = '$_shownPrefix${uid}_$eventId';
        if (prefs.getBool(shownKey) == true) continue;

        // Check if user already submitted recap
        final participantDoc = await FirebaseFirestore.instance
            .collection('event_participants')
            .doc(eventId)
            .collection('users')
            .doc(uid)
            .get();

        final recapAt = participantDoc.data()?['recapSubmittedAt'];
        if (recapAt != null) {
          // Mark as shown so we don't check again
          await prefs.setBool(shownKey, true);
          continue;
        }

        result.add({
          'id': eventId,
          'title': (data['title'] ?? '').toString(),
          'bannerUrl':
              (data['bannerUrl'] ?? data['thumbnailUrl'] ?? '').toString(),
        });
      }

      return result;
    } catch (_) {
      return const [];
    }
  }

  /// Call after the user submits or skips a recap to prevent re-showing.
  static Future<void> markRecapShown(String eventId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_shownPrefix${uid}_$eventId',
        true); // ignore: unnecessary_brace_in_string_interps
  }
}
