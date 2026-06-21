import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/event_avatar_utils.dart';
import '../utils/event_share_service.dart';

/// Static visual card rendered inside a RepaintBoundary for PNG capture.
///
/// Fixed 360 × ~460 logical pixels — captured at 2× → 720 × ~920 px PNG.
/// Works for WhatsApp, Telegram, Discord, Instagram (image upload),
/// and any platform that accepts image attachments.
class EventShareCard extends StatelessWidget {
  const EventShareCard({super.key, required this.data});

  final EventShareData data;

  static const double _cardWidth = 360;
  static const double _imageHeight = 200;

  @override
  Widget build(BuildContext context) {
    final gradientColors = EventShareService.categoryGradient(data.tags);

    return SizedBox(
      width: _cardWidth,
      child: Container(
        width: _cardWidth,
        decoration: BoxDecoration(
          color: const Color(0xFF0F1520),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(100),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Cover ────────────────────────────────────────────────────
            SizedBox(
              width: _cardWidth,
              height: _imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(gradientColors),
                  // Bottom fade into card background
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF0F1520).withAlpha(200),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // YANEGI wordmark badge
                  Positioned(
                    top: 12,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(150),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withAlpha(30),
                          width: 0.5,
                        ),
                      ),
                      child: const Text(
                        'YANEGI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.title.isEmpty ? 'Untitled Event' : data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (data.startAt != null) ...[
                    _MetaRow(
                      icon: Icons.calendar_today_rounded,
                      text: DateFormat('EEE, MMM d · h:mm a').format(data.startAt!),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (data.locationName.isNotEmpty) ...[
                    _MetaRow(
                      icon: Icons.location_on_rounded,
                      text: data.locationName,
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (data.participantsCount > 0) ...[
                    _MetaRow(
                      icon: Icons.people_alt_rounded,
                      text: '${data.participantsCount} going',
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'yanegi.app',
                        style: TextStyle(
                          color: Colors.white.withAlpha(80),
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(List<Color> gradientColors) {
    if (data.bannerUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: data.bannerUrl,
        fit: BoxFit.cover,
        memCacheWidth: 720,
        memCacheHeight: 400,
        errorWidget: (_, __, ___) => _categoryFallback(gradientColors),
      );
    }
    return _categoryFallback(gradientColors);
  }

  Widget _categoryFallback(List<Color> gradientColors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Center(child: _avatarCenter()),
    );
  }

  Widget _avatarCenter() {
    final avatar = data.eventAvatar.trim();
    if (avatar.isEmpty) {
      return Icon(
        Icons.event_rounded,
        size: 64,
        color: Colors.white.withAlpha(100),
      );
    }
    if (isEventAvatarAssetPath(avatar)) {
      return Image.asset(avatar, width: 72, height: 72);
    }
    // Emoji character
    return Text(avatar, style: const TextStyle(fontSize: 60));
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 13, color: Colors.white.withAlpha(130)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withAlpha(175),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
