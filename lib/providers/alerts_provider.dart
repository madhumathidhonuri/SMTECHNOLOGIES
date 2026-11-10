import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/push_service.dart';
import '../core/realtime/socket_service.dart';
import '../data/models/alert.dart';
import '../data/models/vehicle.dart';
import 'core_providers.dart';
import 'fleet_provider.dart';

/// Manages the unread alert count for the app bar bell badge and live alerts.
class UnreadAlertsCountNotifier extends StateNotifier<int> {
  UnreadAlertsCountNotifier(this._ref) : super(0) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<SocketEvent>? _socketSub;

  Future<void> _init() async {
    // Initial fetch
    unawaited(refresh());

    // Listen to real-time events from the socket connection
    try {
      _socketSub = _ref.read(socketServiceProvider).events$.listen((SocketEvent event) {
        if (event.name == 'alert:new' || event.name == 'geofence:event') {
          _handleIncomingSocketAlert(event);
        }
      });
    } catch (_) {}
  }

  Future<void> _handleIncomingSocketAlert(SocketEvent event) async {
    try {
      final Map<String, dynamic> data = event.payload;
      final String? vId = data['vehicleId']?.toString() ?? data['vehicle_id']?.toString();

      String? vName = data['vehicleName']?.toString() ??
          data['vehicle_name']?.toString() ??
          data['plate']?.toString() ??
          data['registrationNumber']?.toString();

      if ((vName == null || vName.isEmpty) && vId != null) {
        final List<Vehicle> vehicles = _ref.read(fleetProvider).vehicles;
        final Vehicle? matched = vehicles.where((Vehicle v) => v.id == vId).firstOrNull;
        if (matched != null) {
          vName = matched.displayName;
        }
      }

      final String rawType = (data['type'] ??
              data['alertType'] ??
              data['alert_type'] ??
              (event.name == 'geofence:event' ? 'geofence' : 'info'))
          .toString();
      final String title = (data['title'] ?? data['name'] ?? FleetAlert.titleFor(rawType)).toString();
      final String message = (data['message'] ?? data['description'] ?? data['body'] ?? title).toString();
      final String alertId = data['alertId']?.toString() ??
          data['id']?.toString() ??
          data['_id']?.toString() ??
          'alert_${DateTime.now().millisecondsSinceEpoch}_${data.hashCode}';

      final Map<String, dynamic> meta = data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : <String, dynamic>{};

      final double? lat = double.tryParse(data['latitude']?.toString() ??
          data['lat']?.toString() ??
          meta['latitude']?.toString() ??
          meta['lat']?.toString() ??
          '');
      final double? lng = double.tryParse(data['longitude']?.toString() ??
          data['lng']?.toString() ??
          meta['longitude']?.toString() ??
          meta['lng']?.toString() ??
          '');
      final String? address = data['address']?.toString() ??
          data['location']?.toString() ??
          meta['address']?.toString() ??
          meta['location']?.toString();

      await PushService.saveLocalAlert(<String, dynamic>{
        'id': alertId,
        'type': rawType,
        'title': title,
        'message': message,
        'vehicleId': vId,
        'vehicleName': vName,
        'createdAt': data['createdAt'] ??
            data['deviceTime'] ??
            data['serverTime'] ??
            data['recorded_at'] ??
            DateTime.now().toIso8601String(),
        'latitude': lat,
        'longitude': lng,
        'address': address,
        'isRead': false,
      });

      await refresh();
    } catch (_) {
      state = state + 1;
    }
  }

  /// Refreshes the unread count from the backend API or fleet alerts list.
  Future<void> refresh() async {
    try {
      final repo = _ref.read(alertRepositoryProvider);
      final List<Vehicle> vehicles = _ref.read(fleetProvider).vehicles;
      final List<String> vIds = vehicles.map((Vehicle v) => v.id).toList();

      final int count = await repo.getUnreadCount(vehicleIds: vIds);
      state = count;
    } catch (_) {}
  }

  void increment() {
    state = state + 1;
  }

  void reset() {
    state = 0;
  }

  void setCount(int count) {
    state = count.clamp(0, 9999);
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<UnreadAlertsCountNotifier, int>
    unreadAlertsCountProvider =
    StateNotifierProvider<UnreadAlertsCountNotifier, int>(
  (Ref ref) => UnreadAlertsCountNotifier(ref),
);

/// Manages the unread overspeed alert count for the dashboard overview tile.
class UnreadOverspeedCountNotifier extends StateNotifier<int> {
  UnreadOverspeedCountNotifier(this._ref) : super(0) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<SocketEvent>? _socketSub;

  Future<void> _init() async {
    unawaited(refresh());

    try {
      _socketSub = _ref.read(socketServiceProvider).events$.listen((SocketEvent event) {
        if (event.name == 'alert:new') {
          final Map<String, dynamic> data = event.payload;
          final String type = (data['type'] ?? data['alertType'] ?? '').toString().toLowerCase();
          final String title = (data['title'] ?? '').toString().toLowerCase();
          final String msg = (data['message'] ?? '').toString().toLowerCase();
          final bool isOver = type.contains('overspeed') ||
              title.contains('overspeed') ||
              msg.contains('overspeed') ||
              msg.contains('speed limit') ||
              msg.contains('speeding');
          if (isOver) {
            state = state + 1;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> refresh() async {
    try {
      final repo = _ref.read(alertRepositoryProvider);
      final List<Vehicle> vehicles = _ref.read(fleetProvider).vehicles;
      final List<String> vIds = vehicles.map((Vehicle v) => v.id).toList();

      final int count = await repo.getUnreadOverspeedCount(vehicleIds: vIds);
      state = count;
    } catch (_) {}
  }

  void increment() {
    state = state + 1;
  }

  void reset() {
    state = 0;
  }

  void setCount(int count) {
    state = count.clamp(0, 9999);
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<UnreadOverspeedCountNotifier, int>
    unreadOverspeedCountProvider =
    StateNotifierProvider<UnreadOverspeedCountNotifier, int>(
  (Ref ref) => UnreadOverspeedCountNotifier(ref),
);

