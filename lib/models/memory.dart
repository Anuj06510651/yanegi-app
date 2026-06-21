import 'package:cloud_firestore/cloud_firestore.dart';

/// Visibility levels for a memory.
enum MemoryVisibility {
  public,
  friendsOnly,
  private_,
}

/// Extension to convert enum to/from Firestore string values.
extension MemoryVisibilityExtension on MemoryVisibility {
  String get value {
    switch (this) {
      case MemoryVisibility.public:
        return 'public';
      case MemoryVisibility.friendsOnly:
        return 'friendsOnly';
      case MemoryVisibility.private_:
        return 'private';
    }
  }

  String get displayName {
    switch (this) {
      case MemoryVisibility.public:
        return 'Public';
      case MemoryVisibility.friendsOnly:
        return 'Friends Only';
      case MemoryVisibility.private_:
        return 'Only Me';
    }
  }

  static MemoryVisibility fromString(String? value) {
    switch (value) {
      case 'friendsOnly':
        return MemoryVisibility.friendsOnly;
      case 'private':
        return MemoryVisibility.private_;
      default:
        return MemoryVisibility.public;
    }
  }
}

/// Represents a memory created from an event.
/// Stored in the Firestore `memories/` collection.
class Memory {
  final String id;
  final String userId;
  final String eventId;
  final String eventTitle;
  final String description;
  final String? imageUrl;
  final List<String> taggedUsers;
  final MemoryVisibility visibility;
  final DateTime createdAt;

  const Memory({
    required this.id,
    required this.userId,
    required this.eventId,
    this.eventTitle = '',
    this.description = '',
    this.imageUrl,
    this.taggedUsers = const [],
    this.visibility = MemoryVisibility.public,
    required this.createdAt,
  });

  String get caption => description;

  factory Memory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Memory(
      id: doc.id,
      userId: data['userId'] ?? '',
      eventId: data['eventId'] ?? '',
      eventTitle: data['eventTitle'] ?? '',
  description: (data['description'] ?? data['caption'] ?? '').toString(),
      imageUrl: data['imageUrl'],
      taggedUsers: List<String>.from(data['taggedUsers'] ?? []),
      visibility: MemoryVisibilityExtension.fromString(data['visibility']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'description': description,
  'caption': description,
      'imageUrl': imageUrl,
      'taggedUsers': taggedUsers,
      'visibility': visibility.value,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Memory copyWith({
    String? description,
    String? imageUrl,
    List<String>? taggedUsers,
    MemoryVisibility? visibility,
  }) {
    return Memory(
      id: id,
      userId: userId,
      eventId: eventId,
      eventTitle: eventTitle,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      taggedUsers: taggedUsers ?? this.taggedUsers,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt,
    );
  }
}
