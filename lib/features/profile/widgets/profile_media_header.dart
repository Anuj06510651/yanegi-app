part of '../../../screens/profile_social_screen.dart';

class StaticProfileMediaHeader extends StatelessWidget {
  final bool isDarkTheme;
  final String bannerUrl;
  final String avatarUrl;
  final String displayName;
  final String username;
  final VoidCallback? onBannerTap;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onBannerLongPress;
  final VoidCallback? onAvatarLongPress;
  final VoidCallback? onRetryBannerTap;
  final VoidCallback? onRetryAvatarTap;
  final bool isUploadingMedia;
  final UploadQueueState? bannerUploadState;
  final UploadQueueState? avatarUploadState;
  final Object? bannerHeroTag;
  final Object? avatarHeroTag;

  const StaticProfileMediaHeader({
    super.key,
    this.isDarkTheme = true,
    required this.bannerUrl,
    required this.avatarUrl,
    required this.displayName,
    required this.username,
    required this.onBannerTap,
    required this.onAvatarTap,
    this.onBannerLongPress,
    this.onAvatarLongPress,
    this.onRetryBannerTap,
    this.onRetryAvatarTap,
    this.isUploadingMedia = false,
    this.bannerUploadState,
    this.avatarUploadState,
    this.bannerHeroTag,
    this.avatarHeroTag,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 248,
        child: _buildMediaScaffold(
          overlay: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDarkTheme
                    ? const [Colors.transparent, Color(0xAA000000)]
                    : [Colors.transparent, Colors.white.withAlpha(170)],
              ),
            ),
          ),
          content: const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildMediaScaffold(
      {required Widget overlay, required Widget content}) {
    final bannerProvider = _imageProviderFor(bannerUrl);
    final avatarProvider = _imageProviderFor(avatarUrl);

    final bannerFailed = bannerUploadState == UploadQueueState.failed;
    final avatarFailed = avatarUploadState == UploadQueueState.failed;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _maybeHero(
            tag: bannerHeroTag,
            child: Container(
            height: 210,
            decoration: BoxDecoration(
              color: isDarkTheme ? YanegiColors.surface : Colors.white,
              image: bannerProvider != null
                  ? DecorationImage(
                      image: bannerProvider,
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (bannerProvider == null)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDarkTheme
                            ? const [
                                Color(0xFF2B3C7A),
                                Color(0xFF1C1C28),
                                Color(0xFF12121A),
                              ]
                            : const [
                                Color(0xFFEAF2FF),
                                Color(0xFFDDEBFF),
                                Color(0xFFF4F8FF),
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
                              color: const Color(0xFF5F8FD9).withOpacity(0.22),
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
                              color: const Color(0xFF7A5FA8).withOpacity(0.18),
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
                  ),
                if (bannerFailed && onRetryBannerTap != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onRetryBannerTap,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withAlpha(200),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withAlpha(70)),
                        ),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  )
                else if (bannerProvider == null && onBannerTap != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onBannerTap,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isDarkTheme
                              ? Colors.black.withAlpha(90)
                              : Colors.white.withAlpha(220),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isDarkTheme
                                ? Colors.white.withAlpha(70)
                                : Colors.black.withAlpha(20),
                          ),
                        ),
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          color: isDarkTheme ? Colors.white : Colors.black87,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onBannerTap,
                    onLongPress: onBannerLongPress,
                    behavior: HitTestBehavior.translucent,
                    child: const SizedBox.expand(),
                  ),
                ),
                IgnorePointer(child: overlay),
                IgnorePointer(child: content),
                if (isUploadingMedia)
                  Container(
                    color: Colors.black.withAlpha(80),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: onAvatarTap,
              onLongPress: onAvatarLongPress,
              child: _maybeHero(
                tag: avatarHeroTag,
                child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDarkTheme
                        ? Colors.white.withAlpha(220)
                        : Colors.black.withAlpha(18),
                    width: 3,
                  ),
                  color: isDarkTheme ? YanegiColors.surface : Colors.white,
                  image: avatarProvider != null
                      ? DecorationImage(
                          image: avatarProvider,
                          fit: BoxFit.cover,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(70),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: avatarProvider == null
                    ? Center(
                        child: Text(
                          _initialsFrom(displayName, username),
                          style: TextStyle(
                            color: isDarkTheme ? Colors.white : Colors.black87,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
              ),
              ),
            ),
          ),
        ),
        if (avatarFailed && onRetryAvatarTap != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: -10,
            child: Align(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onRetryAvatarTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withAlpha(120)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Retry',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (avatarProvider == null && onAvatarTap != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: -6,
            child: Align(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onAvatarTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: YanegiColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: YanegiColors.textSecondary.withAlpha(80)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline,
                          color: YanegiColors.textSecondary, size: 13),
                      SizedBox(width: 4),
                      Text(
                        'Add DP',
                        style: TextStyle(
                          color: YanegiColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _initialsFrom(String name, String username) {
    final base = name.trim().isNotEmpty
        ? name.trim()
        : username.replaceAll('@', '').trim();
    if (base.isEmpty) return 'Y';
    final parts =
        base.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return base.substring(0, base.length > 2 ? 2 : 1).toUpperCase();
  }

  ImageProvider? _imageProviderFor(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    if (isRemoteMediaUrl(value)) {
      return CachedNetworkImageProvider(value);
    }

    return null;
  }

  Widget _maybeHero({required Object? tag, required Widget child}) {
    if (tag == null) return child;
    return Hero(tag: tag, child: Material(type: MaterialType.transparency, child: child));
  }
}
