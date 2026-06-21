// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/map_screen.dart';

extension _MapEventsController on _MapScreenState {
  String _eventNodesSignature(List<EventNode> nodes) {
    return nodes
        .map((node) =>
            '${node.id}:${node.latLng.latitude.toStringAsFixed(5)}:${node.latLng.longitude.toStringAsFixed(5)}:${node.currentAttendees}:${node.date?.millisecondsSinceEpoch ?? 0}')
        .join('|');
  }

  Future<void> _checkEndedEvents() async {
    if (!mounted) return;
    final events = await EventEndDetectorService().findEndedUnrecappedEvents();
    if (events.isEmpty || !mounted) return;
    final first = events.first;
    await EventEndDetectorService.markRecapShown(first['id']!);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EventRecapScreen(
        eventId: first['id']!,
        eventTitle: first['title']!.isNotEmpty ? first['title']! : 'Your event',
        eventBannerUrl: first['bannerUrl'] ?? '',
      ),
    ));
  }

  ExploreJoinState _asExploreJoinState(UserEventState state) {
    switch (state) {
      case UserEventState.joined:
        return ExploreJoinState.joined;
      case UserEventState.pending:
        return ExploreJoinState.requested;
      case UserEventState.notJoined:
        return ExploreJoinState.notJoined;
      case UserEventState.waitlisted:
        return ExploreJoinState.requested;
    }
  }

  UserEventState _eventParticipationStateFor(
    String eventId, {
    String? hostId,
    required bool watch,
    WidgetRef? scopedRef,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return UserEventState.notJoined;

    final normalizedHostId = (hostId ?? '').trim();
    if (normalizedHostId.isNotEmpty && normalizedHostId == uid) {
      return UserEventState.joined;
    }

    final providerRef = scopedRef ?? ref;
    final asyncState = watch
        ? providerRef.watch(eventParticipationStateProvider(eventId))
        : providerRef.read(eventParticipationStateProvider(eventId));

    return asyncState.valueOrNull ?? UserEventState.notJoined;
  }

  void _startEventExpiryPruner() {
    _eventExpiryTimer?.cancel();
    _eventExpiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _eventNodes.isEmpty) return;
      final now = DateTime.now();
      final activeEvents = _eventNodes
          .where((node) => node.date == null || node.date!.isAfter(now))
          .toList(growable: false);

      if (activeEvents.length == _eventNodes.length) return;

      _setStateFromMap(() {
        _eventNodes
          ..clear()
          ..addAll(activeEvents);

        final selected = _selectedMarkerEventId;
        if (selected != null &&
            !_eventNodes.any((event) => event.id == selected)) {
          _selectedMarkerEventId = null;
        }
      });
    });
  }

  DateTime? _extractEventDateTime(Map<String, dynamic> data) {
    final directCandidates = <dynamic>[
      data['endAt'],
      data['endTime'],
      data['endsAt'],
      data['eventDateTime'],
      data['eventDate'],
      data['date'],
      data['startAt'],
      data['startsAt'],
      data['startTime'],
    ];

    for (final raw in directCandidates) {
      final parsed = _parseDateTimeValue(raw);
      if (parsed != null) return parsed;
    }

    final schedule = data['schedule'];
    if (schedule is Map<String, dynamic>) {
      final nestedCandidates = <dynamic>[
        schedule['endAt'],
        schedule['endTime'],
        schedule['startAt'],
        schedule['startTime'],
        schedule['date'],
      ];
      for (final raw in nestedCandidates) {
        final parsed = _parseDateTimeValue(raw);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  DateTime? _parseDateTimeValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  void _loadEventsAfterMapReady() {
    if (_eventsLoadedAfterMapReady) return;
    _eventsLoadedAfterMapReady = true;
    shouldShowTutorial().then((show) {
      if (show && mounted) {
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _showTutorial = true);
        });
      } else {
        // Only check ended events if no tutorial is showing
        Future<void>.delayed(const Duration(seconds: 2), _checkEndedEvents);
      }
    });

    _eventsSub = _eventService.getEvents(limit: 100).listen((snapshot) {
      if (!mounted) return;
      print('STREAM UPDATE RECEIVED');
      final origin = _currentUserLocation;

      final newNodes = snapshot.docs
          .map((doc) {
            final typedDoc = doc;
            final model = EventModel.fromFirestore(typedDoc);

            if (model.status != 'active' || !model.isActive) {
              return null;
            }

            final resolvedLocation = model.location;
            if (resolvedLocation == null) {
              return null;
            }

            final eventDate = model.endTime ?? model.startTime;
            if (eventDate != null && !eventDate.isAfter(DateTime.now())) {
              return null;
            }

            return EventNode(
              id: model.id,
              latLng: resolvedLocation,
              emoji: model.eventAvatar.isNotEmpty ? model.eventAvatar : '📍',
              label: model.title.isEmpty ? 'Event' : model.title,
              activityLevel: model.participantsCount * 0.1,
              bannerImagePath:
                  model.bannerUrl.isNotEmpty ? model.bannerUrl : null,
              currentAttendees: model.participantsCount,
              maxCapacity: model.maxCapacity,
              visibility: model.visibility,
              isPublic: model.isPublic,
              isApprovalRequired: model.isApprovalRequired,
              hostId: model.hostId,
              hostName: model.hostName,
              participants: model.participants,
              date: eventDate,
            );
          })
          .where((node) {
            if (node == null) return false;
            if (origin == null) return true;
            if (node.visibility == 'global') return true;
            return _distanceKm(origin, node.latLng) <= 35;
          })
          .cast<EventNode>()
          .toList();

      final previousSignature = _eventNodesSignature(_eventNodes);
      final nextSignature = _eventNodesSignature(newNodes);
      if (previousSignature == nextSignature) return;

      if (!mounted) return;
      _setStateFromMap(() {
        _eventNodes
          ..clear()
          ..addAll(newNodes);
      });
    });
  }

  Future<void> _handleOrbTap() async {
    final initialLocation = _currentUserLocation ??
        await _ensureUserLocation(moveMap: false, showErrors: false);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _CreateEventSheet(
        initialUserLocation: initialLocation,
        onCreateEvent: _handleCreateEvent,
        onSubmitStarted: _handleCreateEventSubmitStarted,
      ),
    );
  }

  void _handleCreateEventSubmitStarted() {
    if (!mounted) return;
    if (_navIndex == 0) return;
    setState(() {
      _navIndex = 0;
    });
    _syncActiveTabProviderFromIndex(0);
  }

  void _handleCreateEvent(EventNode node) {
    setState(() {
      _eventNodes.add(node);
    });
    _mapController.move(node.latLng, _zoomLevel);
    _maybeFireFirstEventConfetti(node.hostId);
    _maybeShowAppRating();
  }

  Future<void> _maybeShowAppRating() async {
    if (!mounted) return;
    final should = await shouldShowAppRating();
    if (!should || !mounted) return;
    // Small delay so confetti plays first
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    showAppRatingSheet(context);
  }

  Future<void> _maybeFireFirstEventConfetti(String hostId) async {
    if (hostId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'first_event_created_$hostId';
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    _confettiController.play();
  }

  void _handleNodeTap(EventNode node) {
    if (_selectedMarkerEventId != node.id) {
      setState(() => _selectedMarkerEventId = node.id);
    }
    _showMapEventPreviewSheet(node);
  }

  ExploreJoinState _mapJoinStateForNode(
    EventNode node, {
    required bool watch,
    WidgetRef? scopedRef,
  }) {
    final state = _eventParticipationStateFor(
      node.id,
      hostId: node.hostId,
      watch: watch,
      scopedRef: scopedRef,
    );
    return _asExploreJoinState(state);
  }

  String _distanceLabelForNode(EventNode node) {
    if (_currentUserLocation == null) return 'Nearby';
    final km = _distanceKm(_currentUserLocation!, node.latLng);
    if (!km.isFinite) return 'Nearby';
    if (km < 1) return '${(km * 1000).round()} m away';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km away';
  }

  Future<void> _joinFromMapPreview(EventNode node) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to join events.')),
      );
      return;
    }

    if (node.hostId.trim().isNotEmpty && node.hostId.trim() == uid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are the host of this event.')),
      );
      return;
    }

    final currentState = _mapJoinStateForNode(node, watch: false);
    if (currentState != ExploreJoinState.notJoined) return;

    try {
      if (node.isApprovalRequired) {
        await _eventService.requestToJoinEvent(eventId: node.id, userId: uid);
      } else {
        await _eventService.joinEventDirect(eventId: node.id, userId: uid);
        unawaited(_notificationService.sendFriendJoinedEventNotifications(
          joinerId: uid,
          eventId: node.id,
        ));
      }

      if (!mounted) return;
      ref.invalidate(explorePaginatedFeedProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            node.isApprovalRequired
                ? 'Join request sent.'
                : 'You joined the event.',
          ),
        ),
      );
    } catch (e, stack) {
      if (!mounted) return;
      final isBlocked = e.toString().contains('block settings');
      ErrorHandler.showUserMessage(
        context,
        isBlocked ? AppErrorType.friendBlocked : AppErrorType.eventJoinFailed,
        error: e,
        stackTrace: stack,
        where: 'map_screen._joinEventFromMapPreview',
      );
    }
  }

  Future<void> _shareEventFromMapPreview(EventNode node) async {
    final eventId = node.id.trim();
    if (eventId.isEmpty) return;

    final title = node.label?.trim().isNotEmpty == true
        ? node.label!.trim()
        : 'Yanegi event';
    final eventUrl =
        '${AppEnvironment.webBaseUrl}/event/${Uri.encodeComponent(eventId)}';

    try {
      await Share.share(
        'Check out "$title" on Yanegi: $eventUrl',
        subject: title,
      );
    } catch (e, stack) {
      if (!mounted) return;
      ErrorHandler.showUserMessage(
        context,
        AppErrorType.eventShareFailed,
        error: e,
        stackTrace: stack,
        where: 'map_screen._shareEventFromMapPreview',
      );
    }
  }

  void _showMapEventPreviewSheet(EventNode node) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isHost = uid.isNotEmpty &&
        node.hostId.trim().isNotEmpty &&
        node.hostId.trim() == uid;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, modalRef, _) {
            final joinState = _mapJoinStateForNode(
              node,
              watch: true,
              scopedRef: modalRef,
            );
            final bool canJoin =
                !isHost && joinState == ExploreJoinState.notJoined;
            final buttonLabel = isHost
                ? 'Host'
                : switch (joinState) {
                    ExploreJoinState.notJoined =>
                      node.isApprovalRequired ? 'Request to join' : "I'm in",
                    ExploreJoinState.requested => 'Requested',
                    ExploreJoinState.joined => 'Joined',
                  };

            final cardColor = _isDarkTheme
                ? const Color(0xFF171A24)
                : const Color(0xFFFDFDFF);
            final textPrimary =
                _isDarkTheme ? Colors.white : const Color(0xFF12131A);
            final textSecondary = _isDarkTheme
                ? const Color(0xFFADB3C6)
                : const Color(0xFF606678);
            final avatarToken = _markerEmojiFor(node);

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  42,
                  14,
                  12 + MediaQuery.of(sheetContext).padding.bottom,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 56, 18, 16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _isDarkTheme
                              ? Colors.white.withAlpha(14)
                              : Colors.black.withAlpha(10),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              _openMapEventDetail(node);
                            },
                            child: Text(
                              node.label?.trim().isNotEmpty == true
                                  ? node.label!.trim()
                                  : 'Untitled event',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                                decoration: TextDecoration.underline,
                                decorationColor: textPrimary.withAlpha(90),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_distanceLabelForNode(node)} • ${_pillTextForAttendees(node.currentAttendees)}',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (node.hostName.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Hosted by ${node.hostName}',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          // Friends going social proof
                          Builder(builder: (_) {
                            final currentUid =
                                FirebaseAuth.instance.currentUser?.uid ?? '';
                            if (currentUid.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: FriendsGoingStrip(
                                eventId: node.id,
                                currentUserId: currentUid,
                              ),
                            );
                          }),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: canJoin
                                  ? () async {
                                      final navigator =
                                          Navigator.of(sheetContext);
                                      await _joinFromMapPreview(node);
                                      if (!mounted) return;
                                      navigator.pop();
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFF49556D),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                buttonLabel,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: -26,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isDarkTheme
                              ? const Color(0xFF202434)
                              : const Color(0xFFF1F3FB),
                          border: Border.all(
                            color: _isDarkTheme
                                ? Colors.white.withAlpha(18)
                                : Colors.black.withAlpha(10),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withAlpha(_isDarkTheme ? 55 : 20),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isAvatarAssetPath(avatarToken)
                              ? Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Image.asset(
                                    avatarToken,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.event_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                )
                              : Text(
                                  avatarToken,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontFamily: 'Apple Color Emoji',
                                  ),
                                ),
                        ),
                      ),
                    ),
                    // Close button — top right
                    Positioned(
                      right: 14,
                      top: 12,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(sheetContext),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isDarkTheme
                                ? Colors.white.withAlpha(14)
                                : Colors.black.withAlpha(6),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                    // Share button — top left (mirrors close button)
                    Positioned(
                      left: 14,
                      top: 12,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _showMapShareSheet(node);
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isDarkTheme
                                ? Colors.white.withAlpha(14)
                                : Colors.black.withAlpha(6),
                          ),
                          child: Icon(
                            Icons.share_rounded,
                            size: 16,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMapShareSheet(EventNode node) {
    final eventId  = node.id.trim();
    if (eventId.isEmpty || !mounted) return;
    final title    = (node.label ?? '').trim();
    final emoji    = node.emoji.trim();
    final banner   = (node.bannerImagePath ?? '').trim();
    final eventUrl = '${AppEnvironment.webBaseUrl}/event/${Uri.encodeComponent(eventId)}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF101726),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Share Event',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _MapShareTile(
              icon: Icons.chat_bubble_rounded,
              label: 'Share in Chat',
              subtitle: 'Send as a card to a DM',
              onTap: () {
                Navigator.pop(context);
                showShareToChatSheet(
                  context,
                  shareType: 'event_card',
                  metadata: {
                    'targetId': eventId,
                    'title': title.isEmpty ? 'Event' : title,
                    'emoji': emoji.isEmpty ? '📍' : emoji,
                    'bannerUrl': banner,
                    'subtitle': '',
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            _MapShareTile(
              icon: Icons.link_rounded,
              label: 'Copy / Share Link',
              subtitle: eventUrl,
              onTap: () async {
                Navigator.pop(context);
                try {
                  await Share.share(
                    'Check out "${title.isEmpty ? 'this event' : title}" on Yanegi: $eventUrl',
                    subject: title.isEmpty ? 'Yanegi event' : title,
                  );
                } catch (e, stack) {
                  if (!mounted) return;
                  ErrorHandler.showUserMessage(
                    context, AppErrorType.eventShareFailed,
                    error: e, stackTrace: stack,
                    where: 'map_screen._showMapShareSheet',
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openMapEventDetail(EventNode node) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailScreen(
          eventId: node.id,
          userLocation: _currentUserLocation != null
              ? Position(
                  latitude: _currentUserLocation!.latitude,
                  longitude: _currentUserLocation!.longitude,
                  timestamp: DateTime.now(),
                  accuracy: 0,
                  altitude: 0,
                  heading: 0,
                  speed: 0,
                  speedAccuracy: 0,
                  altitudeAccuracy: 0,
                  headingAccuracy: 0,
                )
              : null,
        ),
      ),
    );
  }
}
