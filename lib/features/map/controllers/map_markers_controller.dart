// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/map_screen.dart';

extension _MapMarkersController on _MapScreenState {
  void _syncMarkerCache(List<EventNode> visibleNodes) {
    final mode = _markerModeForZoom(_zoomLevel);
    final clusterBucket = _clusterBucketForZoom(_zoomLevel);
    final key = visibleNodes
        .map((n) =>
            '${n.id}:${n.latLng.latitude.toStringAsFixed(4)}:${n.latLng.longitude.toStringAsFixed(4)}:${n.currentAttendees}:${_selectedMarkerEventId ?? ''}:$mode:$clusterBucket')
        .join('|');
    if (key == _markerCacheKey) return;

    _markerCacheKey = key;
    if (mode == _MarkerVisualMode.farCluster) {
      final clusters = <String, List<EventNode>>{};
      for (final node in visibleNodes) {
        final latKey =
            (node.latLng.latitude / clusterBucket).round().toString();
        final lngKey =
            (node.latLng.longitude / clusterBucket).round().toString();
        final bucketKey = '$latKey:$lngKey';
        clusters.putIfAbsent(bucketKey, () => <EventNode>[]).add(node);
      }

      _cachedEventMarkers = clusters.values.map((group) {
        if (group.length == 1) {
          final node = group.first;
          return Marker(
            point: node.latLng,
            width: 26,
            height: 26,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () => _handleNodeTap(node),
              child: _buildEventMarker(node, mode: mode),
            ),
          );
        }
        final lat = group.fold<double>(0, (sum, n) => sum + n.latLng.latitude) /
            group.length;
        final lng =
            group.fold<double>(0, (sum, n) => sum + n.latLng.longitude) /
                group.length;
        return Marker(
          point: LatLng(lat, lng),
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => _mapController.move(
                LatLng(lat, lng), (_zoomLevel + 1.2).clamp(12.5, 16.5)),
            child: _buildClusterBubble(group.length),
          ),
        );
      }).toList(growable: false);
    } else {
      _cachedEventMarkers = visibleNodes.map((node) {
        return Marker(
          point: node.latLng,
          width: mode == _MarkerVisualMode.closeWithPill ? 80 : 54,
          height: mode == _MarkerVisualMode.closeWithPill ? 78 : 54,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => _handleNodeTap(node),
            child: _buildEventMarker(node, mode: mode),
          ),
        );
      }).toList(growable: false);
    }

    debugPrint('Markers loaded');
  }

  Widget _buildMapLayer(List<EventNode> filteredNodes) {
    final mapBuildDebugKey =
        '${filteredNodes.length}:${_currentUserLocation?.latitude.toStringAsFixed(5) ?? 'none'}:${_currentUserLocation?.longitude.toStringAsFixed(5) ?? 'none'}:${_zoomLevel.toStringAsFixed(2)}:$_isLoadingLocation';
    if (mapBuildDebugKey != _lastMapBuildDebugKey) {
      _lastMapBuildDebugKey = mapBuildDebugKey;
      print('MAP BUILD TRIGGERED');
    }

    final visibleNodes = filteredNodes;
    _syncMarkerCache(visibleNodes);

    return Stack(
      children: [
        FlutterMap(
          key: const ValueKey('yanegi-primary-map'),
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentUserLocation ?? _MapScreenState._nycCenter,
            initialZoom: 14,
            onMapReady: () {
              if (_mapReady) return;
              _mapReady = true;
              debugPrint('Map loaded');
              if (_currentUserLocation != null &&
                  !_didAnimateToInitialUserLocation) {
                _didAnimateToInitialUserLocation = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _currentUserLocation == null) return;
                  _animateToLocation(_currentUserLocation!, zoom: 14);
                });
              }
              _loadEventsAfterMapReady();
            },
            backgroundColor:
                _isDarkTheme ? YanegiColors.mapDark : const Color(0xFFEAF0F8),
            onPositionChanged: (position, hasGesture) {
              _lastKnownMapCenter = position.center;

              if (hasGesture) {
                _zoomCommitTimer?.cancel();
                final targetZoom = position.zoom;
                _zoomCommitTimer = Timer(
                  const Duration(milliseconds: 90),
                  () {
                    if (!mounted) return;
                    if ((targetZoom - _zoomLevel).abs() > 0.02) {
                      _setStateFromMap(() {
                        _zoomLevel = targetZoom;
                      });
                    }
                  },
                );
                return;
              }

              if ((position.zoom - _zoomLevel).abs() > 0.02) {
                if (_cameraAnimationTimer != null) {
                  _zoomLevel = position.zoom;
                } else {
                  _setStateFromMap(() {
                    _zoomLevel = position.zoom;
                  });
                }
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _mapBaseUrlTemplate,
              userAgentPackageName: MapConfig.userAgentPackageName,
              retinaMode: true,
              errorTileCallback: (tile, error, stackTrace) {},
            ),
            MarkerLayer(
              markers: _cachedEventMarkers,
            ),
            if (_currentUserLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentUserLocation!,
                    width: 46,
                    height: 46,
                    child: const _UserLocationMarker(),
                  ),
                ],
              ),
          ],
        ),
        if (visibleNodes.isEmpty)
          Positioned(
            bottom: 120, // Sit just above the taskbar
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isDarkTheme
                    ? YanegiColors.surfaceElevated.withAlpha(240)
                    : Colors.white.withAlpha(240),
                borderRadius: BorderRadius.circular(YanegiRadius.lg),
                border: Border.all(
                  color: YanegiColors.textTertiary.withAlpha(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.satellite_alt_rounded,
                      size: 40, color: YanegiColors.textTertiary),
                  const SizedBox(height: 12),
                  const Text(
                    'No events nearby',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expand your map or be the first to start something within 35 km.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: YanegiColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _handleOrbTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YanegiColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YanegiRadius.pill),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Create event'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapAtmosphereOverlay() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.15),
                  radius: 1.2,
                  colors: _isDarkTheme
                      ? [Colors.transparent, Colors.black.withAlpha(80)]
                      : [Colors.transparent, Colors.black.withAlpha(28)],
                  stops: const [0.62, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _isDarkTheme
                      ? [Colors.black.withAlpha(105), Colors.transparent]
                      : [Colors.white.withAlpha(60), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 145,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: _isDarkTheme
                      ? [Colors.black.withAlpha(118), Colors.transparent]
                      : [Colors.white.withAlpha(64), Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _MarkerVisualMode _markerModeForZoom(double zoom) {
    if (zoom <= 12.8) return _MarkerVisualMode.farCluster;
    if (zoom <= 14.4) return _MarkerVisualMode.mediumEmojiOnly;
    return _MarkerVisualMode.closeWithPill;
  }

  double _clusterBucketForZoom(double zoom) {
    if (zoom <= 11.8) return 0.015;
    if (zoom <= 12.8) return 0.010;
    return 0.0075;
  }

  String _pillTextForAttendees(int attendees) {
    if (attendees <= 1) return 'be 1st';
    if (attendees >= 100) return '100+ 👥';
    return '$attendees 👥';
  }

  bool _isAvatarAssetPath(String token) => isEventAvatarAssetPath(token);

  String _markerEmojiFor(EventNode node) {
    final emoji = node.emoji.trim();
    if (emoji.isNotEmpty && emoji != '📍') return emoji;
    final lower = node.label.toString().toLowerCase();
    if (lower.contains('music')) return kEmojiByTag['Music']!;
    if (lower.contains('art')) return kEmojiByTag['Art']!;
    if (lower.contains('food') || lower.contains('dinner')) {
      return kEmojiByTag['Food']!;
    }
    if (lower.contains('sport')) return kEmojiByTag['Sports']!;
    if (lower.contains('tech')) return kEmojiByTag['Tech']!;
    if (lower.contains('coffee') || lower.contains('social')) {
      return kEmojiByTag['Social']!;
    }
    if (lower.contains('outdoor')) return kEmojiByTag['Outdoor']!;
    if (lower.contains('party')) return kEmojiByTag['Party']!;
    return kEventAvatarAssets.first;
  }

  Widget _buildClusterBubble(int count) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: YanegiColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withAlpha(185), width: 1),
        boxShadow: [
          BoxShadow(
            color: YanegiColors.primary.withOpacity(0.32),
            blurRadius: 10,
            spreadRadius: 1.5,
          ),
        ],
      ),
      child: Text(
        count >= 100 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEventMarker(EventNode node, {required _MarkerVisualMode mode}) {
    final selected = _selectedMarkerEventId == node.id;
    final emoji = _markerEmojiFor(node);
    final baseSize = mode == _MarkerVisualMode.farCluster
        ? 18.0
        : mode == _MarkerVisualMode.mediumEmojiOnly
            ? 44.0
            : 52.0;

    final markerSquare = Container(
      width: baseSize,
      height: baseSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _isDarkTheme ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(
            mode == _MarkerVisualMode.farCluster ? 6 : 14),
        border: Border.all(
          color: _isDarkTheme
              ? Colors.white.withAlpha(22)
              : Colors.black.withAlpha(14),
          width: 1,
        ),
        boxShadow: mode == _MarkerVisualMode.farCluster
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(_isDarkTheme ? 95 : 55),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: _isAvatarAssetPath(emoji)
          ? Padding(
              padding: EdgeInsets.all(mode == _MarkerVisualMode.farCluster ? 2 : 8),
              child: Image.asset(
                emoji,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.event_rounded,
                  color: Colors.white,
                  size: mode == _MarkerVisualMode.farCluster ? 10 : 20,
                ),
              ),
            )
          : Text(
              emoji,
              style: TextStyle(
                fontSize: mode == _MarkerVisualMode.farCluster
                    ? 11
                    : mode == _MarkerVisualMode.mediumEmojiOnly
                        ? 24
                        : 28,
                height: 1.0,
              ),
            ),
    );

    if (mode != _MarkerVisualMode.closeWithPill) return markerSquare;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        markerSquare,
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? YanegiColors.primary
                : (_isDarkTheme
                    ? const Color(0xFF1C1C28)
                    : Colors.black.withAlpha(50)),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? YanegiColors.primary
                  : (_isDarkTheme
                      ? Colors.white.withAlpha(28)
                      : Colors.black.withAlpha(20)),
            ),
          ),
          child: Text(
            _pillTextForAttendees(node.currentAttendees),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}
