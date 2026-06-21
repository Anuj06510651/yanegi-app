import 'package:flutter/material.dart';

/// Represents a social media or external link on a user's profile.
class SocialLink {
  final String platform; // instagram, linkedin, twitter, website, other
  final String url;
  final String? handle;

  const SocialLink({
    required this.platform,
    required this.url,
    this.handle,
  });

  factory SocialLink.fromMap(Map<String, dynamic> map) {
    return SocialLink(
      platform: map['platform'] ?? 'other',
      url: map['url'] ?? '',
      handle: map['handle'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'platform': platform,
      'url': url,
      if (handle != null) 'handle': handle,
    };
  }

  /// Returns the appropriate icon for the given platform.
  IconData get icon {
    switch (platform.toLowerCase()) {
      case 'instagram':
        return Icons.camera_alt_rounded;
      case 'twitter':
      case 'x':
        return Icons.alternate_email_rounded;
      case 'linkedin':
        return Icons.work_rounded;
      case 'github':
        return Icons.code_rounded;
      case 'website':
        return Icons.language_rounded;
      case 'youtube':
        return Icons.play_circle_fill_rounded;
      case 'tiktok':
        return Icons.music_note_rounded;
      case 'snapchat':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  /// Display label for the platform.
  String get displayName {
    switch (platform.toLowerCase()) {
      case 'instagram':
        return 'Instagram';
      case 'twitter':
      case 'x':
        return 'X (Twitter)';
      case 'linkedin':
        return 'LinkedIn';
      case 'github':
        return 'GitHub';
      case 'website':
        return 'Website';
      case 'youtube':
        return 'YouTube';
      case 'tiktok':
        return 'TikTok';
      case 'snapchat':
        return 'Snapchat';
      default:
        return platform;
    }
  }

  /// Supported platform options for the dropdown picker.
  static const List<String> platformOptions = [
    'instagram',
    'twitter',
    'linkedin',
    'github',
    'youtube',
    'tiktok',
    'snapchat',
    'website',
    'other',
  ];
}
