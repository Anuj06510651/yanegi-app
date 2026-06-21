import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/saved_events_service.dart';
import '../theme/yanegi_theme.dart';
import 'event_detail_screen.dart';

/// Private "Saved Events" list — only the signed-in owner ever sees this.
/// Reachable from Settings. Reads pointers from `users/{uid}/savedEvents` and
/// re-fetches each event from the canonical `events` collection so titles,
/// banners and times always reflect the live event (and deleted events drop out).
class SavedEventsScreen extends StatefulWidget {
  const SavedEventsScreen({super.key});

  @override
  State<SavedEventsScreen> createState() => _SavedEventsScreenState();
}

class _SavedEventsScreenState extends State<SavedEventsScreen> {
  final SavedEventsService _savedService = SavedEventsService();

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? YanegiColors.background : const Color(0xFFF7F9FC);
  Color get _surface => _isDark ? YanegiColors.surface : Colors.white;
  Color get _textPrimary =>
      _isDark ? YanegiColors.textPrimary : const Color(0xFF161C22);
  Color get _textSecondary =>
      _isDark ? YanegiColors.textSecondary : const Color(0xFF5E6A7D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          'Saved Events',
          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.w700),
        ),
        iconTheme: IconThemeData(color: _textPrimary),
      ),
      body: StreamBuilder<List<String>>(
        stream: _savedService.savedEventIdsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final ids = snapshot.data ?? const <String>[];
          if (ids.isEmpty) return _buildEmptyState();

          return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _fetchEventsByIds(ids),
            builder: (context, eventSnap) {
              if (eventSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = eventSnap.data ?? const [];
              if (docs.isEmpty) return _buildEmptyState();

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _buildSavedCard(docs[index]),
              );
            },
          );
        },
      ),
    );
  }

  /// Batched fetch (Firestore `whereIn` allows max 10 IDs/query). Preserves the
  /// most-recent-first order from the saved pointers and skips missing/deleted.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchEventsByIds(
      List<String> ids) async {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.skip(i).take(10).toList();
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final status = (doc.data()['status'] ?? '').toString().toLowerCase();
        final deleted = doc.data()['isDeleted'] == true || status == 'deleted';
        if (!deleted) byId[doc.id] = doc;
      }
    }
    return ids
        .where(byId.containsKey)
        .map((id) => byId[id]!)
        .toList(growable: false);
  }

  Widget _buildSavedCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = (data['title'] ?? 'Untitled event').toString().trim();
    final location =
        (data['locationName'] ?? data['locationText'] ?? '').toString().trim();
    final imageUrl =
        (data['bannerUrl'] ?? data['bannerImagePath'] ?? data['imageUrl'] ?? '')
            .toString()
            .trim();
    final dateText = _formatDate(data);

    return Dismissible(
      key: ValueKey('saved_${doc.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withAlpha(40),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.bookmark_remove_rounded,
            color: Colors.redAccent),
      ),
      onDismissed: (_) async {
        await _savedService.unsaveEvent(doc.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from saved.')),
          );
        }
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(eventId: doc.id),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _textSecondary.withAlpha(30)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14)),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          memCacheHeight: 200,
                          errorWidget: (_, __, ___) => _thumbFallback(),
                          placeholder: (_, __) => _thumbFallback(),
                        )
                      : _thumbFallback(),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title.isEmpty ? 'Untitled event' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (dateText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          dateText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _textSecondary, fontSize: 12.5),
                        ),
                      ],
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded,
                                size: 13, color: _textSecondary),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _textSecondary, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_rounded,
                    color: YanegiColors.primary),
                tooltip: 'Remove from saved',
                onPressed: () async {
                  await _savedService.unsaveEvent(doc.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Removed from saved.')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B3C7A), Color(0xFF12121A)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.event_rounded, color: Colors.white38, size: 26),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded,
                size: 44, color: _textSecondary.withAlpha(160)),
            const SizedBox(height: 14),
            Text(
              'No saved events yet',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the bookmark on any event to save it here for later. '
              'Only you can see your saved events.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(Map<String, dynamic> data) {
    final raw = data['startAt'] ?? data['startTime'] ?? data['eventDateTime'];
    DateTime? date;
    if (raw is Timestamp) {
      date = raw.toDate();
    } else if (raw is String) {
      date = DateTime.tryParse(raw);
    }
    if (date != null) {
      return DateFormat('EEE, MMM d • h:mm a').format(date);
    }
    return (data['time'] ?? data['timeLabel'] ?? '').toString().trim();
  }
}
