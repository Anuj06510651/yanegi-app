import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/block_service.dart';
import '../theme/yanegi_theme.dart';
import '../widgets/app_avatars.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Cache the user-profile future so StreamBuilder re-emissions (cache hit
  // then network) don't reset FutureBuilder back to loading state.
  Future<List<_BlockedUserEntry>>? _cachedFuture;
  String _cachedIdsKey = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_BlockedUserEntry>> _cachedLoadEntries(List<String> ids) {
    final key = ids.join(',');
    if (key != _cachedIdsKey || _cachedFuture == null) {
      _cachedIdsKey = key;
      _cachedFuture = _loadBlockedEntries(ids);
    }
    return _cachedFuture!;
  }

  Future<List<_BlockedUserEntry>> _loadBlockedEntries(List<String> ids) async {
    if (ids.isEmpty) return const <_BlockedUserEntry>[];

    final userDocs = await Future.wait(
      ids.map(
        (uid) => FirebaseFirestore.instance.collection('users').doc(uid).get(),
      ),
    );

    final List<_BlockedUserEntry> entries = [];
    for (final doc in userDocs) {
      final data = doc.data() ?? const <String, dynamic>{};
      final name = (data['name'] ?? data['username'] ?? 'Unknown user')
          .toString()
          .trim();
      final usernameRaw = (data['username'] ?? '').toString().trim();
      final username = usernameRaw.isEmpty
          ? ''
          : usernameRaw.startsWith('@')
              ? usernameRaw
              : '@$usernameRaw';
      final avatarUrl =
          (data['avatarUrl'] ?? data['photoUrl'] ?? data['avatar_url'] ?? '')
              .toString();

      entries.add(
        _BlockedUserEntry(
          uid: doc.id,
          displayName: name.isEmpty ? 'Unknown user' : name,
          username: username,
          avatarUrl: avatarUrl,
        ),
      );
    }

    return entries;
  }

  List<_BlockedUserEntry> _applySearch(List<_BlockedUserEntry> entries) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return entries;
    return entries.where((entry) {
      return entry.displayName.toLowerCase().contains(q) ||
          entry.username.toLowerCase().contains(q) ||
          entry.uid.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final surface = scheme.surface;
    final textPrimary = scheme.onSurface;
    final textSecondary = scheme.onSurface.withOpacity(0.68);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        title: Text(
          'Blocked Users',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: currentUid.isEmpty
          ? const _BlockedInfoState(
              icon: Icons.lock_outline,
              title: 'Sign in required',
              subtitle: 'Please sign in to view blocked users.',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('blocked_users')
                  .doc(currentUid)
                  .collection('list')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: YanegiColors.primary),
                  );
                }

                if (snapshot.hasError) {
                  return const _BlockedInfoState(
                    icon: Icons.error_outline,
                    title: 'Could not load blocked users',
                    subtitle: 'Please try again in a moment.',
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const _BlockedInfoState(
                    icon: Icons.verified_user_outlined,
                    title: 'No blocked users',
                    subtitle: 'People you block will appear here.',
                  );
                }

                final blockedIds = docs.map((d) => d.id).toList();

                return FutureBuilder<List<_BlockedUserEntry>>(
                  future: _cachedLoadEntries(blockedIds),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: YanegiColors.primary,
                        ),
                      );
                    }

                    if (userSnapshot.hasError) {
                      return const _BlockedInfoState(
                        icon: Icons.error_outline,
                        title: 'Could not load user profiles',
                        subtitle: 'Please try again in a moment.',
                      );
                    }

                    final allEntries =
                        userSnapshot.data ?? const <_BlockedUserEntry>[];
                    final filteredEntries = _applySearch(allEntries);

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) {
                              if (!mounted) return;
                              setState(() => _searchQuery = value);
                            },
                            style: TextStyle(color: textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search blocked users',
                              hintStyle: TextStyle(
                                color: textSecondary,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: textSecondary,
                              ),
                              suffixIcon: _searchQuery.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        if (!mounted) return;
                                        setState(() => _searchQuery = '');
                                      },
                                      icon: Icon(
                                        Icons.close,
                                        color: textSecondary,
                                      ),
                                    ),
                              filled: true,
                              fillColor: surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: textSecondary.withOpacity(0.2),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: textSecondary.withOpacity(0.2),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: YanegiColors.primary,
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: filteredEntries.isEmpty
                              ? const _BlockedInfoState(
                                  icon: Icons.search_off,
                                  title: 'No matches found',
                                  subtitle:
                                      'Try searching by name or username.',
                                )
                              : ListView.separated(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                  itemCount: filteredEntries.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final entry = filteredEntries[index];
                                    return _BlockedUserTile(entry: entry);
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

class _BlockedUserEntry {
  final String uid;
  final String displayName;
  final String username;
  final String avatarUrl;

  const _BlockedUserEntry({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.avatarUrl,
  });
}

class _BlockedUserTile extends StatefulWidget {
  final _BlockedUserEntry entry;

  const _BlockedUserTile({required this.entry});

  @override
  State<_BlockedUserTile> createState() => _BlockedUserTileState();
}

class _BlockedUserTileState extends State<_BlockedUserTile> {
  final BlockService _blockService = BlockService();
  bool _isUnblocking = false;

  Future<void> _unblock() async {
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: scheme.surface,
        title: Text(
          'Unblock user?',
          style: TextStyle(color: scheme.onSurface),
        ),
        content: Text(
          'You can interact with this user again after unblocking.',
          style: TextStyle(color: scheme.onSurface.withOpacity(0.68)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUnblocking = true);
    try {
      await _blockService.unblockUser(targetUid: widget.entry.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not unblock user.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUnblocking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final scheme = Theme.of(context).colorScheme;
    final textPrimary = scheme.onSurface;
    final textSecondary = scheme.onSurface.withOpacity(0.68);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: textSecondary.withOpacity(0.18),
        ),
      ),
      child: ListTile(
        leading: AppUserAvatar(photoUrl: entry.avatarUrl, radius: 22),
        title: Text(
          entry.displayName,
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: entry.username.isNotEmpty
            ? Text(
                entry.username,
                style: TextStyle(color: textSecondary),
              )
            : Text(
                'User',
                style: TextStyle(color: textSecondary),
              ),
        trailing: _isUnblocking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _unblock,
                child: const Text('Unblock'),
              ),
      ),
    );
  }
}

class _BlockedInfoState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BlockedInfoState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textPrimary = scheme.onSurface;
    final textSecondary = scheme.onSurface.withOpacity(0.68);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
