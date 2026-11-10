import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credential storage.
///
/// * JWT + refresh token → Keychain / EncryptedSharedPreferences.
/// * Non-sensitive UI preferences → SharedPreferences.
class SecureStore {
  SecureStore(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const _kToken = 'ft_access_token';
  static const _kRefresh = 'ft_refresh_token';
  static const _kUser = 'ft_cached_user';
  static const _kFcm = 'ft_fcm_token';

  static const _kThemeMode = 'ft_theme_mode';
  static const _kMapType = 'ft_map_type';
  static const _kUnits = 'ft_units';
  static const _kOnboarded = 'ft_onboarded';
  static const _kLastVehicle = 'ft_last_vehicle';
  static const _kNotifPrompted = 'ft_notif_prompted';

  static Future<SecureStore> create() async {
    const FlutterSecureStorage secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return SecureStore(secure, prefs);
  }

  // ── Tokens ───────────────────────────────────────────────────────
  Future<String?> readToken() async {
    try {
      return await _secure.read(key: _kToken);
    } catch (_) {
      await _secure.delete(key: _kToken);
      return null;
    }
  }
  
  Future<void> writeToken(String v) async {
    try {
      await _secure.write(key: _kToken, value: v);
    } catch (_) {
      await _secure.delete(key: _kToken);
      await _secure.write(key: _kToken, value: v);
    }
  }

  Future<String?> readRefreshToken() async {
    try {
      return await _secure.read(key: _kRefresh);
    } catch (_) {
      return null;
    }
  }
  
  Future<void> writeRefreshToken(String v) async {
    try {
      await _secure.write(key: _kRefresh, value: v);
    } catch (_) {
      // Ignore
    }
  }

  Future<String?> readFcmToken() => _secure.read(key: _kFcm);
  Future<void> writeFcmToken(String v) => _secure.write(key: _kFcm, value: v);

  // ── Cached user (for instant cold-start render) ──────────────────
  Future<Map<String, dynamic>?> readUser() async {
    try {
      final String? raw = await _secure.read(key: _kUser);
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeUser(Map<String, dynamic> user) async {
    try {
      await _secure.write(key: _kUser, value: jsonEncode(user));
    } catch (_) {
      // Ignore
    }
  }

  /// Wipes every credential. Called on logout and on hard 401.
  Future<void> clearSession() async {
    await Future.wait<void>(<Future<void>>[
      _secure.delete(key: _kToken),
      _secure.delete(key: _kRefresh),
      _secure.delete(key: _kUser),
    ]);
    await _prefs.remove(_kLastVehicle);
  }

  // ── Preferences ──────────────────────────────────────────────────
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'light';
  Future<void> setThemeMode(String v) => _prefs.setString(_kThemeMode, 'light');

  String get mapType => _prefs.getString(_kMapType) ?? 'google';
  Future<void> setMapType(String v) => _prefs.setString(_kMapType, v);

  String get units => _prefs.getString(_kUnits) ?? 'metric';
  Future<void> setUnits(String v) => _prefs.setString(_kUnits, v);

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool v) => _prefs.setBool(_kOnboarded, v);

  bool get notificationPrompted => _prefs.getBool(_kNotifPrompted) ?? false;
  Future<void> setNotificationPrompted(bool v) =>
      _prefs.setBool(_kNotifPrompted, v);

  String? get lastVehicleId => _prefs.getString(_kLastVehicle);
  Future<void> setLastVehicleId(String v) => _prefs.setString(_kLastVehicle, v);

  bool get notifSos => _prefs.getBool('ft_notif_sos') ?? true;
  Future<void> setNotifSos(bool v) => _prefs.setBool('ft_notif_sos', v);

  bool get notifTheft => _prefs.getBool('ft_notif_theft') ?? true;
  Future<void> setNotifTheft(bool v) => _prefs.setBool('ft_notif_theft', v);

  bool get notifOverspeed => _prefs.getBool('ft_notif_overspeed') ?? true;
  Future<void> setNotifOverspeed(bool v) =>
      _prefs.setBool('ft_notif_overspeed', v);

  bool get notifGeofence => _prefs.getBool('ft_notif_geofence') ?? true;
  Future<void> setNotifGeofence(bool v) =>
      _prefs.setBool('ft_notif_geofence', v);

  bool get notifIgnition => _prefs.getBool('ft_notif_ignition') ?? true;
  Future<void> setNotifIgnition(bool v) =>
      _prefs.setBool('ft_notif_ignition', v);

  bool get notifHarsh => _prefs.getBool('ft_notif_harsh') ?? true;
  Future<void> setNotifHarsh(bool v) => _prefs.setBool('ft_notif_harsh', v);

  // ── No Data Rule Persistence ───────────────────────────────────────
  static const String _kNodataThresholdHours = 'ft_nodata_threshold_hours';
  double get nodataThresholdHours => _prefs.getDouble(_kNodataThresholdHours) ?? 1.0;
  Future<void> setNodataThresholdHours(double v) => _prefs.setDouble(_kNodataThresholdHours, v);

  // ── Deleted Alert Persistence ──────────────────────────────────────
  static const _kDeletedAlerts = 'ft_deleted_alerts';

  Set<String> getDeletedAlertIds() {
    final List<String>? list = _prefs.getStringList(_kDeletedAlerts);
    return list?.toSet() ?? <String>{};
  }

  Future<void> addDeletedAlertId(String id) async {
    if (id.isEmpty) return;
    final Set<String> current = getDeletedAlertIds();
    current.add(id);
    await _prefs.setStringList(_kDeletedAlerts, current.toList());
  }

  Future<void> addDeletedAlertIds(Iterable<String> ids) async {
    final Set<String> current = getDeletedAlertIds();
    current.addAll(ids.where((String id) => id.isNotEmpty));
    await _prefs.setStringList(_kDeletedAlerts, current.toList());
  }

  // ── Read Alerts & Read Timestamp Persistence ──────────────────────
  static const _kLastAlertsReadTime = 'ft_last_alerts_read_time';
  static const _kReadAlerts = 'ft_read_alerts';

  DateTime? getLastAlertsReadTime() {
    final String? str = _prefs.getString(_kLastAlertsReadTime);
    if (str == null || str.isEmpty) return null;
    return DateTime.tryParse(str);
  }

  Future<void> setLastAlertsReadTime(DateTime time) async {
    await _prefs.setString(_kLastAlertsReadTime, time.toIso8601String());
  }

  Set<String> getReadAlertIds() {
    final List<String>? list = _prefs.getStringList(_kReadAlerts);
    return list?.toSet() ?? <String>{};
  }

  Future<void> addReadAlertId(String id) async {
    if (id.isEmpty) return;
    final Set<String> current = getReadAlertIds();
    current.add(id);
    await _prefs.setStringList(_kReadAlerts, current.toList());
  }

  Future<void> addReadAlertIds(Iterable<String> ids) async {
    final Set<String> current = getReadAlertIds();
    current.addAll(ids.where((String id) => id.isNotEmpty));
    await _prefs.setStringList(_kReadAlerts, current.toList());
  }

  // ── Route Vehicle Assignments Persistence ───────────────────────────
  static const _kRouteVehicles = 'ft_route_vehicles';

  Map<String, List<String>> getRouteVehicleAssignments() {
    try {
      final String? raw = _prefs.getString(_kRouteVehicles);
      if (raw == null || raw.isEmpty) return <String, List<String>>{};
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, List<String>>{};
      return decoded.map<String, List<String>>((dynamic k, dynamic v) {
        final List<String> list = (v is List)
            ? v.map((dynamic e) => e.toString()).toList()
            : <String>[];
        return MapEntry<String, List<String>>(k.toString(), list);
      });
    } catch (_) {
      return <String, List<String>>{};
    }
  }

  Future<void> saveRouteVehicleAssignments(
      String routeId, List<String> vehicleIds) async {
    if (routeId.isEmpty) return;
    try {
      final Map<String, List<String>> current = getRouteVehicleAssignments();
      current[routeId] = vehicleIds;
      await _prefs.setString(_kRouteVehicles, jsonEncode(current));
    } catch (_) {}
  }

  Future<void> removeRouteVehicleAssignments(String routeId) async {
    if (routeId.isEmpty) return;
    try {
      final Map<String, List<String>> current = getRouteVehicleAssignments();
      current.remove(routeId);
      await _prefs.setString(_kRouteVehicles, jsonEncode(current));
    } catch (_) {}
  }

  // ── Custom Local Routes Storage ──────────────────────────────────
  static const _kCustomRoutes = 'ft_custom_routes';

  List<Map<String, dynamic>> getCustomRoutes() {
    try {
      final String? raw = _prefs.getString(_kCustomRoutes);
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((dynamic m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> saveCustomRoute(Map<String, dynamic> routeJson) async {
    try {
      final List<Map<String, dynamic>> current = getCustomRoutes();
      final String id = (routeJson['id'] ?? '').toString();
      final String name = (routeJson['name'] ?? '').toString();
      final List<Map<String, dynamic>> updated = current
          .where((Map<String, dynamic> r) =>
              r['id'] != id && (name.isEmpty || r['name'] != name))
          .toList();
      updated.add(routeJson);
      await _prefs.setString(_kCustomRoutes, jsonEncode(updated));
    } catch (_) {}
  }

  Future<void> removeCustomRoute(String routeId) async {
    if (routeId.isEmpty) return;
    try {
      final List<Map<String, dynamic>> current = getCustomRoutes();
      final List<Map<String, dynamic>> updated = current
          .where((Map<String, dynamic> r) => r['id'] != routeId)
          .toList();
      await _prefs.setString(_kCustomRoutes, jsonEncode(updated));
    } catch (_) {}
  }

  // ── Local Trips Storage ──────────────────────────────────────────
  static const _kLocalTrips = 'ft_local_trips';

  List<Map<String, dynamic>> getLocalTrips() {
    try {
      final String? raw = _prefs.getString(_kLocalTrips);
      if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> saveLocalTrip(Map<String, dynamic> tripJson) async {
    try {
      final List<Map<String, dynamic>> current = getLocalTrips();
      final String id = (tripJson['id'] ?? '').toString();
      final int idx = current.indexWhere((m) => m['id'] == id);
      if (idx >= 0) {
        current[idx] = tripJson;
      } else {
        current.insert(0, tripJson);
      }
      await _prefs.setString(_kLocalTrips, jsonEncode(current));
    } catch (_) {}
  }
}

