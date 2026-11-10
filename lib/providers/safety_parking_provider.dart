import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/socket_service.dart';
import '../core/services/siren_service.dart';
import 'core_providers.dart';
import 'fleet_provider.dart';

class ActiveTheftAlarm {
  const ActiveTheftAlarm({
    required this.vehicleId,
    required this.vehicleName,
    required this.plate,
    required this.alertText,
    required this.triggeredAt,
  });

  final String vehicleId;
  final String vehicleName;
  final String plate;
  final String alertText;
  final DateTime triggeredAt;
}

class SafetyParkingState {
  const SafetyParkingState({
    this.activeAlarm,
    this.isSirenSounding = false,
  });

  final ActiveTheftAlarm? activeAlarm;
  final bool isSirenSounding;

  bool get hasActiveAlarm => activeAlarm != null;

  SafetyParkingState copyWith({
    ActiveTheftAlarm? activeAlarm,
    bool? isSirenSounding,
    bool clearAlarm = false,
  }) {
    return SafetyParkingState(
      activeAlarm: clearAlarm ? null : (activeAlarm ?? this.activeAlarm),
      isSirenSounding: isSirenSounding ?? this.isSirenSounding,
    );
  }
}

class SafetyParkingNotifier extends StateNotifier<SafetyParkingState> {
  SafetyParkingNotifier(this._ref) : super(const SafetyParkingState()) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<SocketEvent>? _socketSub;

  void _init() {
    try {
      _socketSub = _ref.read(socketServiceProvider).events$.listen((SocketEvent event) {
        if (event.name == 'alert:new') {
          handleAlertJson(event.payload);
        } else if (event.name == 'vehicle:safety_park') {
          final String? vId = event.payload['vehicleId']?.toString() ?? event.payload['id']?.toString();
          final String? sp = event.payload['safetyPark']?.toString();
          if (vId != null && (sp == 'NO' || sp == 'false') && state.activeAlarm?.vehicleId == vId) {
            dismissAlarm();
          }
        }
      });
    } catch (_) {}
  }

  void handleAlertJson(Map<String, dynamic> data) {
    final String type = (data['type'] ?? data['alertType'] ?? data['alert_type'] ?? '').toString().toLowerCase();
    final bool isTheft = data['isTheft'] == 'true' ||
        data['isTheft'] == true ||
        type == 'safety_park' ||
        type == 'theft_alarm' ||
        type == 'theft';

    if (isTheft) {
      final String vId = (data['vehicleId'] ?? data['vehicle_id'] ?? '').toString();
      final String vName = (data['vehicleName'] ?? data['vehicle_name'] ?? data['plate'] ?? 'Vehicle').toString();
      final String plate = (data['plate'] ?? data['registrationNumber'] ?? data['vehicleNumber'] ?? '').toString();
      final String text = (data['body'] ?? data['text'] ?? data['message'] ?? data['alertText'] ??
              'Vehicle moved or Engine turned ON while Safety Parking was ACTIVE!')
          .toString();

      final ActiveTheftAlarm alarm = ActiveTheftAlarm(
        vehicleId: vId,
        vehicleName: vName,
        plate: plate,
        alertText: text,
        triggeredAt: DateTime.now(),
      );

      state = SafetyParkingState(
        activeAlarm: alarm,
        isSirenSounding: true,
      );

      SirenService.instance.start(
        title: (data['title'] ?? 'THEFT ALARM: $vName ($plate)').toString(),
        message: text,
      );
    }
  }

  Future<void> arm(String vehicleId) async {
    await _ref.read(fleetProvider.notifier).updateSettings(vehicleId, safetyPark: true);
  }

  Future<void> disarm(String vehicleId) async {
    if (state.activeAlarm?.vehicleId == vehicleId) {
      dismissAlarm();
    }
    try {
      await _ref.read(fleetProvider.notifier).updateSettings(vehicleId, safetyPark: false);
    } catch (_) {
      try {
        await _ref.read(vehicleRepositoryProvider).updateSettings(vehicleId, safetyPark: false);
      } catch (_) {}
    }
  }

  void silenceSiren() {
    SirenService.instance.stop();
    state = state.copyWith(isSirenSounding: false);
  }

  void dismissAlarm() {
    SirenService.instance.stop();
    state = const SafetyParkingState();
  }

  Future<void> disarmAndStopSiren() async {
    final String? vId = state.activeAlarm?.vehicleId;
    dismissAlarm();
    if (vId != null && vId.isNotEmpty) {
      try {
        await _ref.read(fleetProvider.notifier).updateSettings(vId, safetyPark: false);
      } catch (_) {
        try {
          await _ref.read(vehicleRepositoryProvider).updateSettings(vId, safetyPark: false);
        } catch (_) {}
      }
    }
  }

  void triggerTestAlarm({String vehicleName = 'Demo Fleet Vehicle', String plate = 'KA-01-FT-9999'}) {
    final ActiveTheftAlarm alarm = ActiveTheftAlarm(
      vehicleId: 'test_safety_park',
      vehicleName: vehicleName,
      plate: plate,
      alertText: '🚨 TEST THEFT ALARM: Engine turned ON while Safety Parking was ARMED!',
      triggeredAt: DateTime.now(),
    );

    state = SafetyParkingState(
      activeAlarm: alarm,
      isSirenSounding: true,
    );

    SirenService.instance.start(
      title: 'THEFT ALARM: $vehicleName ($plate)',
      message: alarm.alertText,
    );
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    SirenService.instance.stop();
    super.dispose();
  }
}

final StateNotifierProvider<SafetyParkingNotifier, SafetyParkingState>
    safetyParkingProvider =
    StateNotifierProvider<SafetyParkingNotifier, SafetyParkingState>(
  (Ref ref) => SafetyParkingNotifier(ref),
);
