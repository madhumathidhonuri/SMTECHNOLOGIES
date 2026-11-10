import 'dart:async';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../config/brand_config.dart';

// Conditional import for Flutter Web
import 'location_helper_stub.dart'
    if (dart.library.html) 'location_helper_web.dart' as device_geo;

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.isCoordinate = false,
  });

  final String name;
  final String address;
  final double lat;
  final double lng;
  final bool isCoordinate;

  LatLng get toLatLng => LatLng(lat, lng);
}

class LocationSearchService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
      validateStatus: (status) => true,
    ),
  );

  static const String _googleApiKey =
      'AIzaSyBUfwgEy51elZbDcxVXIPJ4x8-7_oMUZDk';

  /// Searches for places by address, landmark, city, or coordinates.
  static Future<List<PlaceSearchResult>> searchPlaces(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // 1. Check if user typed coordinates like "17.385, 78.486" or Google Maps URL
    final LatLng? parsedCoord = _parseCoordinates(trimmed);
    if (parsedCoord != null) {
      return [
        PlaceSearchResult(
          name: 'Exact Coordinates',
          address:
              '${parsedCoord.latitude.toStringAsFixed(6)}, ${parsedCoord.longitude.toStringAsFixed(6)}',
          lat: parsedCoord.latitude,
          lng: parsedCoord.longitude,
          isCoordinate: true,
        ),
      ];
    }

    if (trimmed.length < 2) return const [];

    final List<PlaceSearchResult> results = <PlaceSearchResult>[];

    // 2. Query Google Geocoding API
    try {
      final String gUrl =
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(trimmed)}&key=$_googleApiKey';
      final Response<dynamic> res = await _dio.get(gUrl);
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final Map<String, dynamic> data = res.data as Map<String, dynamic>;
        if (data['status'] == 'OK' && data['results'] is List) {
          final List<dynamic> list = data['results'] as List<dynamic>;
          for (final dynamic item in list.take(5)) {
            if (item is Map<String, dynamic>) {
              final String formatted =
                  item['formatted_address']?.toString() ?? trimmed;
              final dynamic geom = item['geometry'];
              if (geom is Map && geom['location'] is Map) {
                final double? lat = (geom['location']['lat'] as num?)?.toDouble();
                final double? lng = (geom['location']['lng'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  final String primaryName =
                      formatted.split(',').first.trim();
                  results.add(
                    PlaceSearchResult(
                      name: primaryName.isNotEmpty ? primaryName : formatted,
                      address: formatted,
                      lat: lat,
                      lng: lng,
                    ),
                  );
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    // 3. Fallback to OpenStreetMap Nominatim if Google returned no matches
    if (results.isEmpty) {
      try {
        final String nomUrl =
            'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(trimmed)}&limit=5&countrycodes=in';
        final Response<dynamic> res = await _dio.get(
          nomUrl,
          options: Options(headers: {'User-Agent': '${BrandConfig.appName}-FleetApp/1.0'}),
        );
        if (res.statusCode == 200 && res.data is List) {
          for (final dynamic item in res.data as List<dynamic>) {
            if (item is Map<String, dynamic>) {
              final double? lat = double.tryParse(item['lat']?.toString() ?? '');
              final double? lng = double.tryParse(item['lon']?.toString() ?? '');
              final String display = item['display_name']?.toString() ?? trimmed;
              if (lat != null && lng != null) {
                final String primaryName = display.split(',').first.trim();
                results.add(
                  PlaceSearchResult(
                    name: primaryName.isNotEmpty ? primaryName : display,
                    address: display,
                    lat: lat,
                    lng: lng,
                  ),
                );
              }
            }
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// Obtains the current device / phone location (Web HTML5 or IP fallback).
  static Future<LatLng?> getCurrentUserLocation() async {
    // 1. Try Browser / Device Geolocation on Web
    try {
      final LatLng? webLoc = await device_geo.getBrowserCurrentLocation();
      if (webLoc != null) return webLoc;
    } catch (_) {}

    // 2. Fallback to IP-based Geolocation
    try {
      final Response<dynamic> res = await _dio.get('https://ipapi.co/json/');
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final double? lat = (res.data['latitude'] as num?)?.toDouble();
        final double? lng = (res.data['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    } catch (_) {}

    return null;
  }

  static LatLng? _parseCoordinates(String str) {
    // Check for Google Maps URL coordinates: @lat,lng
    final RegExp gmapsMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)');
    final Match? gm = gmapsMatch.firstMatch(str);
    if (gm != null) {
      final double? lat = double.tryParse(gm.group(1)!);
      final double? lng = double.tryParse(gm.group(2)!);
      if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
        return LatLng(lat, lng);
      }
    }

    // Check for plain "lat, lng" or "lat lng"
    final RegExp plainMatch = RegExp(r'^(-?\d{1,3}(?:\.\d+)?)[,\s]+(-?\d{1,3}(?:\.\d+)?)$');
    final Match? pm = plainMatch.firstMatch(str);
    if (pm != null) {
      final double? lat = double.tryParse(pm.group(1)!);
      final double? lng = double.tryParse(pm.group(2)!);
      if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
        return LatLng(lat, lng);
      }
    }

    return null;
  }
}
