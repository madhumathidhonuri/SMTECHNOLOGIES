import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/json_utils.dart';
import '../config/app_config.dart';
import 'polyline_simplifier.dart';

class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationText,
    required this.summary,
    required this.source,
  });

  final List<LatLng> points;
  final double distanceKm;
  final String durationText;
  final String summary;
  final String source; // 'Google Directions' or 'OSRM'
}

class RoutingService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static const String _defaultApiKey = 'AIzaSyBUfwgEy51elZbDcxVXIPJ4x8-7_oMUZDk';

  /// Fetches an optimal driving route snapped to actual roads between [origin] and [destination],
  /// with optional intermediate [waypoints].
  ///
  /// Tries Google Directions API first; falls back seamlessly to OSRM if quota/network fails.
  static Future<RouteResult?> getDirections({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints = const <LatLng>[],
    String? customApiKey,
  }) async {
    // 1. Try Google Directions API
    try {
      final RouteResult? googleRoute = await _fetchGoogleDirections(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
        apiKey: (customApiKey != null && customApiKey.isNotEmpty)
            ? customApiKey
            : (AppConfig.googleMapsApiKey.isNotEmpty
                ? AppConfig.googleMapsApiKey
                : _defaultApiKey),
      );
      if (googleRoute != null && googleRoute.points.isNotEmpty) {
        return googleRoute;
      }
    } catch (e) {
      dev.log('Google Directions failed: $e, falling back to OSRM');
    }

    // 2. Fallback to Open Source Routing Machine (OSRM)
    try {
      final RouteResult? osrmRoute = await _fetchOsrmRoute(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
      );
      if (osrmRoute != null && osrmRoute.points.isNotEmpty) {
        return osrmRoute;
      }
    } catch (e) {
      dev.log('OSRM routing failed: $e');
    }

    return null;
  }

  static Future<RouteResult?> _fetchGoogleDirections({
    required LatLng origin,
    required LatLng destination,
    required List<LatLng> waypoints,
    required String apiKey,
  }) async {
    final StringBuffer url = StringBuffer(
      'https://maps.googleapis.com/maps/api/directions/json?'
      'origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=driving'
      '&key=$apiKey',
    );

    if (waypoints.isNotEmpty) {
      final String wpParam = waypoints
          .map((LatLng w) => '${w.latitude},${w.longitude}')
          .join('|');
      url.write('&waypoints=$wpParam');
    }

    final Response<dynamic> res = await _dio.get(url.toString());
    if (res.statusCode != 200 || res.data is! Map<String, dynamic>) return null;

    final Map<String, dynamic> data = res.data as Map<String, dynamic>;
    if (data['status'] != 'OK' || data['routes'] == null) return null;

    final List<dynamic> routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) return null;

    final Map<String, dynamic> firstRoute = routes.first as Map<String, dynamic>;
    final String? encodedPoints =
        firstRoute['overview_polyline']?['points']?.toString();
    if (encodedPoints == null || encodedPoints.isEmpty) return null;

    List<LatLng> points = decodePolyline(encodedPoints);
    if (points.isEmpty) return null;

    // Simplify if dense (>500 points) to optimize memory and DB storage while preserving curves
    if (points.length > 500) {
      points = _simplify(points, epsilonMeters: 6.0);
    }

    double totalDistanceKm = 0;
    String durationText = '';
    final List<dynamic>? legs = firstRoute['legs'] as List<dynamic>?;
    if (legs != null && legs.isNotEmpty) {
      for (final dynamic leg in legs) {
        if (leg is Map<String, dynamic>) {
          final double? distMeters = toDouble(leg['distance']?['value']);
          if (distMeters != null) totalDistanceKm += distMeters / 1000.0;
          final String? dur = leg['duration']?['text']?.toString();
          if (dur != null && dur.isNotEmpty) durationText = dur;
        }
      }
    }

    final String summary = firstRoute['summary']?.toString() ?? 'Main Route';

    return RouteResult(
      points: points,
      distanceKm: totalDistanceKm,
      durationText: durationText,
      summary: summary,
      source: 'Google Directions',
    );
  }

  static Future<RouteResult?> _fetchOsrmRoute({
    required LatLng origin,
    required LatLng destination,
    required List<LatLng> waypoints,
  }) async {
    final List<LatLng> allStops = <LatLng>[origin, ...waypoints, destination];
    final String coordString = allStops
        .map((LatLng pt) => '${pt.longitude},${pt.latitude}')
        .join(';');

    final String url =
        'https://router.project-osrm.org/route/v1/driving/$coordString?overview=full&geometries=geojson';

    final Response<dynamic> res = await _dio.get(url);
    if (res.statusCode != 200 || res.data is! Map<String, dynamic>) return null;

    final Map<String, dynamic> data = res.data as Map<String, dynamic>;
    if (data['code'] != 'Ok' || data['routes'] == null) return null;

    final List<dynamic> routes = data['routes'] as List<dynamic>;
    if (routes.isEmpty) return null;

    final Map<String, dynamic> route = routes.first as Map<String, dynamic>;
    final dynamic geometry = route['geometry'];
    List<LatLng> points = <LatLng>[];

    if (geometry is Map<String, dynamic> && geometry['coordinates'] is List) {
      final List<dynamic> rawCoords = geometry['coordinates'] as List<dynamic>;
      for (final dynamic coord in rawCoords) {
        if (coord is List && coord.length >= 2) {
          final double? lon = toDouble(coord[0]);
          final double? lat = toDouble(coord[1]);
          if (lat != null && lon != null && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
            points.add(LatLng(lat, lon));
          }
        }
      }
    } else if (geometry is String && geometry.isNotEmpty) {
      points = decodePolyline(geometry);
    }

    if (points.isEmpty) return null;

    if (points.length > 500) {
      points = _simplify(points, epsilonMeters: 8.0);
    }

    final double distMeters = toDouble(route['distance']) ?? 0;
    final int durSeconds = toInt(route['duration']) ?? 0;

    final double distanceKm = distMeters / 1000.0;
    final int hours = durSeconds ~/ 3600;
    final int mins = (durSeconds % 3600) ~/ 60;
    final String durationText = hours > 0 ? '$hours h $mins m' : '$mins min';

    return RouteResult(
      points: points,
      distanceKm: distanceKm,
      durationText: durationText,
      summary: 'Road Network',
      source: 'OSRM',
    );
  }

  /// Decodes a Google Encoded Polyline string (precision 1e-5) into a list of [LatLng].
  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> poly = <LatLng>[];
    int index = 0;
    final int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        if (index >= len) break;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        if (index >= len) break;
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      final double latitude = lat / 1e5;
      final double longitude = lng / 1e5;
      if (latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180) {
        poly.add(LatLng(latitude, longitude));
      }
    }
    return poly;
  }

  static List<LatLng> _simplify(List<LatLng> pts, {double epsilonMeters = 8.0}) {
    if (pts.length <= 2) return pts;
    final List<List<double>> raw =
        pts.map((LatLng p) => <double>[p.latitude, p.longitude]).toList();
    final List<List<double>> simplified =
        PolylineSimplifier.simplify(raw, epsilonMeters);
    return simplified.map((List<double> p) => LatLng(p[0], p[1])).toList();
  }
}
