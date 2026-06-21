import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/yanegi_theme.dart';
import '../widgets/app_avatars.dart';

class EventRequestHistoryScreen extends StatelessWidget {
  const EventRequestHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final textPrimary = scheme.onSurface;
    final textSecondary = scheme.onSurface.withOpacity(0.68);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          iconTheme: IconThemeData(color: textPrimary),
          title: Text(
            'Event Requests',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          bottom: TabBar(
            indicatorColor: YanegiColors.primary,
            labelColor: textPrimary,
            unselectedLabelColor: textSecondary,
            tabs: const [
              Tab(text: 'Received'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: uid.isEmpty
            ? const _RequestInfoState(
                icon: Icons.lock_outline,
                title: 'Sign in required',
                subtitle: 'Please sign in to view event request history.',
              )
            : TabBarView(
                children: [
                  _EventRequestHistoryTab(
                      currentUid: uid, mode: _TabMode.received),
                  _EventRequestHistoryTab(currentUid: uid, mode: _TabMode.sent),
                ],
              ),
      ),
    );
  }
}

enum _TabMode { sent, received }

class _EventRequestHistoryTab extends StatelessWidget {
  final String currentUid;
  final _TabMode mode;

  const _EventRequestHistoryTab({
    required this.currentUid,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance.collection('event_requests').where(
          mode == _TabMode.sent ? 'userId' : 'hostId',
          isEqualTo: currentUid,
        );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: YanegiColors.primary),
          );
        }

        if (snapshot.hasError) {
          return const _RequestInfoState(
            icon: Icons.error_outline,
            title: 'Could not load requests',
            subtitle: 'Please try again in a moment.',
          );
        }

        final rawDocs = snapshot.data?.docs ?? const [];
        final docs = _sortedDocs(rawDocs);

        if (docs.isEmpty) {
          return _RequestInfoState(
            icon: Icons.inbox_outlined,
            title: mode == _TabMode.sent
                ? 'No sent requests yet'
                : 'No received requests yet',
            subtitle: mode == _TabMode.sent
                ? 'When you request to join events, history will appear here.'
                : 'Requests from other users will appear here.',
          );
        }

        final pendingCount = docs
            .where((d) =>
                _EventRequestTile._normalizeStatus(
                  (d.data()['status'] ?? 'pending').toString().toLowerCase(),
                ) ==
                'pending')
            .length;
        final acceptedCount = docs
            .where((d) =>
                _EventRequestTile._normalizeStatus(
                  (d.data()['status'] ?? 'pending').toString().toLowerCase(),
                ) ==
                'accepted')
            .length;
        final declinedCount = docs
            .where((d) =>
                _EventRequestTile._normalizeStatus(
                  (d.data()['status'] ?? 'pending').toString().toLowerCase(),
                ) ==
                'declined')
            .length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _RequestSummaryRow(
              totalCount: docs.length,
              pendingCount: pendingCount,
              acceptedCount: acceptedCount,
              declinedCount: declinedCount,
            ),
            const SizedBox(height: 10),
            ...List.generate(docs.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EventRequestTile(
                  requestDoc: docs[index],
                  mode: mode,
                ),
              );
            }),
          ],
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final copy = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    copy.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aDate = _EventRequestTile._toDateTime(
            aData['createdAt'] ?? aData['timestamp'] ?? aData['updatedAt'],
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = _EventRequestTile._toDateTime(
            bData['createdAt'] ?? bData['timestamp'] ?? bData['updatedAt'],
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return copy;
  }
}

class _EventRequestTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> requestDoc;
  final _TabMode mode;

  const _EventRequestTile({
    required this.requestDoc,
    required this.mode,
  });

  Future<_ResolvedRequestContext> _resolveContext() async {
    final data = requestDoc.data();
    final eventId = (data['eventId'] ?? '').toString();
    final senderId = (data['senderId'] ?? data['userId'] ?? '').toString();
    final hostId = (data['hostId'] ?? '').toString();
    final counterpartUid = mode == _TabMode.sent ? hostId : senderId;

    final firestore = FirebaseFirestore.instance;

    final futures = await Future.wait([
      if (eventId.isNotEmpty) firestore.collection('events').doc(eventId).get(),
      if (counterpartUid.isNotEmpty)
        firestore.collection('users').doc(counterpartUid).get(),
    ]);

    DocumentSnapshot<Map<String, dynamic>>? eventDoc;
    DocumentSnapshot<Map<String, dynamic>>? userDoc;

    if (eventId.isNotEmpty && futures.isNotEmpty) {
      eventDoc = futures.first;
    }

    if (counterpartUid.isNotEmpty) {
      final userIndex = eventId.isNotEmpty ? 1 : 0;
      if (futures.length > userIndex) {
        userDoc = futures[userIndex];
      }
    }

    final eventData = eventDoc?.data() ?? const <String, dynamic>{};
    final userData = userDoc?.data() ?? const <String, dynamic>{};

    final eventTitle =
        (eventData['title'] ?? eventData['name'] ?? 'Unknown event').toString();

    final personName =
        (userData['name'] ?? userData['username'] ?? 'Unknown user').toString();
    final usernameRaw = (userData['username'] ?? '').toString();
    final username = usernameRaw.isEmpty
        ? ''
        : usernameRaw.startsWith('@')
            ? usernameRaw
            : '@$usernameRaw';
    final avatarUrl = (userData['avatarUrl'] ??
            userData['photoUrl'] ??
            userData['avatar_url'] ??
            '')
        .toString();

    return _ResolvedRequestContext(
      eventTitle: eventTitle,
      personName: personName,
      username: username,
      avatarUrl: avatarUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = requestDoc.data();
    final statusRaw = (data['status'] ?? 'pending').toString().toLowerCase();
    final status = _normalizeStatus(statusRaw);
    final createdAt = _toDateTime(data['createdAt'] ?? data['timestamp']);
    final updatedAt = _toDateTime(data['updatedAt']);

    return FutureBuilder<_ResolvedRequestContext>(
      future: _resolveContext(),
      builder: (context, snapshot) {
        final resolved = snapshot.data;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.18),
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            leading:
                AppGroupAvatar(imageUrl: resolved?.avatarUrl, radius: 22),
            title: Text(
              resolved?.eventTitle ?? 'Loading event…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mode == _TabMode.sent
                        ? 'Requested host: ${resolved?.personName ?? 'Loading…'}'
                        : 'Requested by: ${resolved?.personName ?? 'Loading…'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.68),
                    ),
                  ),
                  if ((resolved?.username ?? '').isNotEmpty)
                    Text(
                      resolved!.username,
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.68),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusBadge(status: status),
                      Text(
                        createdAt != null
                            ? 'Requested ${DateFormat('dd MMM yyyy, hh:mm a').format(createdAt)}'
                            : 'Requested time unavailable',
                        style: const TextStyle(
                          color: null,
                          fontSize: 12,
                        ),
                      ),
                      if (updatedAt != null && status != 'pending')
                        Text(
                          'Updated ${DateFormat('dd MMM yyyy, hh:mm a').format(updatedAt)}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.68),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static String _normalizeStatus(String raw) {
    if (raw == 'accepted') return 'accepted';
    if (raw == 'rejected' || raw == 'declined') return 'declined';
    return 'pending';
  }
}

class _RequestSummaryRow extends StatelessWidget {
  final int totalCount;
  final int pendingCount;
  final int acceptedCount;
  final int declinedCount;

  const _RequestSummaryRow({
    required this.totalCount,
    required this.pendingCount,
    required this.acceptedCount,
    required this.declinedCount,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.onSurface.withOpacity(0.18)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _countChip('Total', totalCount, scheme.onSurface),
          _countChip('Pending', pendingCount, YanegiColors.primary),
          _countChip('Accepted', acceptedCount, const Color(0xFFA5D6A7)),
          _countChip('Declined', declinedCount, const Color(0xFFFFCDD2)),
        ],
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ResolvedRequestContext {
  final String eventTitle;
  final String personName;
  final String username;
  final String avatarUrl;

  const _ResolvedRequestContext({
    required this.eventTitle,
    required this.personName,
    required this.username,
    required this.avatarUrl,
  });
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status[0].toUpperCase() +
        (status.length > 1 ? status.substring(1) : '');

    Color bg;
    Color fg;
    switch (status) {
      case 'accepted':
        bg = const Color(0xFF1B5E20).withOpacity(0.2);
        fg = const Color(0xFFA5D6A7);
        break;
      case 'declined':
        bg = const Color(0xFFB71C1C).withOpacity(0.2);
        fg = const Color(0xFFFFCDD2);
        break;
      default:
        bg = YanegiColors.primary.withOpacity(0.18);
        fg = YanegiColors.primary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RequestInfoState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _RequestInfoState({
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
