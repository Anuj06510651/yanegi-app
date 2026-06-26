import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../theme/yanegi_theme.dart';
import '../models/admin_user_detail.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_search_bar.dart';
import '../widgets/admin_skeleton.dart';
import 'user_detail_screen.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';
  String _sortBy = 'newest';

  static const _sorts = [
    ('newest', 'Newest'),
    ('oldest', 'Oldest'),
    ('most_active', 'Most Active'),
    ('inactive_30d', 'Inactive 30d'),
    ('incomplete', 'Incomplete Profile'),
    ('never_hosted', 'Never Hosted'),
  ];

  @override
  Widget build(BuildContext context) {
    final raw = ref.watch(adminAdminUsersProvider(
      (_query, _sortBy == 'oldest' ? 'oldest' : 'newest'),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: AdminSearchBar(
            hint: 'Search by username or UID...',
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        const SizedBox(height: 12),
        _buildFilterChips(),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: raw.maybeWhen(
            data: (users) {
              final filtered = _applyClientFilter(users);
              return Text(
                '${filtered.length} user${filtered.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textTertiary),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 8),
        _buildHeaders(),
        const Divider(height: 1, color: Color(0xFF1A1A1A)),
        Expanded(
          child: raw.when(
            loading: () => const AdminSkeletonList(),
            error: (e, _) => AdminErrorState(message: e.toString()),
            data: (users) {
              final filtered = _applyClientFilter(users);
              if (filtered.isEmpty) {
                return AdminEmptyState(
                  message: _query.isEmpty
                      ? 'No users yet'
                      : 'No users matching "$_query"',
                  icon: Icons.person_off_rounded,
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFF111111)),
                itemBuilder: (context, i) => _UserRow(
                  user: filtered[i],
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => UserDetailScreen(uid: filtered[i].uid),
                  )),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<AdminUserDetail> _applyClientFilter(List<AdminUserDetail> users) {
    switch (_sortBy) {
      case 'inactive_30d':
        return users.where((u) => u.isInactive).toList();
      case 'incomplete':
        return users.where((u) => u.profileCompletion < 60).toList();
      case 'never_hosted':
        return users.where((u) => u.eventsCreated == 0).toList();
      case 'most_active':
        final sorted = List<AdminUserDetail>.from(users);
        sorted.sort((a, b) => b.eventsJoined.compareTo(a.eventsJoined));
        return sorted;
      default:
        return users;
    }
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: _sorts.map((s) {
          final selected = _sortBy == s.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(s.$2),
              selected: selected,
              onSelected: (_) => setState(() => _sortBy = s.$1),
              selectedColor: YanegiColors.primary.withAlpha(40),
              checkmarkColor: YanegiColors.primary,
              backgroundColor: YanegiColors.surface,
              labelStyle: TextStyle(
                fontSize: 12,
                color: selected
                    ? YanegiColors.primary
                    : YanegiColors.textSecondary,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
              ),
              side: BorderSide(
                color: selected
                    ? YanegiColors.primary.withAlpha(80)
                    : const Color(0xFF2A2A2A),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeaders() {
    return Container(
      color: YanegiColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: const Row(
        children: [
          SizedBox(width: 36),
          SizedBox(width: 12),
          Expanded(flex: 3, child: _ColHeader('NAME / USERNAME')),
          Expanded(flex: 1, child: _ColHeader('PROFILE')),
          Expanded(flex: 2, child: _ColHeader('CITY')),
          Expanded(flex: 2, child: _ColHeader('MEMBER SINCE')),
          Expanded(flex: 1, child: _ColHeader('EVENTS')),
          Expanded(flex: 1, child: _ColHeader('FRIENDS')),
          Expanded(flex: 2, child: _ColHeader('LAST SEEN')),
          Expanded(flex: 1, child: _ColHeader('STATUS')),
        ],
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: YanegiColors.textTertiary,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AdminUserDetail user;
  final VoidCallback onTap;

  const _UserRow({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final memberSince = user.createdAt != null
        ? DateFormat('d MMM yyyy').format(user.createdAt!)
        : '—';

    String lastSeenStr;
    if (user.lastSeen == null) {
      lastSeenStr = 'Never';
    } else {
      final days = user.daysSinceLastSeen;
      if (days == 0) {
        lastSeenStr = 'Today';
      } else if (days < 7) {
        lastSeenStr = '${days}d ago';
      } else {
        lastSeenStr = DateFormat('d MMM').format(user.lastSeen!);
      }
    }

    final completionColor = user.profileCompletion >= 80
        ? YanegiColors.accentSuccess
        : user.profileCompletion >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 18,
              backgroundColor: YanegiColors.surfaceElevated,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!,
                      maxWidth: 72, maxHeight: 72)
                  : null,
              child: user.avatarUrl == null
                  ? const Icon(Icons.person_rounded,
                      size: 16, color: YanegiColors.textTertiary)
                  : null,
            ),
            const SizedBox(width: 12),
            // Name / username
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name.isNotEmpty ? user.name : '(no name)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: YanegiColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                        fontSize: 11, color: YanegiColors.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Profile %
            Expanded(
              flex: 1,
              child: Text(
                '${user.profileCompletion}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: completionColor,
                ),
              ),
            ),
            // City
            Expanded(
              flex: 2,
              child: Text(
                user.city ?? '—',
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Member since
            Expanded(
              flex: 2,
              child: Text(
                memberSince,
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textSecondary),
              ),
            ),
            // Events
            Expanded(
              flex: 1,
              child: Text(
                'J:${user.eventsJoined} H:${user.eventsCreated}',
                style: const TextStyle(
                    fontSize: 11, color: YanegiColors.textSecondary),
              ),
            ),
            // Friends
            Expanded(
              flex: 1,
              child: Text(
                '${user.friendsCount}',
                style: const TextStyle(
                    fontSize: 12, color: YanegiColors.textSecondary),
              ),
            ),
            // Last seen
            Expanded(
              flex: 2,
              child: Text(
                lastSeenStr,
                style: TextStyle(
                  fontSize: 12,
                  color: user.isInactive
                      ? const Color(0xFFEF4444)
                      : YanegiColors.textSecondary,
                ),
              ),
            ),
            // Status
            Expanded(
              flex: 1,
              child: _StatusBadge(user: user),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AdminUserDetail user;

  const _StatusBadge({required this.user});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    if (!user.hasCompleted) {
      color = const Color(0xFFF59E0B);
      label = 'Onboarding';
    } else if (user.isInactive) {
      color = const Color(0xFFEF4444);
      label = 'Inactive';
    } else {
      color = YanegiColors.accentSuccess;
      label = 'Active';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
