part of '../../../screens/chat/chat_thread_screen.dart';

class _GroupInfoModal extends StatefulWidget {
  final String eventId;
  final String fallbackTitle;
  final String currentUserId;

  const _GroupInfoModal({
    required this.eventId,
    required this.fallbackTitle,
    required this.currentUserId,
  });

  @override
  State<_GroupInfoModal> createState() => _GroupInfoModalState();
}

class _GroupInfoModalState extends State<_GroupInfoModal> {
  final EventService _eventService = EventService();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _eventStream;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _participantsStream;
  String? _removingUserId;
  String _usersFutureKey = '';
  Future<Map<String, Map<String, dynamic>>>? _usersFuture;

  @override
  void initState() {
    super.initState();
    _eventStream = FirebaseFirestore.instance
        .collection('events')
        .doc(widget.eventId)
        .snapshots();
    _participantsStream = FirebaseFirestore.instance
        .collectionGroup('users')
        .where('eventId', isEqualTo: widget.eventId)
        .where('status', whereIn: const ['joined', 'active']).snapshots();
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsersByIds(
    List<String> userIds,
  ) async {
    final ids = userIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};

    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.skip(i).take(10).toList();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        out[doc.id] = doc.data();
      }
    }
    return out;
  }

  void _ensureUsersFuture(List<String> userIds) {
    final key = [...userIds]..sort();
    final signature = key.join('|');
    if (signature == _usersFutureKey) return;
    _usersFutureKey = signature;
    _usersFuture = _loadUsersByIds(userIds);
  }

  Future<void> _removeParticipant({
    required String hostId,
    required String participantId,
  }) async {
    if (_removingUserId != null) return;
    if (participantId == hostId || participantId == widget.currentUserId) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF101726),
        title: const Text(
          'Remove from event?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This user will be removed from this event.',
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

    setState(() => _removingUserId = participantId);
    try {
      await _eventService.removeParticipantAsHost(
        eventId: widget.eventId,
        hostId: hostId,
        userId: participantId,
      );
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
        where: 'chat_thread._removeParticipant',
      );
    } finally {
      if (mounted) {
        setState(() => _removingUserId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
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
            const SizedBox(height: 14),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _eventStream,
              builder: (context, eventSnapshot) {
                final eventData =
                    eventSnapshot.data?.data() ?? const <String, dynamic>{};
                final hostId =
                    (eventData['hostId'] ?? eventData['host_id'] ?? '')
                        .toString();
                final isHost = widget.currentUserId.isNotEmpty &&
                    hostId.isNotEmpty &&
                    widget.currentUserId == hostId;
                final eventTitle =
                    (eventData['title'] ?? widget.fallbackTitle).toString();
                final subtitle = (eventData['description'] ?? '')
                    .toString()
                    .trim()
                    .split('\n')
                    .first;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eventTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withAlpha(160),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YanegiColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop(_GroupInfoAction.viewEvent);
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text('View ${EventLabel.capitalized(widget.eventId)}'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Participants',
                      style: TextStyle(
                        color: Colors.white.withAlpha(170),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _participantsStream,
                        builder: (context, participantSnapshot) {
                          if (participantSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final participantDocs =
                              participantSnapshot.data?.docs ??
                                  const <QueryDocumentSnapshot<
                                      Map<String, dynamic>>>[];
                          final participantIds = participantDocs
                              .map((doc) =>
                                  (doc.data()['userId'] ?? doc.id).toString())
                              .toList();

                          _ensureUsersFuture(participantIds);

                          if (participantIds.isEmpty) {
                            return Center(
                              child: Text(
                                'No active participants',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(150),
                                ),
                              ),
                            );
                          }

                          return FutureBuilder<
                              Map<String, Map<String, dynamic>>>(
                            future: _usersFuture,
                            builder: (context, usersSnapshot) {
                              final usersById = usersSnapshot.data ??
                                  const <String, Map<String, dynamic>>{};

                              return ListView.separated(
                                itemCount: participantIds.length,
                                separatorBuilder: (_, __) => Divider(
                                  color: Colors.white.withAlpha(15),
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final userId = participantIds[index];
                                  final participantDoc =
                                      participantDocs[index].data();
                                  final isVisible =
                                      participantDoc['isVisible'] != false;
                                  final userData = usersById[userId] ??
                                      const <String, dynamic>{};
                                  final name = isVisible
                                      ? (userData['name'] ??
                                              userData['username'] ??
                                              'User')
                                          .toString()
                                      : 'Someone joined';
                                  final avatarUrl = isVisible
                                      ? (userData['avatarUrl'] ??
                                              userData['avatar_url'] ??
                                              '')
                                          .toString()
                                      : '';
                                  final canRemove = isHost &&
                                      userId != hostId &&
                                      userId != widget.currentUserId;

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: AppUserAvatar(
                                      photoUrl: avatarUrl,
                                      radius: 20,
                                    ),
                                    title: Text(
                                      name,
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                    onTap: isVisible
                                        ? () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    SocialProfileScreen(
                                                  profileUserId: userId,
                                                ),
                                              ),
                                            );
                                          }
                                        : null,
                                    trailing: _removingUserId == userId
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : canRemove
                                            ? PopupMenuButton<String>(
                                                color: const Color(0xFF131A27),
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                  color: Colors.white70,
                                                ),
                                                onSelected: (value) {
                                                  if (value == 'remove') {
                                                    _removeParticipant(
                                                      hostId: hostId,
                                                      participantId: userId,
                                                    );
                                                  }
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem<String>(
                                                    value: 'remove',
                                                    child: Text(
                                                      'Remove from event',
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : null,
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _GroupInfoAction { viewEvent }
