import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/arrival_status_service.dart';

/// Slim event info bar pinned below the chat AppBar.
///
/// Default: single-line compact row — `📍 location` (tappable) + `···` button.
/// No Firestore listeners; all data flows in from the parent's already-open
/// event snapshot. No timer — countdown is computed fresh when the more sheet
/// opens, which is accurate enough for a short-lived modal.
///
/// Tapping the location launches Google Maps (Android geo: scheme) / Apple Maps
/// (iOS) with an HTTPS browser fallback.
/// Tapping `···` opens a bottom sheet with: event title, countdown, attending
/// count, online count, and the arrival-status shortcut.
class EventCommandCenterHeader extends StatefulWidget {
  const EventCommandCenterHeader({
    super.key,
    required this.eventTitle,
    required this.locationLabel,
    required this.startAt,
    required this.endAt,
    required this.attendingCount,
    this.onlineCount,
    this.latitude,
    this.longitude,
    this.eventId,
    this.currentArrivalStatus,
    this.arrivalStatusService,
  });

  final String eventTitle;
  final String locationLabel;
  final DateTime? startAt;
  final DateTime? endAt;
  final int attendingCount;
  final int? onlineCount;
  final double? latitude;
  final double? longitude;
  final String? eventId;
  final ArrivalStatus? currentArrivalStatus;
  final ArrivalStatusService? arrivalStatusService;

  @override
  State<EventCommandCenterHeader> createState() =>
      _EventCommandCenterHeaderState();
}

class _EventCommandCenterHeaderState extends State<EventCommandCenterHeader> {
  late ArrivalStatusService _arrivalService;
  ArrivalStatus? _optimisticArrival;

  bool get _hasMapLocation =>
      widget.latitude != null && widget.longitude != null;

  @override
  void initState() {
    super.initState();
    _arrivalService = widget.arrivalStatusService ?? ArrivalStatusService();
  }

  @override
  void didUpdateWidget(covariant EventCommandCenterHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimisticArrival != null &&
        widget.currentArrivalStatus == _optimisticArrival) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _optimisticArrival = null);
      });
    }
  }

  // ── Maps ────────────────────────────────────────────────────────────────

  Future<void> _openInMaps() async {
    final lat = widget.latitude;
    final lng = widget.longitude;
    if (lat == null || lng == null) return;
    final label = Uri.encodeComponent(
      widget.locationLabel.trim().isEmpty
          ? (widget.eventTitle.trim().isEmpty ? 'Event location' : widget.eventTitle)
          : widget.locationLabel,
    );

    // iOS: Google Maps app → Apple Maps → HTTPS browser.
    // Android: geo: URI (native Maps app) → Google Maps HTTPS → plain HTTPS browser.
    // We attempt launchUrl directly rather than gating on canLaunchUrl, because on
    // some OEM Android devices (Vivo, Xiaomi) canLaunchUrl returns false for valid
    // schemes even with the correct <queries> block declared.
    final candidates = Platform.isIOS
        ? <Uri>[
            Uri.parse('comgooglemaps://?q=$lat,$lng&center=$lat,$lng&zoom=15'),
            Uri.parse('maps://?q=$label&ll=$lat,$lng'),
            Uri.parse('https://maps.apple.com/?q=$label&ll=$lat,$lng'),
            Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
          ]
        : <Uri>[
            Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)'),
            Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
            Uri.parse('https://maps.google.com/?q=$lat,$lng'),
          ];

    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (e) {
        debugPrint('EventCommandCenter._openInMaps: $uri → $e');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open Maps.')),
    );
  }

  // ── Arrival status ──────────────────────────────────────────────────────

  ArrivalStatus get _effectiveArrival =>
      _optimisticArrival ?? widget.currentArrivalStatus ?? ArrivalStatus.none;

  Future<void> _openArrivalSheet() async {
    final eventId = widget.eventId;
    if (eventId == null || eventId.trim().isEmpty) return;

    final selected = await showModalBottomSheet<ArrivalStatus>(
      context: context,
      backgroundColor: const Color(0xFF101726),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final current = _effectiveArrival;

        Widget tile(ArrivalStatus value, String emoji, String label) {
          final isCurrent = current == value;
          return ListTile(
            leading: Text(emoji, style: const TextStyle(fontSize: 22)),
            title: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: isCurrent
                ? const Icon(Icons.check_rounded, color: Colors.greenAccent)
                : null,
            onTap: () => Navigator.of(sheetCtx).pop(value),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(children: [
                  Text(
                    'Your status',
                    style: TextStyle(
                      color: Colors.white.withAlpha(220),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ]),
              ),
              tile(ArrivalStatus.onMyWay, '🚶', 'On my way'),
              tile(ArrivalStatus.arrived, '📍', 'Reached'),
              tile(ArrivalStatus.runningLate, '⏳', 'Running late'),
              if (current != ArrivalStatus.none)
                ListTile(
                  leading: Icon(Icons.cancel_outlined,
                      color: Colors.white.withAlpha(180)),
                  title: const Text('Clear status',
                      style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.of(sheetCtx).pop(ArrivalStatus.none),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    setState(() => _optimisticArrival = selected);
    try {
      await _arrivalService.setStatus(eventId: eventId, status: selected);
    } catch (e) {
      debugPrint('EventCommandCenter._openArrivalSheet write failed: $e');
      if (!mounted) return;
      setState(() => _optimisticArrival = null);
    }
  }

  // ── More sheet ──────────────────────────────────────────────────────────

  Future<void> _openMoreSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF101726),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final now = DateTime.now();
        final countdown = _formatCountdown(now);
        final isLive = _calcIsLive(now);
        final hasEnded = _calcHasEnded(now);
        final showArrival = widget.eventId != null &&
            widget.eventId!.trim().isNotEmpty &&
            widget.currentArrivalStatus != null;

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.eventTitle.trim().isNotEmpty) ...[
                  Text(
                    widget.eventTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon: hasEnded
                          ? Icons.stop_circle_outlined
                          : isLive
                              ? Icons.flash_on_rounded
                              : Icons.schedule_rounded,
                      label: countdown,
                      tint: isLive ? Colors.greenAccent : null,
                    ),
                    _InfoPill(
                      icon: Icons.group_rounded,
                      label: '${widget.attendingCount} attending',
                    ),
                    if (widget.onlineCount != null)
                      _InfoPill(
                        icon: Icons.circle,
                        label: '${widget.onlineCount} online',
                        tint: Colors.greenAccent,
                      ),
                  ],
                ),
                if (widget.locationLabel.trim().isNotEmpty ||
                    _hasMapLocation) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _hasMapLocation
                        ? () {
                            Navigator.pop(sheetCtx);
                            Future.delayed(
                              const Duration(milliseconds: 150),
                              _openInMaps,
                            );
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.place_rounded,
                            color: _hasMapLocation
                                ? const Color(0xFF4FC3F7)
                                : Colors.white54,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.locationLabel.trim().isEmpty
                                  ? 'Open in Maps'
                                  : widget.locationLabel,
                              style: TextStyle(
                                color: _hasMapLocation
                                    ? const Color(0xFF4FC3F7)
                                    : Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (_hasMapLocation)
                            const Icon(Icons.open_in_new_rounded,
                                color: Color(0xFF4FC3F7), size: 14),
                        ],
                      ),
                    ),
                  ),
                ],
                if (showArrival) ...[
                  const Divider(color: Colors.white12, height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.directions_walk_rounded,
                        color: Colors.white70),
                    title: Text(
                      _effectiveArrival == ArrivalStatus.none
                          ? 'Set arrival status'
                          : 'Status: ${_arrivalStatusLabel(_effectiveArrival)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white54),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      await Future.delayed(const Duration(milliseconds: 150));
                      if (mounted) await _openArrivalSheet();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _arrivalStatusLabel(ArrivalStatus s) {
    switch (s) {
      case ArrivalStatus.onMyWay:
        return '🚶 On my way';
      case ArrivalStatus.arrived:
        return '📍 Reached';
      case ArrivalStatus.runningLate:
        return '⏳ Late';
      case ArrivalStatus.none:
        return 'Not set';
    }
  }

  // ── Compact bar ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final locationText = widget.locationLabel.trim().isNotEmpty
        ? widget.locationLabel
        : (_hasMapLocation ? 'Open location' : null);
    final displayText = locationText ??
        (widget.eventTitle.trim().isEmpty ? 'Event' : widget.eventTitle);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _hasMapLocation ? _openInMaps : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_rounded,
                      color: _hasMapLocation
                          ? const Color(0xFF4FC3F7)
                          : Colors.white.withAlpha(130),
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        displayText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _hasMapLocation
                              ? const Color(0xFF4FC3F7)
                              : Colors.white.withAlpha(180),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_hasMapLocation) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new_rounded,
                        color: const Color(0xFF4FC3F7).withAlpha(180),
                        size: 11,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 18,
            color: Colors.white.withAlpha(20),
          ),
          GestureDetector(
            onTap: _openMoreSheet,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(
                Icons.more_horiz_rounded,
                color: Colors.white.withAlpha(140),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Time helpers ─────────────────────────────────────────────────────────

  bool _calcIsLive(DateTime now) {
    final start = widget.startAt;
    final end = widget.endAt;
    if (start == null) return false;
    if (now.isBefore(start)) return false;
    if (end == null) return true;
    return now.isBefore(end);
  }

  bool _calcHasEnded(DateTime now) {
    final end = widget.endAt;
    if (end == null) return false;
    return now.isAfter(end);
  }

  String _formatCountdown(DateTime now) {
    final start = widget.startAt;
    if (start == null) return '—';
    if (_calcHasEnded(now)) return 'Ended';
    if (_calcIsLive(now)) return 'Live now';
    final delta = start.difference(now);
    if (delta.inSeconds <= 0) return 'Starting…';
    final days = delta.inDays;
    final hours = delta.inHours % 24;
    final minutes = delta.inMinutes % 60;
    final seconds = delta.inSeconds % 60;
    if (days > 0) return 'In ${days}d ${hours}h';
    if (hours > 0) return 'In ${hours}h ${minutes}m';
    if (minutes > 5) return 'In ${minutes}m';
    return 'In ${minutes}m ${seconds}s';
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label, this.tint});

  final IconData icon;
  final String label;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Colors.white.withAlpha(180);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (tint ?? Colors.white).withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (tint ?? Colors.white).withAlpha(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience factory: extract a usable command-center header straight from
/// raw event-doc data (the same map the parent already has from its event
/// snapshot listener). Centralises the field-name fallbacks for
/// `participantsCount` / `participants` / coordinates / dates.
EventCommandCenterHeader buildCommandCenterFromEventData({
  required Map<String, dynamic> eventData,
  int? onlineCount,
  String? eventId,
  ArrivalStatus? currentArrivalStatus,
}) {
  final title = (eventData['title'] ?? eventData['name'] ?? '').toString();

  // location field may be a plain String (label), a Map (nested coords), or a
  // GeoPoint — only use it as a display label when it's a non-empty String.
  final rawLocation = eventData['location'];
  final locationLabel = (
    (rawLocation is String && rawLocation.trim().isNotEmpty
        ? rawLocation
        : null) ??
    eventData['locationName']?.toString() ??
    eventData['locationText']?.toString() ??
    ''
  ).trim();

  DateTime? toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  double? toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  final startAt =
      toDate(eventData['startAt']) ?? toDate(eventData['start_at']);
  final endAt = toDate(eventData['endAt']) ?? toDate(eventData['end_at']);

  // Extract coordinates from multiple field-name conventions, including the
  // Firestore GeoPoint stored under `locationGeoPoint` (or `geoPoint`).
  GeoPoint? geoPoint;
  for (final key in ['locationGeoPoint', 'geoPoint', 'geo_point']) {
    final v = eventData[key];
    if (v is GeoPoint) {
      geoPoint = v;
      break;
    }
  }
  // Also accept a GeoPoint stored directly under `location`.
  if (geoPoint == null && rawLocation is GeoPoint) geoPoint = rawLocation;

  final latitude = toDouble(eventData['latitude']) ??
      toDouble(eventData['lat']) ??
      geoPoint?.latitude ??
      toDouble((rawLocation is Map) ? rawLocation['latitude'] : null);
  final longitude = toDouble(eventData['longitude']) ??
      toDouble(eventData['lng']) ??
      toDouble(eventData['lon']) ??
      geoPoint?.longitude ??
      toDouble((rawLocation is Map) ? rawLocation['longitude'] : null);

  int participantsCount = 0;
  final raw = eventData['participantsCount'] ?? eventData['participants_count'];
  if (raw is int) {
    participantsCount = raw;
  } else if (raw is num) {
    participantsCount = raw.toInt();
  } else {
    final list = eventData['participants'];
    if (list is List) participantsCount = list.length;
  }

  return EventCommandCenterHeader(
    eventTitle: title,
    locationLabel: locationLabel,
    startAt: startAt,
    endAt: endAt,
    attendingCount: participantsCount,
    onlineCount: onlineCount,
    latitude: latitude,
    longitude: longitude,
    eventId: eventId,
    currentArrivalStatus: currentArrivalStatus,
  );
}
