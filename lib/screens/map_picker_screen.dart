import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../theme/yanegi_theme.dart';
import '../config/map_config.dart';

// ── Nominatim place result ──────────────────────────────────────────────────

class _PlaceResult {
  final String name;
  final String address;
  final double lat;
  final double lng;

  const _PlaceResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });
}

// ── Screen ─────────────────────────────────────────────────────────────────

class MapPickerScreen extends StatefulWidget {
  final LatLng? initialUserLocation;
  final LatLng? initialSelectedLocation;

  const MapPickerScreen({
    super.key,
    this.initialUserLocation,
    this.initialSelectedLocation,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const LatLng _fallbackCenter = LatLng(28.6139, 77.2090);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  LatLng? _userLocation;
  LatLng? _selectedLocation;
  String? _selectedPlaceName;

  bool _isLoadingLocation = true;
  bool _mapReady = false;

  // Search state
  List<_PlaceResult> _searchResults = [];
  bool _isSearching = false;
  bool _showResults = false;
  Timer? _debounce;
  final Map<String, List<_PlaceResult>> _searchCache = {};

  Timer? _cameraAnimationTimer;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialSelectedLocation;
    _searchFocus.addListener(_onSearchFocusChange);
    _initUserLocation();
  }

  @override
  void dispose() {
    _cameraAnimationTimer?.cancel();
    _debounce?.cancel();
    _mapController.dispose();
    _searchController.dispose();
    _searchFocus.removeListener(_onSearchFocusChange);
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchFocusChange() {
    if (!_searchFocus.hasFocus) {
      setState(() => _showResults = false);
    }
  }

  // ── Location init ───────────────────────────────────────────────────────

  Future<void> _initUserLocation() async {
    LatLng resolved = widget.initialUserLocation ?? _fallbackCenter;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permission denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      resolved = LatLng(position.latitude, position.longitude);
    } catch (_) {
      // Use resolved fallback silently
    }

    if (!mounted) return;

    setState(() {
      _userLocation = resolved;
      _isLoadingLocation = false;
    });
  }

  // ── Camera animation ────────────────────────────────────────────────────

  void _animateCameraTo(LatLng target, {double zoom = 15}) {
    if (!_mapReady) return;

    final start = _mapController.camera.center;
    const totalSteps = 16;
    const stepMs = 16;

    _cameraAnimationTimer?.cancel();
    var step = 0;

    _cameraAnimationTimer = Timer.periodic(
      const Duration(milliseconds: stepMs),
      (timer) {
        step += 1;
        final t = Curves.easeOutCubic.transform(step / totalSteps);
        final next = LatLng(
          start.latitude + (target.latitude - start.latitude) * t,
          start.longitude + (target.longitude - start.longitude) * t,
        );
        _mapController.move(next, zoom);
        if (step >= totalSteps) timer.cancel();
      },
    );
  }

  // ── Map tap ─────────────────────────────────────────────────────────────

  void _handleTap(LatLng tapped) {
    _dismissSearch();
    setState(() {
      _selectedLocation = tapped;
      _selectedPlaceName = null;
    });
  }

  // ── Search ──────────────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();

    final trimmed = query.trim();
    if (trimmed.length < 3) {
      setState(() {
        _searchResults = [];
        _showResults = false;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _performSearch(trimmed),
    );
  }

  Future<void> _performSearch(String query) async {
    final key = query.toLowerCase();
    if (_searchCache.containsKey(key)) {
      if (mounted) {
        setState(() {
          _searchResults = _searchCache[key]!;
          _showResults = _searchResults.isNotEmpty;
          _isSearching = false;
        });
      }
      return;
    }

    try {
      final results = await _nominatimSearch(query);
      _searchCache[key] = results;
      if (mounted) {
        setState(() {
          _searchResults = results;
          _showResults = results.isNotEmpty;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('[map_picker] search error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<List<_PlaceResult>> _nominatimSearch(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '6',
      'addressdetails': '0',
    });

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'Yanegi/1.0 (burmananuj13@gmail.com)',
        'Accept-Language': 'en',
      },
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) {
      final full = (item['display_name'] as String?) ?? '';
      final parts = full.split(',');
      final name = parts.first.trim();
      final address =
          parts.skip(1).take(2).map((s) => s.trim()).join(', ');
      return _PlaceResult(
        name: name,
        address: address,
        lat: double.tryParse(item['lat'] as String? ?? '') ?? 0,
        lng: double.tryParse(item['lon'] as String? ?? '') ?? 0,
      );
    }).where((r) => r.lat != 0 && r.lng != 0).toList();
  }

  void _selectPlace(_PlaceResult place) {
    final target = LatLng(place.lat, place.lng);
    _dismissSearch();
    _searchController.text = place.name;

    setState(() {
      _selectedLocation = target;
      _selectedPlaceName = place.name;
    });

    _animateCameraTo(target, zoom: 15);
  }

  void _dismissSearch() {
    _searchFocus.unfocus();
    setState(() {
      _showResults = false;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _showResults = false;
      _isSearching = false;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final scaffoldBg =
        isDark ? const Color(0xFF090D15) : theme.scaffoldBackgroundColor;
    final cardBg = isDark ? const Color(0xFF12121A) : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withAlpha(18)
        : Colors.black.withAlpha(12);
    final textColor = isDark ? Colors.white : scheme.onSurface;
    final hintColor = isDark ? Colors.white54 : Colors.black45;
    final mapTileUrl = MapConfig.rasterTileUrl(
        isDark ? MapConfig.darkPickerStyleId : MapConfig.lightPickerStyleId);

    if (_isLoadingLocation || _userLocation == null) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: const Center(
          child: CircularProgressIndicator(color: YanegiColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: scaffoldBg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Full-screen map ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selectedLocation ?? _userLocation!,
              initialZoom: 14,
              onMapReady: () {
                if (_mapReady) return;
                _mapReady = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final center = _selectedLocation ?? _userLocation!;
                  _animateCameraTo(center, zoom: 14);
                });
              },
              onTap: (_, point) => _handleTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: mapTileUrl,
                userAgentPackageName: MapConfig.userAgentPackageName,
                retinaMode: true,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userLocation!,
                    width: 36,
                    height: 36,
                    child: const _PickerUserMarker(),
                  ),
                ],
              ),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 44,
                      height: 56,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_pin,
                        size: 44,
                        color: YanegiColors.primary,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Overlays (safe area) ──
          SafeArea(
            child: Stack(
              children: [
                // ── Search + results ──
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Search bar row
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(isDark ? 60 : 20),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Back button
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    left: 10, right: 4),
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  color: textColor,
                                  size: 22,
                                ),
                              ),
                            ),
                            // Search field
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocus,
                                onChanged: _onSearchChanged,
                                style: TextStyle(
                                    color: textColor, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: 'Search for a place or landmark',
                                  hintStyle: TextStyle(
                                      color: hintColor, fontSize: 14),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                ),
                                textInputAction: TextInputAction.search,
                                onSubmitted: (v) {
                                  if (v.trim().isNotEmpty) {
                                    _debounce?.cancel();
                                    _performSearch(v.trim());
                                  }
                                },
                              ),
                            ),
                            // Trailing: spinner or clear
                            if (_isSearching)
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: hintColor,
                                  ),
                                ),
                              )
                            else if (_searchController.text.isNotEmpty)
                              GestureDetector(
                                onTap: _clearSearch,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Icon(Icons.close_rounded,
                                      color: hintColor, size: 18),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child:
                                    Icon(Icons.search, color: hintColor, size: 20),
                              ),
                          ],
                        ),
                      ),
                      // Results dropdown
                      if (_showResults && _searchResults.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          constraints:
                              const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorder),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withAlpha(isDark ? 80 : 24),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _searchResults.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: cardBorder,
                                indent: 16,
                                endIndent: 16,
                              ),
                              itemBuilder: (_, i) {
                                final r = _searchResults[i];
                                return InkWell(
                                  onTap: () => _selectPlace(r),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        Icon(Icons.place_outlined,
                                            size: 18,
                                            color: const Color(
                                                0xFF3B82F6)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r.name,
                                                style: TextStyle(
                                                  color: textColor,
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                              if (r.address.isNotEmpty)
                                                Text(
                                                  r.address,
                                                  style: TextStyle(
                                                    color: hintColor,
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── My location button ──
                Positioned(
                  bottom: 108,
                  right: 12,
                  child: GestureDetector(
                    onTap: () {
                      _dismissSearch();
                      if (_userLocation != null) {
                        _animateCameraTo(_userLocation!, zoom: 15);
                      }
                    },
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: cardBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withAlpha(isDark ? 60 : 20),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.my_location_rounded,
                        color: textColor,
                        size: 20,
                      ),
                    ),
                  ),
                ),

                // ── Bottom panel ──
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomPanel(
                    cardBg: cardBg,
                    cardBorder: cardBorder,
                    textColor: textColor,
                    hintColor: hintColor,
                    isDark: isDark,
                    scheme: scheme,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel({
    required Color cardBg,
    required Color cardBorder,
    required Color textColor,
    required Color hintColor,
    required bool isDark,
    required ColorScheme scheme,
  }) {
    final hasLocation = _selectedLocation != null;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        border: Border(
          top: BorderSide(color: cardBorder),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 16),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location preview
          if (hasLocation) ...[
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16,
                    color: const Color(0xFF3B82F6)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _selectedPlaceName ?? 'Selected location',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                '${_selectedLocation!.latitude.toStringAsFixed(5)}, '
                '${_selectedLocation!.longitude.toStringAsFixed(5)}',
                style: TextStyle(
                  color: hintColor,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Text(
              'Tap the map to set a location',
              style: TextStyle(color: hintColor, fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],
          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: hasLocation
                  ? () {
                      Navigator.pop<Map<String, dynamic>>(context, {
                        'lat': _selectedLocation!.latitude,
                        'lng': _selectedLocation!.longitude,
                        'name': _selectedPlaceName ?? '',
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    scheme.primary.withAlpha(80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: const Text(
                'Confirm Location',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── User location marker ───────────────────────────────────────────────────

class _PickerUserMarker extends StatelessWidget {
  const _PickerUserMarker();

  @override
  Widget build(BuildContext context) {
    const markerBlue = Color(0xFF3B82F6);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: markerBlue.withAlpha(38),
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: markerBlue,
            border: Border.all(color: Colors.white, width: 2.6),
            boxShadow: [
              BoxShadow(
                color: markerBlue.withAlpha(100),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
