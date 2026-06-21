import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/memory.dart';
import 'media_storage_service.dart';

/// Service for creating, reading, deleting, and paginating memories.
/// All memories are stored in the top-level `memories/` Firestore collection.
class MemoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final MediaStorageService _mediaStorageService = MediaStorageService();

  CollectionReference get _memories => _firestore.collection('memories');
  CollectionReference get _events => _firestore.collection('events');

  String? get _currentUid => _auth.currentUser?.uid;

  // ─── CREATE ───────────────────────────────────────────────

  /// Creates a new memory. Uploads image to Storage if provided.
  Future<Memory?> createMemory({
    required String eventId,
    required String eventTitle,
    required String description,
    File? imageFile,
    List<String> taggedUsers = const [],
    MemoryVisibility visibility = MemoryVisibility.public,
  }) async {
    final uid = _currentUid;
    if (uid == null) {
      print('TESTING [ERROR]: Cannot create memory. No authenticated user.');
      return null;
    }

    String? imageUrl;

    // Upload image to Firebase Storage
    if (imageFile != null && imageFile.existsSync()) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        imageUrl = await _mediaStorageService.uploadImageReliable(
          localFilePath: imageFile.path,
          storagePath: 'memories/$uid/${timestamp}_memory.jpg',
          type: 'memory',
        );
        print('TESTING [STORAGE]: Memory image uploaded: $imageUrl');
      } catch (e) {
        print('TESTING [ERROR]: Memory image upload failed: $e');
      }
    }

    try {
      final docRef = await _memories.add({
        'userId': uid,
        'eventId': eventId,
        'eventTitle': eventTitle,
        'description': description,
        'caption': description,
        'imageUrl': imageUrl,
        'taggedUsers': taggedUsers,
        'visibility': visibility.value,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('TESTING [FIRESTORE]: Memory created with ID: ${docRef.id}');

      return Memory(
        id: docRef.id,
        userId: uid,
        eventId: eventId,
        eventTitle: eventTitle,
        description: description,
        imageUrl: imageUrl,
        taggedUsers: taggedUsers,
        visibility: visibility,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      print('TESTING [ERROR]: Memory creation failed: $e');
      return null;
    }
  }

  // ─── READ ─────────────────────────────────────────────────

  /// Fetches paginated memories for a specific user.
  /// Applies visibility filtering based on the viewer's relationship.
  Future<List<Memory>> getMemoriesForUser(
    String uid, {
    int limit = 12,
    DocumentSnapshot? lastDoc,
    String? viewerUid,
  }) async {
    try {
      Query query = _memories
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      final memories =
          snapshot.docs.map((doc) => Memory.fromFirestore(doc)).toList();

      // Filter by visibility
      final effectiveViewer = viewerUid ?? _currentUid;
      if (effectiveViewer == uid) {
        // Viewing own profile — show all
        return memories;
      }

      // Check if viewer is a friend
      bool isFriend = false;
      if (effectiveViewer != null) {
        final viewerDoc =
            await _firestore.collection('users').doc(effectiveViewer).get();
        final viewerFriends = List<String>.from(
          (viewerDoc.data())?['friends'] ?? [],
        );
        isFriend = viewerFriends.contains(uid);
      }

      return memories.where((m) {
        if (m.visibility == MemoryVisibility.public) return true;
        if (m.visibility == MemoryVisibility.friendsOnly && isFriend)
          return true;
        return false; // private memories hidden from others
      }).toList();
    } catch (e) {
      print('TESTING [ERROR]: Failed to fetch memories for $uid: $e');
      return [];
    }
  }

  /// Returns the raw QuerySnapshot for pagination cursor tracking.
  Future<QuerySnapshot> getMemoriesSnapshot(
    String uid, {
    int limit = 12,
    DocumentSnapshot? lastDoc,
  }) async {
    Query query = _memories
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }

    return query.get();
  }

  /// Stream for a single memory document (for detail view).
  Stream<Memory?> getMemoryStream(String memoryId) {
    return _memories.doc(memoryId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Memory.fromFirestore(doc);
    });
  }

  // ─── DELETE ───────────────────────────────────────────────

  /// Deletes a memory. Only the owner can delete.
  Future<bool> deleteMemory(String memoryId) async {
    final uid = _currentUid;
    if (uid == null) return false;

    try {
      final doc = await _memories.doc(memoryId).get();
      if (!doc.exists) return false;

      final data = doc.data() as Map<String, dynamic>;
      if (data['userId'] != uid) {
        print('TESTING [ERROR]: Cannot delete memory — not the owner.');
        return false;
      }

      // Delete image from Storage if exists
      final imageUrl = data['imageUrl'] as String?;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          await _storage.refFromURL(imageUrl).delete();
          print('TESTING [STORAGE]: Memory image deleted.');
        } catch (e) {
          print('TESTING [WARNING]: Could not delete memory image: $e');
        }
      }

      await _memories.doc(memoryId).delete();
      print('TESTING [FIRESTORE]: Memory $memoryId deleted.');
      return true;
    } catch (e) {
      print('TESTING [ERROR]: Memory deletion failed: $e');
      return false;
    }
  }

  // ─── EVENTS HELPER ────────────────────────────────────────

  /// Fetches events the user has joined or hosted (for the event picker).
  Future<List<Map<String, dynamic>>> getUserJoinedEvents(String uid) async {
    try {
      // Events where user is a participant
      final participantQuery = await _events
          .where('participants', arrayContains: uid)
          .orderBy('created_at', descending: true)
          .limit(50)
          .get();

      final events = participantQuery.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'title': data['title'] ?? 'Untitled Event',
          'emoji': data['emoji'] ?? '📍',
          'created_at': data['created_at'],
          'participants': List<String>.from(data['participants'] ?? []),
          'host_id': data['host_id'] ?? data['hostId'] ?? '',
        };
      }).toList();

      return events;
    } catch (e) {
      print('TESTING [ERROR]: Failed to fetch user events: $e');
      return [];
    }
  }
}
