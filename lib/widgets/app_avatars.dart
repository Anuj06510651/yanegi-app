import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/yanegi_theme.dart';
import '../utils/event_avatar_utils.dart';

/// Reusable person avatar.
///
/// Contract:
/// - If [photoUrl] is a non-empty http(s) URL → render that image (cached).
/// - Else → render the premium default single-person icon on a branded
///   surface (no broken/empty placeholder, no flicker).
///
/// One source of truth for avatar sizing, ring color, and fallback look
/// across DM list, friends, discover, profile, notifications, message
/// bubbles, and event participant lists.
class AppUserAvatar extends StatelessWidget {
  const AppUserAvatar({
    super.key,
    this.photoUrl,
    this.radius = 20,
    this.showRing = false,
  });

  /// HTTP(S) URL of the user's profile photo. May be null/empty/non-URL,
  /// in which case the fallback icon is rendered.
  final String? photoUrl;

  /// Avatar radius. Used by both the image and the fallback.
  final double radius;

  /// Whether to draw a thin branded ring around the avatar.
  /// Used for "active" surfaces (profile header, story-style rows).
  final bool showRing;

  bool get _hasImage {
    final url = photoUrl?.trim() ?? '';
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final inner = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: _hasImage
            ? CachedNetworkImage(
                imageUrl: photoUrl!.trim(),
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 120),
                memCacheWidth: (radius * 3).ceil(),
                memCacheHeight: (radius * 3).ceil(),
                placeholder: (_, __) => const _AvatarFallback.person(),
                errorWidget: (_, __, ___) => const _AvatarFallback.person(),
              )
            : const _AvatarFallback.person(),
      ),
    );

    if (!showRing) return inner;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            YanegiColors.primary.withAlpha(220),
            YanegiColors.tertiary.withAlpha(180),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: inner,
    );
  }
}

/// Reusable group / event chat avatar.
///
/// Contract:
/// - If [imageUrl] is a non-empty http(s) URL → render that image (cached).
/// - Else → render the premium event icon on a branded surface.
class AppGroupAvatar extends StatelessWidget {
  const AppGroupAvatar({
    super.key,
    this.imageUrl,
    this.radius = 22,
  });

  /// HTTP(S) URL of the event/group banner or avatar.
  final String? imageUrl;

  final double radius;

  bool get _hasImage {
    final url = imageUrl?.trim() ?? '';
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: _hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl!.trim(),
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 120),
                memCacheWidth: (radius * 3).ceil(),
                memCacheHeight: (radius * 3).ceil(),
                placeholder: (_, __) => const _AvatarFallback.group(),
                errorWidget: (_, __, ___) => const _AvatarFallback.group(),
              )
            : const _AvatarFallback.group(),
      ),
    );
  }
}

/// Event-specific group-chat avatar.
///
/// Priority (first non-empty wins):
/// 1. [bannerUrl] — a remote photo banner from the event (shown as a
///    circular cropped image).
/// 2. [eventAvatar] is a local asset path (ends with .png / contains '/')
///    → rendered via [Image.asset].
/// 3. [eventAvatar] is a short emoji/text string → rendered as text.
/// 4. Generic branded event fallback (same as [AppGroupAvatar]).
///
/// Use this on every surface that shows a group-chat row or header.
/// Do NOT branch on the avatar type in calling code — let this widget decide.
class EventCategoryAvatar extends StatelessWidget {
  const EventCategoryAvatar({
    super.key,
    this.bannerUrl,
    this.eventAvatar,
    this.radius = 24,
  });

  final String? bannerUrl;
  final String? eventAvatar;
  final double radius;

  bool get _hasBanner {
    final url = bannerUrl?.trim() ?? '';
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    // 1 — remote banner photo
    if (_hasBanner) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: CachedNetworkImage(
            imageUrl: bannerUrl!.trim(),
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            memCacheWidth: (radius * 3).ceil(),
            memCacheHeight: (radius * 3).ceil(),
            placeholder: (_, __) => const _AvatarFallback.group(),
            errorWidget: (_, __, ___) => const _AvatarFallback.group(),
          ),
        ),
      );
    }

    final avatar = eventAvatar?.trim() ?? '';

    // 2 — local asset image (e.g. "image assest/soccer-ball_26bd.png")
    if (avatar.isNotEmpty && isEventAvatarAssetPath(avatar)) {
      return ClipOval(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [YanegiColors.surfaceElevated, YanegiColors.surface],
            ),
          ),
          padding: EdgeInsets.all(radius * 0.22),
          child: Image.asset(
            avatar,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const _AvatarFallback.group(),
          ),
        ),
      );
    }

    // 3 — emoji / short text token
    if (avatar.isNotEmpty) {
      return ClipOval(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [YanegiColors.surfaceElevated, YanegiColors.surface],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            avatar,
            style: TextStyle(
              fontSize: radius * 0.85,
              height: 1.0,
              fontFamily: 'Apple Color Emoji',
            ),
          ),
        ),
      );
    }

    // 4 — generic branded fallback
    return AppGroupAvatar(imageUrl: null, radius: radius);
  }
}

/// Branded fallback fill: a soft surface gradient with a centered icon.
/// Never empty, never flickers (it's the same widget the image lays on
/// top of, so swap-in/swap-out is seamless).
class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback.person()
      : _icon = Icons.person_rounded,
        _tint = YanegiColors.primary;

  const _AvatarFallback.group()
      : _icon = Icons.celebration_rounded,
        _tint = YanegiColors.tertiary;

  final IconData _icon;
  final Color _tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            YanegiColors.surfaceElevated,
            YanegiColors.surface,
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize = constraints.maxWidth * 0.5;
          return Center(
            child: Icon(_icon, color: _tint.withAlpha(220), size: iconSize),
          );
        },
      ),
    );
  }
}
