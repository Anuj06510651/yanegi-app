// ignore_for_file: invalid_use_of_protected_member

part of '../../../screens/map_screen.dart';

extension _MapLocationController on _MapScreenState {
  bool _isFallbackLocation(LatLng location) {
    return (location.latitude - _MapScreenState._nycCenter.latitude).abs() < 0.00001 &&
        (location.longitude - _MapScreenState._nycCenter.longitude).abs() < 0.00001;
  }

  bool _isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  bool _sameLatLng(LatLng? a, LatLng? b) {
    if (a == null || b == null) return a == b;
    return (a.latitude - b.latitude).abs() < 0.000001 &&
        (a.longitude - b.longitude).abs() < 0.000001;
  }

  LatLng? _safeLatLng(double? lat, double? lng) {
    if (!_isValidCoordinate(lat, lng)) return null;
    return LatLng(lat!, lng!);
  }

  Future<void> _showLocationIssueSheet({
    required String title,
    required String subtitle,
    required bool openLocationSettings,
  }) async {
    if (!mounted || _isLocationIssueSheetOpen) return;
    _isLocationIssueSheetOpen = true;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      backgroundColor: _isDarkTheme ? const Color(0xFF141926) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _isDarkTheme ? Colors.white : Colors.black87,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _isDarkTheme
                        ? Colors.white.withAlpha(190)
                        : Colors.black54,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      if (openLocationSettings) {
                        await Geolocator.openLocationSettings();
                      } else {
                        await Geolocator.openAppSettings();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YanegiColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      openLocationSettings
                          ? 'Open Location Settings'
                          : 'Open App Settings',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Continue with default location'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    _isLocationIssueSheetOpen = false;
  }

  Future<LatLng?> _ensureUserLocation({
    bool moveMap = false,
    bool showErrors = true,
    bool forceRefresh = false,
  }) async {
    const defaultLocation = _MapScreenState._nycCenter;
    bool deniedForAccuracy = false;
    bool serviceDisabled = false;

    final shouldResolve = forceRefresh ||
        _currentUserLocation == null ||
        (_currentUserLocation != null &&
            _isFallbackLocation(_currentUserLocation!));

    if (shouldResolve) {
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          serviceDisabled = true;
          throw Exception('Location services are disabled.');
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          deniedForAccuracy = true;
          throw Exception('Location permission denied.');
        }

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 8),
        );
        final userLat = position.latitude;
        final userLng = position.longitude;
        print('User location: $userLat, $userLng');

        final nextLocation = LatLng(userLat, userLng);
        if (!_sameLatLng(_currentUserLocation, nextLocation)) {
          _setStateFromMap(() {
            _currentUserLocation = nextLocation;
          });
        }

        if (moveMap && _currentUserLocation != null) {
          _animateToLocation(_currentUserLocation!, zoom: 14);
        }
      } catch (e) {
        print('TESTING [ERROR]: Failed to get location on map: $e');
        if (showErrors && mounted) {
          if (serviceDisabled) {
            await _showLocationIssueSheet(
              title: 'Turn on location service',
              subtitle:
                  'Location service is off. We are showing a default area until you enable it.',
              openLocationSettings: true,
            );
          } else if (deniedForAccuracy) {
            await _showLocationIssueSheet(
              title: 'Allow location permission',
              subtitle:
                  'Location permission helps show nearby events correctly. You can continue with the default area.',
              openLocationSettings: false,
            );
          } else {
            ErrorHandler.showUserMessage(
              context,
              AppErrorType.locationLookupFailed,
              error: e,
              where: 'map_screen._ensureUserLocation',
            );
          }
        }
        if (!_sameLatLng(_currentUserLocation, defaultLocation)) {
          _setStateFromMap(() {
            _currentUserLocation = defaultLocation; // Fallback
          });
        }
        if (moveMap) {
          _animateToLocation(defaultLocation, zoom: 14);
        }
      }
    } else if (moveMap) {
      _animateToLocation(_currentUserLocation!, zoom: 14);
    }

    return _currentUserLocation ?? defaultLocation;
  }

  void _animateToLocation(LatLng target, {double zoom = 14}) {
    if (!_mapReady) return;

    final start = _lastKnownMapCenter ?? _currentUserLocation ?? _MapScreenState._nycCenter;
    const totalSteps = 14;
    const stepMs = 16;

    _cameraAnimationTimer?.cancel();
    var step = 0;

    _cameraAnimationTimer =
        Timer.periodic(const Duration(milliseconds: stepMs), (
      timer,
    ) {
      step += 1;
      final t = Curves.easeOutCubic.transform(step / totalSteps);
      final lat = start.latitude + (target.latitude - start.latitude) * t;
      final lng = start.longitude + (target.longitude - start.longitude) * t;
      final next = LatLng(lat, lng);

      _mapController.move(next, zoom);
      _lastKnownMapCenter = next;
      _zoomLevel = zoom;

      if (step >= totalSteps) {
        _setStateFromMap(() {
          _zoomLevel = zoom;
        });
        timer.cancel();
      }
    });
  }

  Future<void> _initLocation() async {
    await _ensureUserLocation(
      moveMap: false,
      showErrors: true,
      forceRefresh: true,
    );
    if (!mounted) return;
    if (_isLoadingLocation) {
      _setStateFromMap(() => _isLoadingLocation = false);
    }
    // If the map rendered before location resolved, animate to actual position now.
    if (_mapReady && !_didAnimateToInitialUserLocation && _currentUserLocation != null) {
      _didAnimateToInitialUserLocation = true;
      _animateToLocation(_currentUserLocation!, zoom: 14);
    }
  }

  double _distanceKm(LatLng a, LatLng b) {
    const distance = Distance();
    return distance.as(LengthUnit.Kilometer, a, b);
  }
}
