import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../core/connectivity/connectivity_service.dart';
import '../core/network/api_client.dart';
import '../core/payments/payment_service.dart';
import '../core/permissions/permission_service.dart';
import '../core/realtime/socket_service.dart';
import '../core/storage/secure_store.dart';
import '../data/repositories/alert_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/billing_repository.dart';
import '../data/repositories/geofence_repository.dart';
import '../data/repositories/report_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import 'fleet_provider.dart';

/// Overridden in `main()` once `SecureStore.create()` resolves.
final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (Ref ref) =>
      throw UnimplementedError('secureStoreProvider must be overridden'),
);

/// Emitted when a 401 survives refresh — the router listens and boots to login.
final StateProvider<int> sessionExpiredTickProvider =
    StateProvider<int>((Ref ref) => 0);

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final SecureStore store = ref.watch(secureStoreProvider);
  return ApiClient.create(
    store: store,
    onSessionExpired: () async {
      await store.clearSession();
      ref.read(sessionExpiredTickProvider.notifier).state++;
    },
  );
});

// ── Repositories ───────────────────────────────────────────────────
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) => AuthRepository(
          ref.watch(apiClientProvider),
          ref.watch(secureStoreProvider),
        ));

final Provider<VehicleRepository> vehicleRepositoryProvider =
    Provider<VehicleRepository>(
        (Ref ref) => VehicleRepository(ref.watch(apiClientProvider)));

final Provider<AlertRepository> alertRepositoryProvider =
    Provider<AlertRepository>(
        (Ref ref) => AlertRepository(
          ref.watch(apiClientProvider),
          ref.watch(secureStoreProvider),
        ));

final Provider<ReportRepository> reportRepositoryProvider =
    Provider<ReportRepository>(
        (Ref ref) => ReportRepository(ref.watch(apiClientProvider), ref));

final Provider<GeofenceRepository> geofenceRepositoryProvider =
    Provider<GeofenceRepository>(
        (Ref ref) => GeofenceRepository(ref.watch(apiClientProvider)));

final Provider<BillingRepository> billingRepositoryProvider =
    Provider<BillingRepository>(
        (Ref ref) => BillingRepository(ref.watch(apiClientProvider)));

// ── Services ───────────────────────────────────────────────────────
final Provider<SocketService> socketServiceProvider =
    Provider<SocketService>((Ref ref) {
  final SecureStore store = ref.watch(secureStoreProvider);
  final SocketService service =
      SocketService(tokenProvider: () => store.readToken());
  ref.onDispose(service.dispose);
  return service;
});

final Provider<ConnectivityService> connectivityServiceProvider =
    Provider<ConnectivityService>((Ref ref) {
  final ConnectivityService service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

/// Online/offline for the persistent banner.
final StreamProvider<bool> connectivityProvider =
    StreamProvider<bool>((Ref ref) {
  final ConnectivityService service = ref.watch(connectivityServiceProvider);
  return service.onStatusChange;
});

final Provider<bool> isOnlineProvider = Provider<bool>((Ref ref) {
  final AsyncValue<bool> stream = ref.watch(connectivityProvider);
  return stream.maybeWhen(
    data: (bool v) => v,
    orElse: () => ref.watch(connectivityServiceProvider).isOnline,
  );
});

/// Swap this override to go live with a real gateway.
final Provider<PaymentService> paymentServiceProvider =
    Provider<PaymentService>((Ref ref) {
  final PaymentService service = DummyPaymentService();
  ref.onDispose(service.dispose);
  return service;
});

final Provider<PermissionService> permissionServiceProvider =
    Provider<PermissionService>((Ref ref) => const PermissionService());

/// Live socket status for the "Live / Reconnecting" pill.
final StreamProvider<SocketStatus> socketStatusProvider =
    StreamProvider<SocketStatus>(
        (Ref ref) => ref.watch(socketServiceProvider).status$);

// ── App-wide UI preferences ────────────────────────────────────────
final NotifierProvider<ThemeModeNotifier, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    return ThemeMode.light;
  }

  Future<void> set(ThemeMode mode) async {
    state = ThemeMode.light;
    await ref.read(secureStoreProvider).setThemeMode('light');
  }
}

class NotificationPreferences extends Equatable {
  const NotificationPreferences({
    required this.sos,
    required this.theft,
    required this.overspeed,
    required this.geofence,
    required this.ignition,
    required this.harsh,
  });

  final bool sos;
  final bool theft;
  final bool overspeed;
  final bool geofence;
  final bool ignition;
  final bool harsh;

  NotificationPreferences copyWith({
    bool? sos,
    bool? theft,
    bool? overspeed,
    bool? geofence,
    bool? ignition,
    bool? harsh,
  }) =>
      NotificationPreferences(
        sos: sos ?? this.sos,
        theft: theft ?? this.theft,
        overspeed: overspeed ?? this.overspeed,
        geofence: geofence ?? this.geofence,
        ignition: ignition ?? this.ignition,
        harsh: harsh ?? this.harsh,
      );

  @override
  List<Object?> get props =>
      <Object?>[sos, theft, overspeed, geofence, ignition, harsh];
}

class NotificationPreferencesNotifier
    extends Notifier<NotificationPreferences> {
  bool _synced = false;

  @override
  NotificationPreferences build() {
    final SecureStore store = ref.watch(secureStoreProvider);
    
    // Kick off a background sync with the server
    if (!_synced) {
      _synced = true;
      Future<void>.microtask(_syncWithServer);
    }

    return NotificationPreferences(
      sos: store.notifSos,
      theft: store.notifTheft,
      overspeed: store.notifOverspeed,
      geofence: store.notifGeofence,
      ignition: store.notifIgnition,
      harsh: store.notifHarsh,
    );
  }

  Future<void> _syncWithServer() async {
    final Map<String, dynamic>? remote =
        await ref.read(alertRepositoryProvider).getPreferences();
    if (remote == null || remote.isEmpty) return;

    final SecureStore store = ref.read(secureStoreProvider);
    final NotificationPreferences next = NotificationPreferences(
      sos: remote['sos'] as bool? ?? store.notifSos,
      theft: remote['theft'] as bool? ?? store.notifTheft,
      overspeed: remote['overspeed'] as bool? ?? store.notifOverspeed,
      geofence: remote['geofence'] as bool? ?? store.notifGeofence,
      ignition: remote['ignition'] as bool? ?? store.notifIgnition,
      harsh: remote['harsh'] as bool? ?? store.notifHarsh,
    );

    if (next != state) {
      await Future.wait(<Future<void>>[
        store.setNotifSos(next.sos),
        store.setNotifTheft(next.theft),
        store.setNotifOverspeed(next.overspeed),
        store.setNotifGeofence(next.geofence),
        store.setNotifIgnition(next.ignition),
        store.setNotifHarsh(next.harsh),
      ]);
      state = next;
    }
  }

  Future<void> _pushToServer(NotificationPreferences prefs) async {
    await ref.read(alertRepositoryProvider).updatePreferences(<String, bool>{
      'sos': prefs.sos,
      'theft': prefs.theft,
      'overspeed': prefs.overspeed,
      'geofence': prefs.geofence,
      'ignition': prefs.ignition,
      'harsh': prefs.harsh,
    });
  }

  Future<void> toggleSos() async {
    final bool nextVal = !state.sos;
    final NotificationPreferences nextState = state.copyWith(sos: nextVal);
    await ref.read(secureStoreProvider).setNotifSos(nextVal);
    state = nextState;
    await _pushToServer(nextState);
  }

  Future<void> toggleTheft() async {
    final bool nextVal = !state.theft;
    final NotificationPreferences nextState = state.copyWith(theft: nextVal);
    await ref.read(secureStoreProvider).setNotifTheft(nextVal);
    state = nextState;
    await _pushToServer(nextState);
  }

  Future<void> toggleOverspeed() async {
    final bool nextVal = !state.overspeed;
    final NotificationPreferences nextState = state.copyWith(overspeed: nextVal);
    await ref.read(secureStoreProvider).setNotifOverspeed(nextVal);
    state = nextState;
    await _pushToServer(nextState);
  }

  Future<void> toggleGeofence() async {
    final bool nextVal = !state.geofence;
    final NotificationPreferences nextState = state.copyWith(geofence: nextVal);
    await ref.read(secureStoreProvider).setNotifGeofence(nextVal);
    state = nextState;
    await _pushToServer(nextState);
  }

  Future<void> toggleIgnition() async {
    final bool nextVal = !state.ignition;
    final NotificationPreferences nextState = state.copyWith(ignition: nextVal);
    await ref.read(secureStoreProvider).setNotifIgnition(nextVal);
    state = nextState;
    await _pushToServer(nextState);
  }

  Future<void> toggleHarsh() async {
    final bool nextVal = !state.harsh;
    final NotificationPreferences nextState = state.copyWith(harsh: nextVal);
    await ref.read(secureStoreProvider).setNotifHarsh(nextVal);
    state = nextState;
    await _pushToServer(nextState);
  }
}

final NotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>
    notificationPreferencesProvider =
    NotifierProvider<NotificationPreferencesNotifier, NotificationPreferences>(
  NotificationPreferencesNotifier.new,
);

// ── No Data Rule Provider ─────────────────────────────────────────────
class NoDataThresholdNotifier extends StateNotifier<double> {
  NoDataThresholdNotifier(this._ref) : super(AppConfig.noDataThresholdHours) {
    _init();
  }

  final Ref _ref;

  void _init() {
    try {
      final double stored = _ref.read(secureStoreProvider).nodataThresholdHours;
      AppConfig.noDataThresholdHours = stored;
      state = stored;
    } catch (_) {}
  }

  Future<void> setThreshold(double hours) async {
    final double val = hours <= 0 ? 1.0 : hours;
    AppConfig.noDataThresholdHours = val;
    state = val;
    await _ref.read(secureStoreProvider).setNodataThresholdHours(val);

    try {
      await _ref.read(alertRepositoryProvider).updatePreferences(<String, dynamic>{
        'nodata_threshold_hours': val,
      });
    } catch (_) {}

    _ref.read(fleetProvider.notifier).refreshVehicleStatuses();
  }
}

final StateNotifierProvider<NoDataThresholdNotifier, double> noDataThresholdProvider =
    StateNotifierProvider<NoDataThresholdNotifier, double>(
  (Ref ref) => NoDataThresholdNotifier(ref),
);


