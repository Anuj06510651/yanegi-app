import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUserDetail {
  final String uid;
  final String name;
  final String username;
  final String? avatarUrl;
  final String? city;
  final DateTime? createdAt;
  final DateTime? lastSeen;
  final int eventsJoined;
  final int eventsCreated;
  final int friendsCount;
  final int communitiesCount;
  final int profileCompletion; // 0-100
  final bool hasCompleted;
  final bool hasAvatar;
  final bool hasBio;
  final bool hasVibes;
  final bool hasDob;
  final List<String> vibes;
  final String? gender;
  final DateTime? dob;
  final String? bio;

  const AdminUserDetail({
    required this.uid,
    required this.name,
    required this.username,
    this.avatarUrl,
    this.city,
    this.createdAt,
    this.lastSeen,
    required this.eventsJoined,
    required this.eventsCreated,
    required this.friendsCount,
    required this.communitiesCount,
    required this.profileCompletion,
    required this.hasCompleted,
    required this.hasAvatar,
    required this.hasBio,
    required this.hasVibes,
    required this.hasDob,
    this.vibes = const [],
    this.gender,
    this.dob,
    this.bio,
  });

  bool get isInactive {
    if (lastSeen == null) return true;
    return DateTime.now().difference(lastSeen!).inDays > 30;
  }

  int get daysSinceLastSeen {
    if (lastSeen == null) return 999;
    return DateTime.now().difference(lastSeen!).inDays;
  }

  factory AdminUserDetail.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final avatarRaw = data['photoUrl'] ?? data['avatarUrl'] ?? data['avatar_url'];
    final hasAvatar = avatarRaw != null && avatarRaw.toString().isNotEmpty;
    final bio = (data['bio'] ?? '').toString();
    final hasBio = bio.isNotEmpty;
    final vibes = List<String>.from(data['vibes'] ?? []);
    final hasVibes = vibes.isNotEmpty;
    final name = (data['name'] ?? '').toString();
    final hasName = name.isNotEmpty;
    final hasDob = data['dob'] != null;

    int completion = 0;
    if (hasAvatar) completion += 20;
    if (hasBio) completion += 20;
    if (hasName) completion += 20;
    if (hasVibes) completion += 20;
    if (hasDob) completion += 20;

    DateTime? createdAt;
    final createdRaw = data['created_at'] ?? data['createdAt'];
    if (createdRaw is Timestamp) createdAt = createdRaw.toDate();

    DateTime? lastSeen;
    final lastSeenRaw = data['lastSeen'];
    if (lastSeenRaw is Timestamp) lastSeen = lastSeenRaw.toDate();

    DateTime? dob;
    final dobRaw = data['dob'];
    if (dobRaw != null) dob = DateTime.tryParse(dobRaw.toString());

    return AdminUserDetail(
      uid: doc.id,
      name: name,
      username: (data['username'] ?? '').toString(),
      avatarUrl: hasAvatar ? avatarRaw.toString() : null,
      city: data['city']?.toString(),
      createdAt: createdAt,
      lastSeen: lastSeen,
      eventsJoined: (data['events_joined'] ?? data['eventsJoined'] ?? 0) as int,
      eventsCreated: (data['events_created'] ?? data['eventsCreated'] ?? 0) as int,
      friendsCount: (data['friends'] as List?)?.length ?? 0,
      communitiesCount: (data['communities_count'] ?? data['communitiesCount'] ?? 0) as int,
      profileCompletion: completion,
      hasCompleted: data['hasCompleted'] == true,
      hasAvatar: hasAvatar,
      hasBio: hasBio,
      hasVibes: hasVibes,
      hasDob: hasDob,
      vibes: vibes,
      gender: data['gender']?.toString(),
      dob: dob,
      bio: bio.isNotEmpty ? bio : null,
    );
  }
}
