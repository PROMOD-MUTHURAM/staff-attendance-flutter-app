import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/attendance_location.dart';

class LocationService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Future<Position> getCurrentLocation() async {
    final serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'GPS is disabled. Please enable location services.',
      );
    }

    var permission =
    await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
      await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception(
        'Location permission was denied.',
      );
    }

    if (permission ==
        LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. '
            'Please enable it from Settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Future<AttendanceLocation> getAttendanceLocation(
      String locationId,
      ) async {
    final document = await _firestore
        .collection('locations')
        .doc(locationId)
        .get();

    if (!document.exists) {
      throw Exception(
        'Attendance location was not found.',
      );
    }

    final data = document.data();

    if (data == null) {
      throw Exception(
        'Invalid attendance location.',
      );
    }

    return AttendanceLocation.fromMap(
      document.id,
      data,
    );
  }

  double calculateDistance({
    required double currentLatitude,
    required double currentLongitude,
    required double targetLatitude,
    required double targetLongitude,
  }) {
    return Geolocator.distanceBetween(
      currentLatitude,
      currentLongitude,
      targetLatitude,
      targetLongitude,
    );
  }
}