import 'package:flutter/material.dart';
import 'admin_routes.dart';

export 'admin_routes.dart';

enum AttentionSeverity { critical, warning, info }
enum AttentionCategory { moderation, events, users, system }

class AdminAttentionItem {
  final AttentionSeverity severity;
  final AttentionCategory category;
  final String title;
  final String body;
  final int count;
  final AdminRoute route;
  final IconData icon;

  const AdminAttentionItem({
    required this.severity,
    required this.category,
    required this.title,
    required this.body,
    required this.count,
    required this.route,
    required this.icon,
  });
}
