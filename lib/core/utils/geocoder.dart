import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import '../../data/models/json_utils.dart';

class _GeocodeTask {
  _GeocodeTask(this.key, this.lat, this.lon, this.completer);
  final String key;
  final double lat;
  final double lon;
  final Completer<String> completer;
}

class Geocoder {
  static final Map<String, String> _cache = <String, String>{};
  static final Map<String, Completer<String>> _inFlight = <String, Completer<String>>{};
  static final Queue<_GeocodeTask> _queue = Queue<_GeocodeTask>();
  static bool _isProcessing = false;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
      validateStatus: (int? status) => true,
    ),
  );

  /// Synchronously returns a cached address for the coordinates or nearby coordinates (~11m).
  static String? getCachedAddress(double lat, double lon) {
    if (lat == 0 && lon == 0) return null;
    final String key = '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';
    if (_cache.containsKey(key)) {
      final String val = _cache[key]!;
      if (val.isNotEmpty && val != 'Location unavailable' && !_isCoordinates(val)) return val;
    }

    // Proximity search within adjacent ~11m grid tiles
    for (final double dLat in const <double>[-0.0001, 0.0001, -0.0002, 0.0002]) {
      for (final double dLon in const <double>[-0.0001, 0.0001, -0.0002, 0.0002]) {
        final String nearbyKey = '${(lat + dLat).toStringAsFixed(4)},${(lon + dLon).toStringAsFixed(4)}';
        if (_cache.containsKey(nearbyKey)) {
          final String val = _cache[nearbyKey]!;
          if (val.isNotEmpty && val != 'Location unavailable' && !_isCoordinates(val)) return val;
        }
      }
    }
    return null;
  }

  static bool _isCoordinates(String s) =>
      RegExp(r'^-?\d+\.\d+,\s*-?\d+\.\d+$').hasMatch(s.trim());

  /// Reverse geocodes coordinates to a human-readable address.
  /// On Flutter Web, routes via our own backend proxy to avoid CORS issues
  /// with ArcGIS. On mobile/desktop, calls ArcGIS directly.
  static Future<String> getAddress(double lat, double lon) {
    if (lat == 0 && lon == 0) return Future<String>.value('Location unavailable');

    // 4 decimal places is ~11m resolution (street/shop level accuracy)
    final String key = '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';

    // 1. Return from cache immediately if available
    if (_cache.containsKey(key)) {
      return Future<String>.value(_cache[key]!);
    }

    // 2. Return existing in-flight future if another row already requested the same spot
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!.future;
    }

    // Cap pending queue to avoid memory/network buildup when offline or panning rapidly
    while (_queue.length >= 25) {
      final _GeocodeTask stale = _queue.removeFirst();
      _inFlight.remove(stale.key);
      if (!stale.completer.isCompleted) {
        stale.completer.complete(
            '${stale.lat.toStringAsFixed(4)}, ${stale.lon.toStringAsFixed(4)}');
      }
    }

    final Completer<String> completer = Completer<String>();
    _inFlight[key] = completer;
    _queue.add(_GeocodeTask(key, lat, lon, completer));

    _processQueue();

    return completer.future;
  }

  static void _processQueue() {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    Future<void>.microtask(() async {
      while (_queue.isNotEmpty) {
        final _GeocodeTask task = _queue.removeFirst();

        // Double check cache
        if (_cache.containsKey(task.key)) {
          if (!task.completer.isCompleted) {
            task.completer.complete(_cache[task.key]);
          }
          _inFlight.remove(task.key);
          continue;
        }

        // Fallback: show coordinates if geocoding fails
        String result = '${task.lat.toStringAsFixed(4)}, ${task.lon.toStringAsFixed(4)}';

        try {
          String? label;

          // Fetch directly from Google Maps Geocoding API since we have the key.
          // This gives incredibly detailed addresses without needing to restart the backend!
          const String apiKey = 'AIzaSyBUfwgEy51elZbDcxVXIPJ4x8-7_oMUZDk';
          final String url =
              'https://maps.googleapis.com/maps/api/geocode/json?latlng=${task.lat},${task.lon}&key=$apiKey';

          final Response<dynamic> res = await _dio.get(url);
          if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
            final Map<String, dynamic> data = res.data as Map<String, dynamic>;
            if (data['status'] == 'OK' && data['results'] != null) {
              final List<dynamic> results = data['results'] as List<dynamic>;
              if (results.isNotEmpty) {
                // 1. Look for specific landmark / POI / natural feature / neighborhood
                String? landmark;
                for (final dynamic item in results) {
                  if (item is! Map<String, dynamic>) continue;
                  final List<dynamic>? types = item['types'] as List<dynamic>?;
                  if (types == null) continue;

                  final bool isSpecific = types.any((t) => const <String>[
                    'natural_feature',
                    'point_of_interest',
                    'establishment',
                    'neighborhood',
                    'sublocality_level_2',
                    'transit_station',
                    'bus_station',
                    'park',
                    'place_of_worship',
                    'tourist_attraction',
                  ].contains(t.toString()));

                  if (isSpecific) {
                    final dynamic comps = item['address_components'];
                    String? candidate;
                    if (comps is List && comps.isNotEmpty && comps.first is Map) {
                      candidate = comps.first['long_name']?.toString();
                    } else {
                      final String? full = item['formatted_address']?.toString();
                      candidate = full?.split(',').first.trim();
                    }

                    if (candidate != null &&
                        candidate.isNotEmpty &&
                        !candidate.toLowerCase().contains('unnamed') &&
                        !RegExp(r'^[A-Z0-9]{4,8}\+').hasMatch(candidate) &&
                        !RegExp(r'^\d+$').hasMatch(candidate)) {
                      landmark = candidate;
                      break;
                    }
                  }
                }

                // 2. Find the primary road/street/route address
                final dynamic routeResult = results.firstWhere(
                  (dynamic r) {
                    final List<dynamic>? types =
                        (r as Map<String, dynamic>)['types'] as List<dynamic>?;
                    return types != null && types.contains('route');
                  },
                  orElse: () => null,
                );

                final dynamic premiseResult = results.firstWhere(
                  (dynamic r) {
                    final List<dynamic>? types =
                        (r as Map<String, dynamic>)['types'] as List<dynamic>?;
                    return types != null &&
                        (types.contains('street_address') ||
                            types.contains('premise'));
                  },
                  orElse: () => null,
                );

                final dynamic bestResult = routeResult ??
                    premiseResult ??
                    results.firstWhere(
                      (dynamic r) {
                        final List<dynamic>? types =
                            (r as Map<String, dynamic>)['types']
                                as List<dynamic>?;
                        return types != null && !types.contains('plus_code');
                      },
                      orElse: () => results.first,
                    );
                
                label = (bestResult as Map<String, dynamic>)['formatted_address']?.toString();
                
                // Extra safety: strip plus code string if it somehow still leads the address
                if (label != null) {
                  label = label.replaceAll(RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}[,\s]*'), '');
                  
                  // Remove "Unnamed Road" to keep the address clean and beautiful
                  label = label.replaceAll(RegExp(r'Unnamed Road,\s*'), '');
                  label = label.replaceAll('Unnamed Road', '').trim();
                  
                  // Clean up any dangling commas that might have been left at the start
                  if (label.startsWith(', ')) {
                    label = label.substring(2).trim();
                  }

                  // 3. Prepend landmark / area name if discovered and not already included
                  if (landmark != null &&
                      landmark.isNotEmpty &&
                      !label.toLowerCase().contains(landmark.toLowerCase())) {
                    label = '$landmark, $label';
                  }

                  // 4. Extract district (administrative_area_level_3 or level_2) and inject if missing
                  String? district;
                  for (final dynamic item in results) {
                    if (item is! Map<String, dynamic>) continue;
                    final dynamic comps = item['address_components'];
                    if (comps is List) {
                      for (final dynamic c in comps) {
                        if (c is Map<String, dynamic>) {
                          final List<dynamic>? types =
                              c['types'] as List<dynamic>?;
                          if (types != null &&
                              (types.contains('administrative_area_level_3') ||
                                  types.contains('administrative_area_level_2'))) {
                            final String? name = c['long_name']?.toString();
                            if (name != null && name.isNotEmpty) {
                              district = name;
                              break;
                            }
                          }
                        }
                      }
                    }
                    if (district != null) break;
                  }

                  if (district != null &&
                      district.isNotEmpty &&
                      !label.toLowerCase().contains(district.toLowerCase())) {
                    final List<String> parts =
                        label.split(',').map((s) => s.trim()).toList();
                    final int stateIdx = parts.indexWhere((p) {
                      final l = p.toLowerCase();
                      return l.contains('telangana') ||
                          l.contains('andhra') ||
                          l.contains('karnataka') ||
                          l.contains('tamil nadu') ||
                          l.contains('maharashtra') ||
                          l.contains('odisha');
                    });
                    if (stateIdx > 0) {
                      parts.insert(stateIdx, '$district Dist');
                      label = parts.join(', ');
                    } else {
                      label = '$label, $district Dist';
                    }
                  }

                  if (label.isEmpty) {
                    label = null; // Let it fallback to coordinates if it's completely empty
                  }
                }
              }
            }
          }

          // 2. Fallback to ArcGIS World Reverse Geocode if Google failed or returned empty
          if (label == null || label.isEmpty) {
            try {
              final String arcGisUrl =
                  'https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/reverseGeocode?f=json&location=${task.lon},${task.lat}';
              final Response<dynamic> arcRes = await _dio.get(arcGisUrl);
              if (arcRes.statusCode == 200 && arcRes.data is Map<String, dynamic>) {
                final Map<String, dynamic> arcData = arcRes.data as Map<String, dynamic>;
                final dynamic addrObj = arcData['address'];
                if (addrObj is Map<String, dynamic>) {
                  label = addrObj['Match_addr']?.toString() ??
                          addrObj['LongLabel']?.toString();
                }
              }
            } catch (_) {}
          }

          // 3. Fallback to OpenStreetMap Nominatim if ArcGIS also failed
          if (label == null || label.isEmpty) {
            try {
              final String osmUrl =
                  'https://nominatim.openstreetmap.org/reverse?format=json&lat=${task.lat}&lon=${task.lon}';
              final Response<dynamic> osmRes = await _dio.get(
                osmUrl,
                options: Options(headers: {'User-Agent': 'SMTechnologiesApp/1.0'}),
              );
              if (osmRes.statusCode == 200 && osmRes.data is Map<String, dynamic>) {
                final Map<String, dynamic> osmData = osmRes.data as Map<String, dynamic>;
                label = osmData['display_name']?.toString();
              }
            } catch (_) {}
          }

          if (label != null && label.isNotEmpty) {
            result = formatToNearestAddress(label);
          }
        } catch (_) {
          // Graceful fallback on network/timeout error — result stays as coordinates
        }

        if (result != '${task.lat.toStringAsFixed(4)}, ${task.lon.toStringAsFixed(4)}') {
          _cache[task.key] = result;
        }
        
        _inFlight.remove(task.key);
        if (!task.completer.isCompleted) {
          task.completer.complete(result);
        }

        // Pacing delay to avoid rate-limits
        if (_queue.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      _isProcessing = false;
    });
  }

  /// Formats any raw or geocoded address into a clean, complete human-readable address.
  /// Preserves street/road, landmarks, locality, district, state, country, and postal code.
  /// Safely strips Plus Codes (e.g. 47XR+PJQ) and "Unnamed Road".
  static String formatToNearestAddress(String raw, {int maxWords = 50}) {
    if (raw.isEmpty) return 'Location unavailable';
    if (raw == 'Location unavailable' || raw == '...') return raw;
    if (RegExp(r'^-?\d+\.\d+,\s*-?\d+\.\d+$').hasMatch(raw.trim())) {
      return raw.trim();
    }

    // 1. Clean out plus codes, unnamed road, and special prefixes
    String cleaned = raw
        .replaceAll(RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}[,\s]*'), '')
        .replaceAll(RegExp(r'\b[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\b[,\s]*'), '')
        .replaceAll(RegExp(r'Unnamed Road,\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'Unnamed Road', caseSensitive: false), '')
        .trim();

    // 2. Clean up any double commas and leading/trailing punctuation
    cleaned = cleaned.replaceAll(RegExp(r',\s*,'), ',');
    if (cleaned.startsWith(',')) cleaned = cleaned.substring(1).trim();
    if (cleaned.endsWith(',')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }

    return cleaned.isNotEmpty ? cleaned : raw.trim();
  }

  /// Extracts a clean, concise town or locality name from a formatted address.
  /// E.g. "Moktyala, Krishna, Andhra Pradesh 521175, India" -> "Moktyala".
  static String cleanPlaceName(String raw) {
    if (raw.isEmpty || raw.startsWith('Location')) return 'Place';
    if (RegExp(r'^\d+\.\d+').hasMatch(raw)) return 'Place';
    final List<String> parts = raw.split(',').map((String s) => s.trim()).toList();
    const Set<String> ignored = <String>{
      'india',
      'andhra pradesh',
      'telangana',
      'karnataka',
      'maharashtra',
      'tamil nadu',
      'unnamed road',
    };
    final List<String> candidates = parts.where((String p) {
      if (p.isEmpty) return false;
      if (RegExp(r'^\d+$').hasMatch(p)) return false;
      if (RegExp(r'\b\d{6}\b').hasMatch(p)) return false;
      if (ignored.contains(p.toLowerCase())) return false;
      if (RegExp(r'^(nh|sh)\s*\d+', caseSensitive: false).hasMatch(p)) return false;
      return true;
    }).toList();

    if (candidates.isNotEmpty) {
      return candidates.first;
    }
    return parts.first.isNotEmpty ? parts.first : 'Place';
  }

  /// Geocodes a text query to a list of matching locations.
  static Future<List<GeocodeSearchResult>> searchPlaces(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return <GeocodeSearchResult>[];
    try {
      const String apiKey = 'AIzaSyBUfwgEy51elZbDcxVXIPJ4x8-7_oMUZDk';
      final String url =
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(q)}&key=$apiKey';
      final Response<dynamic> res = await _dio.get(url);
      if (res.statusCode == 200 && res.data is Map<String, dynamic>) {
        final Map<String, dynamic> data = res.data as Map<String, dynamic>;
        if (data['status'] == 'OK' && data['results'] != null) {
          final List<dynamic> results = data['results'] as List<dynamic>;
          return results.map((dynamic r) {
            final Map<String, dynamic> item = r as Map<String, dynamic>;
            final dynamic geom = item['geometry'];
            final dynamic loc = geom is Map ? geom['location'] : null;
            final double lat = toDouble(loc?['lat']) ?? 0.0;
            final double lng = toDouble(loc?['lng']) ?? 0.0;
            final String fullAddress = item['formatted_address']?.toString() ?? '';
            final String name = cleanPlaceName(fullAddress.isNotEmpty ? fullAddress : q);
            return GeocodeSearchResult(
              name: name,
              address: fullAddress,
              lat: lat,
              lon: lng,
            );
          }).toList();
        }
      }
    } catch (_) {}

    // Fallback to ArcGIS World Geocoding
    try {
      final String arcGisUrl =
          'https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates?f=json&SingleLine=${Uri.encodeComponent(q)}&maxLocations=5';
      final Response<dynamic> arcRes = await _dio.get(arcGisUrl);
      if (arcRes.statusCode == 200 && arcRes.data is Map<String, dynamic>) {
        final Map<String, dynamic> data = arcRes.data as Map<String, dynamic>;
        final List<dynamic>? candidates = data['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          return candidates.map((dynamic c) {
            final Map<String, dynamic> item = c as Map<String, dynamic>;
            final dynamic loc = item['location'];
            final double lat = toDouble(loc?['y']) ?? 0.0;
            final double lng = toDouble(loc?['x']) ?? 0.0;
            final String addr = item['address']?.toString() ?? '';
            final String name = cleanPlaceName(addr.isNotEmpty ? addr : q);
            return GeocodeSearchResult(
              name: name,
              address: addr,
              lat: lat,
              lon: lng,
            );
          }).toList();
        }
      }
    } catch (_) {}

    return <GeocodeSearchResult>[];
  }
}

class GeocodeSearchResult {
  const GeocodeSearchResult({
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String address;
  final double lat;
  final double lon;
}
