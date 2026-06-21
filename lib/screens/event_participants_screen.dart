import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/event_service.dart';
import '../utils/error_handler.dart';
import '../widgets/app_avatars.dart';
import 'profile_social_screen.dart';

class EventParticipantsScreen extends StatefulWidget {
  final String eventId;
  final String hostId;
  final String currentUserId;

  const EventParticipantsScreen({
    super.key,
    required this.eventId,
    required this.hostId,
    required this.currentUserId,
  });

  @override
  State<EventParticipantsScreen> createState() =>
      _EventParticipantsScreenState();
}

class _EventParticipantsScreenState extends State<EventParticipantsScreen> {
  final EventService _eventService = EventService();
  static const bool _forceShowHostControlsForDebug = false;
  String? _removingUserId;

  Future<Map<String, Map<String, dynamic>>> _loadUsersByIds(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};

    final ids = userIds.where((id) => id.trim().isNotEmpty).toList();
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += 10) {
      final end = (i + 10) > ids.length ? ids.length : i + 10;
      chunks.add(ids.sublist(i, end));
    }

    final usersRef = FirebaseFirestore.instance.collection('users');
    final snapshots = await Future.wait(
      chunks.map(
        (chunk) => usersRef.where(FieldPath.documentId, whereIn: chunk).get(),
      ),
    );

    final byId = <String, Map<String, dynamic>>{};
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        byId[doc.id] = doc.data();
      }
    }
    return byId;
  }

  Future<void> _handleDeleteEvent({
    required String currentUserId,
  }) async {
    if (currentUserId.trim().isEmpty) return;

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
        hostId: currentUserId,
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
        where: 'event_participants._deleteEvent',
      );
    }
  }

  Future<void> _removeParticipant({
    required String participantUserId,
    required String currentStatus,
    required String currentUserId,
    required String hostId,
    required bool canManageParticipants,
  }) async {
    if (!canManageParticipants) return;

    if (participantUserId == hostId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host cannot be removed.')),
      );
      return;
    }

    if (currentStatus.toLowerCase() == 'removed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User is already removed.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101726),
        title: const Text(
          'Remove participant?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to remove this user from the event?',
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
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _removingUserId = participantUserId);
    try {
      await _eventService.removeParticipantAsHost(
        eventId: widget.eventId,
        hostId: currentUserId,
        userId: participantUserId,
      );
      print('Participant removed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Participant removed from event.')),
      );
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.generic,
        error: e,
        stackTrace: stack,
        where: 'event_participants._removeParticipant',
      );
    } finally {
      if (mounted) setState(() => _removingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final currentUserId = authUid.isNotEmpty ? authUid : widget.currentUserId;

    final eventStream = FirebaseFirestore.instance
        .collection('events')
        .doc(widget.eventId)
        .snapshots();

    final participantsStream = FirebaseFirestore.instance
        .collection('event_participants')
        .doc(widget.eventId)
        .collection('users')
        .where('status', whereIn: const ['joined', 'active']).snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFF090D15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1420),
        title: const Text('Participants'),
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: eventStream,
            builder: (context, eventSnapshot) {
              final eventData =
                  eventSnapshot.data?.data() ?? const <String, dynamic>{};
              final hostId = ((eventData['hostId'] ?? eventData['host_id']) ??
                      widget.hostId)
                  .toString()
                  .trim();
              final isHost = currentUserId.isNotEmpty &&
                  hostId.isNotEmpty &&
                  currentUserId == hostId;
              final showHostControls = isHost || _forceShowHostControlsForDebug;

              if (!showHostControls) {
                return const SizedBox.shrink();
              }

              return PopupMenuButton<String>(
                color: const Color(0xFF131A27),
                onSelected: (value) {
                  if (value == 'delete') {
                    _handleDeleteEvent(currentUserId: currentUserId);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete Event'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: eventStream,
        builder: (context, eventSnapshot) {
          final eventData =
              eventSnapshot.data?.data() ?? const <String, dynamic>{};
          final hostId =
              ((eventData['hostId'] ?? eventData['host_id']) ?? widget.hostId)
                  .toString()
                  .trim();
          final isHost = currentUserId.isNotEmpty &&
              hostId.isNotEmpty &&
              currentUserId == hostId;
          final canManageParticipants =
              isHost || _forceShowHostControlsForDebug;

          print('Current User: $currentUserId');
          print('Host ID: $hostId');

          if (hostId.isEmpty) {
            print(
                'Warning: hostId missing in event document ${widget.eventId}');
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: participantsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No participants yet',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final participantIds = docs
                  .map((d) => (d.data()['userId'] ?? d.id).toString())
                  .where((id) => id.trim().isNotEmpty)
                  .toSet();

              return FutureBuilder<Map<String, Map<String, dynamic>>>(
                future: _loadUsersByIds(participantIds),
                builder: (context, usersSnapshot) {
                  if (!usersSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final usersById = usersSnapshot.data ??
                      const <String, Map<String, dynamic>>{};

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: Colors.white.withAlpha(16), height: 1),
                    itemBuilder: (context, index) {
                      final participant = docs[index].data();
                      final participantUserId =
                          (participant['userId'] ?? docs[index].id).toString();
                      final participantStatus = (participant['status'] ?? '')
                          .toString()
                          .toLowerCase();
                      final isVisible = participant['isVisible'] != false;

                      final userData = usersById[participantUserId] ??
                          const <String, dynamic>{};
                      final displayName = isVisible
                          ? (userData['name'] ?? userData['username'] ?? 'User')
                              .toString()
                          : 'Someone joined';
                      final avatarUrl = isVisible
                          ? (userData['avatarUrl'] ??
                                  userData['avatar_url'] ??
                                  '')
                              .toString()
                          : '';

                      final canRemove = canManageParticipants &&
                          participantUserId != hostId &&
                          participantUserId != currentUserId;

                      return ListTile(
                        leading:
                            AppUserAvatar(photoUrl: avatarUrl, radius: 20),
                        title: Text(
                          displayName,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: _removingUserId == participantUserId
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : PopupMenuButton<String>(
                                color: const Color(0xFF131A27),
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: Colors.white70,
                                ),
                                onSelected: (action) async {
                                  if (action == 'view_profile') {
                                    if (!isVisible) return;
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => SocialProfileScreen(
                                          profileUserId: participantUserId,
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (action == 'remove') {
                                    await _removeParticipant(
                                      participantUserId: participantUserId,
                                      currentStatus: participantStatus,
                                      currentUserId: currentUserId,
                                      hostId: hostId,
                                      canManageParticipants:
                                          canManageParticipants,
                                    );
                                  }
                                },
                                itemBuilder: (context) {
                                  final items = <PopupMenuEntry<String>>[];

                                  if (isVisible) {
                                    items.add(
                                      const PopupMenuItem<String>(
                                        value: 'view_profile',
                                        child: Text('View Profile'),
                                      ),
                                    );
                                  }

                                  if (canRemove) {
                                    items.add(
                                      const PopupMenuItem<String>(
                                        value: 'remove',
                                        child: Text('Remove from Event'),
                                      ),
                                    );
                                  }

                                  return items;
                                },
                              ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
