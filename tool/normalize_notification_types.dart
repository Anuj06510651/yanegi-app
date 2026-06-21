import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yanegi/services/notification_types.dart';

/// One-time safe migration utility for legacy notification type values.
///
/// Usage (while authenticated in app/dev environment):
///   dart run tool/normalize_notification_types.dart
Future<void> main() async {
  final firestore = FirebaseFirestore.instance;
  const pageSize = 200;

  DocumentSnapshot<Map<String, dynamic>>? cursor;
  var totalUpdated = 0;

  while (true) {
    Query<Map<String, dynamic>> query = firestore
        .collection('notifications')
        .orderBy('createdAt')
        .limit(pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) break;

    final batch = firestore.batch();
    var batchUpdates = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final currentType = (data['type'] ?? '').toString();
      final normalizedType = normalizeType(currentType);
      if (normalizedType == currentType) continue;

      batch.update(doc.reference, {
        'type': normalizedType,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batchUpdates++;
    }

    if (batchUpdates > 0) {
      await batch.commit();
      totalUpdated += batchUpdates;
    }

    cursor = snapshot.docs.last;
    if (snapshot.docs.length < pageSize) break;
  }

  // ignore: avoid_print
  print('Notification type migration complete. Updated: $totalUpdated docs.');
}
