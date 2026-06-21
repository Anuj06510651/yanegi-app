import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/activity_notification_model.dart';
import '../services/activity_notification_service.dart';
import '../services/notification_types.dart';
import '../theme/yanegi_theme.dart';
import '../widgets/app_avatars.dart';
import 'chat/chat_thread_screen.dart';
import 'event_detail_screen.dart';
import 'profile_social_screen.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const int _initialNotificationLimit = 20;

  final ActivityNotificationService _service = ActivityNotificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Set<String> _busyActionNotificationIds = <String>{};
  final Map<String, String> _eventNameCache = <String, String>{};
  final Set<String> _eventNameFetchInFlight = <String>{};
  final List<ActivityNotification> _olderNotifications =
      <ActivityNotification>[];
  bool _markReadInFlight = false;

  QueryDocumentSnapshot<Map<String, dynamic>>? _olderCursor;
  bool _isLoadingOlder = false;
  bool _hasMoreOlder = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapPaginationCursor();
      _markAllAsReadOnOpen();
    });
  }

  Future<void> _markAllAsReadOnOpen() async {
    try {
      await _service.markAllCurrentUserNotificationsAsRead();
    } catch (_) {
      // Keep screen usable if mark-all read fails.
    }
  }

  Future<void> _bootstrapPaginationCursor() async {
    try {
      final cursor = await _service.getLatestNotificationsCursor(
        limit: _initialNotificationLimit,
      );
      if (!mounted) return;
      setState(() {
        _olderCursor = cursor;
        _hasMoreOlder = cursor != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _olderCursor = null;
        _hasMoreOlder = false;
      });
    }
  }

  Future<void> _loadOlderNotifications() async {
    if (_isLoadingOlder || !_hasMoreOlder || _olderCursor == null) return;

    setState(() => _isLoadingOlder = true);
    try {
      final page = await _service.fetchOlderNotificationsPage(
        startAfter: _olderCursor!,
        limit: _initialNotificationLimit,
      );
      if (!mounted) return;
      setState(() {
        _olderNotifications.addAll(page.items);
        _olderCursor = page.lastVisible;
        _hasMoreOlder = page.hasMore;
      });
    } catch (_) {
      // Keep existing list; avoid hard-failing Activity UI.
    } finally {
      if (mounted) {
        setState(() => _isLoadingOlder = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D15),
      appBar: AppBar(
        title: const Text('Activity',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<ActivityNotification>>(
        stream: _service.getNotifications(limit: _initialNotificationLimit),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('Notifications stream error: ${snapshot.error}');
          }

          if (!snapshot.hasData) {
            return const NotificationSkeleton();
          }

          final docs = snapshot.data!;
          if (kDebugMode) {
            print('Notifications count: ${docs.length}');
          }

          final liveNotifications = docs;
          _syncReadStateForVisible(liveNotifications);

          final mergedById = <String, ActivityNotification>{};
          for (final item in _olderNotifications) {
            final key = item.id.trim().isNotEmpty
                ? item.id
                : '${item.type}_${item.senderId}_${item.createdAt.microsecondsSinceEpoch}';
            mergedById[key] = item;
          }
          for (final item in liveNotifications) {
            final key = item.id.trim().isNotEmpty
                ? item.id
                : '${item.type}_${item.senderId}_${item.createdAt.microsecondsSinceEpoch}';
            mergedById[key] = item;
          }

          final visibleNotifications = mergedById.values
              .where(_shouldDisplayNotification)
              .toList(growable: false);

          final grouped = _dedupeNotifications(visibleNotifications);
          _primeEventNameCache(grouped);

          if (grouped.isEmpty) {
            return Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'No activity yet',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          final sections = _groupIntoSections(grouped);
          final entries = <_ActivityListEntry>[];
          for (final section in sections) {
            entries.add(_ActivityHeaderEntry(section.title));
            for (final item in section.items) {
              entries.add(_ActivityItemEntry(item));
            }
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: entries.length + (_hasMoreOlder ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= entries.length) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed:
                          _isLoadingOlder ? null : _loadOlderNotifications,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withAlpha(40)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isLoadingOlder
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Load older activity',
                              style: TextStyle(color: Colors.white70),
                            ),
                    ),
                  ),
                );
              }

              final entry = entries[index];
              if (entry is _ActivityHeaderEntry) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    entry.title,
                    style: TextStyle(
                      color: Colors.white.withAlpha(165),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }

              return _buildNotificationItem(
                (entry as _ActivityItemEntry).item,
              );
            },
          );
        },
      ),
    );
  }

  void _syncReadStateForVisible(List<ActivityNotification> notifications) {
    if (_markReadInFlight) return;

    final unreadIds = notifications
        .where((n) => !n.isRead)
        .map((n) => n.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (unreadIds.isEmpty) return;

    _markReadInFlight = true;
    Future<void>(() async {
      try {
        await _service.markAllAsRead(unreadIds);
      } catch (_) {
        // Ignore read-sync failures to avoid blocking Activity UI.
      } finally {
        _markReadInFlight = false;
      }
    });
  }

  bool _shouldDisplayNotification(ActivityNotification notification) {
    final type = normalizeType(notification.type);
    final status = notification.actionStatus.trim().toLowerCase();

    if ((type == 'friend_request' &&
            (status == 'declined' || status == 'rejected')) ||
        type == 'friend_request_declined' ||
        type == NotificationType.eventReject) {
      return false;
    }

    final normalized = _normalizeActionText(notification);
    if (normalized.contains('declined your request') ||
        normalized == 'declined') {
      return false;
    }

    return true;
  }

  List<_NotificationGroupItem> _dedupeNotifications(
    List<ActivityNotification> notifications,
  ) {
    final sorted = [...notifications]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final groupedByKey = <String, List<ActivityNotification>>{};
    final keyOrder = <String>[];

    for (final n in sorted) {
      final shouldGroup = _canBeGrouped(n);
      final key = shouldGroup
          ? '${_bucketKey(n.createdAt)}|${n.type}|${n.senderId}|${_normalizeActionText(n)}'
          : '__single__${n.id}';

      final list = groupedByKey.putIfAbsent(key, () {
        keyOrder.add(key);
        return <ActivityNotification>[];
      });
      list.add(n);
    }

    return keyOrder.map((key) {
      final items = groupedByKey[key]!;
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return _NotificationGroupItem(notifications: items);
    }).toList()
      ..sort((a, b) => b.primary.createdAt.compareTo(a.primary.createdAt));
  }

  bool _canBeGrouped(ActivityNotification n) {
    final type = normalizeType(n.type);
    final actionStatus = n.actionStatus.trim().toLowerCase();
    if (type == NotificationType.friendRequest && actionStatus == 'pending') {
      return false;
    }
    if (type == NotificationType.eventRequest) return false;
    return true;
  }

  String _bucketKey(DateTime date) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    final day = DateTime(date.year, date.month, date.day);
    if (day == startOfToday) return 'today';
    if (day == startOfYesterday) return 'yesterday';
    return 'earlier';
  }

  List<_ActivitySection> _groupIntoSections(
      List<_NotificationGroupItem> items) {
    final today = <_NotificationGroupItem>[];
    final yesterday = <_NotificationGroupItem>[];
    final earlier = <_NotificationGroupItem>[];

    for (final item in items) {
      switch (_bucketKey(item.primary.createdAt)) {
        case 'today':
          today.add(item);
          break;
        case 'yesterday':
          yesterday.add(item);
          break;
        default:
          earlier.add(item);
      }
    }

    final sections = <_ActivitySection>[];
    if (today.isNotEmpty) sections.add(_ActivitySection('Today', today));
    if (yesterday.isNotEmpty) {
      sections.add(_ActivitySection('Yesterday', yesterday));
    }
    if (earlier.isNotEmpty) sections.add(_ActivitySection('Earlier', earlier));
    return sections;
  }

  void _primeEventNameCache(List<_NotificationGroupItem> grouped) {
    final missingIds = grouped
        .map((g) => g.primary.eventId?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .where((id) => !_eventNameCache.containsKey(id))
        .where((id) => !_eventNameFetchInFlight.contains(id))
        .toSet()
        .toList();

    if (missingIds.isEmpty) return;

    for (final id in missingIds) {
      _eventNameFetchInFlight.add(id);
    }

    Future<void>(() async {
      try {
        await Future.wait(missingIds.map((id) async {
          try {
            final doc = await _firestore.collection('events').doc(id).get();
            if (doc.exists) {
              final data = doc.data() ?? const <String, dynamic>{};
              _eventNameCache[id] =
                  (data['title'] ?? data['label'] ?? 'Event').toString();
            }
          } catch (_) {
            // Inaccessible event — leave for putIfAbsent fallback below.
          }
        }));
      } finally {
        for (final id in missingIds) {
          _eventNameFetchInFlight.remove(id);
          _eventNameCache.putIfAbsent(id, () => 'Event');
        }
        if (mounted) setState(() {});
      }
    });
  }

  Widget _buildNotificationItem(_NotificationGroupItem item) {
    final notification = item.primary;
    final friendActionStatus = notification.actionStatus.trim().isEmpty
        ? 'pending'
        : notification.actionStatus.trim().toLowerCase();
    final normalizedType = normalizeType(notification.type);
    final isFriendRequest = normalizedType == NotificationType.friendRequest;
    final isUnread = item.notifications.any((n) => !n.isRead);
    final isBusy = _busyActionNotificationIds.contains(notification.id);
    final line1Action = _line1ActionText(notification, item.count);
    final eventName = _resolveEventName(notification);
    final line2Text = _line2Text(notification, eventName);

    final senderStyle = TextStyle(
      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
      color: isUnread ? Colors.white : Colors.white.withAlpha(195),
    );
    final messageStyle = TextStyle(
      color: isUnread ? Colors.white : Colors.white.withAlpha(170),
      fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
    );
    final eventAccentMessageStyle = messageStyle.copyWith(
      color: const Color(0xFF67B4FF),
      fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
    );

    return InkWell(
      onTap: () => _handleNotificationGroupTap(item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isUnread ? Colors.white.withAlpha(12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNotificationLeadingMedia(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14),
                      children: [
                        TextSpan(
                          text: notification.senderName,
                          style: senderStyle,
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _openProfile(notification),
                        ),
                        TextSpan(
                          text: ' $line1Action',
                          style: _isEventRelated(notification)
                              ? eventAccentMessageStyle
                              : messageStyle,
                        ),
                      ],
                    ),
                  ),
                  if (line2Text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildSecondLine(
                      notification: notification,
                      eventName: eventName,
                      fallbackText: line2Text,
                      style: TextStyle(
                        color: isUnread
                            ? const Color(0xFF9BCFFF)
                            : const Color(0xFF82B8E9),
                        fontWeight:
                            isUnread ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${_getTimeAgo(notification.createdAt)}${item.count > 1 ? ' • ${item.count} notifications' : ''}',
                    style: TextStyle(
                      color: isUnread ? Colors.white70 : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  if ((normalizedType == NotificationType.friendRequest ||
                          normalizedType == NotificationType.eventRequest) &&
                      item.count == 1 &&
                      (!isFriendRequest || friendActionStatus == 'pending'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: YanegiColors.primary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: isBusy
                                  ? null
                                  : () => _handleAccept(notification),
                              child: const Text('Accept',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                side: BorderSide(
                                    color: Colors.white.withAlpha(50)),
                              ),
                              onPressed: isBusy
                                  ? null
                                  : () => _handleDecline(notification),
                              child: const Text('Decline',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondLine({
    required ActivityNotification notification,
    required String eventName,
    required String fallbackText,
    required TextStyle style,
  }) {
    if ((notification.eventId ?? '').trim().isNotEmpty && eventName.isNotEmpty) {
      return RichText(
        text: TextSpan(
          style: style,
          children: [
            TextSpan(
              text: eventName,
              style: style.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: style.color,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => _openEvent(notification),
            ),
          ],
        ),
      );
    }

    if (fallbackText.isNotEmpty) {
      return Text(fallbackText, style: style);
    }

    return const SizedBox.shrink();
  }

  String _resolveEventName(ActivityNotification notification) {
    final eventId = (notification.eventId ?? '').trim();
    if (eventId.isEmpty) return 'Event';
    return _eventNameCache[eventId] ?? 'Event';
  }

  String _normalizeActionText(ActivityNotification notification) {
    final status = notification.actionStatus.trim().toLowerCase();
    final type = normalizeType(notification.type);

    if (type == NotificationType.friendRequest && status == 'accepted') {
      return 'accepted';
    }
    if (type == NotificationType.friendRequest && status == 'declined') {
      return 'declined';
    }
    if (type == NotificationType.friendAccept) {
      return 'accepted';
    }
    if (type == NotificationType.eventAccept) {
      return 'approved';
    }
    return (notification.message ?? notification.title).toLowerCase().trim();
  }

  String _line1ActionText(ActivityNotification notification, int count) {
    final normalized = _normalizeActionText(notification);
    final normalizedLower = normalized.toLowerCase();
    if (count > 1 && normalized.contains('accept')) {
      return 'accepted $count requests';
    }

    final status = notification.actionStatus.trim().toLowerCase();
    final type = normalizeType(notification.type);

    if (type == NotificationType.friendRequest) {
      if (status == 'accepted') return 'accepted your request';
      if (status == 'declined' || status == 'rejected') {
        return 'declined your request';
      }
      return 'sent you a friend request';
    }

    if (type == NotificationType.friendAccept) {
      return 'accepted your request';
    }

    if (type == NotificationType.eventRequest) {
      return 'requested to join your event';
    }

    if (type == NotificationType.eventAccept) {
      final raw = (notification.message ?? notification.title).trim();
      final rawLower = raw.toLowerCase();
      if (rawLower.startsWith('accepted ') ||
          rawLower.startsWith('you accepted')) {
        return raw;
      }
      return 'accepted your event request';
    }

    if (type == NotificationType.eventReject) {
      return 'declined your event request';
    }

    if (type == NotificationType.eventCreated) {
      return 'posted a new event nearby';
    }

    if (type == NotificationType.chatMessage) {
      final raw = (notification.message ?? '').trim();
      if (raw.isNotEmpty) return raw;
      return 'sent you a message';
    }

    if (type == NotificationType.mention) {
      final raw = (notification.message ?? '').trim();
      if (raw.isNotEmpty) return raw;
      return 'mentioned you in a group';
    }

    if (type == NotificationType.friendJoinedEvent) {
      final raw = (notification.message ?? notification.title).trim();
      if (raw.isNotEmpty) return raw;
      return 'joined an event';
    }

    if (type == NotificationType.waitlistSpotAvailable) {
      final raw = (notification.message ?? '').trim();
      if (raw.isNotEmpty) return raw;
      return 'A spot opened — join now!';
    }

    if (type == NotificationType.shoutout) {
      final raw = (notification.message ?? notification.title)
          .trim()
          .replaceAll(RegExp(r'\s*🎉\s*$'), '')
          .trim();
      if (raw.isNotEmpty) return raw;
      return 'gave you a shoutout';
    }

    if (type == NotificationType.postEventRecap) {
      return 'How was your event? Share your recap';
    }

    if (normalizedLower.contains('wants to join your event') ||
        normalizedLower.contains('requested to join your event')) {
      return 'requested to join your event';
    }

    if (normalizedLower.contains('accepted your event request') ||
        normalizedLower.contains('accepted your request to join')) {
      return 'accepted your event request';
    }

    if (normalizedLower.contains('approved your request')) {
      return 'approved your request';
    }

    if (normalizedLower.contains('friend request')) {
      return 'sent you a friend request';
    }

    if (normalizedLower.contains('new message')) {
      return 'sent a new message';
    }

    final msg = (notification.message ?? notification.title).trim();
    return msg.isEmpty ? 'sent an update' : msg;
  }

  String _line2Text(ActivityNotification notification, String eventName) {
    final type = normalizeType(notification.type);
    if (type == NotificationType.chatMessage) {
      if ((notification.eventId ?? '').trim().isNotEmpty &&
          eventName.isNotEmpty) {
        return eventName;
      }
      return 'Open conversation';
    }
    if ((notification.eventId ?? '').trim().isNotEmpty) {
      return eventName.isNotEmpty ? eventName : '';
    }
    return '';
  }

  bool _isEventRelated(ActivityNotification notification) {
    final type = normalizeType(notification.type);
    return type == NotificationType.eventRequest ||
        type == NotificationType.eventAccept ||
        type == NotificationType.eventReject ||
        type == NotificationType.eventCreated;
  }

  Widget _buildNotificationLeadingMedia(_NotificationGroupItem item) {
    final notification = item.primary;
    final type = normalizeType(notification.type);
    final bannerUrl = notification.eventBannerUrl.trim();
    final avatarUrl = notification.senderAvatar.trim();

    // Join request: the REQUESTER is acting — show their profile photo.
    if (type == NotificationType.eventRequest) {
      return AppUserAvatar(photoUrl: avatarUrl, radius: 22);
    }

    // Event outcomes and reminders: the EVENT is acting — show event cover.
    if (type == NotificationType.eventAccept ||
        type == NotificationType.eventReject ||
        type == NotificationType.eventCreated ||
        type == NotificationType.waitlistSpotAvailable ||
        type == NotificationType.postEventRecap) {
      return _buildEventThumbnail(bannerUrl);
    }

    // Chat: DM → sender photo; group chat → event cover.
    if (type == NotificationType.chatMessage) {
      final chatId = (notification.chatId ?? '').trim();
      if (chatId.startsWith('grp_')) {
        return _buildEventThumbnail(bannerUrl);
      }
      return AppUserAvatar(photoUrl: avatarUrl, radius: 22);
    }

    // All other types (friend request, accept, mention, shoutout,
    // friend_joined_event): show the sender's profile photo.
    return AppUserAvatar(photoUrl: avatarUrl, radius: 22);
  }

  Widget _buildEventThumbnail(String bannerUrl) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(45),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: bannerUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: bannerUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 120),
                memCacheWidth: 92,
                memCacheHeight: 92,
                errorWidget: (_, __, ___) => _eventIconFallback(),
              )
            : _eventIconFallback(),
      ),
    );
  }

  Widget _eventIconFallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [YanegiColors.surfaceElevated, YanegiColors.surface],
        ),
      ),
      child: const Center(
        child: Icon(Icons.event_rounded, color: Colors.white54, size: 20),
      ),
    );
  }

  Future<void> _handleAccept(ActivityNotification notification) async {
    if (_busyActionNotificationIds.contains(notification.id)) return;
    setState(() => _busyActionNotificationIds.add(notification.id));

    try {
      final type = normalizeType(notification.type);
      if (type == NotificationType.friendRequest) {
        await _service.acceptFriendRequest(notification);
      } else if (type == NotificationType.eventRequest) {
        final accepted = await _service.acceptEventRequest(notification);
        if (!accepted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not approve request. Please try again.'),
            ),
          );
        }
      }
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final String display;
      if (msg.contains('already ended') || msg.contains('no longer active')) {
        display = 'This event has already ended. The request has been cancelled.';
      } else if (msg.contains('is full')) {
        display = 'The event is full. Cannot approve more participants.';
      } else {
        display = 'Could not approve request. Please try again.';
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(display)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _busyActionNotificationIds.remove(notification.id));
      }
    }
  }

  Widget _fallbackMedia({required IconData icon}) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white12,
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white70),
    );
  }

  Future<void> _handleNotificationGroupTap(_NotificationGroupItem item) async {
    final idsToMarkRead = item.notifications
        .where((n) => !n.isRead)
        .map((n) => n.id)
        .where((id) => id.trim().isNotEmpty)
        .toList();
    if (idsToMarkRead.isNotEmpty) {
      await _service.markAllAsRead(idsToMarkRead);
    }
    await _handleNotificationTap(item.primary, skipMarkRead: true);
  }

  Future<void> _openProfile(ActivityNotification notification) async {
    if (!mounted) return;
    if (notification.senderId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not available.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SocialProfileScreen(profileUserId: notification.senderId),
      ),
    );
  }

  Future<void> _openEvent(ActivityNotification notification) async {
    if (!mounted) return;
    final eventId = notification.eventId?.trim() ?? '';
    if (eventId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event not available.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(eventId: eventId),
      ),
    );
  }

  Future<void> _handleDecline(ActivityNotification notification) async {
    if (_busyActionNotificationIds.contains(notification.id)) return;
    setState(() => _busyActionNotificationIds.add(notification.id));

    try {
      final type = normalizeType(notification.type);
      if (type == NotificationType.friendRequest) {
        await _service.declineFriendRequest(notification);
      } else if (type == NotificationType.eventRequest) {
        await _service.declineEventRequest(notification);
      }
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message.toLowerCase();
      final String display = (msg.contains('no pending') ||
              msg.contains('already') ||
              msg.contains('not found'))
          ? 'This request is no longer pending.'
          : 'Could not decline request. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(display)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _busyActionNotificationIds.remove(notification.id));
      }
    }
  }

  Future<void> _handleNotificationTap(
    ActivityNotification notification, {
    bool skipMarkRead = false,
  }) async {
    print('Notification tapped: ${notification.type}');

    if (!skipMarkRead && !notification.isRead) {
      await _service.markAsRead(notification.id);
    }

    switch (normalizeType(notification.type)) {
      case NotificationType.friendRequest:
      case NotificationType.friendAccept:
      case 'friend_request_declined':
        await _openProfile(notification);
        return;

      case NotificationType.eventRequest:
      case NotificationType.eventAccept:
      case NotificationType.eventReject:
      case NotificationType.eventCreated:
        await _openEvent(notification);
        return;

      case NotificationType.chatMessage:
        if (!mounted) return;
        final chatId = notification.chatId?.trim() ?? '';
        if (chatId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat not available.')),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatThreadScreen(
              chatId: chatId,
              title: chatId.startsWith('grp_')
                  ? 'Group Chat'
                  : notification.senderName,
              isGroup: chatId.startsWith('grp_'),
            ),
          ),
        );
        return;

      default:
        return;
    }
  }

  String _getTimeAgo(DateTime date) {
    final difference = DateTime.now().difference(date);

    if (difference.isNegative) return 'Just now';

    if (difference.inDays >= 30) {
      return DateFormat('d MMM').format(date);
    } else if (difference.inDays >= 7) {
      return '${difference.inDays ~/ 7}w';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'Just now';
    }
  }
}

class _ActivitySection {
  final String title;
  final List<_NotificationGroupItem> items;

  const _ActivitySection(this.title, this.items);
}

class NotificationSkeleton extends StatelessWidget {
  const NotificationSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationGroupItem {
  final List<ActivityNotification> notifications;

  const _NotificationGroupItem({required this.notifications});

  ActivityNotification get primary => notifications.first;
  int get count => notifications.length;
}

sealed class _ActivityListEntry {
  const _ActivityListEntry();
}

class _ActivityHeaderEntry extends _ActivityListEntry {
  final String title;
  const _ActivityHeaderEntry(this.title);
}

class _ActivityItemEntry extends _ActivityListEntry {
  final _NotificationGroupItem item;
  const _ActivityItemEntry(this.item);
}
