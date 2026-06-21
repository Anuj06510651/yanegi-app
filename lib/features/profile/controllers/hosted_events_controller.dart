// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/profile_social_screen.dart';

extension _HostedEventsController on _SocialProfileScreenState {
  Future<void> _loadInitialHostedEvents() async {
    if (_profileUid.isEmpty || _isLoadingHostedEvents) return;

    setState(() {
      _isLoadingHostedEvents = true;
      _hostedEvents.clear();
      _lastHostedEventDoc = null;
      _hasMoreHostedEvents = true;
    });

    try {
      debugPrint('EVENTS QUERY: loadHostedEvents profileUid=$_profileUid isOwnProfile=$_isOwnProfile');
      var eventsQuery = FirebaseFirestore.instance
          .collection('events')
          .where('hostId', isEqualTo: _profileUid)
          .where('status', isEqualTo: 'active');
      if (!_isOwnProfile) {
        eventsQuery = eventsQuery.where('visibility', isEqualTo: 'public');
      }
      final snapshot = await eventsQuery.limit(_SocialProfileScreenState._hostedEventsPageSize).get();

      if (!mounted) return;
      setState(() {
        _hostedEvents.addAll(snapshot.docs);
        _sortHostedEventsByBestDateDesc();
        _lastHostedEventDoc =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreHostedEvents = snapshot.docs.length == _SocialProfileScreenState._hostedEventsPageSize;
      });
    } catch (e, stack) {
      debugPrint('EVENTS QUERY ERROR: loadHostedEvents failed: $e');
      debugPrintStack(stackTrace: stack);
    } finally {
      if (mounted) {
        setState(() => _isLoadingHostedEvents = false);
      }
    }

    if (mounted) {
      await _autoFillLiveHostedFeedIfNeeded();
    }
  }

  Future<void> _loadMoreHostedEvents({bool skipAutoFill = false}) async {
    if (!_hasMoreHostedEvents ||
        _isLoadingMore ||
        _isLoadingHostedEvents ||
        _profileUid.isEmpty) {
      return;
    }

    setState(() => _isLoadingMore = true);
    try {
      final lastDoc = _lastHostedEventDoc;
      if (lastDoc == null) {
        if (mounted) {
          setState(() => _isLoadingMore = false);
        }
        return;
      }

      debugPrint('EVENTS QUERY: loadMoreHostedEvents profileUid=$_profileUid isOwnProfile=$_isOwnProfile');
      var eventsQuery = FirebaseFirestore.instance
          .collection('events')
          .where('hostId', isEqualTo: _profileUid)
          .where('status', isEqualTo: 'active');
      if (!_isOwnProfile) {
        eventsQuery = eventsQuery.where('visibility', isEqualTo: 'public');
      }
      final snapshot = await eventsQuery
          .startAfterDocument(lastDoc)
          .limit(_SocialProfileScreenState._hostedEventsPageSize)
          .get();

      if (!mounted) return;
      setState(() {
        _hostedEvents.addAll(snapshot.docs);
        _sortHostedEventsByBestDateDesc();
        _lastHostedEventDoc =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastHostedEventDoc;
        _hasMoreHostedEvents = snapshot.docs.length == _SocialProfileScreenState._hostedEventsPageSize;
      });
    } catch (e, stack) {
      debugPrint('EVENTS QUERY ERROR: loadMoreHostedEvents failed: $e');
      debugPrintStack(stackTrace: stack);
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }

    if (!skipAutoFill && mounted) {
      await _autoFillLiveHostedFeedIfNeeded();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final extentAfter = _scrollController.position.extentAfter;
    if (extentAfter < 360) {
      _loadMoreHostedEvents();
    }
  }

  Future<void> _autoFillLiveHostedFeedIfNeeded({int minLiveCards = 4}) async {
    if (_isAutoFillingLiveHosted ||
        _isLoadingHostedEvents ||
        _isLoadingMore ||
        !_hasMoreHostedEvents ||
        _profileUid.isEmpty) {
      return;
    }

    if (_liveHostedEvents.length >= minLiveCards) {
      return;
    }

    _isAutoFillingLiveHosted = true;
    try {
      while (mounted &&
          _hasMoreHostedEvents &&
          _liveHostedEvents.length < minLiveCards) {
        await _loadMoreHostedEvents(skipAutoFill: true);
      }
    } catch (e, stack) {
      debugPrint('EVENTS QUERY ERROR: autoFill failed: $e');
      debugPrintStack(stackTrace: stack);
    } finally {
      _isAutoFillingLiveHosted = false;
    }
  }

  Future<void> _openHostedEvent(String eventId) async {
    if (eventId.trim().isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(eventId: eventId),
      ),
    );
  }

  Widget _buildHostedEventsHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Live Hosting',
            style: TextStyle(
              color: _textPrimaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (_liveHostedEvents.isNotEmpty)
          Text(
            '${_liveHostedEvents.length}',
            style: TextStyle(
              color: YanegiColors.textSecondary.withAlpha(200),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildHostedEventsSection() {
    if (_isLoadingHostedEvents && _hostedEvents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_liveHostedEvents.isEmpty) {
      if (_hasMoreHostedEvents &&
          !_isLoadingMore &&
          !_isAutoFillingLiveHosted &&
          mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _autoFillLiveHostedFeedIfNeeded();
        });
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          _hasMoreHostedEvents
              ? 'Loading live hosting…'
              : 'No live hosting yet.',
          style: TextStyle(color: _textSecondaryColor),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHostedEventsList(),
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: CircularProgressIndicator(),
          )
        else if (_hasMoreHostedEvents)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Loading more as you scroll…',
              style: TextStyle(
                color: YanegiColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHostedEventsList() {
    final liveEvents = _liveHostedEvents;

    return Column(
      children: [
        for (var index = 0; index < liveEvents.length; index++) ...[
          Builder(
            builder: (context) {
              final doc = liveEvents[index];
              final eventId = doc.id;
              final data = doc.data();
              return InkWell(
                onTap: () => _openHostedEvent(eventId),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 132,
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _textSecondaryColor.withAlpha(30),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildHostedEventCard(data),
                  ),
                ),
              );
            },
          ),
          if (index != liveEvents.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildHostedEventCard(Map<String, dynamic> data) {
    final title = (data['title'] ?? 'Untitled event').toString().trim();
    final dateText = _formatEventDate(data);
    final location =
        (data['locationName'] ?? data['locationText'] ?? data['locationLabel'])
            .toString()
            .trim();
    final imageUrl =
        (data['bannerImagePath'] ?? data['imageUrl'] ?? '').toString().trim();

    if (imageUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 120),
            memCacheWidth: 600,
            memCacheHeight: 264,
            placeholder: (context, _) => Container(
              color: YanegiColors.surface,
              child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (context, _, __) => _buildEventGradientBackground(),
          ),
          _buildEventCardOverlay(
            title: title,
            dateText: dateText,
            location: location,
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildEventGradientBackground(),
        _buildEventCardOverlay(
          title: title,
          dateText: dateText,
          location: location,
        ),
      ],
    );
  }

  Widget _buildEventCardOverlay({
    required String title,
    required String dateText,
    required String location,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withAlpha(95),
            Colors.black.withAlpha(30),
            Colors.black.withAlpha(165),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? 'Untitled event' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          if (dateText.isNotEmpty)
            Text(
              dateText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withAlpha(230),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventGradientBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D4FA6),
            Color(0xFF08306D),
            Color(0xFF041024),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -26,
            right: -20,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(25),
              ),
            ),
          ),
          const Center(
            child: Icon(
              Icons.event_rounded,
              size: 28,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  String _formatEventDate(Map<String, dynamic> data) {
    final date = _extractEventDateTime(data);
    if (date != null) {
      return DateFormat('EEE, MMM d • h:mm a').format(date);
    }

    final rawLabel =
        (data['timeLabel'] ?? data['time'] ?? '').toString().trim();
    if (rawLabel.isNotEmpty) {
      return rawLabel;
    }

    return 'Event date';
  }

  bool _isHostedEventLive(Map<String, dynamic> data) {
    final eventDate = _extractEventDateTime(data);
    if (eventDate == null) return false;
    return !eventDate.isBefore(DateTime.now());
  }

  DateTime? _extractEventDateTime(Map<String, dynamic> data) {
    final directCandidates = <dynamic>[
      data['timestamp'],
      data['time'],
      data['eventDateTime'],
      data['eventDate'],
      data['date'],
      data['startAt'],
      data['startsAt'],
      data['startTime'],
      data['endAt'],
      data['endsAt'],
      data['endTime'],
      data['createdAt'],
      data['created_at'],
      data['updatedAt'],
      data['updated_at'],
    ];

    for (final raw in directCandidates) {
      final parsed = _parseDateTimeValue(raw);
      if (parsed != null) return parsed;
    }

    final schedule = data['schedule'];
    if (schedule is Map<String, dynamic>) {
      final nestedCandidates = <dynamic>[
        schedule['date'],
        schedule['eventDate'],
        schedule['startAt'],
        schedule['startTime'],
        schedule['endAt'],
        schedule['endTime'],
      ];
      for (final raw in nestedCandidates) {
        final parsed = _parseDateTimeValue(raw);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  void _sortHostedEventsByBestDateDesc() {
    if (_hostedEvents.length < 2) return;
    _hostedEvents.sort((a, b) {
      final aDate = _bestHostedEventSortDate(a.data());
      final bDate = _bestHostedEventSortDate(b.data());

      final compare = bDate.compareTo(aDate);
      if (compare != 0) return compare;

      // Stable-ish tiebreaker to reduce visual jumping.
      return b.id.compareTo(a.id);
    });
  }

  DateTime _bestHostedEventSortDate(Map<String, dynamic> data) {
    final preferredCandidates = <dynamic>[
      data['eventDateTime'],
      data['eventDate'],
      data['date'],
      data['startAt'],
      data['startsAt'],
      data['startTime'],
      data['endAt'],
      data['endsAt'],
      data['endTime'],
      data['timestamp'],
      data['time'],
      data['created_at'],
      data['createdAt'],
      data['updated_at'],
      data['updatedAt'],
    ];

    for (final raw in preferredCandidates) {
      final parsed = _parseDateTimeValue(raw);
      if (parsed != null) return parsed;
    }

    final schedule = data['schedule'];
    if (schedule is Map<String, dynamic>) {
      final scheduleCandidates = <dynamic>[
        schedule['date'],
        schedule['eventDate'],
        schedule['startAt'],
        schedule['startTime'],
        schedule['endAt'],
        schedule['endTime'],
      ];
      for (final raw in scheduleCandidates) {
        final parsed = _parseDateTimeValue(raw);
        if (parsed != null) return parsed;
      }
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _parseDateTimeValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      final millis = raw < 100000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (raw is num) {
      final value = raw.toInt();
      final millis = value < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }

    if (raw is Map<String, dynamic>) {
      final seconds = raw['_seconds'] ?? raw['seconds'];
      final nanos = raw['_nanoseconds'] ?? raw['nanoseconds'] ?? 0;
      if (seconds is num && nanos is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds.toInt() * 1000) + (nanos.toInt() ~/ 1000000),
        );
      }
    }

    if (raw is String) {
      final value = raw.trim();
      if (value.isEmpty) return null;

      final asNumber = int.tryParse(value);
      if (asNumber != null) {
        final millis = asNumber < 100000000000 ? asNumber * 1000 : asNumber;
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }

      final iso = DateTime.tryParse(value);
      if (iso != null) return iso;

      final nowYear = DateTime.now().year;
      final patternCandidates = <DateFormat>[
        DateFormat('EEE, MMM d • h:mm a'),
        DateFormat('MMM d • h:mm a'),
        DateFormat('EEE, MMM d, yyyy • h:mm a'),
        DateFormat('MMM d, yyyy • h:mm a'),
      ];

      for (final format in patternCandidates) {
        try {
          final parsed = format.parseStrict(value);
          if (!format.pattern!.contains('yyyy')) {
            return DateTime(
              nowYear,
              parsed.month,
              parsed.day,
              parsed.hour,
              parsed.minute,
            );
          }
          return parsed;
        } catch (_) {
          // try next format
        }
      }
    }

    return null;
  }
}
