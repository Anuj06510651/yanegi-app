import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_avatars.dart';

/// Opens the "Who's Going" bottom sheet.
///
/// Friends (people the current user knows) appear in the **Friends** section
/// at the top. All other visible participants appear below in **Others**.
void showEventGoingSheet({
  required BuildContext context,
  required String eventId,
  required String currentUserId,
  required List<String> friendParticipantIds,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EventGoingSheet(
      eventId: eventId,
      currentUserId: currentUserId,
      friendParticipantIds: friendParticipantIds,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _EventGoingSheet extends StatefulWidget {
  const _EventGoingSheet({
    required this.eventId,
    required this.currentUserId,
    required this.friendParticipantIds,
  });

  final String eventId;
  final String currentUserId;
  final List<String> friendParticipantIds;

  @override
  State<_EventGoingSheet> createState() => _EventGoingSheetState();
}

class _EventGoingSheetState extends State<_EventGoingSheet> {
  late Future<_SheetData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SheetData> _load() async {
    // 1. All active participants for this event.
    final participantsSnap = await FirebaseFirestore.instance
        .collection('event_participants')
        .doc(widget.eventId)
        .collection('users')
        .where('status', whereIn: const ['joined', 'active'])
        .get();

    final allUids = participantsSnap.docs
        .map((d) => (d.data()['userId'] ?? d.id).toString())
        .where((id) => id.isNotEmpty && id != widget.currentUserId)
        .toList();

    if (allUids.isEmpty) return const _SheetData(friends: [], others: []);

    // 2. Batch-fetch user docs in chunks of 10.
    final usersById = await _fetchUsers(allUids);

    // 3. Partition: friends vs others.
    final friendSet = widget.friendParticipantIds.toSet();
    final friends = <_ParticipantRow>[];
    final others = <_ParticipantRow>[];

    for (final uid in allUids) {
      final data = usersById[uid] ?? const <String, dynamic>{};
      final isVisible = data.isNotEmpty;
      if (!isVisible) continue;

      final row = _ParticipantRow(
        uid: uid,
        name: (data['name'] ?? data['username'] ?? 'User').toString(),
        username: (data['username'] ?? '').toString(),
        avatarUrl:
            (data['avatarUrl'] ?? data['avatar_url'] ?? '').toString(),
        isFriend: friendSet.contains(uid),
      );

      if (row.isFriend) {
        friends.add(row);
      } else {
        others.add(row);
      }
    }

    // Sort each section alphabetically.
    friends.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    others.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return _SheetData(friends: friends, others: others);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchUsers(
      List<String> ids) async {
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.skip(i).take(10).toList();
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        out[doc.id] = doc.data();
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
        minHeight: MediaQuery.of(context).size.height * 0.35,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle bar ──────────────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
            child: FutureBuilder<_SheetData>(
              future: _future,
              builder: (_, snap) {
                final total = snap.hasData
                    ? snap.data!.friends.length + snap.data!.others.length
                    : null;
                return Row(
                  children: [
                    const Text(
                      "Who's Going",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    if (total != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$total',
                          style: TextStyle(
                            color: Colors.white.withAlpha(200),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Flexible(
            child: FutureBuilder<_SheetData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final data =
                    snapshot.data ?? const _SheetData(friends: [], others: []);

                if (data.friends.isEmpty && data.others.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text(
                        'No participants yet',
                        style: TextStyle(color: Colors.white.withAlpha(120)),
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: EdgeInsets.only(
                    bottom:
                        MediaQuery.of(context).viewPadding.bottom + 16,
                  ),
                  children: [
                    // ── Friends section ─────────────────────────────────
                    if (data.friends.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'Friends',
                        count: data.friends.length,
                        iconColor: const Color(0xFF22E7A2),
                      ),
                      for (final row in data.friends)
                        _ParticipantTile(row: row, isFriendSection: true),
                    ],

                    // ── Others section ──────────────────────────────────
                    if (data.others.isNotEmpty) ...[
                      if (data.friends.isNotEmpty)
                        Divider(
                          color: Colors.white.withAlpha(12),
                          height: 24,
                          indent: 20,
                          endIndent: 20,
                        ),
                      _SectionHeader(
                        label: 'Others',
                        count: data.others.length,
                        iconColor: Colors.white54,
                      ),
                      for (final row in data.others)
                        _ParticipantTile(row: row, isFriendSection: false),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SheetData {
  const _SheetData({
    required this.friends,
    required this.others,
  });

  final List<_ParticipantRow> friends;
  final List<_ParticipantRow> others;
}

class _ParticipantRow {
  const _ParticipantRow({
    required this.uid,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.isFriend,
  });

  final String uid;
  final String name;
  final String username;
  final String avatarUrl;
  final bool isFriend;
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.iconColor,
  });

  final String label;
  final int count;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: iconColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(160),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              color: Colors.white.withAlpha(100),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.row,
    required this.isFriendSection,
  });

  final _ParticipantRow row;
  final bool isFriendSection;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Avatar — slightly larger in friend section (Instagram uses bigger for mutuals)
          AppUserAvatar(
            photoUrl: row.avatarUrl,
            radius: isFriendSection ? 22 : 19,
          ),
          const SizedBox(width: 12),

          // Name + username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Friend badge
                    if (isFriendSection) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22E7A2).withAlpha(28),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: const Color(0xFF22E7A2).withAlpha(80),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Friend',
                          style: TextStyle(
                            color: Color(0xFF22E7A2),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (row.username.isNotEmpty)
                  Text(
                    '@${row.username}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(120),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
