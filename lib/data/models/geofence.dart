import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'json_utils.dart';

enum GeofenceShape { circle, polygon }

class Geofence extends Equatable {
  const Geofence({
    required this.id,
    required this.name,
    required this.shape,
    this.description,
    this.centerLat,
    this.centerLng,
    this.radiusMeters = 200,
    this.points = const <LatLng>[],
    this.colorHex = '#4F6BFF',
    this.alertOnEnter = true,
    this.alertOnExit = true,
    this.isActive = true,
    this.vehicleIds = const <String>[],
    this.createdAt,
  });

  final String id;
  final String name;
  final GeofenceShape shape;
  final String? description;
  final double? centerLat;
  final double? centerLng;
  final double radiusMeters;
  final List<LatLng> points;
  final String colorHex;
  final bool alertOnEnter;
  final bool alertOnExit;
  final bool isActive;
  final List<String> vehicleIds;
  final DateTime? createdAt;

  LatLng? get center {
    if (centerLat != null && centerLng != null) {
      return LatLng(centerLat!, centerLng!);
    }
    if (points.isEmpty) return null;
    final double lat =
        points.map((LatLng p) => p.latitude).reduce((double a, double b) => a + b) /
            points.length;
    final double lng =
        points.map((LatLng p) => p.longitude).reduce((double a, double b) => a + b) /
            points.length;
    return LatLng(lat, lng);
  }

  /// Approximate enclosed area in km² (shoelace on an equirectangular
  /// projection — accurate enough for the sizes geofences realistically take).
  double get areaKm2 {
    if (shape == GeofenceShape.circle) {
      final double r = radiusMeters / 1000;
      return math.pi * r * r;
    }
    if (points.length < 3) return 0;
    const double kmPerDegLat = 110.574;
    final double refLat = center?.latitude ?? 0;
    final double kmPerDegLng = 111.320 * math.cos(refLat * math.pi / 180).abs();

    double sum = 0;
    for (int i = 0; i < points.length; i++) {
      final LatLng a = points[i];
      final LatLng b = points[(i + 1) % points.length];
      sum += (a.longitude * kmPerDegLng) * (b.latitude * kmPerDegLat) -
          (b.longitude * kmPerDegLng) * (a.latitude * kmPerDegLat);
    }
    return (sum / 2).abs();
  }

  factory Geofence.fromJson(Map<String, dynamic> json) {
    final List<LatLng> pts = <LatLng>[];

    dynamic rawPoints = json['points'] ??
        json['coordinates'] ??
        json['polygon'] ??
        json['area'] ??
        (json['geometry'] is Map ? (json['geometry'] as Map)['coordinates'] : null);

    // If coordinates came as a JSON string from Postgres TEXT column, decode it
    if (rawPoints is String && rawPoints.trim().isNotEmpty) {
      try {
        rawPoints = jsonDecode(rawPoints);
      } catch (_) {
        // Leave rawPoints as is if not JSON-encoded
      }
    }

    // GeoJSON polygons nest one level deeper: [[[lng,lat], ...]]
    if (rawPoints is List && rawPoints.isNotEmpty && rawPoints.first is List) {
      final List<dynamic> first = rawPoints.first as List<dynamic>;
      if (first.isNotEmpty && first.first is List) {
        rawPoints = first;
      }
    }

    if (rawPoints is List) {
      for (final dynamic p in rawPoints) {
        if (p is List && p.length >= 2) {
          final double? a = (p[0] as num?)?.toDouble();
          final double? b = (p[1] as num?)?.toDouble();
          if (a == null || b == null) continue;

          // Intelligent lat/lng resolution:
          // Check 1: India bounds (longitude 60..100, latitude 5..40)
          if (a >= 60 && a <= 100 && b >= 5 && b <= 40) {
            pts.add(LatLng(b, a)); // a is lng, b is lat
          } else if (b >= 60 && b <= 100 && a >= 5 && a <= 40) {
            pts.add(LatLng(a, b)); // a is lat, b is lng
          } else if (a.abs() > 90) {
            // Longitude cannot be latitude if |value| > 90
            pts.add(LatLng(b, a));
          } else if (b.abs() > 90) {
            pts.add(LatLng(a, b));
          } else {
            // Default GeoJSON standard order: [longitude, latitude]
            pts.add(LatLng(b, a));
          }
        } else if (p is Map) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(p);
          final double? lat = asDoubleOrNull(m, <String>['lat', 'latitude', 'Lat', 'Latitude']);
          final double? lng = asDoubleOrNull(m, <String>['lng', 'lon', 'longitude', 'Lng', 'Lon', 'Longitude']);
          if (lat != null && lng != null) {
            if (lat >= 60 && lat <= 100 && lng >= 5 && lng <= 40) {
              // Reversed lat/lng in map
              pts.add(LatLng(lng, lat));
            } else {
              pts.add(LatLng(lat, lng));
            }
          }
        }
      }
    }

    final String shapeRaw =
        asString(json, <String>['shape', 'type', 'geofenceType'], fallback: '')
            .toLowerCase();
    final GeofenceShape shape = shapeRaw.contains('poly') || pts.length >= 3
        ? GeofenceShape.polygon
        : GeofenceShape.circle;

    final Map<String, dynamic> centerMap = asMap(json, <String>['center', 'centre']);

    double? cLat = asDoubleOrNull(centerMap, <String>['lat', 'latitude']) ??
        asDoubleOrNull(json, <String>['centerLat', 'latitude', 'lat', 'center_lat']);
    double? cLng = asDoubleOrNull(centerMap, <String>['lng', 'longitude', 'lon']) ??
        asDoubleOrNull(json, <String>['centerLng', 'longitude', 'lng', 'center_lng']);

    // Fallback: If center coordinates are null for polygon, compute centroid
    if ((cLat == null || cLng == null) && pts.isNotEmpty) {
      cLat = pts.map((LatLng p) => p.latitude).reduce((double a, double b) => a + b) / pts.length;
      cLng = pts.map((LatLng p) => p.longitude).reduce((double a, double b) => a + b) / pts.length;
    }

    return Geofence(
      id: asString(json, <String>['_id', 'id', 'geofenceId']),
      name: asString(json, <String>['name', 'title', 'label'], fallback: 'Geofence'),
      shape: shape,
      description: asStringOrNull(json, <String>['description', 'notes', 'remarks']),
      centerLat: cLat,
      centerLng: cLng,
      radiusMeters:
          asDouble(json, <String>['radius', 'radiusMeters', 'radiusInMeters'],
              fallback: 200),
      points: pts,
      colorHex: asString(json, <String>['color', 'colour'], fallback: '#4F6BFF'),
      alertOnEnter: asBool(json, <String>['alertOnEnter', 'onEnter', 'entryAlert'],
          fallback: true),
      alertOnExit: asBool(json, <String>['alertOnExit', 'onExit', 'exitAlert'],
          fallback: true),
      isActive: asBool(json, <String>['isActive', 'active', 'enabled'], fallback: true),
      vehicleIds: (json['vehicles'] is List)
          ? (json['vehicles'] as List<dynamic>)
              .map((dynamic e) => e is Map ? (e['_id'] ?? e['id']).toString() : e.toString())
              .toList()
          : const <String>[],
      createdAt: asDate(json, <String>['createdAt', 'created_at']),
    );
  }

  Map<String, dynamic> toCreateJson() => <String, dynamic>{
        'name': name,
        'description': description,
        'shape': shape.name,
        'type': shape.name,
        if (shape == GeofenceShape.circle) ...<String, dynamic>{
          'centerLat': centerLat,
          'centerLng': centerLng,
          'center_lat': centerLat,
          'center_lng': centerLng,
          'latitude': centerLat,
          'longitude': centerLng,
          'coordinates': <double>[centerLng ?? 0.0, centerLat ?? 0.0],
          'radius': radiusMeters,
        },
        if (shape == GeofenceShape.polygon) ...<String, dynamic>{
          'coordinates': points
              .map((LatLng p) => <String, double>{
                    'lat': p.latitude,
                    'lng': p.longitude,
                  })
              .toList(),
          'points': points
              .map((LatLng p) => <String, double>{
                    'lat': p.latitude,
                    'lng': p.longitude,
                  })
              .toList(),
        },
        'color': colorHex,
        'alertOnEnter': alertOnEnter,
        'alertOnExit': alertOnExit,
        'isActive': isActive,
        if (vehicleIds.isNotEmpty) 'vehicles': vehicleIds,
      };

  Geofence copyWith({
    String? name,
    String? description,
    double? radiusMeters,
    bool? alertOnEnter,
    bool? alertOnExit,
    bool? isActive,
    String? colorHex,
  }) =>
      Geofence(
        id: id,
        name: name ?? this.name,
        shape: shape,
        description: description ?? this.description,
        centerLat: centerLat,
        centerLng: centerLng,
        radiusMeters: radiusMeters ?? this.radiusMeters,
        points: points,
        colorHex: colorHex ?? this.colorHex,
        alertOnEnter: alertOnEnter ?? this.alertOnEnter,
        alertOnExit: alertOnExit ?? this.alertOnExit,
        isActive: isActive ?? this.isActive,
        vehicleIds: vehicleIds,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props =>
      <Object?>[id, name, shape, centerLat, centerLng, radiusMeters, isActive];
}
