import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart' as xml;
import '../models/poi_marker.dart';

class POIService {
  static const String _overpassUrl =
      'https://overpass-api.de/api/interpreter';

  // Cache POIs for 10 minutes per bbox to avoid repeated API calls
  static final Map<String, CachedPOIs> _poiCache = {};

  static Future<List<POIMarker>> fetchPOIsForBounds({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    final bbox = '$minLat,$minLng,$maxLat,$maxLng';

    // Check cache
    final cached = _poiCache[bbox];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt).inMinutes < 10) {
      return cached.pois;
    }

    try {
      final allPOIs = <POIMarker>[];

      // Fetch each POI type
      allPOIs.addAll(
        await _fetchPOIType('school', bbox, POIType.school),
      );
      allPOIs.addAll(
        await _fetchPOIType('hospital', bbox, POIType.hospital),
      );
      allPOIs.addAll(
        await _fetchPOIType('shop', bbox, POIType.shop),
      );
      allPOIs.addAll(
        await _fetchPOIType('restaurant', bbox, POIType.restaurant),
      );
      allPOIs.addAll(
        await _fetchPOIType('village', bbox, POIType.village),
      );
      allPOIs.addAll(
        await _fetchPOIType('government', bbox, POIType.government),
      );

      // Cache the results
      _poiCache[bbox] = CachedPOIs(
        pois: allPOIs,
        fetchedAt: DateTime.now(),
      );

      return allPOIs;
    } catch (e) {
      // Fail silently — return empty list if API is unreachable
      debugLog('POI fetch failed: $e');
      return [];
    }
  }

  static Future<List<POIMarker>> _fetchPOIType(
    String type,
    String bbox,
    POIType poiType,
  ) async {
    final query = _buildOverpassQuery(type, bbox);

    try {
      final response = await http
          .post(
            Uri.parse(_overpassUrl),
            body: query,
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return [];
      }

      return _parseOSMResponse(response.body, poiType);
    } catch (e) {
      return [];
    }
  }

  static String _buildOverpassQuery(String type, String bbox) {
    switch (type) {
      case 'school':
        return '''
[bbox:${bbox.split(',').join(',')}];
(node["amenity"="school"];way["amenity"="school"];);
out center geom;
''';
      case 'hospital':
        return '''
[bbox:${bbox.split(',').join(',')}];
(node["amenity"="hospital"];way["amenity"="hospital"];);
out center geom;
''';
      case 'shop':
        return '''
[bbox:${bbox.split(',').join(',')}];
(node["shop"];way["shop"];);
out center geom;
''';
      case 'restaurant':
        return '''
[bbox:${bbox.split(',').join(',')}];
(node["amenity"="restaurant"];way["amenity"="restaurant"];);
out center geom;
''';
      case 'village':
        return '''
[bbox:${bbox.split(',').join(',')}];
(node["place"="village"];node["place"="hamlet"];);
out geom;
''';
      case 'government':
        return '''
[bbox:${bbox.split(',').join(',')}];
(node["office"="government"];way["office"="government"];);
out center geom;
''';
      default:
        return '';
    }
  }

  static List<POIMarker> _parseOSMResponse(String responseBody, POIType poiType) {
    final pois = <POIMarker>[];

    try {
      final document = xml.XmlDocument.parse(responseBody);
      final nodes = document.findAllElements('node');

      for (final node in nodes) {
        final id = node.getAttribute('id') ?? '';
        final lat = double.tryParse(node.getAttribute('lat') ?? '');
        final lng = double.tryParse(node.getAttribute('lon') ?? '');

        if (lat == null || lng == null) continue;

        final nameTag = node.findElements('tag').firstWhere(
              (tag) => tag.getAttribute('k') == 'name',
              orElse: () => xml.XmlElement.tag('tag'),
            );

        final typeLabel = _getTypeLabel(poiType);
        final name = nameTag.getAttribute('v') ?? 'Unnamed $typeLabel';

        pois.add(
          POIMarker(
            id: id,
            name: name,
            latLng: LatLng(lat, lng),
            type: poiType,
          ),
        );
      }
    } catch (e) {
      // Silently fail on parse errors
    }

    return pois;
  }

  static void clearCache() {
    _poiCache.clear();
  }

  static String _getTypeLabel(POIType type) {
    switch (type) {
      case POIType.school:
        return 'School';
      case POIType.hospital:
        return 'Hospital';
      case POIType.shop:
        return 'Shop';
      case POIType.restaurant:
        return 'Restaurant';
      case POIType.village:
        return 'Village';
      case POIType.government:
        return 'Government Office';
    }
  }
}

class CachedPOIs {
  final List<POIMarker> pois;
  final DateTime fetchedAt;

  CachedPOIs({required this.pois, required this.fetchedAt});
}

void debugLog(String message) {
  // Use print for debug logging (filtered at build time if needed)
  // ignore: avoid_print
  print('[POI Service] $message');
}
