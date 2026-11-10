import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'json_utils.dart';

/// A named route with waypoints that a vehicle is expected to follow.
/// Created and managed by the fleet customer via the Routes screen.
class AppRoute extends Equatable {
  const AppRoute({
    required this.id,
    required this.name,
    required this.coordinates,
    this.toleranceMeters = 100,
    this.isActive = true,
    this.vehicleIds = const <String>[],
    this.createdAt,
  });

  final String id;
  final String name;

  /// Ordered waypoints defining the route path.
  final List<LatLng> coordinates;

  /// How far from the route (in metres) before a deviation alert fires.
  final double toleranceMeters;

  final bool isActive;

  /// Vehicle IDs currently assigned to follow this route.
  final List<String> vehicleIds;

  final DateTime? createdAt;

  // ── Derived helpers ─────────────────────────────────────────────

  /// Approximate route length in km using haversine between consecutive points.
  double get approxLengthKm {
    if (coordinates.length < 2) return 0;
    const Distance haversine = Distance();
    double total = 0;
    for (int i = 0; i < coordinates.length - 1; i++) {
      total += haversine(coordinates[i], coordinates[i + 1]);
    }
    return total / 1000;
  }

  // ── Serialisation ────────────────────────────────────────────────

  factory AppRoute.fromJson(Map<String, dynamic> json) {
    final List<LatLng> pts = <LatLng>[];

    // Backend stores coordinates as [{"lat": ..., "lng": ...}, ...]
    // or as [[lat, lng], ...] depending on the insertion path.
    final dynamic rawCoords = json['coordinates'];
    if (rawCoords is List) {
      for (final dynamic item in rawCoords) {
        if (item is Map) {
          final double? lat = asDoubleOrNull(
              Map<String, dynamic>.from(item), <String>['lat', 'latitude']);
          final double? lng = asDoubleOrNull(
              Map<String, dynamic>.from(item), <String>['lng', 'lon', 'longitude']);
          if (lat != null && lng != null) pts.add(LatLng(lat, lng));
        } else if (item is List && item.length >= 2) {
          final double? a = toDouble(item[0]);
          final double? b = toDouble(item[1]);
          if (a != null && b != null) {
            // Heuristic: |value| > 90 must be longitude
            pts.add(a.abs() > 90 ? LatLng(b, a) : LatLng(a, b));
          }
        }
      }
    }

    final List<String> vids = <String>[];
    final dynamic rawVehicles = json['vehicles'] ??
        json['vehicleIds'] ??
        json['vehicle_ids'] ??
        json['assignedVehicles'] ??
        json['assigned_vehicles'];
    if (rawVehicles is List) {
      for (final dynamic v in rawVehicles) {
        final String id = v is Map
            ? (v['id'] ?? v['_id'] ?? v['vehicleId'] ?? '').toString()
            : v.toString();
        if (id.isNotEmpty && !vids.contains(id)) vids.add(id);
      }
    }

    return AppRoute(
      id: asString(json, <String>['id', '_id']),
      name: asString(json, <String>['name', 'title'], fallback: 'Unnamed Route'),
      coordinates: pts,
      toleranceMeters:
          asDouble(json, <String>['tolerance', 'toleranceMeters'], fallback: 100),
      isActive: asBool(json, <String>['is_active', 'isActive'], fallback: true),
      vehicleIds: vids,
      createdAt: asDate(json, <String>['created_at', 'createdAt']),
    );
  }

  /// JSON body sent when creating a new route.
  Map<String, dynamic> toCreateJson() => <String, dynamic>{
        'name': name,
        'coordinates': coordinates
            .map((LatLng p) => <String, double>{
                  'lat': p.latitude,
                  'lng': p.longitude,
                })
            .toList(),
        'tolerance': toleranceMeters.round(),
        if (vehicleIds.isNotEmpty) 'vehicles': vehicleIds,
        if (vehicleIds.isNotEmpty) 'vehicleIds': vehicleIds,
      };

  AppRoute copyWith({
    String? name,
    List<LatLng>? coordinates,
    double? toleranceMeters,
    bool? isActive,
    List<String>? vehicleIds,
  }) =>
      AppRoute(
        id: id,
        name: name ?? this.name,
        coordinates: coordinates ?? this.coordinates,
        toleranceMeters: toleranceMeters ?? this.toleranceMeters,
        isActive: isActive ?? this.isActive,
        vehicleIds: vehicleIds ?? this.vehicleIds,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props =>
      <Object?>[id, name, toleranceMeters, isActive, coordinates.length];
}
