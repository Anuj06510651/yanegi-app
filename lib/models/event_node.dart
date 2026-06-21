import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../theme/yanegi_theme.dart';

class EventNode {
  final String id;
  final LatLng latLng;
  final String emoji;
  final String? label;
  final Color color;
  final double activityLevel;
  final String? bannerImagePath;
  final int currentAttendees;
  final int maxCapacity;

  final List<String> categories;
  final List<String> vibes;
  final DateTime? date;
  final double price;
  final bool isPublic;
  final String visibility;
  final bool isApprovalRequired;
  final String hostId;
  final String hostName;
  final String locationText;
  final List<String> participants;

  const EventNode({
    required this.id,
    required this.latLng,
    required this.emoji,
    this.label,
    this.color = YanegiColors.accentViolet,
    this.activityLevel = 0.5,
    this.bannerImagePath,
    this.currentAttendees = 0,
    this.maxCapacity = 10,
    this.categories = const [],
    this.vibes = const [],
    this.date,
    this.price = 0,
    this.isPublic = true,
    this.visibility = 'public',
    this.isApprovalRequired = true,
    this.hostId = '',
    this.hostName = '',
    this.locationText = '',
    this.participants = const [],
  });
}
