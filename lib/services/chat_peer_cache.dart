import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Hive-backed persistent cache for chat peer (DM partner) display data.
///
/// Stores name, username, avatarUrl, and avatarEmoji per UID so that the
/// chat hub can render peer info instantly on cold start without waiting for
/// Firestore user-doc fetches.
///
/// The image bytes themselves are cached by CachedNetworkImage; this cache
/// just ensures the URL is always available so CachedNetworkImage can find
/// its disk-cached bytes.
class ChatPeerCache {
  static const _boxName = 'yanegi_chat_peers_v1';

  static Box? _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Persist display fields for [uid] extracted from a Firestore user doc.
  static void save(String uid, Map<String, dynamic> userData) {
    final box = _box;
    if (box == null || uid.trim().isEmpty) return;
    final avatarRaw = (userData['avatarUrl'] ??
            userData['photoUrl'] ??
            userData['profileImageUrl'] ??
            userData['avatar_url'] ??
            '')
        .toString()
        .trim();
    // Skip Google-hosted profile pictures (sanitize same as the repo).
    final uri = Uri.tryParse(avatarRaw);
    final host = (uri?.host ?? '').toLowerCase();
    final avatarUrl = (host.contains('googleusercontent.com') ||
            host.contains('ggpht.com'))
        ? ''
        : avatarRaw;

    box.put(
      uid,
      jsonEncode({
        'name': (userData['name'] ?? userData['username'] ?? '').toString(),
        'username': (userData['username'] ?? '').toString(),
        'avatarUrl': avatarUrl,
        'avatarEmoji': (userData['avatarEmoji'] ?? '💬').toString(),
      }),
    );
  }

  /// Returns cached display fields for [uid], or null if not cached.
  static Map<String, dynamic>? load(String uid) {
    final box = _box;
    if (box == null || uid.trim().isEmpty) return null;
    final raw = box.get(uid) as String?;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Clears all peer cache entries. Call on sign-out.
  static void clear() {
    _box?.clear();
  }
}
