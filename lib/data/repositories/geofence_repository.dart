import '../../core/config/backend_capabilities.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/geofence.dart';
import '../models/json_utils.dart';

class GeofenceRepository {
  GeofenceRepository(this._api);

  final ApiClient _api;

  Future<List<Geofence>> getGeofences({String? vehicleId}) async {
    if (vehicleId != null && vehicleId.isNotEmpty) {
      try {
        final dynamic res = await _api.get<dynamic>('/vehicles/$vehicleId/geofences');
        final List<Map<String, dynamic>> list = asMapList(res);
        if (list.isNotEmpty) {
          return list
              .map(Geofence.fromJson)
              .where((Geofence g) => g.id.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
    }

    if (!BackendCapabilities.geofences) return const <Geofence>[];

    final dynamic res = await _api.get<dynamic>('/admin/geofences');
    final List<Geofence> all = asMapList(res)
        .map(Geofence.fromJson)
        .where((Geofence g) => g.id.isNotEmpty)
        .toList(growable: false);

    if (vehicleId != null && vehicleId.isNotEmpty) {
      final List<Geofence> filtered = all
          .where((Geofence g) => g.vehicleIds.contains(vehicleId))
          .toList(growable: false);
      return filtered.isNotEmpty ? filtered : all;
    }
    return all;
  }

  Future<Geofence> create(Geofence geofence, {String? vehicleId}) async {
    final String? vId = vehicleId ?? (geofence.vehicleIds.isNotEmpty ? geofence.vehicleIds.first : null);
    if (vId != null && vId.isNotEmpty) {
      try {
        final dynamic res = await _api.post<dynamic>(
          '/vehicles/$vId/geofences',
          body: geofence.toCreateJson(),
        );
        final dynamic data = (res is Map && res['data'] != null) ? res['data'] : res;
        if (data is Map && data.isNotEmpty) {
          return Geofence.fromJson(Map<String, dynamic>.from(data));
        }
      } catch (_) {}
    }

    if (!BackendCapabilities.geofences) {
      throw const ApiException(
        message: 'Geofencing is not enabled on your account yet.',
        statusCode: 404,
      );
    }
    final dynamic res = await _api.post<dynamic>(
      '/admin/geofences',
      body: geofence.toCreateJson(),
    );
    final dynamic data = (res is Map && res['data'] != null) ? res['data'] : res;
    final Geofence created = Geofence.fromJson(
      data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{}),
    );
    if (geofence.vehicleIds.isNotEmpty && created.id.isNotEmpty) {
      try {
        await _api.post<dynamic>(
          '/admin/geofences/${created.id}/assign',
          body: <String, dynamic>{'vehicleIds': geofence.vehicleIds},
        );
      } catch (_) {}
    }
    return created;
  }

  Future<Geofence> update(String id, Map<String, dynamic> changes, {String? vehicleId}) async {
    if (vehicleId != null && vehicleId.isNotEmpty) {
      try {
        final dynamic res = await _api.put<dynamic>('/vehicles/$vehicleId/geofences/$id', body: changes);
        final dynamic data = (res is Map && res['data'] != null) ? res['data'] : res;
        if (data is Map && data.isNotEmpty) {
          return Geofence.fromJson(Map<String, dynamic>.from(data));
        }
      } catch (_) {}
    }
    final dynamic res = await _api.put<dynamic>('/admin/geofences/$id', body: changes);
    final dynamic data = (res is Map && res['data'] != null) ? res['data'] : res;
    return Geofence.fromJson(
      data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{}),
    );
  }

  Future<void> delete(String id, {String? vehicleId}) async {
    if (vehicleId != null && vehicleId.isNotEmpty) {
      try {
        await _api.delete<dynamic>('/vehicles/$vehicleId/geofences/$id');
      } catch (_) {}
    }
    await _api.delete<dynamic>('/admin/geofences/$id');
  }
}
