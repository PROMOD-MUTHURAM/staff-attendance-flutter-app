
class AttendanceLocation {
  final String id;
  final String name;
  final String branch;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool active;

  AttendanceLocation({
    required this.id,
    required this.name,
    required this.branch,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.active,
  });

  factory AttendanceLocation.fromMap(
      String id,
      Map<String, dynamic> data,
      ) {
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final radius = data['radiusMeters'];

    if (latitude is! num ||
        longitude is! num ||
        radius is! num) {
      throw Exception('Invalid GPS fields in location $id.');
    }

    return AttendanceLocation(
      id: id,
      name: data['name']?.toString() ?? '',
      branch: data['branch']?.toString() ?? '',
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      radiusMeters: radius.toDouble(),
      active: data['active'] == true,
    );
  }
}
