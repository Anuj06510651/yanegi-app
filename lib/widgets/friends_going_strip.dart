import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_avatars.dart';
import 'event_going_sheet.dart';

/// Instagram-style mutual strip:
///   [avatar][avatar][avatar]  "Alex, Sarah and 2 more going"  ›
///
/// Tapping opens the full [EventGoingSheet] which lists all participants
/// with friends sorted to the top.
///
/// Renders nothing when the current user has no friends going.
class FriendsGoingStrip extends StatefulWidget {
  const FriendsGoingStrip({
    super.key,
    required this.eventId,
    required this.currentUserId,
    this.precomputedFriendParticipantIds,
  });

  final String eventId;
  final String currentUserId;
  final List<String>? precomputedFriendParticipantIds;

  @override
  State<FriendsGoingStrip> createState() => _FriendsGoingStripState();
}

class _FriendsGoingStripState extends State<FriendsGoingStrip> {
  late Future<_StripData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(FriendsGoingStrip old) {
    super.didUpdateWidget(old);
    if (old.eventId != widget.eventId ||
        old.currentUserId != widget.currentUserId) {
      setState(() => _future = _load());
    }
  }

  Future<_StripData?> _load() async {
    if (widget.currentUserId.isEmpty || widget.eventId.isEmpty) return null;

    List<String> friendParticipantIds;

    if (widget.precomputedFriendParticipantIds != null) {
      friendParticipantIds = widget.precomputedFriendParticipantIds!;
    } else {
      final friendsSnap = await FirebaseFirestore.instance
          .collection('friends')
          .doc(widget.currentUserId)
          .collection('list')
          .get();
      final friendIds = friendsSnap.docs.map((d) => d.id).toSet();
      if (friendIds.isEmpty) return null;

      final participantsSnap = await FirebaseFirestore.instance
          .collection('event_participants')
          .doc(widget.eventId)
          .collection('users')
          .where('status', whereIn: const ['joined', 'active'])
          .get();

      final participantUids = participantsSnap.docs
          .map((d) => (d.data()['userId'] ?? d.id).toString())
          .toSet();

      friendParticipantIds =
          friendIds.where(participantUids.contains).toList();
    }

    if (friendParticipantIds.isEmpty) return null;

    // Fetch user docs for the first 3 friend-avatars.
    final topIds = friendParticipantIds.take(3).toList();
    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: topIds)
        .get();
    final usersById = {for (final d in usersSnap.docs) d.id: d.data()};

    return _StripData(
      friendParticipantIds: friendParticipantIds,
      topUsers:
          topIds.map((id) => usersById[id] ?? const <String, dynamic>{}).toList(),
    );
  }

  void _openSheet(_StripData data) {
    showEventGoingSheet(
      context: context,
      eventId: widget.eventId,
      currentUserId: widget.currentUserId,
      friendParticipantIds: data.friendParticipantIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StripData?>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data!;
        return GestureDetector(
          onTap: () => _openSheet(data),
          behavior: HitTestBehavior.opaque,
          child: _StripRow(data: data),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StripData {
  const _StripData({
    required this.friendParticipantIds,
    required this.topUsers,
  });

  final List<String> friendParticipantIds;
  final List<Map<String, dynamic>> topUsers; // up to 3
}

// ─────────────────────────────────────────────────────────────────────────────
// Instagram-style inline strip row
// ─────────────────────────────────────────────────────────────────────────────

class _StripRow extends StatelessWidget {
  const _StripRow({required this.data});
  final _StripData data;

  String get _label {
    final names = data.topUsers
        .map((u) => (u['name'] ?? u['username'] ?? 'Friend').toString())
        .map((n) => n.split(' ').first)
        .toList();

    final total = data.friendParticipantIds.length;
    final extra = total - data.topUsers.length;

    if (total == 1) return '${names[0]} is going';
    if (total == 2) return '${names[0]} and ${names[1]} are going';
    if (extra <= 0) {
      return '${names[0]}, ${names[1]} and ${names[2]} are going';
    }
    return '${names[0]}, ${names[1]} and $extra more going';
  }

  @override
  Widget build(BuildContext context) {
    final avatarCount = data.topUsers.length;
    // Each avatar is 26px diameter; they overlap by 8px each.
    final stackWidth = 26.0 + (avatarCount - 1) * 18.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Overlapping avatar stack (Instagram mutuals style)
        SizedBox(
          width: stackWidth,
          height: 26,
          child: Stack(
            children: [
              for (int i = 0; i < avatarCount; i++)
                Positioned(
                  left: i * 18.0,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        // border matches the parent surface so avatars
                        // appear to float above each other
                        color: const Color(0xFF090D15),
                        width: 2,
                      ),
                    ),
                    child: AppUserAvatar(
                      photoUrl: (data.topUsers[i]['avatarUrl'] ??
                              data.topUsers[i]['avatar_url'] ??
                              '')
                          .toString(),
                      radius: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Label
        Flexible(
          child: Text(
            _label,
            style: TextStyle(
              color: Colors.white.withAlpha(200),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        const SizedBox(width: 4),

        // Chevron — indicates it's tappable
        Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: Colors.white.withAlpha(120),
        ),
      ],
    );
  }
}
