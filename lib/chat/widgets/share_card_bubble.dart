import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import '../../screens/event_detail_screen.dart';
import '../../screens/profile_social_screen.dart';

/// Chat bubble for event_card and profile_card message types.
///
/// Event card  — shows event banner image (if any), else the eventAvatar emoji.
/// Profile card — shows the user's circular profile photo, else initial letter.
///
/// Fallback chain is fully offline-safe:
///   image loads   → show image
///   image fails   → show emoji / initial bubble
///   emoji empty   → show default icon
class ShareCardBubble extends StatelessWidget {
  const ShareCardBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  bool get _isEvent => message.type == 'event_card';

  @override
  Widget build(BuildContext context) {
    final meta = message.metadata;
    final title     = (meta['title']     ?? '').toString();
    final subtitle  = (meta['subtitle']  ?? '').toString();
    final emoji     = (meta['emoji']     ?? (_isEvent ? '📍' : '👤')).toString();
    final bannerUrl = (meta['bannerUrl'] ?? '').toString().trim();
    final avatarUrl = (meta['avatarUrl'] ?? '').toString().trim();
    final targetId  = (meta['targetId']  ?? '').toString();

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _navigate(context, targetId),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: const Color(0xFF171D2A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isEvent
                  ? const Color(0xFF3B82F6).withAlpha(70)
                  : Colors.white.withAlpha(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Event: banner image strip ────────────────────────────────
              if (_isEvent && bannerUrl.isNotEmpty)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(13)),
                  child: CachedNetworkImage(
                    imageUrl: bannerUrl,
                    height: 100,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    memCacheWidth: 500,
                    memCacheHeight: 200,
                    placeholder: (_, __) => Container(
                      height: 100,
                      color: const Color(0xFF1A2535),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Type label ─────────────────────────────────────────
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isEvent
                              ? Icons.event_rounded
                              : Icons.person_rounded,
                          size: 11,
                          color: _isEvent
                              ? const Color(0xFF3B82F6)
                              : Colors.white.withAlpha(130),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isEvent ? 'Event' : 'Profile',
                          style: TextStyle(
                            color: _isEvent
                                ? const Color(0xFF3B82F6)
                                : Colors.white.withAlpha(130),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ── Card body ──────────────────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Avatar — event emoji OR profile circular photo
                        if (_isEvent)
                          _EventAvatar(emoji: emoji, bannerShown: bannerUrl.isNotEmpty)
                        else
                          _ProfileAvatar(avatarUrl: avatarUrl, name: title),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title.isEmpty ? 'Untitled' : title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(140),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: Colors.white.withAlpha(100),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String targetId) {
    if (targetId.isEmpty) return;
    if (_isEvent) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: targetId),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SocialProfileScreen(profileUserId: targetId),
        ),
      );
    }
  }
}

/// Shows the event's emoji avatar.
/// When a banner is already shown above, shows a smaller version to avoid
/// redundancy. When no banner, shows a larger avatar circle.
class _EventAvatar extends StatelessWidget {
  const _EventAvatar({required this.emoji, required this.bannerShown});
  final String emoji;
  final bool bannerShown;

  @override
  Widget build(BuildContext context) {
    final radius = bannerShown ? 16.0 : 20.0;
    final fontSize = bannerShown ? 16.0 : 20.0;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.black.withAlpha(80),
      child: Text(
        emoji.isEmpty ? '📍' : emoji,
        style: TextStyle(fontSize: fontSize),
      ),
    );
  }
}

/// Shows the user's actual profile photo in a circle.
/// Falls back to a colored initial letter — never shows a broken image.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.avatarUrl, required this.name});
  final String avatarUrl;
  final String name;

  Color _colorForName(String n) {
    const palette = [
      Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFF8D6E63),
      Color(0xFF42A5F5), Color(0xFF66BB6A), Color(0xFFAB47BC),
      Color(0xFFEF5350), Color(0xFF78909C),
    ];
    if (n.isEmpty) return const Color(0xFF546E7A);
    final hash = n.codeUnits.fold(0, (a, c) => a + c);
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    if (avatarUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl,
        memCacheWidth: 120,
        memCacheHeight: 120,
        imageBuilder: (_, imageProvider) => CircleAvatar(
          radius: 20,
          backgroundImage: imageProvider,
        ),
        placeholder: (_, __) => CircleAvatar(
          radius: 20,
          backgroundColor: _colorForName(name),
          child: Text(initial,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: 20,
          backgroundColor: _colorForName(name),
          child: Text(initial,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
      );
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: _colorForName(name),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}
