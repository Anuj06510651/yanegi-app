import 'package:latlong2/latlong.dart';

enum POIType {
  school,
  hospital,
  shop,
  restaurant,
  village,
  government,
}

class POIMarker {
  final String id;
  final String name;
  final LatLng latLng;
  final POIType type;
  final String? address;
  final String? details;

  POIMarker({
    required this.id,
    required this.name,
    required this.latLng,
    required this.type,
    this.address,
    this.details,
  });

  static POIType typeFromString(String typeStr) {
    switch (typeStr.toLowerCase()) {
      case 'school':
        return POIType.school;
      case 'hospital':
        return POIType.hospital;
      case 'shop':
        return POIType.shop;
      case 'restaurant':
        return POIType.restaurant;
      case 'village':
        return POIType.village;
      case 'government':
        return POIType.government;
      default:
        return POIType.shop;
    }
  }

  String get emoji {
    switch (type) {
      case POIType.school:
        return '🏫';
      case POIType.hospital:
        return '🏥';
      case POIType.shop:
        return '🏪';
      case POIType.restaurant:
        return '🍽️';
      case POIType.village:
        return '🏘️';
      case POIType.government:
        return '🏛️';
    }
  }

  String get label {
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
