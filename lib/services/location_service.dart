import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  static const Duration _maxCachedLocationAge = Duration(minutes: 2);
  static const double _maxCachedLocationAccuracyMeters = 150;

  bool _isUsableCachedPosition(Position position) {
    final age = DateTime.now().difference(position.timestamp);
    return age <= _maxCachedLocationAge &&
        position.accuracy <= _maxCachedLocationAccuracyMeters;
  }

  Future<Position> _getFreshPosition({required bool isWeb}) async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy:
            isWeb ? LocationAccuracy.high : LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 12),
      );
    } catch (_) {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );
    }
  }

  Future<Position> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    Position? position;

    if (kIsWeb) {
      // `getLastKnownPosition` is not supported on web.
      position = await _getFreshPosition(isWeb: true);
    } else {
      final cachedPosition = await Geolocator.getLastKnownPosition();
      if (cachedPosition != null && _isUsableCachedPosition(cachedPosition)) {
        position = cachedPosition;
      }
      position ??= await _getFreshPosition(isWeb: false);
    }
    await _saveLocationToFirestore(position);
    return position;
  }

  Future<void> _saveLocationToFirestore(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('USER WRITE SKIPPED: LocationService _saveLocationToFirestore — no auth user');
      return;
    }
    final uid = user.uid;
    final payload = <String, dynamic>{
      'location': {
        'lat': position.latitude,
        'lng': position.longitude,
      },
      'locationGeoPoint': GeoPoint(position.latitude, position.longitude),
      'latitude': position.latitude,
      'longitude': position.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    debugPrint('USER WRITE START: LocationService _saveLocationToFirestore → user_locations');
    debugPrint('USER WRITE UID: $uid');
    debugPrint('USER WRITE PAYLOAD: ${payload.keys.toList()}');
    try {
      await FirebaseFirestore.instance
          .collection('user_locations')
          .doc(uid)
          .set(payload, SetOptions(merge: true));
      debugPrint('USER WRITE SUCCESS: LocationService _saveLocationToFirestore');
    } catch (e) {
      debugPrint('USER WRITE FAILED: LocationService _saveLocationToFirestore: $e');
    }
  }
}
