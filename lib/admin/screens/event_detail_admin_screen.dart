import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/event_model.dart';
import '../../models/user_profile.dart';
import '../../theme/yanegi_theme.dart';
import '../services/admin_firestore_service.dart';
import '../widgets/admin_empty_state.dart';
import '../widgets/admin_error_state.dart';
import '../widgets/admin_skeleton.dart';
import 'user_detail_screen.dart';

class EventDetailAdminScreen extends StatefulWidget {
  final String eventId;

  const EventDetailAdminScreen({super.key, required this.eventId});

  @override
  State<EventDetailAdminScreen> createState() =>
      _EventDetailAdminScreenState();
}

class _EventDetailAdminScreenState extends State<EventDetailAdminScreen> {
  final _service = AdminFirestoreService();
  late Future<_EventDetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_EventDetailData> _load() async {
    final event = await _service.fetchEvent(widget.eventId);
    UserProfile? host;
    if (event != null && event.hostId.isNotEmpty) {
      host = await _service.fetchUser(event.hostId);
    }
    return _EventDetailData(event: event, host: host);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YanegiColors.background,
      appBar: AppBar(
        backgroundColor: YanegiColors.surface,
        foregroundColor: YanegiColors.textPrimary,
        elevation: 0,
        title: const Text('Event Detail', style: TextStyle(fontSize: 15)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                widget.eventId.length > 12
                    ? '${widget.eventId.substring(0, 12)}...'
                    : widget.eventId,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: YanegiColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<_EventDetailData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AdminSkeletonDetail();
          }
          if (snap.hasError) {
            return AdminErrorState(message: snap.error.toString());
          }
          if (snap.data?.event == null) {
            return const AdminEmptyState(message: 'Event not found');
          }
          return _EventOpsView(data: snap.data!);
        },
      ),
    );
  }
}

class _EventDetailData {
  final EventModel? event;
  final UserProfile? host;

  const _EventDetailData({required this.event, required this.host});
}

class _EventOpsView extends StatelessWidget {
  final _EventDetailData data;

  const _EventOpsView({required this.data});

  @override
  Widget build(BuildContext context) {
    final event = data.event!;
    final dateStr = event.startTime != null
        ? DateFormat('EEEE, d MMMM yyyy · h:mm a').format(event.startTime!)
        : '—';
    final endStr =
        event.endTime != null ? DateFormat('h:mm a').format(event.endTime!) : '—';
    final tags = (event.raw['tags'] as List<dynamic>?)
            ?.map((t) => t.toString())
            .toList() ??
        [];
    final meetingPoint =
        (event.raw['meetingPoint'] as String?)?.trim() ?? '';
    final fillRate = event.maxCapacity > 0
        ? '${(event.participantsCount / event.maxCapacity * 100).toStringAsFixed(0)}%'
        : '—';
    final createdAt = event.raw['createdAt'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          if (event.bannerUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(YanegiRadius.md),
              child: CachedNetworkImage(
                imageUrl: event.bannerUrl,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 800,
                placeholder: (_, __) => Container(
                    height: 200, color: YanegiColors.surfaceElevated),
              ),
            ),
            const SizedBox(height: 20),
          ],
          // Title + badges
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.eventAvatar.isNotEmpty)
                Text(event.eventAvatar,
                    style: const TextStyle(fontSize: 28)),
              if (event.eventAvatar.isNotEmpty) const SizedBox(width: 10),
              Expanded(
                child: Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: YanegiColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Badge(
                label: event.visibility != 'private' ? 'Public' : 'Private',
                color: event.visibility != 'private'
                    ? YanegiColors.accentSuccess
                    : YanegiColors.tertiary,
              ),
              const SizedBox(width: 6),
              _Badge(
                label: event.isActive ? 'Active' : 'Ended',
                color: event.isActive
                    ? YanegiColors.primary
                    : YanegiColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Stats bar
          _buildStatsBar(event, fillRate),
          const SizedBox(height: 24),
          // Details section
          _buildSection('DETAILS', [
            _row('Event ID', event.id, monospace: true, copyable: true),
            _row('Start', dateStr),
            _row('End', endStr),
            _row('Location',
                event.locationName.isNotEmpty ? event.locationName : '—'),
            if (meetingPoint.isNotEmpty)
              _row('Meeting Point', meetingPoint),
            _row('Approval Required',
                event.isApprovalRequired ? 'Yes' : 'No'),
            if (tags.isNotEmpty) _row('Tags', tags.join(', ')),
          ]),
          const SizedBox(height: 20),
          // Host section
          _buildHostSection(context, event, data.host),
          const SizedBox(height: 20),
          // Participants
          if (event.participants.isNotEmpty)
            _buildParticipantsSection(context, event),
          const SizedBox(height: 20),
          // Timeline
          _buildTimeline(event, createdAt),
          const SizedBox(height: 20),
          // Moderation panel
          _buildModerationPanel(),
        ],
      ),
    );
  }

  Widget _buildStatsBar(EventModel event, String fillRate) {
    final stats = [
      ('CAPACITY', '${event.maxCapacity > 0 ? event.maxCapacity : "∞"}'),
      ('JOINED', '${event.participantsCount}'),
      ('ATTENDANCE', '—'),
      ('WAITLIST', '—'),
      ('FILL RATE', fillRate),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      decoration: BoxDecoration(
        color: YanegiColors.surface,
        borderRadius: BorderRadius.circular(YanegiRadius.md),
        border: Border.all(color: Colors.white.withAlpha(8)),
      ),
      child: Row(
        children: stats.map((s) {
          return Expanded(
            child: Column(
              children: [
                Text(
                  s.$1,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: YanegiColors.textTertiary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.$2,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: YanegiColors.textPrimary,
                    height: 1,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHostSection(
      BuildContext context, EventModel event, UserProfile? host) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('HOST'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: YanegiColors.surface,
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(color: Colors.white.withAlpha(8)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: YanegiColors.surfaceElevated,
                backgroundImage: host?.avatarUrl != null
                    ? CachedNetworkImageProvider(host!.avatarUrl!,
                        maxWidth: 96, maxHeight: 96)
                    : null,
                child: host?.avatarUrl == null
                    ? const Icon(Icons.person_rounded,
                        size: 22, color: YanegiColors.textTertiary)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.hostName.isNotEmpty ? event.hostName : '—',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: YanegiColors.textPrimary,
                      ),
                    ),
                    if (host != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Hosted ${host.eventsCreated} event${host.eventsCreated == 1 ? '' : 's'} · ${host.friendsCount} friends',
                        style: const TextStyle(
                            fontSize: 12, color: YanegiColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              UserDetailScreen(uid: event.hostId),
                        ),
                      ),
                      child: const Text(
                        'View Profile →',
                        style: TextStyle(
                          fontSize: 12,
                          color: YanegiColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsSection(BuildContext context, EventModel event) {
    final shown = event.participants.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('PARTICIPANTS (${event.participantsCount})'),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: YanegiColors.surface,
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(color: Colors.white.withAlpha(8)),
          ),
          child: Column(
            children: [
              ...shown.asMap().entries.map((e) => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: YanegiColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(Icons.person_rounded,
                                  size: 16,
                                  color: YanegiColors.textTertiary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                e.value.length > 16
                                    ? '${e.value.substring(0, 16)}...'
                                    : e.value,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: YanegiColors.textSecondary,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UserDetailScreen(uid: e.value),
                                ),
                              ),
                              child: const Text(
                                'View',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: YanegiColors.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (e.key < shown.length - 1)
                        const Divider(
                            height: 1,
                            color: Color(0xFF1A1A1A),
                            indent: 16,
                            endIndent: 16),
                    ],
                  )),
              if (event.participants.length > 10)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'and ${event.participants.length - 10} more',
                    style: const TextStyle(
                        fontSize: 12, color: YanegiColors.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(EventModel event, dynamic createdAtRaw) {
    String createdStr = '—';
    if (createdAtRaw != null) {
      try {
        final dt = createdAtRaw.toDate() as DateTime;
        createdStr = DateFormat('d MMM yyyy · h:mm a').format(dt);
      } catch (_) {}
    }

    final steps = [
      ('Created', createdStr, true),
      ('Published',
          createdStr,
          true),
      ('Start',
          event.startTime != null
              ? DateFormat('d MMM yyyy · h:mm a').format(event.startTime!)
              : '—',
          event.startTime != null),
      ('End',
          event.endTime != null
              ? DateFormat('d MMM yyyy · h:mm a').format(event.endTime!)
              : '—',
          event.endTime != null),
      ('Status', event.isActive ? 'Active' : 'Ended', true),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('TIMELINE'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: YanegiColors.surface,
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(color: Colors.white.withAlpha(8)),
          ),
          child: Column(
            children: steps.asMap().entries.map((entry) {
              final step = entry.value;
              final isLast = entry.key == steps.length - 1;
              final color = step.$3
                  ? YanegiColors.primary
                  : YanegiColors.textTertiary;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (!isLast)
                        Container(
                            width: 2,
                            height: 32,
                            color: const Color(0xFF2A2A2A)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                      child: Row(
                        children: [
                          Text(
                            step.$1,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: YanegiColors.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            step.$2,
                            style: const TextStyle(
                                fontSize: 12,
                                color: YanegiColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildModerationPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('MODERATION'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: YanegiColors.surfaceElevated,
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(color: Colors.white.withAlpha(8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Moderation actions are read-only in this release.',
                style: TextStyle(
                    fontSize: 12, color: YanegiColors.textTertiary),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ('Cancel Event', Icons.cancel_outlined,
                      const Color(0xFFEF4444)),
                  ('Hide Event', Icons.visibility_off_outlined,
                      const Color(0xFFF59E0B)),
                  ('Warn Host', Icons.warning_amber_rounded,
                      const Color(0xFFF59E0B)),
                  ('Delete Event', Icons.delete_outline_rounded,
                      const Color(0xFFEF4444)),
                ].map((btn) {
                  return Tooltip(
                    message: 'Available in next release',
                    child: OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(btn.$2, size: 14),
                      label: Text(btn.$1,
                          style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: YanegiColors.textTertiary,
                        side: BorderSide(color: btn.$3.withAlpha(60)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: YanegiColors.surface,
            borderRadius: BorderRadius.circular(YanegiRadius.md),
            border: Border.all(color: Colors.white.withAlpha(8)),
          ),
          child: Column(
            children: rows
                .asMap()
                .entries
                .map((e) => Column(children: [
                      e.value,
                      if (e.key < rows.length - 1)
                        const Divider(
                            height: 1,
                            color: Color(0xFF1A1A1A),
                            indent: 16,
                            endIndent: 16),
                    ]))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value,
      {bool monospace = false, bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: YanegiColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: YanegiColors.textPrimary,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
          if (copyable)
            GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: value)),
              child: const Icon(Icons.copy_rounded,
                  size: 13, color: YanegiColors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: YanegiColors.textTertiary,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
