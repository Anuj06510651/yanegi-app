import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../chat/data/firebase_chat_repository.dart';
import '../services/friend_service.dart';
import '../theme/yanegi_theme.dart';
import '../widgets/app_avatars.dart';
import 'event_detail_screen.dart';
import 'profile_social_screen.dart';
import 'chat/chat_thread_screen.dart';

class ConnectionsScreen extends StatefulWidget {
  final String userId;
  final String initialTab; // friends | joined | hosted

  const ConnectionsScreen({
    super.key,
    required this.userId,
    required this.initialTab,
  });

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FriendService _friendService = FriendService();
  final FirebaseChatRepository _chatRepository = FirebaseChatRepository();

  final Map<String, Map<String, dynamic>> _userCache =
      <String, Map<String, dynamic>>{};
  late final TabController _tabController;
  late int _currentIndex;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isOwnProfile =>
      _currentUid.isNotEmpty && _currentUid == widget.userId;

  void _handleTabChanged() {
    if (!mounted) return;
    if (_currentIndex == _tabController.index) return;
    setState(() => _currentIndex = _tabController.index);
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = _tabIndexFromInput(widget.initialTab);
    _tabController =
        TabController(length: 3, vsync: this, initialIndex: _currentIndex)
          ..addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  int _tabIndexFromInput(String input) {
    switch (input.trim().toLowerCase()) {
      case 'joined':
        return 1;
      case 'hosted':
        return 2;
      case 'friends':
      default:
        return 0;
    }
  }

  String _titleForIndex(int index) {
    switch (index) {
      case 1:
        return 'Joined Events';
      case 2:
        return 'Hosted Events';
      case 0:
      default:
        return 'Friends';
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsersByIds(
      List<String> ids) async {
    final filteredIds = ids.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (filteredIds.isEmpty) return <String, Map<String, dynamic>>{};

    final missingIds =
        filteredIds.where((id) => !_userCache.containsKey(id)).toList();

    for (int i = 0; i < missingIds.length; i += 10) {
      final chunk = missingIds.skip(i).take(10).toList();
      final snapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in snapshot.docs) {
        _userCache[doc.id] = doc.data();
      }
    }

    final out = <String, Map<String, dynamic>>{};
    for (final id in filteredIds) {
      out[id] = _userCache[id] ?? const <String, dynamic>{};
    }
    return out;
  }

  Future<void> _openAvatarViewer(String avatarUrl) async {
    final trimmed = avatarUrl.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No avatar available.')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: trimmed,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Future<void> _openProfile(String userId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SocialProfileScreen(profileUserId: userId),
      ),
    );
  }

  Future<void> _openDm({required String friendId, required String name}) async {
    if (_currentUid.isEmpty || friendId.trim().isEmpty) return;

    final chatId = await _chatRepository.createOrGetDM(_currentUid, friendId);
    if (!mounted) return;
    if (chatId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat unavailable for this user.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          chatId: chatId,
          title: name,
          isGroup: false,
          peerUserId: friendId,
        ),
      ),
    );
  }

  Future<void> _sendFriendRequest(String targetUid) async {
    final sent = await _friendService.sendFriendRequest(targetUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            sent ? 'Friend request sent.' : 'Could not send friend request.'),
      ),
    );
  }

  Future<void> _removeFriend(String targetUid) async {
    final removed = await _friendService.removeFriend(targetUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(removed ? 'Friend removed.' : 'Could not remove friend.'),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(color: YanegiColors.textSecondary),
      ),
    );
  }

  Widget _buildFriendTile({
    required String friendId,
    required Map<String, dynamic> user,
    required Widget trailing,
  }) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final targetUserId = friendId;
    final name = (user['name'] ?? user['username'] ?? 'User').toString();
    final usernameRaw = (user['username'] ?? '').toString().trim();
    final username = usernameRaw.isNotEmpty
        ? (usernameRaw.startsWith('@') ? usernameRaw : '@$usernameRaw')
        : '@user';
    final avatarUrl =
        (user['avatarUrl'] ?? user['avatar_url'] ?? '').toString();

    if (targetUserId == currentUserId && currentUserId.isNotEmpty) {
      if (kDebugMode) {
        print('Rendering self profile - no actions');
      }

      return ListTile(
        leading: GestureDetector(
          onTap: () => _openAvatarViewer(avatarUrl),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white24,
            backgroundImage: avatarUrl.trim().isNotEmpty
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl.trim().isEmpty
                ? const Icon(Icons.person, color: Colors.white)
                : null,
          ),
        ),
        title: GestureDetector(
          onTap: () => _openProfile(friendId),
          child: Text(
            '$name (You)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: YanegiColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        subtitle: GestureDetector(
          onTap: () => _openProfile(friendId),
          child: Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: YanegiColors.textSecondary),
          ),
        ),
        trailing: const SizedBox.shrink(),
      );
    }

    return ListTile(
      leading: GestureDetector(
        onTap: () => _openAvatarViewer(avatarUrl),
        child: AppUserAvatar(photoUrl: avatarUrl, radius: 22),
      ),
      title: GestureDetector(
        onTap: () => _openProfile(friendId),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: YanegiColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      subtitle: GestureDetector(
        onTap: () => _openProfile(friendId),
        child: Text(
          username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: YanegiColors.textSecondary),
        ),
      ),
      trailing: trailing,
    );
  }

  Widget _buildFriendsTab() {
    if (widget.userId.trim().isEmpty) {
      return _buildEmptyState('No friends yet');
    }

    final targetFriendsStream = _firestore
        .collection('friends')
        .doc(widget.userId)
        .collection('list')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: targetFriendsStream,
      builder: (context, targetFriendsSnapshot) {
        if (targetFriendsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final targetIds =
            targetFriendsSnapshot.data?.docs.map((d) => d.id).toList() ??
                <String>[];
        if (targetIds.isEmpty) {
          return _buildEmptyState('No friends yet');
        }

        if (_isOwnProfile) {
          return FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: _loadUsersByIds(targetIds),
            builder: (context, usersSnapshot) {
              if (usersSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users =
                  usersSnapshot.data ?? const <String, Map<String, dynamic>>{};

              return ListView.separated(
                itemCount: targetIds.length,
                separatorBuilder: (_, __) => Divider(
                  color: YanegiColors.textSecondary.withAlpha(28),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final friendId = targetIds[index];
                  final user = users[friendId] ?? const <String, dynamic>{};
                  final displayName =
                      (user['name'] ?? user['username'] ?? 'User').toString();

                  return _buildFriendTile(
                    friendId: friendId,
                    user: user,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                            color: YanegiColors.textSecondary,
                          ),
                          onPressed: friendId == _currentUid
                              ? null
                              : () => _openDm(
                                  friendId: friendId, name: displayName),
                        ),
                        PopupMenuButton<String>(
                          color: const Color(0xFF131A27),
                          icon: const Icon(
                            Icons.more_vert,
                            color: YanegiColors.textSecondary,
                            size: 20,
                          ),
                          onSelected: (value) {
                            if (value == 'remove' && friendId != _currentUid) {
                              _removeFriend(friendId);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem<String>(
                              value: 'remove',
                              child: Text(
                                'Remove Friend',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        }

        if (_currentUid.isEmpty) {
          return FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: _loadUsersByIds(targetIds),
            builder: (context, usersSnapshot) {
              if (usersSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users =
                  usersSnapshot.data ?? const <String, Map<String, dynamic>>{};

              return ListView.separated(
                itemCount: targetIds.length,
                separatorBuilder: (_, __) => Divider(
                  color: YanegiColors.textSecondary.withAlpha(28),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final friendId = targetIds[index];
                  final user = users[friendId] ?? const <String, dynamic>{};
                  return _buildFriendTile(
                    friendId: friendId,
                    user: user,
                    trailing: const SizedBox.shrink(),
                  );
                },
              );
            },
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('friends')
              .doc(_currentUid)
              .collection('list')
              .snapshots(),
          builder: (context, myFriendsSnapshot) {
            final myFriendIds =
                myFriendsSnapshot.data?.docs.map((d) => d.id).toSet() ??
                    <String>{};

            final mutual = targetIds.where(myFriendIds.contains).toList();
            final others =
                targetIds.where((id) => !myFriendIds.contains(id)).toList();
            final allIds = <String>[...mutual, ...others];

            return FutureBuilder<Map<String, Map<String, dynamic>>>(
              future: _loadUsersByIds(allIds),
              builder: (context, usersSnapshot) {
                if (usersSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = usersSnapshot.data ??
                    const <String, Map<String, dynamic>>{};

                return ListView(
                  children: [
                    if (mutual.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Text(
                          'Mutual Friends',
                          style: TextStyle(
                            color: YanegiColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      ...mutual.map((friendId) {
                        final user =
                            users[friendId] ?? const <String, dynamic>{};
                        final name =
                            (user['name'] ?? user['username'] ?? 'User')
                                .toString();
                        return _buildFriendTile(
                          friendId: friendId,
                          user: user,
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 20,
                              color: YanegiColors.textSecondary,
                            ),
                            onPressed: () =>
                                _openDm(friendId: friendId, name: name),
                          ),
                        );
                      }),
                    ],
                    if (others.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Text(
                          'Other Friends',
                          style: TextStyle(
                            color: YanegiColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      ...others.map((friendId) {
                        final user =
                            users[friendId] ?? const <String, dynamic>{};
                        final name =
                            (user['name'] ?? user['username'] ?? 'User')
                                .toString();
                        return _buildFriendTile(
                          friendId: friendId,
                          user: user,
                          trailing: StreamBuilder<FriendRelationshipState>(
                            stream: _friendService.friendStateStream(
                                _currentUid, friendId),
                            builder: (context, stateSnapshot) {
                              final state = stateSnapshot.data ??
                                  FriendRelationshipState.notFriend;
                              if (state == FriendRelationshipState.friend) {
                                return IconButton(
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 20,
                                    color: YanegiColors.textSecondary,
                                  ),
                                  onPressed: () =>
                                      _openDm(friendId: friendId, name: name),
                                );
                              }

                              if (state ==
                                  FriendRelationshipState.requestSent) {
                                return const Text(
                                  'Requested',
                                  style: TextStyle(
                                      color: YanegiColors.textSecondary),
                                );
                              }

                              return TextButton(
                                onPressed: () => _sendFriendRequest(friendId),
                                child: const Text('Add Friend'),
                              );
                            },
                          ),
                        );
                      }),
                    ],
                    if (mutual.isEmpty && others.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: _buildEmptyState('No friends yet'),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<_EventSummary>> _fetchEventsByIds(Set<String> eventIds) async {
    if (eventIds.isEmpty) return const <_EventSummary>[];

    final results = await Future.wait(eventIds.map((id) async {
      try {
        return await _firestore.collection('events').doc(id).get();
      } catch (_) {
        return null;
      }
    }));

    final items = <_EventSummary>[];
    for (final doc in results) {
      if (doc == null || !doc.exists) continue;
      final data = doc.data() ?? const <String, dynamic>{};
      final status = (data['status'] ?? 'active').toString().toLowerCase();
      // Show active and completed events; only hide explicitly deleted ones.
      if (status == 'deleted') continue;
      final eventDate = _EventSummary._extractEventDate(data);
      final timeLabel = (data['timeLabel'] ?? data['time'] ?? '').toString().trim();
      items.add(_EventSummary(
        id: doc.id,
        title: (data['title'] ?? data['label'] ?? 'Untitled Event').toString(),
        location: (data['locationName'] ?? data['locationText'] ?? 'Location TBD').toString(),
        bannerUrl: (data['bannerUrl'] ?? data['bannerImagePath'] ?? '').toString(),
        eventDate: eventDate,
        dateLabel: eventDate != null
            ? DateFormat('EEE, MMM d • h:mm a').format(eventDate)
            : (timeLabel.isNotEmpty ? timeLabel : 'Event date'),
      ));
    }
    items.sort((a, b) {
      if (a.eventDate == null && b.eventDate == null) return 0;
      if (a.eventDate == null) return 1;
      if (b.eventDate == null) return -1;
      return b.eventDate!.compareTo(a.eventDate!);
    });
    return items;
  }

  Future<List<_EventSummary>> _loadJoinedEvents(String userId) async {
    if (userId.trim().isEmpty) return const <_EventSummary>[];

    final participantSnapshot = await _firestore
        .collectionGroup('users')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: const ['joined', 'active']).get();

    final eventIds = <String>{};
    for (final doc in participantSnapshot.docs) {
      final data = doc.data();
      final dataEventId = (data['eventId'] ?? '').toString();
      final pathEventId = doc.reference.parent.parent?.id ?? '';
      if (dataEventId.trim().isNotEmpty) {
        eventIds.add(dataEventId);
      } else if (pathEventId.trim().isNotEmpty) {
        eventIds.add(pathEventId);
      }
    }

    if (eventIds.isEmpty) {
      final legacy = await _firestore
          .collection('events')
          .where('participants', arrayContains: userId)
          .where('status', isEqualTo: 'active')
          .limit(150)
          .get();
      return legacy.docs.map((doc) => _EventSummary.fromDoc(doc)).toList();
    }

    return _fetchEventsByIds(eventIds);
  }

  Future<List<_EventSummary>> _loadHostedEvents(String userId) async {
    if (userId.trim().isEmpty) return const <_EventSummary>[];

    debugPrint('EVENTS QUERY: loadHostedEvents connectionUserId=$userId');
    // Include active AND completed events so past hosting history is visible.
    // Only public events are shown (respect the host's visibility setting).
    final hostedModern = await _firestore
        .collection('events')
        .where('hostId', isEqualTo: userId)
        .where('visibility', isEqualTo: 'public')
        .limit(150)
        .get();

    final hostedLegacy = await _firestore
        .collection('events')
        .where('host_id', isEqualTo: userId)
        .where('visibility', isEqualTo: 'public')
        .limit(150)
        .get();

    final dedupe = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in hostedModern.docs) {
      final s = (doc.data()['status'] ?? '').toString().toLowerCase();
      if (s != 'deleted') dedupe[doc.id] = doc;
    }
    for (final doc in hostedLegacy.docs) {
      final s = (doc.data()['status'] ?? '').toString().toLowerCase();
      if (s != 'deleted') dedupe[doc.id] = doc;
    }

    final items =
        dedupe.values.map((doc) => _EventSummary.fromDoc(doc)).toList();
    items.sort((a, b) {
      if (a.eventDate == null && b.eventDate == null) return 0;
      if (a.eventDate == null) return 1;
      if (b.eventDate == null) return -1;
      return b.eventDate!.compareTo(a.eventDate!);
    });

    return items;
  }

  Widget _buildEventsTab({
    required Future<List<_EventSummary>> future,
    required String emptyMessage,
  }) {
    return FutureBuilder<List<_EventSummary>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final events = snapshot.data ?? const <_EventSummary>[];
        if (events.isEmpty) return _buildEmptyState(emptyMessage);

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final event = events[index];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDetailScreen(eventId: event.id),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: YanegiColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: YanegiColors.textSecondary.withAlpha(28)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                      ),
                      child: SizedBox(
                        height: 140,
                        width: double.infinity,
                        child: event.bannerUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: event.bannerUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 600,
                                memCacheHeight: 280,
                                errorWidget: (_, __, ___) =>
                                    _eventBannerFallback(),
                              )
                            : _eventBannerFallback(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YanegiColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            event.dateLabel,
                            style: const TextStyle(
                              color: YanegiColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            event.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YanegiColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _eventBannerFallback() {
    return Container(
      color: const Color(0xFF1B2231),
      child: const Center(
        child: Icon(Icons.event, color: Colors.white54, size: 34),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.trim().isEmpty) {
      return Scaffold(
        backgroundColor: YanegiColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title:
              const Text('Connections', style: TextStyle(color: Colors.white)),
        ),
        body: _buildEmptyState('No user selected'),
      );
    }

    return Scaffold(
      backgroundColor: YanegiColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _titleForIndex(_currentIndex),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: YanegiColors.primary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Joined'),
            Tab(text: 'Hosted'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(),
          _buildEventsTab(
            future: _loadJoinedEvents(widget.userId),
            emptyMessage: 'No events joined',
          ),
          _buildEventsTab(
            future: _loadHostedEvents(widget.userId),
            emptyMessage: 'No events hosted',
          ),
        ],
      ),
    );
  }
}

class _EventSummary {
  final String id;
  final String title;
  final String location;
  final String bannerUrl;
  final DateTime? eventDate;
  final String dateLabel;

  const _EventSummary({
    required this.id,
    required this.title,
    required this.location,
    required this.bannerUrl,
    required this.eventDate,
    required this.dateLabel,
  });

  static _EventSummary fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final eventDate = _extractEventDate(data);
    final timeLabel =
        (data['timeLabel'] ?? data['time'] ?? '').toString().trim();

    return _EventSummary(
      id: doc.id,
      title: (data['title'] ?? data['label'] ?? 'Untitled Event').toString(),
      location: (data['locationName'] ?? data['locationText'] ?? 'Location TBD')
          .toString(),
      bannerUrl:
          (data['bannerUrl'] ?? data['bannerImagePath'] ?? '').toString(),
      eventDate: eventDate,
      dateLabel: eventDate != null
          ? DateFormat('EEE, MMM d • h:mm a').format(eventDate)
          : (timeLabel.isNotEmpty ? timeLabel : 'Event date'),
    );
  }

  static DateTime? _extractEventDate(Map<String, dynamic> data) {
    final directCandidates = <dynamic>[
      data['eventDateTime'],
      data['eventDate'],
      data['date'],
      data['startAt'],
      data['startsAt'],
      data['startTime'],
      data['endAt'],
      data['endsAt'],
      data['endTime'],
      data['timestamp'],
      data['time'],
      data['createdAt'],
      data['created_at'],
      data['updatedAt'],
      data['updated_at'],
    ];

    for (final value in directCandidates) {
      final parsed = _parseDate(value);
      if (parsed != null) return parsed;
    }

    final schedule = data['schedule'];
    if (schedule is Map<String, dynamic>) {
      final scheduleCandidates = <dynamic>[
        schedule['date'],
        schedule['eventDate'],
        schedule['startAt'],
        schedule['startTime'],
        schedule['endAt'],
        schedule['endTime'],
      ];
      for (final value in scheduleCandidates) {
        final parsed = _parseDate(value);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      final millis = value < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (value is num) {
      final intValue = value.toInt();
      final millis = intValue < 100000000000 ? intValue * 1000 : intValue;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (value is Map<String, dynamic>) {
      final seconds = value['_seconds'] ?? value['seconds'];
      final nanos = value['_nanoseconds'] ?? value['nanoseconds'] ?? 0;
      if (seconds is num && nanos is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds.toInt() * 1000) + (nanos.toInt() ~/ 1000000),
        );
      }
    }
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return null;

      final numeric = int.tryParse(raw);
      if (numeric != null) {
        final millis = numeric < 100000000000 ? numeric * 1000 : numeric;
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }

      final iso = DateTime.tryParse(raw);
      if (iso != null) return iso;

      final nowYear = DateTime.now().year;
      final patternCandidates = <DateFormat>[
        DateFormat('EEE, MMM d • h:mm a'),
        DateFormat('MMM d • h:mm a'),
        DateFormat('EEE, MMM d, yyyy • h:mm a'),
        DateFormat('MMM d, yyyy • h:mm a'),
      ];

      for (final format in patternCandidates) {
        try {
          final parsed = format.parseStrict(raw);
          if (!format.pattern!.contains('yyyy')) {
            return DateTime(
              nowYear,
              parsed.month,
              parsed.day,
              parsed.hour,
              parsed.minute,
            );
          }
          return parsed;
        } catch (_) {
          // try next pattern
        }
      }
    }
    return null;
  }
}
