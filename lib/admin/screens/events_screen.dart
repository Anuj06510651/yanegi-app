import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/event_model.dart';
import '../../theme/yanegi_theme.dart';
import '../providers/admin_providers.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_search_bar.dart';
import '../widgets/admin_skeleton.dart';
import 'event_detail_admin_screen.dart';

// Fixed pixel column widths — identical in header and every row so columns
// always align regardless of content length.
const double _colHost        = 200;
const double _colDate        = 130;
const double _colParticipants = 110;
const double _colCategory    = 130;
const double _colStatus      = 90;

/// Searchable table of all events.
/// Fixes:
///   • eventAvatar stores asset file paths (e.g. "image assest/handshake…"),
///     NOT emojis — displaying it as Text caused massive overflow.
///     Now filtered out; title column shows event title only.
///   • hostName field can be a short username, not a display name.
///     Host cell now fetches the full user profile via hostId and shows
///     avatar + display name + @username.
///   • Columns use fixed SizedBox widths so header and rows always align.
class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(adminEventsProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: AdminSearchBar(
            hint: 'Search by event title...',
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: eventsAsync.maybeWhen(
            data: (events) => Text(
              '${events.length} result${events.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: YanegiColors.textTertiary),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 12),
        _buildColumnHeaders(),
        const Divider(height: 1, color: Color(0xFF1A1A1A)),
        Expanded(
          child: eventsAsync.when(
            loading: () => const AdminSkeletonList(),
            error: (e, _) => AdminErrorState(message: e.toString()),
            data: (events) => events.isEmpty
                ? AdminEmptyState(
                    message: _query.isEmpty
                        ? 'No events yet'
                        : 'No events matching "$_query"',
                    icon: Icons.event_busy_rounded,
                  )
                : _buildList(events),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnHeaders() {
    return Container(
      color: YanegiColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          // Title takes remaining space
          const Expanded(child: _ColHeader('TITLE')),
          const SizedBox(width: _colHost,        child: _ColHeader('HOST')),
          const SizedBox(width: _colDate,        child: _ColHeader('DATE')),
          const SizedBox(width: _colParticipants,child: _ColHeader('PARTICIPANTS')),
          const SizedBox(width: _colCategory,    child: _ColHeader('CATEGORY')),
          SizedBox(width: _colStatus,            child: const _ColHeader('STATUS')),
        ],
      ),
    );
  }

  Widget _buildList(List<EventModel> events) {
    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF111111)),
      itemBuilder: (context, i) => _EventRow(
        event: events[i],
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EventDetailAdminScreen(eventId: events[i].id),
        )),
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

class _EventRow extends ConsumerWidget {
  final EventModel event;
  final VoidCallback onTap;

  const _EventRow({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = event.startTime != null
        ? DateFormat('d MMM yyyy').format(event.startTime!)
        : '—';
    final capacityStr =
        '${event.participantsCount} / ${event.maxCapacity > 0 ? event.maxCapacity.toString() : '∞'}';
    final tags = event.raw['tags'] as List<dynamic>?;
    final category = tags?.isNotEmpty == true ? tags!.first.toString() : '—';

    // Fetch host profile to show real display name + avatar + username.
    // Riverpod caches by hostId — same host across multiple events only fetched once.
    final hostAsync = ref.watch(adminHostProfileProvider(event.hostId));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // TITLE — Expanded takes all remaining space.
            // eventAvatar field stores asset file paths, not renderable emojis —
            // we intentionally skip it and show only the title text.
            Expanded(
              child: Text(
                event.title.isNotEmpty ? event.title : '(untitled)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: YanegiColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // HOST — fixed 200px, avatar + name + @username
            SizedBox(
              width: _colHost,
              child: hostAsync.when(
                loading: () => _HostCell(
                  name: event.hostName,
                  username: null,
                  avatarUrl: null,
                ),
                error: (_, __) => _HostCell(
                  name: event.hostName,
                  username: null,
                  avatarUrl: null,
                ),
                data: (profile) => _HostCell(
                  name: profile?.name.isNotEmpty == true
                      ? profile!.name
                      : event.hostName,
                  username: profile?.username,
                  avatarUrl: profile?.avatarUrl,
                ),
              ),
            ),
            // DATE
            SizedBox(
              width: _colDate,
              child: Text(
                dateStr,
                style: const TextStyle(fontSize: 12, color: YanegiColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // PARTICIPANTS
            SizedBox(
              width: _colParticipants,
              child: Text(
                capacityStr,
                style: const TextStyle(fontSize: 12, color: YanegiColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // CATEGORY
            SizedBox(
              width: _colCategory,
              child: Text(
                category,
                style: const TextStyle(fontSize: 12, color: YanegiColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // STATUS
            SizedBox(
              width: _colStatus,
              child: _StatusBadge(isActive: event.isActive),
            ),
          ],
        ),
      ),
    );
  }
}

/// Host cell: 28px circular avatar + display name + @username stacked vertically.
class _HostCell extends StatelessWidget {
  final String name;
  final String? username;
  final String? avatarUrl;

  const _HostCell({required this.name, this.username, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final displayName = name.isNotEmpty ? name : '—';
    final initials = displayName != '—'
        ? displayName[0].toUpperCase()
        : '?';

    return Row(
      children: [
        // Avatar — network image or initial fallback
        CircleAvatar(
          radius: 14,
          backgroundColor: YanegiColors.primary.withAlpha(40),
          backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
              ? CachedNetworkImageProvider(avatarUrl!, maxWidth: 56, maxHeight: 56)
              : null,
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: YanegiColors.primary,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 8),
        // Name + username
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: YanegiColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (username != null && username!.isNotEmpty)
                Text(
                  '@$username',
                  style: const TextStyle(
                    fontSize: 10,
                    color: YanegiColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;
  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? YanegiColors.accentSuccess : YanegiColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isActive ? 'Active' : 'Ended',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
