import '../../core/network/api_client.dart';
import '../models/json_utils.dart';
import '../models/user_trip.dart';

class TripRepository {
  TripRepository(this._api);

  final ApiClient _api;

  Future<List<UserTrip>> getTrips({String? vehicleId, String? status}) async {
    final Map<String, dynamic> params = <String, dynamic>{};
    if (vehicleId != null) params['vehicleId'] = vehicleId;
    if (status != null) params['status'] = status;

    final dynamic res = await _api.get<dynamic>('/trips', query: params);
    return asMapList(res).map(UserTrip.fromJson).where((UserTrip t) => t.id.isNotEmpty).toList();
  }

  Future<UserTrip> createTrip(UserTrip trip) async {
    final dynamic res = await _api.post<dynamic>('/trips', body: trip.toCreateJson());
    final Map<String, dynamic> data =
        res is Map<String, dynamic> ? res : <String, dynamic>{};
    return UserTrip.fromJson(data);
  }

  Future<UserTrip> startTrip(String tripId) async {
    final dynamic res = await _api.post<dynamic>('/trips/$tripId/start', body: <String, dynamic>{});
    final Map<String, dynamic> data =
        res is Map<String, dynamic> ? res : <String, dynamic>{};
    return UserTrip.fromJson(data);
  }

  Future<UserTrip> endTrip(String tripId) async {
    final dynamic res = await _api.post<dynamic>('/trips/$tripId/end', body: <String, dynamic>{});
    final Map<String, dynamic> data =
        res is Map<String, dynamic> ? res : <String, dynamic>{};
    return UserTrip.fromJson(data);
  }

  Future<void> cancelTrip(String tripId) async {
    await _api.delete<dynamic>('/trips/$tripId');
  }

  Future<UserTrip?> getActiveTrip(String vehicleId) async {
    final dynamic res = await _api.get<dynamic>('/trips/active/$vehicleId');
    if (res == null) return null;
    if (res is Map<String, dynamic> && res.isEmpty) return null;
    return UserTrip.fromJson(res is Map<String, dynamic> ? res : <String, dynamic>{});
  }
}
