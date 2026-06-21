import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/app_avatars.dart';

/// Shows a bottom sheet with who reacted with what emoji.
///
/// • "All" tab (when >1 emoji) shows every reactor with their emoji badge.
/// • Per-emoji tabs show only reactors for that emoji.
/// • The current user's row is highlighted with "Tap to remove" — tapping it
///   calls [onRemoveReaction] and closes the sheet.
void showReactionDetails({
  required BuildContext context,
  required Map<String, List<String>> reactions,
  required String currentUserId,
  required void Function(String emoji) onRemoveReaction,
  String? initialEmoji,
}) {
  if (reactions.isEmpty) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReactionDetailsSheet(
      reactions: reactions,
      currentUserId: currentUserId,
      onRemoveReaction: onRemoveReaction,
      initialEmoji: initialEmoji,
    ),
  );
}

class _ReactionDetailsSheet extends StatefulWidget {
  const _ReactionDetailsSheet({
    required this.reactions,
    required this.currentUserId,
    required this.onRemoveReaction,
    this.initialEmoji,
  });

  final Map<String, List<String>> reactions;
  final String currentUserId;
  final void Function(String emoji) onRemoveReaction;
  final String? initialEmoji;

  @override
  State<_ReactionDetailsSheet> createState() => _ReactionDetailsSheetState();
}

class _ReactionDetailsSheetState extends State<_ReactionDetailsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Tab order: "All" (when >1 emoji) then each emoji.
  late final List<String?> _tabs; // null = "All" tab
  late final List<String> _emojis;
  late Future<Map<String, Map<String, dynamic>>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _emojis = widget.reactions.keys.toList();

    final hasMultiple = _emojis.length > 1;
    _tabs = hasMultiple ? [null, ..._emojis] : _emojis;

    int initialIndex = 0;
    if (widget.initialEmoji != null) {
      final emojiIdx = _emojis.indexOf(widget.initialEmoji!);
      if (emojiIdx >= 0) {
        initialIndex = hasMultiple ? emojiIdx + 1 : emojiIdx;
      }
    }

    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, _tabs.length - 1),
    );

    final allUids =
        widget.reactions.values.expand((l) => l).toSet().toList();
    _usersFuture = _fetchUsers(allUids);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, Map<String, dynamic>>> _fetchUsers(
      List<String> uids) async {
    final ids = uids.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};
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

  void _handleRemove(String emoji) {
    Navigator.of(context).pop();
    widget.onRemoveReaction(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final totalReactors =
        widget.reactions.values.expand((l) => l).toSet().length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
        minHeight: MediaQuery.of(context).size.height * 0.40,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF151C2A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(55),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Row(
              children: [
                const Text(
                  'Reactions',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$totalReactors',
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tab bar — always shown so the user knows which emoji each person used.
          TabBar(
            controller: _tabController,
            isScrollable: _tabs.length > 4,
            indicatorColor: const Color(0xFF7C7AFF),
            indicatorWeight: 2.5,
            labelPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            dividerColor: Colors.white.withAlpha(15),
            tabs: [
              for (final tab in _tabs)
                Tab(
                  child: tab == null
                      // "All" tab
                      ? Text(
                          'All',
                          style: TextStyle(
                            color: Colors.white.withAlpha(210),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        )
                      // Per-emoji tab
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tab,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.reactions[tab]!.length}',
                              style: TextStyle(
                                color: Colors.white.withAlpha(180),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
            ],
          ),

          // List body
          Flexible(
            child: FutureBuilder<Map<String, Map<String, dynamic>>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final usersById = snapshot.data ?? const {};

                return TabBarView(
                  controller: _tabController,
                  children: [
                    for (final tab in _tabs)
                      tab == null
                          ? _AllReactorsList(
                              reactions: widget.reactions,
                              usersById: usersById,
                              currentUserId: widget.currentUserId,
                              onRemove: _handleRemove,
                            )
                          : _ReactorList(
                              emoji: tab,
                              uids: widget.reactions[tab] ?? const [],
                              usersById: usersById,
                              currentUserId: widget.currentUserId,
                              onRemove: () => _handleRemove(tab),
                            ),
                  ],
                );
              },
            ),
          ),
          SizedBox(
              height: MediaQuery.of(context).viewPadding.bottom + 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "All" tab: flat list of every (uid, emoji) pair, current user first.
// ─────────────────────────────────────────────────────────────────────────────

class _AllReactorsList extends StatelessWidget {
  const _AllReactorsList({
    required this.reactions,
    required this.usersById,
    required this.currentUserId,
    required this.onRemove,
  });

  final Map<String, List<String>> reactions;
  final Map<String, Map<String, dynamic>> usersById;
  final String currentUserId;
  final void Function(String emoji) onRemove;

  @override
  Widget build(BuildContext context) {
    // Build flat list of (emoji, uid) sorted: current user first, then alphabetical name.
    final pairs = <({String emoji, String uid})>[];
    for (final entry in reactions.entries) {
      for (final uid in entry.value) {
        pairs.add((emoji: entry.key, uid: uid));
      }
    }
    pairs.sort((a, b) {
      if (a.uid == currentUserId) return -1;
      if (b.uid == currentUserId) return 1;
      final nameA = _name(usersById[a.uid]);
      final nameB = _name(usersById[b.uid]);
      return nameA.compareTo(nameB);
    });

    if (pairs.isEmpty) {
      return Center(
        child: Text('No reactions yet',
            style: TextStyle(color: Colors.white.withAlpha(120))),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: pairs.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withAlpha(10), height: 1),
      itemBuilder: (context, i) {
        final pair = pairs[i];
        final isMe = pair.uid == currentUserId;
        return _ReactorRow(
          uid: pair.uid,
          emoji: pair.emoji,
          data: usersById[pair.uid] ?? const {},
          isCurrentUser: isMe,
          onTap: isMe ? () => onRemove(pair.emoji) : null,
        );
      },
    );
  }

  String _name(Map<String, dynamic>? data) =>
      (data?['name'] ?? data?['username'] ?? '').toString().toLowerCase();
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-emoji tab: all reactors for one emoji.
// ─────────────────────────────────────────────────────────────────────────────

class _ReactorList extends StatelessWidget {
  const _ReactorList({
    required this.emoji,
    required this.uids,
    required this.usersById,
    required this.currentUserId,
    required this.onRemove,
  });

  final String emoji;
  final List<String> uids;
  final Map<String, Map<String, dynamic>> usersById;
  final String currentUserId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // Current user first, then alphabetical.
    final sorted = [...uids]..sort((a, b) {
        if (a == currentUserId) return -1;
        if (b == currentUserId) return 1;
        final nameA = (usersById[a]?['name'] ??
                usersById[a]?['username'] ??
                '')
            .toString()
            .toLowerCase();
        final nameB = (usersById[b]?['name'] ??
                usersById[b]?['username'] ??
                '')
            .toString()
            .toLowerCase();
        return nameA.compareTo(nameB);
      });

    if (sorted.isEmpty) {
      return Center(
        child: Text('No reactions yet',
            style: TextStyle(color: Colors.white.withAlpha(120))),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withAlpha(10), height: 1),
      itemBuilder: (context, i) {
        final uid = sorted[i];
        final isMe = uid == currentUserId;
        return _ReactorRow(
          uid: uid,
          emoji: emoji,
          data: usersById[uid] ?? const {},
          isCurrentUser: isMe,
          onTap: isMe ? onRemove : null,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single reactor row used by both list types.
// ─────────────────────────────────────────────────────────────────────────────

class _ReactorRow extends StatelessWidget {
  const _ReactorRow({
    required this.uid,
    required this.emoji,
    required this.data,
    required this.isCurrentUser,
    this.onTap,
  });

  final String uid;
  final String emoji;
  final Map<String, dynamic> data;
  final bool isCurrentUser;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? data['username'] ?? 'Unknown').toString();
    final username = (data['username'] ?? '').toString();
    final avatarUrl =
        (data['avatarUrl'] ?? data['avatar_url'] ?? '').toString();

    return InkWell(
      onTap: onTap,
      splashColor:
          isCurrentUser ? Colors.redAccent.withAlpha(30) : Colors.transparent,
      highlightColor:
          isCurrentUser ? Colors.redAccent.withAlpha(15) : Colors.transparent,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            // Avatar
            AppUserAvatar(photoUrl: avatarUrl, radius: 22),
            const SizedBox(width: 14),

            // Name + username + "Tap to remove" hint for self
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: TextStyle(
                            color: isCurrentUser
                                ? Colors.white
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              color: Colors.white.withAlpha(180),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (username.isNotEmpty)
                    Text(
                      '@$username',
                      style: TextStyle(
                        color: Colors.white.withAlpha(130),
                        fontSize: 12,
                      ),
                    ),
                  if (isCurrentUser)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Tap to remove reaction',
                        style: TextStyle(
                          color: Colors.redAccent.withAlpha(200),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Emoji badge — always visible so you know who reacted with what
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCurrentUser
                    ? const Color(0xFF7C7AFF).withAlpha(30)
                    : Colors.white.withAlpha(12),
                shape: BoxShape.circle,
                border: isCurrentUser
                    ? Border.all(
                        color: const Color(0xFF7C7AFF).withAlpha(120),
                        width: 1.2)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }
}
