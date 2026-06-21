// Single source of truth for event category icons.
// Used by: map markers, group chat avatars, event cards, explore feed.
// DO NOT duplicate this mapping in any other file.

/// Maps event category/vibe tag names to their local asset image paths.
/// Every path in this map is also present in [kEventAvatarAssets].
const Map<String, String> kEmojiByTag = {
  'Music': 'image assest/studio-microphone_1f399-fe0f.png',
  'Art': 'image assest/artist-palette_1f3a8.png',
  'Food': 'image assest/shopping-bags_1f6cd-fe0f.png',
  'Sports': 'image assest/soccer-ball_26bd.png',
  'Tech': 'image assest/video-game_1f3ae.png',
  'Social': 'image assest/love-letter_1f48c.png',
  'Networking':
      'image assest/handshake-no-skin-tone-no-skin-tone_1faf1-200d-1faf2.png',
  'Party': 'image assest/confetti-ball_1f38a.png',
  'Outdoor': 'image assest/camping_1f3d5-fe0f.png',
  'Indoor': 'image assest/performing-arts_1f3ad.png',
};

/// Full list of selectable event avatar assets (shown in the event-creation
/// avatar picker). The first item is the default fallback.
const List<String> kEventAvatarAssets = [
  'image assest/airplane_2708-fe0f.png',
  'image assest/artist-palette_1f3a8.png',
  'image assest/auto-rickshaw_1f6fa.png',
  'image assest/barber-pole_1f488.png',
  'image assest/basketball_1f3c0.png',
  'image assest/beach-with-umbrella_1f3d6-fe0f.png',
  'image assest/books_1f4da.png',
  'image assest/bowling_1f3b3.png',
  'image assest/camping_1f3d5-fe0f.png',
  'image assest/carousel-horse_1f3a0.png',
  'image assest/chart-increasing-with-yen_1f4b9.png',
  'image assest/confetti-ball_1f38a.png',
  'image assest/cricket-game_1f3cf.png',
  'image assest/fountain_26f2.png',
  'image assest/grinning-face_1f600.png',
  'image assest/growing-heart_1f497.png',
  'image assest/handshake-no-skin-tone-no-skin-tone_1faf1-200d-1faf2.png',
  'image assest/kaaba_1f54b.png',
  'image assest/light-blue-heart_1fa75.png',
  'image assest/love-letter_1f48c.png',
  'image assest/mending-heart_2764-fe0f-200d-1fa79.png',
  'image assest/mosque_1f54c.png',
  'image assest/motor-scooter_1f6f5.png',
  'image assest/parachute_1fa82.png',
  'image assest/performing-arts_1f3ad.png',
  'image assest/pool-8-ball_1f3b1.png',
  'image assest/racing-car_1f3ce-fe0f.png',
  'image assest/sailboat_26f5.png',
  'image assest/shinto-shrine_26e9-fe0f.png',
  'image assest/shopping-bags_1f6cd-fe0f.png',
  'image assest/slot-machine_1f3b0.png',
  'image assest/snow-capped-mountain_1f3d4-fe0f.png',
  'image assest/soccer-ball_26bd.png',
  'image assest/softball_1f94e.png',
  'image assest/sparkler_1f387.png',
  'image assest/studio-microphone_1f399-fe0f.png',
  'image assest/synagogue_1f54d.png',
  'image assest/video-game_1f3ae.png',
];

/// Returns true if [token] is a local asset image path (ends with .png,
/// .jpg, etc. or contains a path separator), rather than an emoji character
/// or a remote URL.
bool isEventAvatarAssetPath(String token) {
  final t = token.trim().toLowerCase();
  return t.endsWith('.png') ||
      t.endsWith('.jpg') ||
      t.endsWith('.jpeg') ||
      t.endsWith('.webp') ||
      t.endsWith('.gif') ||
      (t.contains('/') && !t.startsWith('http'));
}

/// Resolves an emoji/asset token from a raw Firestore event document.
///
/// Priority:
/// 1. `eventAvatar` field
/// 2. `hostAvatarEmoji` field
/// 3. `avatarEmoji` field
/// 4. Derived from `categories` / `vibes` via [kEmojiByTag]
/// 5. Returns empty string if nothing found (caller should apply fallback)
String resolveEventAvatarFromData(Map<String, dynamic> data) {
  final direct = _pick(data, ['eventAvatar', 'hostAvatarEmoji', 'avatarEmoji']);
  if (direct.isNotEmpty) return direct;

  // Try deriving from categories / vibes
  final tags = <String>[
    ...(_toStringList(data['categories'])),
    ...(_toStringList(data['vibes'])),
    ...(_toStringList(data['tags'])),
  ];
  for (final tag in tags) {
    final found = kEmojiByTag[tag];
    if (found != null && found.isNotEmpty) return found;
  }
  return '';
}

String _pick(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final v = (data[key] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

List<String> _toStringList(dynamic raw) {
  if (raw is List) return raw.map((e) => e.toString().trim()).toList();
  if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
  return const [];
}
