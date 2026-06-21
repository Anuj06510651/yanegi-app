import 'package:cloud_firestore/cloud_firestore.dart';
import 'social_link.dart';
import '../utils/media_url_resolver.dart';

/// Central profile model that maps to the Firestore `users/{uid}` document.
/// Aggregates identity, social, and stats data for display and editing.
class UserProfile {
  final String uid;
  final String name;
  final String username;
  final String bio;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? gender;
  final DateTime? dob;
  final List<String> vibes;
  final List<SocialLink> socialLinks;
  final List<String> friends;
  final List<String> blockedUsers;
  final int eventsCreated;
  final int eventsJoined;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.uid,
    this.name = '',
    this.username = '',
    this.bio = '',
    this.avatarUrl,
    this.bannerUrl,
    this.gender,
    this.dob,
    this.vibes = const [],
    this.socialLinks = const [],
    this.friends = const [],
    this.blockedUsers = const [],
    this.eventsCreated = 0,
    this.eventsJoined = 0,
    this.createdAt,
    this.updatedAt,
  });

  int get friendsCount => friends.length;

  bool isFriendWith(String otherUid) => friends.contains(otherUid);

  bool hasBlocked(String otherUid) => blockedUsers.contains(otherUid);

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserProfile(
      uid: doc.id,
      name: data['name'] ?? '',
      username: data['username'] ?? '',
      bio: data['bio'] ?? '',
      avatarUrl: resolveRemoteMediaUrl(<dynamic>[
        data['photoUrl'],
        data['avatarUrl'],
        data['avatar_url'],
        data['profileImage'],
        data['profile_image'],
      ]),
      bannerUrl: resolveRemoteMediaUrl(<dynamic>[
        data['bannerUrl'],
        data['banner_url'],
        data['bannerImage'],
        data['banner_image'],
      ]),
      gender: data['gender'],
      dob: data['dob'] != null ? DateTime.tryParse(data['dob']) : null,
      vibes: List<String>.from(data['vibes'] ?? []),
      socialLinks: (data['social_links'] as List<dynamic>?)
              ?.map((e) => SocialLink.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      friends: List<String>.from(data['friends'] ?? []),
      blockedUsers: List<String>.from(data['blocked_users'] ?? []),
      eventsCreated: data['events_created'] ?? 0,
      eventsJoined: data['events_joined'] ?? 0,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> data, String uid) {
    return UserProfile(
      uid: uid,
      name: data['name'] ?? '',
      username: data['username'] ?? '',
      bio: data['bio'] ?? '',
      avatarUrl: resolveRemoteMediaUrl(<dynamic>[
        data['photoUrl'],
        data['avatarUrl'],
        data['avatar_url'],
        data['profileImage'],
        data['profile_image'],
      ]),
      bannerUrl: resolveRemoteMediaUrl(<dynamic>[
        data['bannerUrl'],
        data['banner_url'],
        data['bannerImage'],
        data['banner_image'],
      ]),
      gender: data['gender'],
      dob: data['dob'] != null ? DateTime.tryParse(data['dob']) : null,
      vibes: List<String>.from(data['vibes'] ?? []),
      socialLinks: (data['social_links'] as List<dynamic>?)
              ?.map((e) => SocialLink.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      friends: List<String>.from(data['friends'] ?? []),
      blockedUsers: List<String>.from(data['blocked_users'] ?? []),
      eventsCreated: data['events_created'] ?? 0,
      eventsJoined: data['events_joined'] ?? 0,
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'username': username,
      'bio': bio,
      'avatar_url': avatarUrl,
      'banner_url': bannerUrl,
      'gender': gender,
      'dob': dob?.toIso8601String(),
      'vibes': vibes,
      'social_links': socialLinks.map((e) => e.toMap()).toList(),
      'friends': friends,
      'blocked_users': blockedUsers,
      'events_created': eventsCreated,
      'events_joined': eventsJoined,
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  /// Creates a copy with optional field overrides.
  UserProfile copyWith({
    String? name,
    String? username,
    String? bio,
    String? avatarUrl,
    String? bannerUrl,
    String? gender,
    DateTime? dob,
    List<String>? vibes,
    List<SocialLink>? socialLinks,
    List<String>? friends,
    List<String>? blockedUsers,
    int? eventsCreated,
    int? eventsJoined,
  }) {
    return UserProfile(
      uid: uid,
      name: name ?? this.name,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      vibes: vibes ?? this.vibes,
      socialLinks: socialLinks ?? this.socialLinks,
      friends: friends ?? this.friends,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      eventsCreated: eventsCreated ?? this.eventsCreated,
      eventsJoined: eventsJoined ?? this.eventsJoined,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
