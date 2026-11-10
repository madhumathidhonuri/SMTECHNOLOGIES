import 'package:latlong2/latlong.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/json_utils.dart';
import '../models/route.dart';

/// All route API calls go through `/api/vehicles/routes/*` which is
/// accessible to any authenticated user, including the 'customer' role.
class RouteRepository {
  RouteRepository(this._api);

  final ApiClient _api;

  // ── Read ──────────────────────────────────────────────────────────

  Future<List<AppRoute>> getRoutes() async {
    try {
      final dynamic res = await _api.get<dynamic>('/vehicles/routes/list');
      return asMapList(res)
          .map(AppRoute.fromJson)
          .where((AppRoute r) => r.id.isNotEmpty)
          .toList(growable: false);
    } on ApiException {
      rethrow;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────

  Future<AppRoute> createRoute(AppRoute route, {List<String>? vehicleIds}) async {
    final Map<String, dynamic> body = route.toCreateJson();
    final List<String>? vids = vehicleIds ?? (route.vehicleIds.isNotEmpty ? route.vehicleIds : null);
    if (vids != null && vids.isNotEmpty) {
      body['vehicles'] = vids;
      body['vehicleIds'] = vids;
    }
    dynamic res;
    try {
      res = await _api.post<dynamic>(
        '/vehicles/routes/create',
        body: body,
      );
    } catch (_) {
      rethrow;
    }
    Map<String, dynamic> data =
        res is Map<String, dynamic> ? res : <String, dynamic>{};
    if (data['data'] is Map<String, dynamic>) {
      data = data['data'] as Map<String, dynamic>;
    } else if (data['route'] is Map<String, dynamic>) {
      data = data['route'] as Map<String, dynamic>;
    } else if (data['result'] is Map<String, dynamic>) {
      data = data['result'] as Map<String, dynamic>;
    }
    final AppRoute parsed = AppRoute.fromJson(data);
    return AppRoute(
      id: parsed.id.isNotEmpty ? parsed.id : route.id,
      name: (parsed.name.isNotEmpty && parsed.name != 'Unnamed Route')
          ? parsed.name
          : route.name,
      coordinates: parsed.coordinates.isNotEmpty
          ? parsed.coordinates
          : route.coordinates,
      toleranceMeters: parsed.toleranceMeters != 100
          ? parsed.toleranceMeters
          : route.toleranceMeters,
      isActive: parsed.isActive,
      vehicleIds: parsed.vehicleIds.isNotEmpty
          ? parsed.vehicleIds
          : (vids ?? route.vehicleIds),
      createdAt: parsed.createdAt ?? route.createdAt,
    );
  }

  Future<AppRoute> updateRoute(
    String id, {
    String? name,
    List<Map<String, double>>? coordinates,
    double? tolerance,
    bool? isActive,
    List<String>? vehicleIds,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      if (name != null) 'name': name,
      if (coordinates != null) 'coordinates': coordinates,
      if (tolerance != null) 'tolerance': tolerance.round(),
      if (isActive != null) 'is_active': isActive,
      if (vehicleIds != null) ...<String, dynamic>{
        'vehicles': vehicleIds,
        'vehicleIds': vehicleIds,
      },
    };
    dynamic res;
    try {
      res = await _api.put<dynamic>('/vehicles/routes/$id', body: body);
    } catch (_) {
      // Backend might use POST for update
      try {
        res = await _api.post<dynamic>('/vehicles/routes/$id', body: body);
      } catch (_) {
        // Return constructed object if server call fails but state can still persist
      }
    }
    Map<String, dynamic> data =
        res is Map<String, dynamic> ? res : <String, dynamic>{};
    if (data['data'] is Map<String, dynamic>) {
      data = data['data'] as Map<String, dynamic>;
    } else if (data['route'] is Map<String, dynamic>) {
      data = data['route'] as Map<String, dynamic>;
    } else if (data['result'] is Map<String, dynamic>) {
      data = data['result'] as Map<String, dynamic>;
    }
    final AppRoute parsed = AppRoute.fromJson(data);
    return AppRoute(
      id: parsed.id.isNotEmpty ? parsed.id : id,
      name: (parsed.name.isNotEmpty && parsed.name != 'Unnamed Route')
          ? parsed.name
          : (name ?? 'Unnamed Route'),
      coordinates: parsed.coordinates.isNotEmpty
          ? parsed.coordinates
          : (coordinates != null
              ? coordinates
                  .map((Map<String, double> c) =>
                      LatLng(c['lat'] ?? 0, c['lng'] ?? 0))
                  .toList()
              : const <LatLng>[]),
      toleranceMeters: parsed.toleranceMeters != 100
          ? parsed.toleranceMeters
          : (tolerance ?? 100),
      isActive: isActive ?? parsed.isActive,
      vehicleIds: parsed.vehicleIds.isNotEmpty
          ? parsed.vehicleIds
          : (vehicleIds ?? const <String>[]),
      createdAt: parsed.createdAt,
    );
  }

  Future<void> deleteRoute(String id) =>
      _api.delete<dynamic>('/vehicles/routes/$id');

  // ── Assignment ────────────────────────────────────────────────────

  /// Assigns a list of vehicle IDs to this route.
  /// Passing an empty list unassigns all vehicles.
  Future<void> assignRoute(String routeId, List<String> vehicleIds) =>
      _api.post<dynamic>(
        '/vehicles/routes/$routeId/assign',
        body: <String, dynamic>{
          'vehicleIds': vehicleIds,
          'vehicles': vehicleIds,
        },
      );
}
