import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/user_profile.dart';

/// Hive-backed cache for the current user's own profile.
///
/// Stores only the fields needed for fast display on startup:
/// name, username, bio, avatarUrl, bannerUrl, vibes.
/// Also persists the hasCompletedProfile flag so [AuthBootstrapper]
/// can route to the map without waiting for Firestore.
class LocalProfileCache {
  static const _boxName = 'yanegi_profile_v1';
  static const _profilePrefix = 'p_';
  static const _completedPrefix = 'c_';

  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  static void save(
    UserProfile profile, {
    required bool hasCompletedProfile,
  }) {
    final box = _box;
    if (box == null) return;
    final payload = jsonEncode({
      'name': profile.name,
      'username': profile.username,
      'bio': profile.bio,
      'avatarUrl': profile.avatarUrl,
      'bannerUrl': profile.bannerUrl,
      'vibes': profile.vibes,
    });
    box.put(_profilePrefix + profile.uid, payload);
    box.put(_completedPrefix + profile.uid, hasCompletedProfile);
  }

  /// Returns a [UserProfile] populated with cached display fields, or null
  /// if no cache entry exists for [uid].
  static UserProfile? load(String uid) {
    final box = _box;
    if (box == null) return null;
    final raw = box.get(_profilePrefix + uid) as String?;
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile(
        uid: uid,
        name: data['name'] as String? ?? '',
        username: data['username'] as String? ?? '',
        bio: data['bio'] as String? ?? '',
        avatarUrl: data['avatarUrl'] as String?,
        bannerUrl: data['bannerUrl'] as String?,
        vibes: List<String>.from(data['vibes'] as List? ?? const []),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the last persisted [hasCompletedProfile] value, or null if the
  /// cache has no entry for [uid] (first install or cache cleared).
  static bool? loadHasCompleted(String uid) {
    return _box?.get(_completedPrefix + uid) as bool?;
  }

  /// Clears the profile and completion flag for [uid]. Call on sign-out.
  static void clear(String uid) {
    _box?.delete(_profilePrefix + uid);
    _box?.delete(_completedPrefix + uid);
  }
}
