import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/yanegi_theme.dart';

/// Reusable banner image with branded fallback.
///
/// - HTTP(S) URL → cached network image, fit cover.
/// - Empty/null/error → soft gradient fallback with a small image-outline
///   glyph (no broken placeholder, no flicker).
class AppBannerImage extends StatelessWidget {
  const AppBannerImage({
    super.key,
    this.imageUrl,
    this.height = 210,
    this.fit = BoxFit.cover,
  });

  final String? imageUrl;
  final double height;
  final BoxFit fit;

  bool get _hasImage {
    final url = imageUrl?.trim() ?? '';
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: _hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl!.trim(),
              fit: fit,
              fadeInDuration: const Duration(milliseconds: 120),
              memCacheWidth: 800,
              placeholder: (_, __) => const _BannerFallback(),
              errorWidget: (_, __, ___) => const _BannerFallback(),
            )
          : const _BannerFallback(),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

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
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: YanegiColors.primary.withOpacity(0.18),
              ),
            ),
          ),
          Positioned(
            right: -35,
            bottom: -55,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: YanegiColors.tertiary.withOpacity(0.14),
              ),
            ),
          ),
          const Center(
            child: Icon(
              Icons.image_outlined,
              color: YanegiColors.textSecondary,
              size: 34,
            ),
          ),
        ],
      ),
    );
  }
}
