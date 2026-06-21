import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/event_model.dart';
import '../theme/yanegi_theme.dart';
import '../widgets/app_avatars.dart';
import '../widgets/action_gate.dart';
import '../services/activity_notification_service.dart';
import '../services/event_service.dart';
import '../services/saved_events_service.dart';
import '../providers/explore_feed_provider.dart';
import '../utils/error_handler.dart';
import '../utils/event_label.dart';
import '../utils/event_share_service.dart';
import '../widgets/friends_going_strip.dart';
import '../widgets/share_to_chat_sheet.dart';
import 'event_participants_screen.dart';
import 'event_share_sheet.dart';
import 'profile_social_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;
  final Position? userLocation;

  const EventDetailScreen({
    super.key,
    required this.eventId,
    this.userLocation,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  final EventService _eventService = EventService();
  final SavedEventsService _savedEventsService = SavedEventsService();
  static const bool _forceShowHostControlsForDebug = false;
  bool _isJoining = false;
  bool _isRequesting = false;
  bool _isWaitlisting = false;
  bool _didSyncLifecycle = false;

  @override
  void initState() {
    super.initState();
    unawaited(_syncLifecycleOnce());
  }

  /// Bookmark toggle backed by the owner-private saved-events store.
  Widget _buildSaveToggleButton() {
    return StreamBuilder<bool>(
      stream: _savedEventsService.isSavedStream(widget.eventId),
      builder: (context, snapshot) {
        final saved = snapshot.data ?? false;
        return IconButton(
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: saved ? YanegiColors.primary : Colors.white,
          ),
          tooltip: saved ? 'Saved' : 'Save event',
          onPressed: () async {
            final nowSaved =
                await _savedEventsService.toggleSaved(widget.eventId);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(nowSaved ? 'Saved.' : 'Removed from saved.'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _syncLifecycleOnce() async {
    if (_didSyncLifecycle) return;
    _didSyncLifecycle = true;
    try {
      await _eventService.syncEventLifecycle(widget.eventId);
    } catch (e) {
      debugPrint('Lifecycle sync failed: $e');
    }
  }

  /// Try to launch a native maps app (Google Maps / Apple Maps) for the given
  /// coordinates. Falls through a candidate list of URI schemes until one
  /// succeeds, then shows a friendly SnackBar if every attempt fails. We do
  /// NOT gate on `canLaunchUrl` because some OEM Android devices report
  /// `false` for valid schemes even with the correct `<queries>` manifest
  /// block.
  Future<void> _openInMaps({
    required double latitude,
    required double longitude,
    required String label,
  }) async {
    final encodedLabel = Uri.encodeComponent(
      label.trim().isEmpty ? 'Event location' : label,
    );
    final candidates = Platform.isIOS
        ? <Uri>[
            Uri.parse(
                'comgooglemaps://?q=$latitude,$longitude&center=$latitude,$longitude&zoom=15'),
            Uri.parse('maps://?q=$encodedLabel&ll=$latitude,$longitude'),
            Uri.parse(
                'https://maps.apple.com/?q=$encodedLabel&ll=$latitude,$longitude'),
            Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude'),
          ]
        : <Uri>[
            Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude($encodedLabel)'),
            Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude'),
            Uri.parse('https://maps.google.com/?q=$latitude,$longitude'),
          ];

    for (final uri in candidates) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (e) {
        debugPrint('event_detail._openInMaps: $uri → $e');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open Maps.')),
    );
  }

  ({double? lat, double? lng}) _extractCoordinates(
      Map<String, dynamic> eventData) {
    double? toDouble(dynamic raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }

    GeoPoint? geoPoint;
    for (final key in const ['locationGeoPoint', 'geoPoint', 'geo_point']) {
      final v = eventData[key];
      if (v is GeoPoint) {
        geoPoint = v;
        break;
      }
    }
    final rawLocation = eventData['location'];
    if (geoPoint == null && rawLocation is GeoPoint) {
      geoPoint = rawLocation;
    }

    final lat = toDouble(eventData['latitude']) ??
        toDouble(eventData['lat']) ??
        geoPoint?.latitude ??
        toDouble((rawLocation is Map) ? rawLocation['latitude'] : null) ??
        toDouble((rawLocation is Map) ? rawLocation['lat'] : null);
    final lng = toDouble(eventData['longitude']) ??
        toDouble(eventData['lng']) ??
        toDouble(eventData['lon']) ??
        geoPoint?.longitude ??
        toDouble((rawLocation is Map) ? rawLocation['longitude'] : null) ??
        toDouble((rawLocation is Map) ? rawLocation['lng'] : null);
    return (lat: lat, lng: lng);
  }

  void _shareEvent({
    required Map<String, dynamic> eventData,
    required bool isHost,
    required bool isParticipant,
  }) {
    final eventId = widget.eventId.trim();
    if (eventId.isEmpty || !mounted) return;

    final startAt = eventData['startAt'];
    final title = (eventData['title'] ?? '').toString().trim();
    final bannerUrl =
        (eventData['bannerUrl'] ?? eventData['bannerImagePath'] ?? '')
            .toString()
            .trim();
    final emoji =
        (eventData['eventAvatar'] ?? eventData['emoji'] ?? '').toString().trim();
    final locationName =
        (eventData['locationName'] ?? '').toString().trim();
    final participantsCount =
        int.tryParse('${eventData['participantsCount'] ?? 0}') ?? 0;

    showEventShareSheet(
      context,
      data: EventShareData(
        eventId: eventId,
        title: title,
        bannerUrl: bannerUrl,
        eventAvatar: emoji,
        tags: (eventData['tags'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        startAt: startAt is Timestamp ? startAt.toDate() : null,
        locationName: locationName,
        participantsCount: participantsCount,
        isHost: isHost,
        isParticipant: isParticipant,
      ),
      onShareInChat: () {
        if (!mounted) return;
        showShareToChatSheet(
          context,
          shareType: 'event_card',
          metadata: {
            'targetId': eventId,
            'title': title.isEmpty ? 'Event' : title,
            'bannerUrl': bannerUrl,
            'emoji': emoji,
            'subtitle': locationName.isNotEmpty
                ? locationName
                : participantsCount > 0
                    ? '$participantsCount going'
                    : '',
          },
        );
      },
    );
  }

  Future<void> _handleDeleteEvent() async {
    if (_currentUserId.isEmpty) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101726),
        title: const Text(
          'Delete event?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this event?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await _eventService.softDeleteEvent(
        eventId: widget.eventId,
        hostId: _currentUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event deleted. Chat is now closed.')),
      );
      Navigator.of(context).pop();
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.eventDeleteFailed,
        error: e,
        stackTrace: stack,
        where: 'event_detail._handleDeleteEvent',
      );
    }
  }

  Future<void> _handleLeaveEvent() async {
    if (_currentUserId.isEmpty) return;

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101726),
        title: const Text(
          'Leave event?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to leave this event?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (shouldLeave != true) return;

    try {
      await _eventService.removeUserFromEventAndChat(
        eventId: widget.eventId,
        userId: _currentUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You left the ${EventLabel.of(widget.eventId)}.')),
      );
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.eventLeaveFailed,
        error: e,
        stackTrace: stack,
        where: 'event_detail._handleLeaveEvent',
      );
    }
  }

  Future<void> _openParticipants({
    required String hostId,
    required String currentUserId,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventParticipantsScreen(
          eventId: widget.eventId,
          hostId: hostId,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadUsersByIds(List<String> ids) async {
    final uniqueIds = ids.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return const <Map<String, dynamic>>[];

    final snapshots = await Future.wait(
      uniqueIds.map(
        (uid) => FirebaseFirestore.instance.collection('users').doc(uid).get(),
      ),
    );

    return snapshots
        .map((doc) => {
              'id': doc.id,
              ...(doc.data() ?? const <String, dynamic>{}),
            })
        .toList();
  }

  Widget _buildParticipantsSection({
    required String hostId,
    required String currentUserId,
    required Map<String, dynamic> eventData,
  }) {
    final maxCapacity = int.tryParse('${eventData['maxCapacity'] ?? 0}') ?? 0;
    final activeParticipantsStream = FirebaseFirestore.instance
        .collection('event_participants')
        .doc(widget.eventId)
        .collection('users')
        .where('status', whereIn: const ['joined', 'active']).snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: activeParticipantsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final activeCount = docs.length;
        final goingCount = activeCount > 0
            ? activeCount
            : (int.tryParse('${eventData['participantsCount'] ?? 0}') ?? 0);
        final leftCount = maxCapacity <= 0
            ? 0
            : (maxCapacity - goingCount).clamp(0, maxCapacity);
        final topUserIds = docs
            .map((d) => (d.data()['userId'] ?? d.id).toString())
            .take(3)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'PARTICIPANTS',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _openParticipants(
                    hostId: hostId,
                    currentUserId: currentUserId,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A223E),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$goingCount going · $leftCount left',
                      style: const TextStyle(
                        color: Color(0xFF67B4FF),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openParticipants(
                hostId: hostId,
                currentUserId: currentUserId,
              ),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF070B14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadUsersByIds(topUserIds),
                      builder: (context, userSnapshot) {
                        final users =
                            userSnapshot.data ?? const <Map<String, dynamic>>[];
                        if (users.isEmpty) {
                          return const AppUserAvatar(radius: 20);
                        }

                        return SizedBox(
                          width: 44 + ((users.length - 1) * 28),
                          height: 44,
                          child: Stack(
                            children: [
                              for (int i = 0; i < users.length; i++)
                                Positioned(
                                  left: i * 28,
                                  child: AppUserAvatar(
                                    photoUrl: (users[i]['avatarUrl'] ??
                                            users[i]['avatar_url'] ??
                                            '')
                                        .toString(),
                                    radius: 22,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 14),
                    Text(
                      '$goingCount going · $leftCount left',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleJoinRequest() async {
    debugPrint('JOIN BUTTON TAP');
    if (_isRequesting) return;
    if (!await ActionGate.ensureCanAct(context,
        message: 'Complete your profile to join events.')) {
      return;
    }

    if (mounted) {
      setState(() {
        _isRequesting = true;
      });
    } else {
      return;
    }

    if (_currentUserId.isEmpty) {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please sign in to request joining this event.')),
        );
      }
      return;
    }

    try {
      debugPrint('REQUEST START');
      await _eventService.requestToJoinEvent(
        eventId: widget.eventId,
        userId: _currentUserId,
      );
      debugPrint('REQUEST SUCCESS');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request sent.')),
        );
      }
    } catch (e, stack) {
      debugPrint('REQUEST FAILED');
      if (!mounted) return;
      final isBlocked = e.toString().contains('block settings');
      ErrorHandler.showUserMessage(
        context,
        isBlocked
            ? AppErrorType.friendBlocked
            : AppErrorType.eventJoinRequestFailed,
        error: e,
        stackTrace: stack,
        where: 'event_detail_screen._handleRequestJoin',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }

  Future<void> _handleDirectJoin() async {
    debugPrint('JOIN BUTTON TAP');
    if (_isJoining) return;

    if (mounted) {
      setState(() {
        _isJoining = true;
      });
    } else {
      return;
    }

    if (_currentUserId.isEmpty) {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to join this event.')),
        );
      }
      return;
    }

    try {
      debugPrint('JOIN START');
      await _eventService.joinEventDirect(
        eventId: widget.eventId,
        userId: _currentUserId,
      );
      debugPrint('JOIN SUCCESS');
      // Notify friends who are already in this event — fire-and-forget.
      unawaited(ActivityNotificationService().sendFriendJoinedEventNotifications(
        joinerId: _currentUserId,
        eventId: widget.eventId,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You joined the ${EventLabel.of(widget.eventId)}.')),
        );
      }
    } catch (e, stack) {
      debugPrint('JOIN FAILED');
      if (!mounted) return;
      final isBlocked = e.toString().contains('block settings');
      ErrorHandler.showUserMessage(
        context,
        isBlocked ? AppErrorType.friendBlocked : AppErrorType.eventJoinFailed,
        error: e,
        stackTrace: stack,
        where: 'event_detail_screen._handleDirectJoin',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  Future<void> _handleJoinWaitlist() async {
    if (_isWaitlisting) return;
    if (!await ActionGate.ensureCanAct(context,
        message: 'Complete your profile to join events.')) {
      return;
    }
    if (mounted) setState(() => _isWaitlisting = true);
    try {
      await _eventService.joinWaitlist(eventId: widget.eventId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You're on the waitlist! We'll notify you if a spot opens."),
          ),
        );
      }
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.eventJoinFailed,
        error: e,
        stackTrace: stack,
        where: 'event_detail._handleJoinWaitlist',
      );
    } finally {
      if (mounted) setState(() => _isWaitlisting = false);
    }
  }

  Future<void> _handleLeaveWaitlist() async {
    if (_isWaitlisting) return;
    if (mounted) setState(() => _isWaitlisting = true);
    try {
      await _eventService.leaveWaitlist(eventId: widget.eventId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You left the waitlist.')),
        );
      }
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.eventLeaveFailed,
        error: e,
        stackTrace: stack,
        where: 'event_detail._handleLeaveWaitlist',
      );
    } finally {
      if (mounted) setState(() => _isWaitlisting = false);
    }
  }

  Widget _buildJoinButton({
    required Map<String, dynamic> eventData,
    required UserEventState userEventState,
  }) {
    final hostId =
        ((eventData['hostId'] ?? eventData['host_id']) ?? '').toString().trim();
    final isHost = hostId.isNotEmpty && hostId == _currentUserId;
    if (isHost) {
      return _actionButton('Host', Colors.grey[800]!, null);
    }

    final status = (eventData['status'] ?? 'active').toString().toLowerCase();
    final endAt = eventData['endAt'];
    final endTime = endAt is Timestamp
        ? endAt.toDate().toUtc()
        : (endAt is DateTime ? endAt.toUtc() : null);
    final isEnded = status == EventService.statusCompleted ||
        (endTime != null && endTime.isBefore(DateTime.now().toUtc()));
    if (isEnded) {
      return _actionButton('Event ended', Colors.grey[800]!, null);
    }

    if (userEventState == UserEventState.joined) {
      return _actionButton('Leave Event', Colors.redAccent, _handleLeaveEvent);
    }

    // Waitlist states — shown when event is full.
    if (userEventState == UserEventState.waitlisted) {
      return _actionButton(
        _isWaitlisting ? 'Leaving waitlist...' : 'On Waitlist — Leave',
        const Color(0xFFFF8C00),
        _isWaitlisting ? null : _handleLeaveWaitlist,
      );
    }

    final isApprovalRequired = eventData['isApprovalRequired'] == true;
    final isRequestLoading = _isRequesting;
    final isJoinLoading = _isJoining;

    // Check if event is full.
    final maxCap = int.tryParse('${eventData['maxCapacity'] ?? 0}') ?? 0;
    final pCount = int.tryParse('${eventData['participantsCount'] ?? 0}') ?? 0;
    final isFull = maxCap > 0 && pCount >= maxCap;

    if (userEventState == UserEventState.pending) {
      return _actionButton(
        isRequestLoading ? 'Requesting...' : 'Requested',
        YanegiColors.primary,
        null,
      );
    }

    // Event full and user not joined / pending → offer waitlist.
    if (isFull) {
      return _actionButton(
        _isWaitlisting ? 'Joining waitlist...' : 'Join Waitlist',
        const Color(0xFFFF8C00),
        _isWaitlisting ? null : _handleJoinWaitlist,
      );
    }

    return _actionButton(
      isApprovalRequired
          ? (isRequestLoading ? 'Requesting...' : 'Request to Join')
          : (isJoinLoading ? 'Joining...' : 'Join Event'),
      const Color(0xFF007BFF),
      isApprovalRequired
          ? (isRequestLoading ? null : _handleJoinRequest)
          : (isJoinLoading ? null : _handleDirectJoin),
    );
  }

  Widget _actionButton(String text, Color color, VoidCallback? onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic startAt) {
    if (startAt is! Timestamp) return 'Time unavailable';
    final start = startAt.toDate();
    return DateFormat('EEEE, MMM d • hh:mm a').format(start);
  }

  Widget _buildHostSection({
    required String? hostId,
    required Map<String, dynamic> eventData,
  }) {
    Widget buildTile({
      required String username,
      required String? avatarUrl,
    }) {
      return InkWell(
        onTap: hostId == null || hostId.isEmpty
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SocialProfileScreen(profileUserId: hostId),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              AppUserAvatar(photoUrl: avatarUrl, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'HOSTED BY',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      );
    }

    if (hostId == null || hostId.isEmpty) {
      final fallbackName =
          (eventData['hostName'] ?? eventData['host_name'] ?? 'Unknown')
              .toString();
      return buildTile(username: fallbackName, avatarUrl: null);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(hostId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return buildTile(username: 'Loading...', avatarUrl: null);
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          final fallbackName =
              (eventData['hostName'] ?? eventData['host_name'] ?? 'Unknown')
                  .toString();
          return buildTile(username: fallbackName, avatarUrl: null);
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>?;
        final username =
            (userData?['username'] ?? userData?['name'] ?? 'Unknown')
                .toString();
        final avatarUrl =
            (userData?['avatarUrl'] ?? userData?['avatar_url'])?.toString();

        return buildTile(username: username, avatarUrl: avatarUrl);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: YanegiColors.background,
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .doc(widget.eventId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            late final Map<String, dynamic> eventData;
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text(
                  'Event not found',
                  style: TextStyle(color: Colors.white),
                ),
              );
            } else {
              final model = EventModel.fromFirestore(snapshot.data!);
              eventData = <String, dynamic>{
                ...model.raw,
                'eventId': model.id,
                'title': model.title,
                'hostId': model.hostId,
                'status': model.status,
                'isActive': model.isActive,
                'visibility': model.visibility,
                'isApprovalRequired': model.isApprovalRequired,
                'participants': model.participants,
                'participantsCount': model.participantsCount,
                'maxCapacity': model.maxCapacity,
                'locationName': model.locationName,
                'bannerImagePath': model.bannerUrl,
                'bannerUrl': model.bannerUrl,
                if (model.startTime != null)
                  'startAt': Timestamp.fromDate(model.startTime!),
                if (model.endTime != null)
                  'endAt': Timestamp.fromDate(model.endTime!),
              };
            }

            final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
            final hostId = ((eventData['hostId'] ?? eventData['host_id']) ?? '')
                .toString()
                .trim();
            print('Current User: $currentUserId');
            print('Host ID: $hostId');

            if (hostId.isEmpty) {
              print(
                  'Warning: hostId missing in event document ${widget.eventId}');
            }

            final status =
                (eventData['status'] ?? 'active').toString().toLowerCase();
            final isDeleted =
                status == 'deleted' || eventData['isActive'] == false;

            if (isDeleted) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_busy,
                        color: Colors.white70,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Event no longer available',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Go back'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final isHost = currentUserId.isNotEmpty &&
                hostId.isNotEmpty &&
                currentUserId == hostId;
            final showHostDeleteMenu = isHost || _forceShowHostControlsForDebug;

            return Consumer(
              builder: (context, ref, _) {
                final participationStateAsync = currentUserId.isEmpty
                    ? const AsyncData<UserEventState>(
                        UserEventState.notJoined,
                      )
                    : ref
                        .watch(eventParticipationStateProvider(widget.eventId));

                final participationState =
                    participationStateAsync.valueOrNull ??
                        UserEventState.notJoined;
                final userState = (hostId.isNotEmpty && hostId == currentUserId)
                    ? UserEventState.joined
                    : participationState;

                return Stack(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Banner / Header
                          SizedBox(
                            height: 250,
                            width: double.infinity,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (eventData['bannerImagePath'] != null &&
                                    eventData['bannerImagePath']
                                        .toString()
                                        .isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: eventData['bannerImagePath'],
                                    fit: BoxFit.cover,
                                    memCacheWidth: 800,
                                    errorWidget: (context, url, err) =>
                                        Container(color: Colors.grey[800]),
                                  )
                                else
                                  Container(color: Colors.grey[800]),
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        YanegiColors.background,
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      stops: [0.55, 1.0],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: showHostDeleteMenu ? 52 : 8,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => _shareEvent(
                                      eventData: eventData,
                                      isHost: isHost,
                                      isParticipant: !isHost &&
                                          userState == UserEventState.joined,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: showHostDeleteMenu ? 96 : 52,
                                  child: _buildSaveToggleButton(),
                                ),
                                if (showHostDeleteMenu)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: PopupMenuButton<String>(
                                      color: const Color(0xFF131A27),
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.white,
                                      ),
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _handleDeleteEvent();
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Text('Delete Event'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 2. Title + Tags
                                Text(
                                  eventData['title'] ?? 'Event',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      (eventData['tags'] as List<dynamic>? ??
                                              ['Public Event'])
                                          .map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.blue.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            tag
                                                    .toString()
                                                    .toLowerCase()
                                                    .contains('game')
                                                ? Icons.sports_esports
                                                : Icons.public,
                                            size: 16,
                                            color: Colors.blueAccent,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            tag.toString(),
                                            style: const TextStyle(
                                              color: Colors.blueAccent,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 24),

                                // 3. Date & Time
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _formatDate(eventData['startAt']),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // 4. Location + Open in Maps + Meeting Point
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        eventData['locationName'] ??
                                            'Location to be announced',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                () {
                                  // Only joined participants (and the host,
                                  // who is forced to `joined`) get the
                                  // Open in Maps affordance. Visitors and
                                  // pending requesters see the location
                                  // text but no launch button.
                                  if (userState != UserEventState.joined) {
                                    return const SizedBox.shrink();
                                  }
                                  final coords = _extractCoordinates(eventData);
                                  final lat = coords.lat;
                                  final lng = coords.lng;
                                  if (lat == null || lng == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: BorderSide(
                                            color:
                                                Colors.white.withAlpha(60),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 12),
                                        ),
                                        onPressed: () => _openInMaps(
                                          latitude: lat,
                                          longitude: lng,
                                          label: (eventData['locationName']
                                                      ??
                                                  eventData['title'] ??
                                                  'Event location')
                                              .toString(),
                                        ),
                                        icon: const Icon(
                                          Icons.map_outlined,
                                          size: 18,
                                        ),
                                        label: const Text('Open in Maps'),
                                      ),
                                    ),
                                  );
                                }(),
                                Builder(builder: (_) {
                                  final mp = (eventData['meetingPoint'] ?? '')
                                      .toString()
                                      .trim();
                                  if (mp.isEmpty) return const SizedBox.shrink();
                                  return Column(
                                    children: [
                                      const SizedBox(height: 16),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[900],
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'MEETING POINT',
                                              style: TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              mp,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                }),

                                // 5. Host Section
                                _buildHostSection(
                                  hostId: hostId,
                                  eventData: eventData,
                                ),
                                const SizedBox(height: 12),
                                // Friends going social proof
                                if (currentUserId.isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: FriendsGoingStrip(
                                      eventId: widget.eventId,
                                      currentUserId: currentUserId,
                                    ),
                                  ),
                                if (hostId.isNotEmpty)
                                  _buildParticipantsSection(
                                    hostId: hostId,
                                    currentUserId: currentUserId,
                                    eventData: eventData,
                                  ),
                                const SizedBox(height: 24),

                                // 6. About Section
                                const Text(
                                  'About',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  eventData['description'] ??
                                      'No description provided.',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    height: 1.5,
                                    fontSize: 15,
                                  ),
                                  softWrap: true,
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Fixed CTA
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: _buildJoinButton(
                        eventData: eventData,
                        userEventState: userState,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
