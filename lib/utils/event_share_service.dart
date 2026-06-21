import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yanegi/config/app_environment.dart';

/// All event fields needed to generate share content.
class EventShareData {
  const EventShareData({
    required this.eventId,
    required this.title,
    this.bannerUrl = '',
    this.eventAvatar = '',
    this.tags = const [],
    this.startAt,
    this.locationName = '',
    this.participantsCount = 0,
    this.isHost = false,
    this.isParticipant = false,
  });

  final String eventId;
  final String title;
  final String bannerUrl;
  final String eventAvatar;
  final List<String> tags;
  final DateTime? startAt;
  final String locationName;
  final int participantsCount;
  final bool isHost;
  final bool isParticipant;
}

abstract class EventShareService {
  // ── Deep link ──────────────────────────────────────────────────────────────

  static String deepLink(String eventId) =>
      '${AppEnvironment.webBaseUrl}/event/${Uri.encodeComponent(eventId.trim())}';

  // ── Text generation ────────────────────────────────────────────────────────

  static String generateText(EventShareData data) {
    final dateStr = _formatShareDate(data.startAt);
    final link = deepLink(data.eventId);
    final tagline = _categoryTagline(data.tags);
    final tagPart = tagline.isNotEmpty ? '\n\n$tagline' : '';

    if (data.isHost) {
      return "I'm hosting ${data.title} on $dateStr.$tagPart\n\nJoin through Yanegi:\n\n$link";
    }

    if (data.isParticipant) {
      return "I'm joining ${data.title} on $dateStr.$tagPart\n\nLooks interesting:\n\n$link";
    }

    return "${data.title} on $dateStr.$tagPart\n\nCheck it out on Yanegi:\n\n$link";
  }

  static String _formatShareDate(DateTime? dt) {
    if (dt == null) return 'an upcoming date';
    return DateFormat('EEEE, MMM d').format(dt);
  }

  // Maps the first matching tag to a one-line natural-language tagline.
  static String _categoryTagline(List<String> tags) {
    for (final tag in tags) {
      switch (tag.toLowerCase()) {
        case 'music':
        case 'concert':
        case 'dj':
          return 'A night of great music.';
        case 'sports':
        case 'fitness':
        case 'running':
        case 'gym':
        case 'outdoor':
          return 'Come stay active.';
        case 'startup':
        case 'networking':
        case 'business':
          return 'Grow your network.';
        case 'tech':
          return 'Connect with the tech community.';
        case 'food':
        case 'dinner':
        case 'brunch':
        case 'drinks':
          return 'Good food, good company.';
        case 'art':
        case 'culture':
        case 'exhibition':
          return 'An evening of culture and creativity.';
        case 'gaming':
        case 'game':
        case 'esports':
          return 'Compete, connect, and level up.';
        case 'study':
        case 'workshop':
        case 'lecture':
        case 'education':
          return 'Learn something new.';
        case 'party':
        case 'social':
          return 'Should be a great time.';
        case 'indoor':
          return 'A great indoor experience.';
      }
    }
    return '';
  }

  // ── Category gradient ──────────────────────────────────────────────────────

  /// Returns a two-stop dark gradient for the given event tags.
  /// Used as the fallback cover when no [bannerUrl] is available.
  static List<Color> categoryGradient(List<String> tags) {
    for (final tag in tags) {
      switch (tag.toLowerCase()) {
        case 'music':
        case 'concert':
        case 'dj':
          return [const Color(0xFF4A1D8F), const Color(0xFF1A0D3E)];
        case 'sports':
        case 'fitness':
        case 'running':
        case 'outdoor':
          return [const Color(0xFF0D4A1A), const Color(0xFF0A2410)];
        case 'startup':
        case 'networking':
        case 'business':
          return [const Color(0xFF1A2F4A), const Color(0xFF0D1A2A)];
        case 'tech':
        case 'gaming':
        case 'esports':
          return [const Color(0xFF0D1F3A), const Color(0xFF061020)];
        case 'food':
        case 'dinner':
        case 'brunch':
          return [const Color(0xFF3A1A0A), const Color(0xFF1F0D05)];
        case 'art':
        case 'culture':
          return [const Color(0xFF2A0A3A), const Color(0xFF15051F)];
        case 'party':
        case 'social':
          return [const Color(0xFF3B1A1A), const Color(0xFF1A0A0A)];
        case 'study':
        case 'workshop':
          return [const Color(0xFF0A1A2A), const Color(0xFF050E18)];
      }
    }
    return [const Color(0xFF1C1C28), const Color(0xFF0A0A0F)];
  }

  // ── Share actions ──────────────────────────────────────────────────────────

  /// Share plain text + deep link via the native OS share sheet.
  static Future<void> shareText(EventShareData data) async {
    await Share.share(
      generateText(data),
      subject: data.title.isEmpty ? 'Event on Yanegi' : data.title,
    );
  }

  /// Capture the widget bound to [cardKey] as a 2× PNG, save to a temp file,
  /// and open the native OS share sheet.
  static Future<void> shareCard(GlobalKey cardKey, EventShareData data) async {
    final context = cardKey.currentContext;
    if (context == null) throw StateError('Share card widget not mounted');

    final boundary = context.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw StateError('Failed to encode share card as PNG');
    final bytes = byteData.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/yanegi_share_${data.eventId}.png';
    await File(path).writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(path, mimeType: 'image/png')],
      text: deepLink(data.eventId),
      subject: data.title.isEmpty ? 'Event on Yanegi' : data.title,
    );
  }
}
