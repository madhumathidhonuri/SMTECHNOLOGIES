import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/network/api_exception.dart';
import '../core/realtime/socket_service.dart';
import '../data/models/user.dart';
import '../data/models/vehicle.dart';
import 'auth_provider.dart';
import 'core_providers.dart';

class FleetStats {
  const FleetStats({
    this.total = 0,
    this.moving = 0,
    this.idle = 0,
    this.stopped = 0,
    this.offline = 0,
    this.noData = 0,
    this.overspeeding = 0,
    this.expiringSoon = 0,
    this.totalDistanceToday = 0,
  });

  final int total;
  final int moving;
  final int idle;
  final int stopped;
  final int offline;
  final int noData;
  final int overspeeding;
  final int expiringSoon;
  final double totalDistanceToday;

  int get online => moving + idle + stopped;

  double get onlinePercent => total == 0 ? 0 : online / total;
  double get utilisation => total == 0 ? 0 : moving / total;

  factory FleetStats.from(List<Vehicle> vehicles) {
    int moving = 0, idle = 0, stopped = 0, offline = 0, noData = 0;
    int over = 0, expiring = 0;
    double distance = 0;

    for (final Vehicle v in vehicles) {
      switch (v.status) {
        case VehicleStatus.moving:
          moving++;
        case VehicleStatus.idle:
          idle++;
        case VehicleStatus.stopped:
          stopped++;
        case VehicleStatus.offline:
          offline++;
        case VehicleStatus.noData:
          noData++;
      }
      if (v.status != VehicleStatus.offline &&
          v.status != VehicleStatus.noData &&
          v.isOverspeeding) {
        over++;
      }
      if (v.isExpiringSoon) expiring++;
      distance += v.todayDistanceKm ?? 0;
    }

    return FleetStats(
      total: vehicles.length,
      moving: moving,
      idle: idle,
      stopped: stopped,
      offline: offline,
      noData: noData,
      overspeeding: over,
      expiringSoon: expiring,
      totalDistanceToday: distance,
    );
  }
}

class FleetState {
  const FleetState({
    this.vehicles = const <Vehicle>[],
    this.isLoading = true,
    this.isRefreshing = false,
    this.error,
    this.lastSyncedAt,
  });

  final List<Vehicle> vehicles;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? lastSyncedAt;

  FleetStats get stats => FleetStats.from(vehicles);
  bool get isEmpty => vehicles.isEmpty && !isLoading;

  FleetState copyWith({
    List<Vehicle>? vehicles,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    DateTime? lastSyncedAt,
    bool clearError = false,
  }) =>
      FleetState(
        vehicles: vehicles ?? this.vehicles,
        isLoading: isLoading ?? this.isLoading,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        error: clearError ? null : (error ?? this.error),
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
}

final NotifierProvider<FleetController, FleetState> fleetProvider =
    NotifierProvider<FleetController, FleetState>(FleetController.new);

/// Owns the canonical vehicle list and folds socket frames into it.
///
/// Update strategy: socket frames land in a pending buffer and are flushed to
/// state on a timer ([AppConfig.mapThrottle]). With 300 vehicles each pushing
/// ~1Hz, naive setState would rebuild the tree 300×/second; buffering keeps
/// it at a steady ~2 rebuilds/second with zero perceptible lag.
class FleetController extends Notifier<FleetState> {
  StreamSubscription<SocketEvent>? _socketSub;
  Timer? _flushTimer;
  Timer? _staleTimer;
  bool _mounted = true;

  final Map<String, Vehicle> _pending = <String, Vehicle>{};
  final Map<String, Vehicle> _vehiclesById = <String, Vehicle>{};
  final Map<String, String> _identifierToVehicleId = <String, String>{};

  void _rebuildIndexes(List<Vehicle> list) {
    _vehiclesById.clear();
    _identifierToVehicleId.clear();
    for (final Vehicle v in list) {
      if (v.id.isNotEmpty) {
        _vehiclesById[v.id] = v;
        _identifierToVehicleId[v.id] = v.id;
      }
      if (v.deviceId.isNotEmpty) {
        _identifierToVehicleId[v.deviceId] = v.id;
        _identifierToVehicleId[v.deviceId.toLowerCase()] = v.id;
      }
      if (v.imei.isNotEmpty) {
        _identifierToVehicleId[v.imei] = v.id;
        _identifierToVehicleId[v.imei.toLowerCase()] = v.id;
      }
      if (v.registrationNumber.isNotEmpty) {
        final String cleanReg = v.registrationNumber.toUpperCase().replaceAll(RegExp(r'\s+'), '');
        _identifierToVehicleId[cleanReg] = v.id;
        _identifierToVehicleId[v.registrationNumber] = v.id;
      }
      if (v.name.isNotEmpty) {
        final String cleanName = v.name.toUpperCase().replaceAll(RegExp(r'\s+'), '');
        _identifierToVehicleId[cleanName] = v.id;
        _identifierToVehicleId[v.name] = v.id;
      }
    }
  }

  @override
  FleetState build() {
    _mounted = true;
    ref.onDispose(() {
      _mounted = false;
      _socketSub?.cancel();
      _flushTimer?.cancel();
      _staleTimer?.cancel();
    });
    return const FleetState();
  }

  // ── Loading ──────────────────────────────────────────────────────

  Future<void> load({bool silent = false}) async {
    if (!_mounted) return;
    if (!silent) {
      _safeSetState(state.copyWith(
        isLoading: state.vehicles.isEmpty,
        isRefreshing: true,
        clearError: true,
      ));
    }

    try {
      final List<Vehicle> vehicles =
          await ref.read(vehicleRepositoryProvider).getVehicles();

      if (!_mounted) return;

      // Preserve fresher socket data: prefer in-flight pending frames,
      // then existing state, over the REST snapshot.
      final Map<String, Vehicle> current = <String, Vehicle>{
        for (final Vehicle v in state.vehicles) v.id: v,
        // Pending frames are always fresher than anything REST returns.
        ..._pending,
      };

      // Deduplicate incoming API response by ID to prevent duplicate ValueKey crashes
      final Map<String, Vehicle> incomingMap = <String, Vehicle>{
        for (final Vehicle v in vehicles) v.id: v,
      };

      final List<Vehicle> merged = incomingMap.values.map((Vehicle incoming) {
        // If an in-flight socket frame is buffered, prefer the live socket frame
        final Vehicle? pendingSocketFrame = _pending[incoming.id];
        if (pendingSocketFrame != null) return pendingSocketFrame;

        final Vehicle? existing = current[incoming.id];
        if (existing == null) return incoming;

        if (incoming.lastPacketAt == null && existing.lastPacketAt != null) {
          return existing;
        }

        final DateTime? a = existing.lastPacketAt;
        final DateTime? b = incoming.lastPacketAt;
        // Never let REST polling rewind an active vehicle to an older packet.
        // If the vehicle is currently moving, give live socket telemetry precedence over REST snapshots
        // unless REST is significantly newer (>15s), preventing snapshot position rollbacks.
        if (a != null && b != null) {
          if (!b.isAfter(a)) return existing;
          if (existing.status == VehicleStatus.moving &&
              b.difference(a).inSeconds < 15) {
            // Retain fresher socket location if REST coordinates are identical or older
            if (existing.hasLocation && incoming.hasLocation) {
              return existing;
            }
          }
        }
        return incoming;
      }).toList();

      // Deduplicate vehicles by registrationNumber & deviceId so ghost duplicates never appear
      final Map<String, Vehicle> deduplicated = <String, Vehicle>{};
      for (final Vehicle v in merged) {
        final String dedupKey = v.registrationNumber.trim().isNotEmpty
            ? v.registrationNumber.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '')
            : (v.deviceId.trim().isNotEmpty ? 'dev_${v.deviceId.trim()}' : v.id);
        final Vehicle? prev = deduplicated[dedupKey];
        if (prev == null) {
          deduplicated[dedupKey] = v;
        } else {
          final DateTime? tPrev = prev.lastPacketAt;
          final DateTime? tCurr = v.lastPacketAt;
          if (tCurr != null && (tPrev == null || tCurr.isAfter(tPrev))) {
            deduplicated[dedupKey] = v;
          }
        }
      }
      final List<Vehicle> cleanMerged = deduplicated.values.toList();

      if (state.vehicles.isEmpty || !silent) {
        _sort(cleanMerged);
      } else {
        // Silent background sync: preserve the existing display order so cards don't jump
        final Map<String, int> existingOrder = <String, int>{
          for (int i = 0; i < state.vehicles.length; i++) state.vehicles[i].id: i,
        };
        cleanMerged.sort((Vehicle a, Vehicle b) {
          final int orderA = existingOrder[a.id] ?? 999999;
          final int orderB = existingOrder[b.id] ?? 999999;
          if (orderA != orderB) return orderA.compareTo(orderB);
          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
      }
      _rebuildIndexes(cleanMerged);

      if (!_mounted) return;
      _safeSetState(state.copyWith(
        vehicles: cleanMerged,
        isLoading: false,
        isRefreshing: false,
        lastSyncedAt: DateTime.now(),
        clearError: true,
      ));

      // For small fleets (<= 25), joining individual vehicle rooms is fine.
      // For large fleets (e.g. 568+), the org/user room already streams all telemetry
      // without flooding the WebSocket with hundreds of frame emissions.
      if (merged.length <= 25) {
        final SocketService socket = ref.read(socketServiceProvider);
        for (final Vehicle v in merged) {
          socket.joinVehicle(v.id);
        }
      }

      // Dynamically tune throttle based on fleet size to keep UI at 60 FPS
      if (_socketSub != null) {
        _flushTimer?.cancel();
        final Duration throttle = merged.length > 100
            ? const Duration(milliseconds: 1500)
            : (merged.length > 30
                ? const Duration(milliseconds: 800)
                : AppConfig.mapThrottle);
        _flushTimer = Timer.periodic(throttle, (_) => _flush());
      }

      _startStaleTimer();
    } on ApiException catch (e) {
      if (!_mounted) return;
      _safeSetState(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: e.message,
      ));
    } catch (e) {
      if (!_mounted) return;
      _safeSetState(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: e.toString(),
      ));
    }
  }

  /// Called by the lifecycle observer on resume — REST first, socket after.
  Future<void> resyncAfterForeground() async {
    debugPrint('[fleet] foreground resync');
    await load(silent: true);
  }

  // ── Real-time ────────────────────────────────────────────────────

  void attachSocket() {
    _socketSub?.cancel();
    final SocketService socket = ref.read(socketServiceProvider);

    _socketSub = socket.events$.listen(_onSocketEvent);

    final AppUser? user = ref.read(authProvider).user;
    if (user?.orgId != null && user!.orgId.isNotEmpty) {
      socket.joinOrg(user.orgId);
    } else if (user?.id != null) {
      socket.joinUser(user!.id);
    }

    _flushTimer?.cancel();
    final Duration throttle = state.vehicles.length > 100
        ? const Duration(milliseconds: 1500)
        : (state.vehicles.length > 30
            ? const Duration(milliseconds: 800)
            : AppConfig.mapThrottle);
    _flushTimer = Timer.periodic(throttle, (_) => _flush());
  }

  void detachSocket() {
    _socketSub?.cancel();
    _socketSub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
  }

  void _onSocketEvent(SocketEvent event) {
    switch (event.name) {
      case 'fleet:update':
      case 'vehicle:update':
      case 'location:update':
      case 'position:update':
      case 'positions':
      case 'vehicle:status':
        _bufferUpdate(event.payload);
        break;
      case 'alert:new':
      case 'geofence:event':
        // FCM handles push notifications now. Socket is just for UI state.
        break;
      case 'vehicle:safety_park':
        final String? vId = event.payload['vehicleId']?.toString() ?? event.payload['id']?.toString();
        final String? sp = event.payload['safetyPark']?.toString();
        if (vId != null && sp != null) {
          final bool armed = sp == 'YES' || sp == 'true';
          final List<Vehicle> updated = state.vehicles.map((Vehicle v) {
            if (v.id == vId) return v.withSafetyPark(armed);
            return v;
          }).toList();
          _safeSetState(state.copyWith(vehicles: updated));
        }
        break;
      default:
        break;
    }
  }

  void _bufferUpdate(Map<String, dynamic> payload) {
    // A frame may be one vehicle or a batch.
    final Object? list = payload['vehicles'] ?? payload['data'];
    if (list is List) {
      for (final Object? item in list) {
        if (item is Map) _bufferOne(Map<String, dynamic>.from(item));
      }
      return;
    }
    _bufferOne(payload);
  }

  void _bufferOne(Map<String, dynamic> frame) {
    // 1. Check all identifier fields, prioritizing device/vehicle identifiers over packet ID
    final String? devId = frame['deviceId']?.toString() ??
        frame['device_id']?.toString() ??
        (frame['device'] is Map ? (frame['device'] as Map)['id']?.toString() : null);
    final String? imei = frame['imei']?.toString() ??
        frame['IMEI']?.toString() ??
        (frame['device'] is Map ? (frame['device'] as Map)['imei']?.toString() : null);
    final String? vehicleId = frame['vehicleId']?.toString() ?? frame['_id']?.toString();
    final String? regNo = frame['registrationNumber']?.toString() ??
        frame['regNo']?.toString() ??
        frame['plateNumber']?.toString();
    final String? name = frame['name']?.toString() ?? frame['vehicleName']?.toString();
    final String? rawId = frame['vehicle']?.toString() ?? frame['id']?.toString();

    // 2. Resolve matching vehicle from indexes in order of precision
    String? resolvedId;
    if (vehicleId != null && vehicleId.isNotEmpty) {
      resolvedId = _identifierToVehicleId[vehicleId] ?? (_vehiclesById.containsKey(vehicleId) ? vehicleId : null);
    }
    if (resolvedId == null && devId != null && devId.isNotEmpty) {
      resolvedId = _identifierToVehicleId[devId] ?? (_vehiclesById.containsKey(devId) ? devId : null);
    }
    if (resolvedId == null && imei != null && imei.isNotEmpty) {
      resolvedId = _identifierToVehicleId[imei] ?? (_vehiclesById.containsKey(imei) ? imei : null);
    }
    if (resolvedId == null && regNo != null && regNo.isNotEmpty) {
      final String cleanReg = regNo.toUpperCase().replaceAll(RegExp(r'\s+'), '');
      resolvedId = _identifierToVehicleId[cleanReg] ?? _identifierToVehicleId[regNo];
    }
    if (resolvedId == null && name != null && name.isNotEmpty) {
      final String cleanName = name.toUpperCase().replaceAll(RegExp(r'\s+'), '');
      resolvedId = _identifierToVehicleId[cleanName] ?? _identifierToVehicleId[name];
    }
    if (resolvedId == null && rawId != null && rawId.isNotEmpty) {
      resolvedId = _identifierToVehicleId[rawId] ?? (_vehiclesById.containsKey(rawId) ? rawId : null);
    }
    // Single-vehicle fleet fallback: if the fleet only has 1 vehicle, socket frames belong to it
    if (resolvedId == null && _vehiclesById.length == 1) {
      resolvedId = _vehiclesById.keys.first;
    }

    final Vehicle? existing = resolvedId != null
        ? (_pending[resolvedId] ?? _vehiclesById[resolvedId])
        : null;

    if (existing == null) {
      // If we cannot match an existing vehicle, do NOT inject an unverified ghost record.
      // Doing so creates a duplicate marker on the map!
      if (state.vehicles.isNotEmpty) {
        return;
      }
      final Vehicle fresh = Vehicle.fromJson(frame);
      if (fresh.id.isNotEmpty && fresh.displayName.isNotEmpty) {
        _pending[fresh.id] = fresh;
        _vehiclesById[fresh.id] = fresh;
        _identifierToVehicleId[fresh.id] = fresh.id;
        if (fresh.deviceId.isNotEmpty) _identifierToVehicleId[fresh.deviceId] = fresh.id;
        if (fresh.imei.isNotEmpty) _identifierToVehicleId[fresh.imei] = fresh.id;
      }
      return;
    }

    final Vehicle updated = existing.mergeLive(frame);
    _pending[existing.id] = updated;
    _vehiclesById[existing.id] = updated;
  }

  /// Updates provider state safely so state mutations never collide
  /// with widget unmounting or frame pipeline execution.
  void _safeSetState(FleetState nextState) {
    if (!_mounted) return;
    try {
      final WidgetsBinding binding = WidgetsBinding.instance;
      if (binding.buildOwner?.debugBuilding == true) {
        Future.microtask(() {
          if (_mounted) {
            try {
              state = nextState;
            } catch (_) {}
          }
        });
      } else {
        state = nextState;
      }
    } catch (_) {}
  }

  /// Flush buffered socket frames.
  /// Telemetry data updates the vehicle in-place at its exact position in the list
  /// without re-sorting, ensuring vehicle cards never jump or shift unexpectedly while
  /// the user is focusing on or viewing them. Real-time data sync remains instant.
  void _flush() {
    if (!_mounted || _pending.isEmpty) return;

    final Map<String, Vehicle> snapshot = Map<String, Vehicle>.from(_pending);
    _pending.clear();

    if (state.vehicles.isEmpty) {
      final List<Vehicle> initialList = snapshot.values.toList();
      _sort(initialList);
      _rebuildIndexes(initialList);
      _safeSetState(state.copyWith(vehicles: initialList));
      return;
    }

    // 1. In-place update preserving exact card order on screen.
    final Set<String> updatedVehicleIds = <String>{};
    final List<Vehicle> updatedList = <Vehicle>[];

    for (final Vehicle current in state.vehicles) {
      final Vehicle? live = snapshot[current.id];
      if (live != null) {
        updatedList.add(live);
        updatedVehicleIds.add(current.id);
      } else {
        updatedList.add(current);
      }
    }

    // 2. Append any genuinely new vehicles in snapshot that were not in state.vehicles yet
    for (final MapEntry<String, Vehicle> entry in snapshot.entries) {
      if (!updatedVehicleIds.contains(entry.key)) {
        final Vehicle newVeh = entry.value;
        final String newDedupKey = newVeh.registrationNumber.trim().isNotEmpty
            ? newVeh.registrationNumber.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '')
            : (newVeh.deviceId.trim().isNotEmpty ? 'dev_${newVeh.deviceId.trim()}' : newVeh.id);

        final bool alreadyExists = updatedList.any((Vehicle v) {
          if (v.id == newVeh.id) return true;
          final String existingDedupKey = v.registrationNumber.trim().isNotEmpty
              ? v.registrationNumber.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '')
              : (v.deviceId.trim().isNotEmpty ? 'dev_${v.deviceId.trim()}' : v.id);
          return existingDedupKey == newDedupKey;
        });

        if (!alreadyExists) {
          updatedList.add(newVeh);
        }
      }
    }

    _rebuildIndexes(updatedList);
    _safeSetState(state.copyWith(vehicles: updatedList));
  }

  /// Manually force a re-render so vehicles immediately evaluate against
  /// any newly updated No Data Rule threshold.
  void refreshVehicleStatuses() {
    if (!_mounted || state.vehicles.isEmpty) return;
    _safeSetState(
        state.copyWith(vehicles: List<Vehicle>.from(state.vehicles)));
  }

  /// Vehicles go stale silently (no packet = no event), so we re-render
  /// periodically to let `status` flip to offline on its own.
  void _startStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_mounted || state.vehicles.isEmpty) return;
      _safeSetState(
          state.copyWith(vehicles: List<Vehicle>.from(state.vehicles)));
    });
  }

  /// Moving first, then idle, stopped, offline — then alphabetical.
  /// Operators care most about what is currently in motion.
  void _sort(List<Vehicle> list) {
    int rank(VehicleStatus s) => switch (s) {
          VehicleStatus.moving => 0,
          VehicleStatus.idle => 1,
          VehicleStatus.stopped => 2,
          VehicleStatus.offline => 3,
          VehicleStatus.noData => 4,
        };

    list.sort((Vehicle a, Vehicle b) {
      final int r = rank(a.status).compareTo(rank(b.status));
      if (r != 0) return r;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  }

  Future<void> updateSettings(
    String vehicleId, {
    double? overSpeedLimit,
    double? overspeedDurationAlert,
    double? idleDurationAlert,
    double? stoppageThreshold,
    double? parkingDurationAlert,
    double? movingDurationAlert,
    Map<String, bool>? alertConfig,
    bool? safetyPark,
  }) async {
    try {
      if (safetyPark != null) {
        final List<Vehicle> updated = state.vehicles.map((Vehicle v) {
          if (v.id == vehicleId) return v.withSafetyPark(safetyPark);
          return v;
        }).toList();
        _safeSetState(state.copyWith(vehicles: updated));
      }

      await ref.read(vehicleRepositoryProvider).updateSettings(
            vehicleId,
            overSpeedLimit: overSpeedLimit,
            overspeedDurationAlert: overspeedDurationAlert,
            idleDurationAlert: idleDurationAlert,
            stoppageThreshold: stoppageThreshold,
            parkingDurationAlert: parkingDurationAlert,
            movingDurationAlert: movingDurationAlert,
            alertConfig: alertConfig,
            safetyPark: safetyPark,
          );
      // Reload fleet so changes reflect instantly in UI
      await load(silent: true);
    } catch (e) {
      _safeSetState(state.copyWith(error: e.toString()));
      rethrow;
    }
  }

  void clear() {
    detachSocket();
    _staleTimer?.cancel();
    _vehiclesById.clear();
    _identifierToVehicleId.clear();
    state = const FleetState();
  }
}

// ── Derived providers ──────────────────────────────────────────────

final Provider<FleetStats> fleetStatsProvider =
    Provider<FleetStats>((Ref ref) => ref.watch(fleetProvider).stats);

final ProviderFamily<Vehicle?, String> vehicleByIdProvider =
    Provider.family<Vehicle?, String>((Ref ref, String id) {
  final List<Vehicle> list = ref.watch(fleetProvider).vehicles;
  if (id.isEmpty) return null;
  final String cleanId = Uri.decodeComponent(id).trim().toLowerCase();
  for (final Vehicle v in list) {
    if (v.id == id ||
        v.id.toLowerCase() == cleanId ||
        v.registrationNumber.toLowerCase() == cleanId ||
        v.displayName.toLowerCase() == cleanId ||
        v.name.toLowerCase() == cleanId) {
      return v;
    }
  }
  return null;
});

/// Dashboard search + status filter.
final StateProvider<String> fleetSearchProvider =
    StateProvider<String>((Ref ref) => '');

enum FleetSortOption {
  statusDefault,
  speedDesc,
  nameAsc,
  batteryDesc,
}

final StateProvider<VehicleStatus?> fleetFilterProvider =
    StateProvider<VehicleStatus?>((Ref ref) => null);

final StateProvider<String?> fleetTypeFilterProvider =
    StateProvider<String?>((Ref ref) => null);

final StateProvider<FleetSortOption> fleetSortProvider =
    StateProvider<FleetSortOption>((Ref ref) => FleetSortOption.statusDefault);

final StateProvider<bool> fleetAlertsOnlyProvider =
    StateProvider<bool>((Ref ref) => false);

final Provider<List<Vehicle>> filteredVehiclesProvider =
    Provider<List<Vehicle>>((Ref ref) {
  final List<Vehicle> all = ref.watch(fleetProvider).vehicles;
  final String query = ref.watch(fleetSearchProvider).trim().toLowerCase();
  final VehicleStatus? filter = ref.watch(fleetFilterProvider);
  final String? typeFilter = ref.watch(fleetTypeFilterProvider);
  final bool alertsOnly = ref.watch(fleetAlertsOnlyProvider);
  final FleetSortOption sortOption = ref.watch(fleetSortProvider);

  final List<Vehicle> list = all.where((Vehicle v) {
    if (filter != null && v.status != filter) return false;
    if (typeFilter != null) {
      final String t = v.displayType.toLowerCase();
      if (typeFilter == 'other') {
        if (t == 'truck' || t == 'car' || t == 'bike') return false;
      } else if (!t.contains(typeFilter)) {
        return false;
      }
    }
    if (alertsOnly && !v.isOverspeeding) return false;
    if (query.isEmpty) return true;
    return v.displayName.toLowerCase().contains(query) ||
        v.name.toLowerCase().contains(query) ||
        v.imei.toLowerCase().contains(query) ||
        (v.driverName ?? '').toLowerCase().contains(query);
  }).toList();

  switch (sortOption) {
    case FleetSortOption.speedDesc:
      list.sort((a, b) => b.speed.compareTo(a.speed));
    case FleetSortOption.nameAsc:
      list.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    case FleetSortOption.batteryDesc:
      list.sort((a, b) => (b.batteryLevel ?? 0).compareTo(a.batteryLevel ?? 0));
    case FleetSortOption.statusDefault:
      break;
  }

  return list;
});
