import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/route.dart';
import '../data/repositories/route_repository.dart';
import 'core_providers.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class RouteState {
  const RouteState({
    this.routes = const <AppRoute>[],
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  final List<AppRoute> routes;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  RouteState copyWith({
    List<AppRoute>? routes,
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
  }) =>
      RouteState(
        routes: routes ?? this.routes,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        error: clearError ? null : (error ?? this.error),
      );
}

// ── Controller ────────────────────────────────────────────────────────────────

class RouteController extends Notifier<RouteState> {
  @override
  RouteState build() => const RouteState();

  RouteRepository get _repo => ref.read(routeRepositoryProvider);

  // ── Load ──────────────────────────────────────────────────────

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      List<AppRoute> remoteRoutes = <AppRoute>[];
      try {
        remoteRoutes = await _repo.getRoutes();
      } catch (_) {}

      final List<Map<String, dynamic>> localCustomRaw =
          ref.read(secureStoreProvider).getCustomRoutes();
      final List<AppRoute> localCustom = localCustomRaw
          .map(AppRoute.fromJson)
          .where((AppRoute r) => r.id.isNotEmpty || r.name.isNotEmpty)
          .toList();

      final Map<String, List<String>> localAssignments =
          ref.read(secureStoreProvider).getRouteVehicleAssignments();

      final Map<String, AppRoute> combinedMap = <String, AppRoute>{};
      for (final AppRoute r in remoteRoutes) {
        combinedMap[r.id] = r;
      }
      for (final AppRoute r in localCustom) {
        final String key = r.id.isNotEmpty ? r.id : r.name;
        combinedMap[key] = r;
      }

      final List<AppRoute> merged = combinedMap.values.map((AppRoute r) {
        final List<String>? byId = localAssignments[r.id];
        final List<String>? byName = localAssignments[r.name];
        final Set<String> combined = <String>{
          ...r.vehicleIds,
          if (byId != null) ...byId,
          if (byName != null) ...byName,
        };
        return r.copyWith(vehicleIds: combined.toList());
      }).toList();

      state = state.copyWith(routes: merged, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  // ── Create ────────────────────────────────────────────────────

  Future<AppRoute?> create(AppRoute route, {List<String>? vehicleIds}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    final List<String> vids = vehicleIds ?? route.vehicleIds;
    AppRoute created;
    try {
      created = await _repo.createRoute(route, vehicleIds: vids);
    } catch (_) {
      // Fallback: If backend returns foreign key constraint error ("Referenced record does not exist")
      // or network error, save as a persistent local custom route!
      final String fallbackId =
          route.id.isNotEmpty ? route.id : 'route_${DateTime.now().millisecondsSinceEpoch}';
      created = AppRoute(
        id: fallbackId,
        name: route.name,
        coordinates: route.coordinates,
        toleranceMeters: route.toleranceMeters,
        isActive: route.isActive,
        vehicleIds: vids,
        createdAt: DateTime.now(),
      );
    }

    // Persist locally
    final Map<String, dynamic> rJson = <String, dynamic>{
      'id': created.id,
      'name': created.name,
      'tolerance': created.toleranceMeters.round(),
      'is_active': created.isActive,
      'vehicleIds': vids,
      'coordinates': created.coordinates
          .map((LatLng p) => <String, double>{'lat': p.latitude, 'lng': p.longitude})
          .toList(),
    };
    await ref.read(secureStoreProvider).saveCustomRoute(rJson);

    if (vids.isNotEmpty) {
      if (created.id.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .saveRouteVehicleAssignments(created.id, vids);
      }
      if (created.name.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .saveRouteVehicleAssignments(created.name, vids);
      }
      try {
        if (created.id.isNotEmpty && !created.id.startsWith('route_')) {
          await _repo.assignRoute(created.id, vids);
        }
      } catch (_) {}
    }
    final AppRoute result = created.copyWith(vehicleIds: vids);
    state = state.copyWith(
      isSaving: false,
      routes: <AppRoute>[
        ...state.routes.where((AppRoute r) => r.id != result.id),
        result,
      ],
    );
    return result;
  }

  // ── Update ────────────────────────────────────────────────────

  Future<AppRoute?> update(AppRoute route, {List<String>? vehicleIds}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final List<String> vids = vehicleIds ?? route.vehicleIds;
      final String targetId = route.id;
      final String targetName = route.name;

      // 1. Immediately persist locally by ID and name so assignments never disappear
      if (targetId.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .saveRouteVehicleAssignments(targetId, vids);
      }
      if (targetName.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .saveRouteVehicleAssignments(targetName, vids);
      }

      // 2. Update remote backend
      AppRoute? remote;
      try {
        remote = await _repo.updateRoute(
          targetId,
          name: route.name,
          coordinates: route.coordinates
              .map((LatLng p) =>
                  <String, double>{'lat': p.latitude, 'lng': p.longitude})
              .toList(),
          tolerance: route.toleranceMeters,
          isActive: route.isActive,
          vehicleIds: vids,
        );
      } catch (_) {}

      // 3. Best-effort assign to backend
      if (targetId.isNotEmpty) {
        try {
          await _repo.assignRoute(targetId, vids);
        } catch (_) {}
      }

      final AppRoute updated = AppRoute(
        id: (remote != null && remote.id.isNotEmpty) ? remote.id : targetId,
        name: (remote != null && remote.name.isNotEmpty && remote.name != 'Unnamed Route')
            ? remote.name
            : targetName,
        coordinates: (remote != null && remote.coordinates.isNotEmpty)
            ? remote.coordinates
            : route.coordinates,
        toleranceMeters: route.toleranceMeters,
        isActive: remote?.isActive ?? route.isActive,
        vehicleIds: vids,
        createdAt: remote?.createdAt ?? route.createdAt,
      );

      final List<AppRoute> next = state.routes.map((AppRoute r) {
        if (r.id == targetId || (targetName.isNotEmpty && r.name == targetName)) {
          return updated;
        }
        return r;
      }).toList();

      state = state.copyWith(isSaving: false, routes: next);
      return updated;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
      return null;
    }
  }

  // ── Assign vehicles ────────────────────────────────────────────

  Future<bool> assign(String routeId, List<String> vehicleIds,
      {String? routeName}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      // 1. Persist locally to SharedPreferences by ID and Route Name
      if (routeId.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .saveRouteVehicleAssignments(routeId, vehicleIds);
      }
      if (routeName != null && routeName.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .saveRouteVehicleAssignments(routeName, vehicleIds);
      }

      // 2. Best-effort send to remote backend
      if (routeId.isNotEmpty) {
        try {
          await _repo.assignRoute(routeId, vehicleIds);
        } catch (_) {}
      }

      // 3. Update in-memory state
      final List<AppRoute> updated = state.routes.map((AppRoute r) {
        if (r.id == routeId || (routeName != null && r.name == routeName)) {
          return r.copyWith(vehicleIds: vehicleIds);
        }
        return r;
      }).toList();
      state = state.copyWith(isSaving: false, routes: updated);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
      return false;
    }
  }

  // ── Toggle active ──────────────────────────────────────────────

  Future<void> toggleActive(AppRoute route) async {
    try {
      final AppRoute updated = await _repo.updateRoute(
        route.id,
        isActive: !route.isActive,
      );
      final List<AppRoute> next = state.routes
          .map((AppRoute r) => r.id == route.id ? updated : r)
          .toList();
      state = state.copyWith(routes: next);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // ── Delete ────────────────────────────────────────────────────

  Future<bool> delete(String routeId, {String? routeName}) async {
    try {
      try {
        await _repo.deleteRoute(routeId);
      } catch (_) {}
      if (routeId.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .removeRouteVehicleAssignments(routeId);
        await ref
            .read(secureStoreProvider)
            .removeCustomRoute(routeId);
      }
      if (routeName != null && routeName.isNotEmpty) {
        await ref
            .read(secureStoreProvider)
            .removeRouteVehicleAssignments(routeName);
      }
      state = state.copyWith(
        routes: state.routes.where((AppRoute r) => r.id != routeId).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final Provider<RouteRepository> routeRepositoryProvider =
    Provider<RouteRepository>(
        (Ref ref) => RouteRepository(ref.watch(apiClientProvider)));

final NotifierProvider<RouteController, RouteState> routeProvider =
    NotifierProvider<RouteController, RouteState>(RouteController.new);
