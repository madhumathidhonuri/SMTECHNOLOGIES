import '../../core/config/backend_capabilities.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/notifications/push_service.dart';
import '../../core/storage/secure_store.dart';
import '../models/alert.dart';
import '../models/json_utils.dart';

class AlertRepository {
  AlertRepository(this._api, this._store);

  final ApiClient _api;
  final SecureStore _store;

  Future<List<FleetAlert>> getAlerts({
    int page = 1,
    int limit = 30,
    String? vehicleId,
    String? type,
    DateTime? start,
    DateTime? end,
    List<String>? vehicleIds,
  }) async {
    // `/api/alerts` is not deployed yet (404). Return empty so the screen
    // shows an honest "not enabled" state instead of a red error.
    if (!BackendCapabilities.alertsHistory) return const <FleetAlert>[];

    final Set<String> deletedIds = _store.getDeletedAlertIds();
    final DateTime? lastReadTime = _store.getLastAlertsReadTime();
    final Set<String> readIds = _store.getReadAlertIds();

    // 1. Read notifications stored on-device from push delivery
    final List<Map<String, dynamic>> localRaw = await PushService.getLocalAlerts();
    final List<FleetAlert> localAlerts = localRaw
        .map(FleetAlert.fromJson)
        .where((FleetAlert a) => a.id.isNotEmpty && !deletedIds.contains(a.id))
        .map((FleetAlert a) {
          final bool isLocallyRead = a.isRead ||
              readIds.contains(a.id) ||
              (lastReadTime != null &&
                  a.createdAt != null &&
                  !a.createdAt!.isAfter(lastReadTime));
          return isLocallyRead ? a.copyWith(isRead: true) : a;
        })
        .toList();

    // 2. Fetch server alerts
    List<FleetAlert> apiAlerts = const <FleetAlert>[];
    final String url = vehicleId != null ? '/vehicles/$vehicleId/alerts' : '/alerts';
    try {
      dynamic res;
      try {
        res = await _api.get<dynamic>(
          url,
          query: <String, dynamic>{
            'page': page,
            'limit': limit,
            if (vehicleId != null) 'vehicleId': vehicleId,
            if (type != null) 'alertType': type,
            if (type != null) 'type': type,
            if (start != null) 'startDate': start.toUtc().toIso8601String(),
            if (end != null) 'endDate': end.toUtc().toIso8601String(),
          },
        );
      } catch (_) {
        // Fallback: try clean request without extra query params
        res = await _api.get<dynamic>(url);
      }

      apiAlerts = asMapList(res)
          .map(FleetAlert.fromJson)
          .where((FleetAlert a) => a.id.isNotEmpty && !deletedIds.contains(a.id))
          .map((FleetAlert a) {
            final bool isLocallyRead = a.isRead ||
                readIds.contains(a.id) ||
                (lastReadTime != null &&
                    a.createdAt != null &&
                    !a.createdAt!.isAfter(lastReadTime));
            return isLocallyRead ? a.copyWith(isRead: true) : a;
          })
          .toList(growable: false);
    } catch (_) {}

    // 3. Merge server alerts and local push notifications (deduplicated by ID)
    final Map<String, FleetAlert> byId = <String, FleetAlert>{};
    for (final FleetAlert a in localAlerts) {
      if (vehicleId == null || a.vehicleId == vehicleId) {
        if (vehicleId == null && vehicleIds != null && vehicleIds.isNotEmpty && a.vehicleId != null && a.vehicleId!.isNotEmpty) {
          if (!vehicleIds.contains(a.vehicleId)) continue;
        }
        byId[a.id] = a;
      }
    }
    for (final FleetAlert a in apiAlerts) {
      byId[a.id] = a;
    }

    final List<FleetAlert> merged = byId.values.toList();
    merged.sort((FleetAlert a, FleetAlert b) {
      final DateTime tA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime tB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tB.compareTo(tA);
    });

    // Intelligent debouncing: prevent duplicate bursts of overspeed / parking alerts
    // for the same vehicle occurring within 3 minutes of each other
    final List<FleetAlert> debounced = <FleetAlert>[];
    for (final FleetAlert a in merged) {
      final bool isDuplicate = debounced.any((FleetAlert existing) {
        if (existing.vehicleId != null &&
            existing.vehicleId!.isNotEmpty &&
            existing.vehicleId == a.vehicleId &&
            existing.type == a.type) {
          final DateTime? tExisting = existing.createdAt;
          final DateTime? tA = a.createdAt;
          if (tExisting != null && tA != null) {
            return tExisting.difference(tA).inSeconds.abs() < 180; // 3 minutes
          }
        }
        return false;
      });
      if (!isDuplicate) {
        debounced.add(a);
      }
    }

    if (debounced.isNotEmpty || vehicleId != null) {
      return debounced;
    }

    // Fallback: If /alerts returned empty and vehicleId is null (Fleet mode),
    // aggregate alerts from fleet vehicles ONLY if fleet is small (<= 10) to prevent
    // spawning hundreds of concurrent HTTP connections on large fleets.
    if (vehicleId == null && vehicleIds != null && vehicleIds.isNotEmpty && vehicleIds.length <= 10) {
      try {
        final List<List<FleetAlert>> perVehicle = await Future.wait(
          vehicleIds.map(
            (vId) => getAlerts(
              vehicleId: vId,
              type: type,
              start: start,
              end: end,
              limit: 25,
            ),
          ),
        );
        final DateTime? lastReadTime = _store.getLastAlertsReadTime();
        final Set<String> readIds = _store.getReadAlertIds();
        final List<FleetAlert> combined = perVehicle
            .expand((l) => l)
            .map((FleetAlert a) {
              final bool isLocallyRead = a.isRead ||
                  readIds.contains(a.id) ||
                  (lastReadTime != null &&
                      a.createdAt != null &&
                      !a.createdAt!.isAfter(lastReadTime));
              return isLocallyRead ? a.copyWith(isRead: true) : a;
            })
            .toList();
        combined.sort((a, b) {
          final DateTime tA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final DateTime tB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tB.compareTo(tA);
        });
        return combined;
      } catch (_) {}
    }

    return const <FleetAlert>[];
  }

  Future<int> getUnreadCount({List<String>? vehicleIds}) async {
    // Compute accurate unread count from recent alerts
    final List<FleetAlert> recent = await getAlerts(
      limit: 50,
      vehicleIds: vehicleIds,
    );
    return recent.where((FleetAlert a) => !a.isRead).length;
  }

  Future<int> getUnreadOverspeedCount({List<String>? vehicleIds}) async {
    final List<FleetAlert> recent = await getAlerts(
      limit: 50,
      vehicleIds: vehicleIds,
    );
    return recent.where((FleetAlert a) => !a.isRead && a.isOverspeed).length;
  }

  Future<void> markAsRead(String alertId) async {
    await _store.addReadAlertId(alertId);
    try {
      await _api.put<dynamic>('/alerts/$alertId/read');
    } on ApiException {/* non-critical */}
  }

  Future<void> markAllAsRead({DateTime? upToTime}) async {
    await _store.setLastAlertsReadTime(upToTime ?? DateTime.now());
    try {
      await _api.put<dynamic>('/alerts/read-all');
    } on ApiException {/* non-critical */}
  }

  Future<Map<String, dynamic>?> getPreferences() async {
    try {
      final dynamic res = await _api.get<dynamic>('/alerts/preferences');
      if (res is Map<String, dynamic> && res['preferences'] is Map) {
        return Map<String, dynamic>.from(res['preferences']);
      }
    } on ApiException {/* fallback to local */}
    return null;
  }

  Future<void> updatePreferences(Map<String, dynamic> preferences) async {
    try {
      await _api.put<dynamic>('/alerts/preferences', body: <String, dynamic>{
        'preferences': preferences,
      });
    } on ApiException {/* non-critical */}
  }

  Future<void> deleteAlert(String alertId) async {
    await _store.addDeletedAlertId(alertId);
    await PushService.deleteLocalAlert(alertId);
    try {
      await _api.delete<dynamic>('/alerts/$alertId');
    } on ApiException {/* non-critical */}
  }

  Future<void> deleteAlerts(Iterable<String> alertIds) async {
    await _store.addDeletedAlertIds(alertIds);
    for (final String id in alertIds) {
      await PushService.deleteLocalAlert(id);
      try {
        await _api.delete<dynamic>('/alerts/$id');
      } catch (_) {}
    }
  }

  Future<void> clearVehicleAlerts(String vehicleId) async {
    final List<Map<String, dynamic>> local = await PushService.getLocalAlerts();
    for (final Map<String, dynamic> item in local) {
      if (item['vehicleId']?.toString() == vehicleId || item['vehicle_id']?.toString() == vehicleId) {
        final String? id = item['id']?.toString();
        if (id != null) await PushService.deleteLocalAlert(id);
      }
    }
    try {
      await _api.delete<dynamic>('/vehicles/$vehicleId/alerts');
    } on ApiException {/* non-critical */}
  }

  Future<void> clearAllAlerts() async {
    await PushService.clearLocalAlerts();
    try {
      await _api.delete<dynamic>('/alerts');
    } on ApiException {/* non-critical */}
  }
}
