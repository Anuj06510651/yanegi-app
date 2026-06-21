// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/map_screen.dart';

extension _MapExploreController on _MapScreenState {
  Widget _buildYanegiExplorePage(
    AsyncValue<ExplorePaginatedFeedState> rankedExploreAsync,
    ExploreFeedRequest exploreRequest,
  ) {
    return Container(
      color: _isDarkTheme
          ? const Color(0xFF090D15).withAlpha(225)
          : Colors.white.withAlpha(235),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: _buildExploreTopBar(),
            ),
            _buildExploreChipRow(),
            const SizedBox(height: 8),
            Expanded(
              child: rankedExploreAsync.when(
                loading: () => RefreshIndicator(
                  color: const Color(0xFF3B82F6),
                  backgroundColor:
                      _isDarkTheme ? const Color(0xFF111827) : Colors.white,
                  onRefresh: () => _refreshExploreFeed(exploreRequest),
                  child: _buildExploreSkeletonListView(),
                ),
                error: (error, stackTrace) {
                  debugPrint('🔥 UI Build Error: $error');
                  debugPrintStack(stackTrace: stackTrace);
                  return Center(
                    child: _buildExploreErrorState(
                      onRetry: () {
                        ref.invalidate(
                          explorePaginatedFeedProvider(exploreRequest),
                        );
                      },
                    ),
                  );
                },
                data: (exploreFeedState) {
                  final items = _buildExploreFeedItems(exploreFeedState.items);

                  if (items.isEmpty) {
                    return RefreshIndicator(
                      color: const Color(0xFF3B82F6),
                      backgroundColor:
                          _isDarkTheme ? const Color(0xFF111827) : Colors.white,
                      onRefresh: () => _refreshExploreFeed(exploreRequest),
                      child: _buildExploreEmptyListView(),
                    );
                  }

                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.pixels >=
                          notification.metrics.maxScrollExtent - 280) {
                        ref
                            .read(explorePaginatedFeedProvider(exploreRequest)
                                .notifier)
                            .loadMore();
                      }
                      return false;
                    },
                    child: RefreshIndicator(
                      color: const Color(0xFF3B82F6),
                      backgroundColor:
                          _isDarkTheme ? const Color(0xFF111827) : Colors.white,
                      onRefresh: () => _refreshExploreFeed(exploreRequest),
                      child: _buildExploreListView(
                        items: items,
                        state: exploreFeedState,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExploreTopBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _tabSurfaceColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _tabBorderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: _tabSecondaryTextColor),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _exploreSearchController,
                    decoration: InputDecoration(
                      hintText: 'Search events, places, vibes...',
                      hintStyle: TextStyle(
                        color: _tabSecondaryTextColor,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    style: TextStyle(color: _tabPrimaryTextColor, fontSize: 14),
                    onChanged: (val) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        ref
                            .read(filterProvider.notifier)
                            .updateFilters(searchQuery: val);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _showFilterSheet,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _tabSurfaceColor,
              shape: BoxShape.circle,
              border: Border.all(color: _tabBorderColor),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: _tabPrimaryTextColor,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExploreChipRow() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final chip = _MapScreenState._exploreChips[index];
          final selected = _selectedExploreChip == chip;
          return GestureDetector(
            onTap: () => setState(() => _selectedExploreChip = chip),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF3B82F6) : _tabSurfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? const Color(0xFF3B82F6) : _tabBorderColor,
                ),
              ),
              child: Text(
                chip,
                style: TextStyle(
                  color: selected ? Colors.white : _tabPrimaryTextColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemCount: _MapScreenState._exploreChips.length,
      ),
    );
  }

  Widget _buildExploreSectionedContent(List<_ExploreFeedItem> items) {
    final nearby = items.where(_isNearbyItem).toList();
    final trending = items.where(_isTrendingItem).toList();
    final exploreMore = items
        .where((item) => !_isNearbyItem(item) && !_isTrendingItem(item))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (nearby.isNotEmpty) ...[
          _buildExploreSectionTitle('Nearby'),
          _buildExploreStaggeredColumns(nearby),
          const SizedBox(height: 8),
        ],
        if (trending.isNotEmpty) ...[
          _buildExploreSectionTitle('Trending'),
          _buildExploreStaggeredColumns(trending),
          const SizedBox(height: 8),
        ],
        if (exploreMore.isNotEmpty) ...[
          _buildExploreSectionTitle('Explore more'),
          _buildExploreStaggeredColumns(exploreMore),
        ],
      ],
    );
  }

  Widget _buildExploreSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      child: Text(
        title,
        style: TextStyle(
          color: _tabPrimaryTextColor,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildExploreListView({
    required List<_ExploreFeedItem> items,
    required ExplorePaginatedFeedState state,
  }) {
    final rows = _buildExploreListRows(items, state);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      cacheExtent: 500,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is String) {
          return _buildExploreSectionTitle(row);
        }

        if (row is _ExploreFeedListFooter) {
          if (row.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.only(top: 14),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),
            );
          }

          if (!row.hasMore) {
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: Text(
                  'No more events nearby',
                  style: TextStyle(
                    color: _tabSecondaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }

          return const SizedBox.shrink();
        }

        if (row is _ExploreRefreshingRow) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Center(
              child: Text(
                'Refreshing...',
                style: TextStyle(
                  color: _tabSecondaryTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }

        final item = row as _ExploreFeedItem;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RepaintBoundary(
            child: _buildExploreFeedCard(item),
          ),
        );
      },
    );
  }

  Widget _buildExploreSkeletonListView() {
    const rows = <double>[180, 130, 170, 120, 180, 130];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      cacheExtent: 500,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
            child: Text(
              'Nearby',
              style: TextStyle(
                color: _tabPrimaryTextColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        final height = rows[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RepaintBoundary(
            child: _ExploreSkeletonCard(height: height),
          ),
        );
      },
    );
  }

  Widget _buildExploreEmptyListView() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      cacheExtent: 500,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: 1,
      itemBuilder: (context, index) => _buildExploreEmptyState(),
    );
  }

  List<Object> _buildExploreListRows(
    List<_ExploreFeedItem> items,
    ExplorePaginatedFeedState state,
  ) {
    final nearby = items.where(_isNearbyItem).toList(growable: false);
    final trending = items.where(_isTrendingItem).toList(growable: false);
    final exploreMore = items
        .where((item) => !_isNearbyItem(item) && !_isTrendingItem(item))
        .toList(growable: false);

    final rows = <Object>[];

    if (state.isRefreshing) {
      rows.add(const _ExploreRefreshingRow());
    }

    if (nearby.isNotEmpty) {
      rows
        ..add('Nearby')
        ..addAll(nearby);
    }

    if (trending.isNotEmpty) {
      rows
        ..add('Trending')
        ..addAll(trending);
    }

    if (exploreMore.isNotEmpty) {
      rows
        ..add('Explore more')
        ..addAll(exploreMore);
    }

    rows.add(_ExploreFeedListFooter(
      isLoadingMore: state.isLoadingMore,
      hasMore: state.hasMore,
    ));

    return rows;
  }

  Widget _buildExploreSkeletonState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildExploreSectionTitle('Nearby'),
        _buildExploreSkeletonRow(),
        const SizedBox(height: 8),
        _buildExploreSectionTitle('Trending'),
        _buildExploreSkeletonRow(),
      ],
    );
  }

  Widget _buildExploreSkeletonRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(child: _ExploreSkeletonCard(height: 180)),
        SizedBox(width: 10),
        Expanded(child: _ExploreSkeletonCard(height: 130)),
      ],
    );
  }

  Widget _buildExploreEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 26, 12, 0),
      child: Column(
        children: [
          Icon(
            Icons.location_off,
            size: 42,
            color: _tabSecondaryTextColor,
          ),
          const SizedBox(height: 10),
          Text(
            'No events nearby',
            style: TextStyle(
              color: _tabPrimaryTextColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Try changing filters or location',
            style: TextStyle(
              color: _tabSecondaryTextColor,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildExploreErrorState({required VoidCallback onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error,
            size: 42,
            color: _tabSecondaryTextColor,
          ),
          const SizedBox(height: 10),
          Text(
            'Something went wrong',
            style: TextStyle(
              color: _tabPrimaryTextColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  bool _isNearbyItem(_ExploreFeedItem item) {
    return item.ranked.distanceKm.isFinite && item.ranked.distanceKm <= 8;
  }

  bool _isTrendingItem(_ExploreFeedItem item) {
    return item.ranked.friendJoined ||
        item.ranked.friendHost ||
        item.ranked.participantsCount >= 12 ||
        item.ranked.score >= 90;
  }

  Widget _buildExploreStaggeredColumns(List<_ExploreFeedItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldUseSingleColumn = constraints.maxWidth < 390 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.15;

        if (shouldUseSingleColumn) {
          return Column(
            children: items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildExploreFeedCard(item),
                  ),
                )
                .toList(),
          );
        }

        final left = <_ExploreFeedItem>[];
        final right = <_ExploreFeedItem>[];
        double leftWeight = 0;
        double rightWeight = 0;

        for (final item in items) {
          final weight = item.layoutWeight;
          if (leftWeight <= rightWeight) {
            left.add(item);
            leftWeight += weight;
          } else {
            right.add(item);
            rightWeight += weight;
          }
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: left
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildExploreFeedCard(item),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: right
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildExploreFeedCard(item),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  List<_ExploreFeedItem> _buildExploreFeedItems(
    List<RankedExploreEvent> rankedEvents,
  ) {
    if (rankedEvents.isEmpty) return [];
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    final dedupedByEventId = <String, RankedExploreEvent>{};
    for (final ranked in rankedEvents) {
      final eventId = ranked.eventId.trim();
      if (eventId.isEmpty) continue;
      if (currentUid != null &&
          currentUid.isNotEmpty &&
          ranked.hostId == currentUid) {
        continue;
      }

      final existing = dedupedByEventId[eventId];
      if (existing == null) {
        dedupedByEventId[eventId] = ranked;
        continue;
      }

      final existingHasBanner = (existing.bannerUrl ?? '').trim().isNotEmpty;
      final nextHasBanner = (ranked.bannerUrl ?? '').trim().isNotEmpty;
      if (!existingHasBanner && nextHasBanner) {
        dedupedByEventId[eventId] = ranked;
      }
    }

    final rankedList = dedupedByEventId.values.toList(growable: false);
    final list = <_ExploreFeedItem>[];

    for (int i = 0; i < rankedList.length; i++) {
      final ranked = rankedList[i];
      final bannerUrl = (ranked.bannerUrl ?? '').trim();
      final thumbnailUrl = (ranked.thumbnailUrl ?? '').trim();
      final cardImageUrl = bannerUrl.isNotEmpty ? bannerUrl : thumbnailUrl;
      final hasBanner = cardImageUrl.isNotEmpty;

      final type =
          hasBanner ? _ExploreCardType.banner : _ExploreCardType.avatar;

      final node = EventNode(
        id: ranked.eventId,
        latLng: ranked.location,
        emoji: _emojiForRankedEvent(ranked),
        label: ranked.title,
        bannerImagePath: cardImageUrl.isNotEmpty ? cardImageUrl : null,
        currentAttendees: ranked.participantsCount,
        maxCapacity: ranked.maxParticipants,
        categories: ranked.categories,
        vibes: ranked.vibes,
        date: ranked.eventTime,
        isPublic: ranked.isPublic,
        visibility: ranked.visibility,
        hostId: ranked.hostId,
        hostName: ranked.hostName,
        locationText: ranked.locationName,
        participants: ranked.participantIds,
      );

      final distanceText = ranked.distanceKm.isFinite
          ? ranked.distanceKm < 1
              ? '${(ranked.distanceKm * 1000).round()}m away'
              : '${ranked.distanceKm.toStringAsFixed(1)}km away'
          : 'Distance unknown';

      final spotsLeft = (ranked.maxParticipants - ranked.participantsCount)
          .clamp(0, ranked.maxParticipants);

      final peopleText = '${ranked.participantsCount} going';
      final socialProofText = ranked.friendHost
          ? 'Hosted by a friend'
          : ranked.friendJoined
              ? 'Friends joined'
              : ranked.distanceKm.isFinite
                  ? (ranked.distanceKm < 1
                      ? '${(ranked.distanceKm * 1000).round()} m away'
                      : '${ranked.distanceKm.toStringAsFixed(1)} km away')
                  : 'Popular nearby';

      final timeText = _rankedTimeText(ranked.eventTime, ranked.createdAt);

      list.add(
        _ExploreFeedItem(
          id: ranked.eventId,
          ranked: ranked,
          node: node,
          title: ranked.title,
          emoji: node.emoji,
          type: type,
          timeText: timeText,
          distanceText: distanceText,
          peopleText: peopleText,
          socialProofText: socialProofText,
          spotsLeftText: '$spotsLeft spots left',
        ),
      );
    }

    final filtered = _applyChipFilter(list);
    return _applyRefreshTwist(filtered);
  }

  Future<void> _refreshExploreFeed(ExploreFeedRequest exploreRequest) async {
    try {
      ref.invalidate(explorePaginatedFeedProvider(exploreRequest));
      await ref.read(explorePaginatedFeedProvider(exploreRequest).future);
    } catch (_) {
      // Keep pull-to-refresh stable during transient network/provider races.
    }

    if (!mounted) return;
    setState(() {
      _exploreRefreshCycle++;
    });
  }

  List<_ExploreFeedItem> _applyRefreshTwist(List<_ExploreFeedItem> list) {
    if (_exploreRefreshCycle == 0 || list.length < 4) return list;

    final twisted = List<_ExploreFeedItem>.from(list);
    final mode = _exploreRefreshCycle % 3;

    if (mode == 1) {
      final item = twisted.removeAt(1);
      twisted.insert(3, item);
      return twisted;
    }

    if (mode == 2) {
      final item = twisted.removeAt(2);
      twisted.insert(1, item);
      return twisted;
    }

    return twisted;
  }

  String _emojiForRankedEvent(RankedExploreEvent ranked) {
    final tags = [...ranked.categories, ...ranked.vibes];
    if (tags.isEmpty) return '📍';
    return kEmojiByTag[tags.first] ?? '📍';
  }

  String _rankedTimeText(DateTime? eventTime, DateTime createdAt) {
    if (eventTime == null) {
      final hours = DateTime.now().difference(createdAt).inHours;
      return hours < 24 ? 'New' : 'Upcoming';
    }

    final now = DateTime.now();
    if (eventTime.isBefore(now.add(const Duration(hours: 1)))) {
      return 'Now';
    }

    if (eventTime.day == now.day &&
        eventTime.month == now.month &&
        eventTime.year == now.year) {
      return 'Today';
    }

    return DateFormat('EEE, h:mm a').format(eventTime);
  }

  List<_ExploreFeedItem> _applyChipFilter(List<_ExploreFeedItem> list) {
    switch (_selectedExploreChip) {
      case 'Nearby':
        return list
            .where(
                (i) => i.ranked.distanceKm.isFinite && i.ranked.distanceKm <= 8)
            .toList();
      case 'Today':
        return list
            .where((i) => i.timeText == 'Now' || i.timeText == 'Today')
            .toList();
      case 'Free':
        return list.where((i) => i.id.hashCode.isEven).toList();
      case 'Trending':
        return list
            .where(
              (i) =>
                  i.ranked.friendJoined ||
                  i.ranked.friendHost ||
                  i.ranked.participantsCount >= 12,
            )
            .toList();
      case 'Nightlife':
        return list.where((i) => i.timeText == 'Tonight').toList();
      case 'Chill':
        return list.where((i) => i.type == _ExploreCardType.avatar).toList();
      default:
        return list;
    }
  }

  Widget _buildExploreFeedCard(_ExploreFeedItem item) {
    switch (item.type) {
      case _ExploreCardType.banner:
        return _buildFeaturedExploreCard(item);
      case _ExploreCardType.avatar:
        return _buildCompactExploreCard(item);
      case _ExploreCardType.suggestion:
        return _buildSuggestionExploreCard(item);
    }
  }

  Future<void> _handleExploreJoinTap(_ExploreFeedItem item) async {
    final eventId = item.ranked.eventId;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to join events.')),
      );
      return;
    }

    if (_joiningExploreEventIds.contains(eventId)) return;
    final currentState = _asExploreJoinState(
      _eventParticipationStateFor(
        item.ranked.eventId,
        hostId: item.ranked.hostId,
        watch: false,
      ),
    );
    if (currentState != ExploreJoinState.notJoined) return;

    setState(() => _joiningExploreEventIds.add(eventId));

    try {
      if (item.ranked.isApprovalRequired) {
        await _eventService.requestToJoinEvent(eventId: eventId, userId: uid);
      } else {
        await _eventService.joinEventDirect(eventId: eventId, userId: uid);
        unawaited(_notificationService.sendFriendJoinedEventNotifications(
          joinerId: uid,
          eventId: eventId,
        ));
      }

      if (mounted) {
        ref.invalidate(explorePaginatedFeedProvider);
      }
    } catch (e, stack) {
      if (!mounted) return;
      final isBlocked = e.toString().contains('block settings');
      ErrorHandler.showUserMessage(
        context,
        isBlocked ? AppErrorType.friendBlocked : AppErrorType.eventJoinFailed,
        error: e,
        stackTrace: stack,
        where: 'map_screen._joinExploreEvent',
      );
    } finally {
      if (mounted) {
        setState(() => _joiningExploreEventIds.remove(eventId));
      }
    }
  }

  Widget _buildExploreJoinButton(
    _ExploreFeedItem item,
  ) {
    // Consumer scopes the ref.watch to this button widget only.
    // Without it, every participation state change rebuilds the entire map screen.
    return Consumer(
      builder: (context, btnRef, _) {
        final state = _eventParticipationStateFor(
          item.ranked.eventId,
          hostId: item.ranked.hostId,
          watch: true,
          scopedRef: btnRef,
        );
        final joinState = _asExploreJoinState(state);
        final isBusy = _joiningExploreEventIds.contains(item.ranked.eventId);

        String label;
        Color bg;
        VoidCallback? onPressed;

        if (isBusy) {
          label = 'Joining...';
          bg = const Color(0xFF3B4558);
          onPressed = null;
        } else {
          switch (joinState) {
            case ExploreJoinState.notJoined:
              label = 'Join';
              bg = const Color(0xFF3B82F6);
              onPressed = () => _handleExploreJoinTap(item);
              break;
            case ExploreJoinState.requested:
              label = 'Requested';
              bg = const Color(0xFF49556D);
              onPressed = null;
              break;
            case ExploreJoinState.joined:
              label = 'Joined';
              bg = const Color(0xFF2D8F68);
              onPressed = null;
              break;
          }
        }

        return SizedBox(
          height: 30,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: Colors.white,
              minimumSize: const Size(78, 30),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeaturedExploreCard(_ExploreFeedItem item) {
    return _exploreCardShell(
      onTap: () => _openExploreDetail(item),
      onLongPress: () => _openExploreDetail(item),
      child: Container(
        height: 206,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildExploreBannerImage(
                item.node.bannerImagePath,
                eventId: item.node.id,
                previewSource: item.ranked.thumbnailUrl,
                borderRadius: BorderRadius.circular(18),
                fallbackGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2B2D42), Color(0xFF1A1F2E)],
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(20),
                      Colors.black.withAlpha(140),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 10,
              child: _buildExploreAvatarBubble(item.emoji, size: 36),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _metaPill(item.timeText),
                      _metaPill(item.distanceText),
                      _metaPill(item.peopleText),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildExploreJoinButton(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandardExploreCard(_ExploreFeedItem item) {
    return _exploreCardShell(
      onTap: () => _openExploreDetail(item),
      onLongPress: () => _openExploreDetail(item),
      child: Container(
        constraints: const BoxConstraints(minHeight: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: YanegiColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(8), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: _buildExploreBannerImage(
                  item.node.bannerImagePath,
                  eventId: item.node.id,
                  previewSource: item.ranked.thumbnailUrl,
                  fallbackGradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF20293C), Color(0xFF151A25)],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildExploreAvatarBubble(item.emoji, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${item.timeText} • ${item.distanceText}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withAlpha(165),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            _buildAvatarRow(3),
            const SizedBox(height: 10),
            Text(
              item.peopleText,
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _buildExploreJoinButton(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactExploreCard(_ExploreFeedItem item) {
    return _exploreCardShell(
      onTap: () => _openExploreDetail(item),
      onLongPress: () => _openExploreDetail(item),
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF171D2A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Colors.black.withAlpha(70),
              child: _buildExploreAvatarBubble(item.emoji, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.distanceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withAlpha(140),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${item.timeText} • ${item.peopleText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withAlpha(140),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: _buildExploreJoinButton(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveExploreCard(_ExploreFeedItem item) {
    return _exploreCardShell(
      onTap: () => _openExploreDetail(item),
      onLongPress: () => _openExploreDetail(item),
      child: Container(
        constraints: const BoxConstraints(minHeight: 118),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF241B27),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFF3B82F6).withAlpha(70)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22E7A2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Happening now',
                  style: TextStyle(
                    color: const Color(0xFF22E7A2),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.socialProofText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withAlpha(160),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _buildExploreJoinButton(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicroExploreCard(_ExploreFeedItem item) {
    return _exploreCardShell(
      onTap: () => _openExploreDetail(item),
      onLongPress: () => _openExploreDetail(item),
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF151A25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _buildExploreAvatarBubble(item.emoji, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withAlpha(220),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: _buildExploreJoinButton(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionExploreCard(_ExploreFeedItem item) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YanegiColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(8), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need better options?',
            style: TextStyle(
              color: Colors.white.withAlpha(230),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try expanding your radius or check trending nearby areas.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withAlpha(145), fontSize: 12),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _handleOrbTap,
            child: const Text(
              'Start your own event',
              style: TextStyle(
                color: Color(0xFF3B82F6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exploreCardShell({
    required Widget child,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return _ExploreCardInteraction(
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }

  Widget _metaPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  bool _isNetworkImagePath(String token) {
    final lower = token.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  bool _isFileImagePath(String token) {
    final trimmed = token.trim().toLowerCase();
    return trimmed.startsWith('/') || trimmed.startsWith('file://');
  }

  Widget _buildExploreAvatarBubble(String token, {double size = 24}) {
    if (_isAvatarAssetPath(token)) {
      return Image.asset(
        token,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.event_rounded,
          color: Colors.white,
          size: size,
        ),
      );
    }

    return Text(
      token,
      style: TextStyle(
        fontSize: size,
        fontFamily: 'Apple Color Emoji',
        height: 1,
      ),
    );
  }

  Widget _buildExploreBannerImage(
    String? source, {
    String? eventId,
    String? previewSource,
    BorderRadius? borderRadius,
    LinearGradient? fallbackGradient,
  }) {
    final resolved = source?.trim() ?? '';
    final preview = previewSource?.trim() ?? '';
    final fallback = Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: fallbackGradient ??
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2B2D42), Color(0xFF1A1F2E)],
            ),
      ),
    );

    if (resolved.isEmpty) {
      return fallback;
    }

    if (_isNetworkImagePath(resolved)) {
      return CachedNetworkImage(
        imageUrl: resolved,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 120),
        memCacheWidth: 600,
        placeholder: (context, url) => _buildExploreNetworkPlaceholder(
          borderRadius: borderRadius,
          lowResUrl: _isNetworkImagePath(preview) ? preview : null,
        ),
        errorWidget: (_, __, ___) => fallback,
      );
    }

    if (_isAvatarAssetPath(resolved)) {
      return Image.asset(
        resolved,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    if (_isFileImagePath(resolved)) {
      final file = resolved.startsWith('file://')
          ? File.fromUri(Uri.parse(resolved))
          : File(resolved);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return fallback;
  }

  Widget _buildExploreNetworkPlaceholder({
    BorderRadius? borderRadius,
    String? lowResUrl,
  }) {
    final radius = borderRadius ?? BorderRadius.zero;
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.grey.shade300),
          if (lowResUrl != null && lowResUrl.isNotEmpty)
            Opacity(
              opacity: 0.55,
              child: CachedNetworkImage(
                imageUrl: lowResUrl,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                memCacheWidth: 120,
                memCacheHeight: 120,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          if (lowResUrl != null && lowResUrl.isNotEmpty)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.transparent),
              ),
            ),
          Container(color: Colors.black.withAlpha(12)),
        ],
      ),
    );
  }

  Widget _buildAvatarRow(int count) {
    return SizedBox(
      height: 20,
      child: Stack(
        children: List.generate(count, (index) {
          return Positioned(
            left: index * 14,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: [
                  const Color(0xFF3B82F6),
                  const Color(0xFF7C7AFF),
                  const Color(0xFF22E7A2),
                ][index % 3],
                border: Border.all(color: const Color(0xFF171D2A), width: 2),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _openExploreDetail(_ExploreFeedItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EventDetailScreen(
          eventId: item.node.id,
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
