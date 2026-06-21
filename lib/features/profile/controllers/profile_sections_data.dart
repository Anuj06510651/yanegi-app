// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

/// Data loaders for the redesigned profile sections: interest tags (derived from
/// event history), the friends preview strip (mutual-first on friend profiles),
/// lazily-loaded joined events, and the shared-events count.
///
/// Backward compatibility: every loader degrades gracefully to an empty result
/// — old users with no events, no `vibes`, or no friends simply render the
/// section hidden rather than crashing.
extension _ProfileSectionsData on _SocialProfileScreenState {
  // ─── INTEREST TAGS ────────────────────────────────────────
  // Derived automatically — no new collection. Priority:
  //   1. tags from the user's events (hosted, + joined for own profile)
  //   2. fallback to onboarding `vibes` if there is no event history
  Future<void> _loadInterestTags() async {
    if (_profileUid.isEmpty) return;
    try {
      final tagCounts = <String, int>{};

      // Hosted-event tags. Non-own profiles only ever see public events.
      var hostedQuery = FirebaseFirestore.instance
          .collection('events')
          .where('hostId', isEqualTo: _profileUid);
      if (!_isOwnProfile) {
        hostedQuery = hostedQuery.where('visibility', isEqualTo: 'public');
      }
      final hosted = await hostedQuery.limit(30).get();
      for (final doc in hosted.docs) {
        _accumulateTags(tagCounts, doc.data()['tags']);
      }

      // Joined-event tags — only for the owner's own profile (joining a private
      // event must never be inferable by strangers).
      if (_isOwnProfile) {
        final joined = await FirebaseFirestore.instance
            .collectionGroup('users')
            .where('userId', isEqualTo: _profileUid)
            .limit(50)
            .get();
        final joinedEventIds = <String>{};
        for (final doc in joined.docs) {
          final data = doc.data();
          if (!data.containsKey('eventId')) continue;
          final id = (data['eventId'] ?? '').toString().trim();
          if (id.isNotEmpty) joinedEventIds.add(id);
        }
        for (var i = 0; i < joinedEventIds.length; i += 10) {
          final chunk = joinedEventIds.skip(i).take(10).toList();
          if (chunk.isEmpty) continue;
          final events = await FirebaseFirestore.instance
              .collection('events')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final doc in events.docs) {
            _accumulateTags(tagCounts, doc.data()['tags']);
          }
        }
      }

      // Rank by frequency, take the strongest signals.
      final ranked = tagCounts.keys.toList()
        ..sort((a, b) => tagCounts[b]!.compareTo(tagCounts[a]!));
      var tags = ranked.take(5).map(_prettifyTag).toList();

      // Fallback to onboarding vibes when there is no event history.
      if (tags.isEmpty && _vibes.isNotEmpty) {
        tags = _vibes.take(5).map(_prettifyTag).toList();
      }

      if (!mounted) return;
      setState(() => _interestTags = tags);
    } catch (e) {
      debugPrint('PROFILE: _loadInterestTags failed: $e');
    }
  }

  void _accumulateTags(Map<String, int> counts, dynamic rawTags) {
    if (rawTags is! List) return;
    for (final t in rawTags) {
      final key = t.toString().trim().toLowerCase();
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }

  String _prettifyTag(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return t;
    return t
        .split(RegExp(r'[\s_]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  // ─── FRIENDS PREVIEW STRIP ────────────────────────────────
  Future<void> _loadFriendsPreview() async {
    if (_profileUid.isEmpty || _isLoadingFriends) return;
    _isLoadingFriends = true;
    try {
      final friends = await _friendService.getFriendsList(_profileUid);

      // Compute mutuals (only meaningful on someone else's profile) so we can
      // order them first, matching the friend-profile spec.
      Set<String> mutualIds = const <String>{};
      if (!_isOwnProfile && _currentUid.isNotEmpty) {
        final mineSnap = await FirebaseFirestore.instance
            .collection('friends')
            .doc(_currentUid)
            .collection('list')
            .get();
        final mine = mineSnap.docs.map((d) => d.id).toSet();
        mutualIds = friends
            .map((f) => f.uid)
            .where(mine.contains)
            .toSet();
      }

      final ordered = [...friends];
      if (mutualIds.isNotEmpty) {
        ordered.sort((a, b) {
          final am = mutualIds.contains(a.uid) ? 0 : 1;
          final bm = mutualIds.contains(b.uid) ? 0 : 1;
          return am.compareTo(bm);
        });
      }

      if (!mounted) return;
      setState(() {
        _friendsTotalCount = friends.length;
        _mutualFriendIds = mutualIds;
        _friendsPreview
          ..clear()
          ..addAll(ordered.take(9));
      });
    } catch (e) {
      debugPrint('PROFILE: _loadFriendsPreview failed: $e');
    } finally {
      _isLoadingFriends = false;
    }
  }

  // ─── JOINED EVENTS (lazy, for the "Joined" tab) ───────────
  Future<void> _loadJoinedEventsIfNeeded() async {
    if (_joinedEventsLoaded || _isLoadingJoinedEvents || _profileUid.isEmpty) {
      return;
    }
    _isLoadingJoinedEvents = true;
    if (mounted) setState(() {});
    try {
      final participantSnap = await FirebaseFirestore.instance
          .collectionGroup('users')
          .where('userId', isEqualTo: _profileUid)
          .where('status', whereIn: const ['joined', 'active'])
          .get();

      final eventIds = <String>{};
      for (final doc in participantSnap.docs) {
        final data = doc.data();
        final dataEventId = (data['eventId'] ?? '').toString().trim();
        final pathEventId = doc.reference.parent.parent?.id ?? '';
        if (dataEventId.isNotEmpty) {
          eventIds.add(dataEventId);
        } else if (pathEventId.trim().isNotEmpty) {
          eventIds.add(pathEventId);
        }
      }

      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (var i = 0; i < eventIds.length; i += 10) {
        final chunk = eventIds.skip(i).take(10).toList();
        if (chunk.isEmpty) continue;
        final snap = await FirebaseFirestore.instance
            .collection('events')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'deleted' || data['isDeleted'] == true) continue;
          // Privacy: never surface another user's private events.
          if (!_isOwnProfile &&
              (data['visibility'] ?? 'public').toString() != 'public') {
            continue;
          }
          docs.add(doc);
        }
      }

      if (!mounted) return;
      setState(() {
        _joinedEvents
          ..clear()
          ..addAll(docs);
        _joinedEventsLoaded = true;
      });
    } catch (e) {
      debugPrint('PROFILE: _loadJoinedEventsIfNeeded failed: $e');
    } finally {
      _isLoadingJoinedEvents = false;
      if (mounted) setState(() {});
    }
  }

  // ─── SHARED EVENTS COUNT (friend profile only) ────────────
  Future<void> _loadSharedEventsCount() async {
    if (_isOwnProfile || _currentUid.isEmpty || _profileUid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('events')
          .where('participants', arrayContains: _profileUid)
          .where('visibility', isEqualTo: 'public')
          .limit(80)
          .get();
      var count = 0;
      for (final doc in snap.docs) {
        final participants =
            List<String>.from(doc.data()['participants'] ?? const <String>[]);
        if (participants.contains(_currentUid)) count++;
      }
      if (!mounted) return;
      setState(() => _sharedEventsCount = count);
    } catch (e) {
      debugPrint('PROFILE: _loadSharedEventsCount failed: $e');
    }
  }

  // ─── MEMBER SINCE label ───────────────────────────────────
  String? get _memberSinceLabel {
    final date = _memberSince;
    if (date == null) return null;
    return 'Member since ${DateFormat('MMMM yyyy').format(date)}';
  }
}
