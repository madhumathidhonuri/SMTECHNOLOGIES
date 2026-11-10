import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/report_models.dart';
import '../../features/alerts/alerts_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/billing/renewals_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/geofences/geofences_screen.dart';
import '../../features/live_map/live_map_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reports/report_detail_screen.dart';
import '../../features/reports/reports_hub_screen.dart';
import '../../features/reports/screens/primary_engine_on_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/routes/routes_screen.dart';
import '../../features/trips/trips_screen.dart';
import '../../features/vehicle/vehicle_detail_screen.dart';
import '../../features/vehicle/vehicle_menu_screen.dart';
import '../../features/vehicle/screens/vehicle_live_screen.dart';
import '../../features/vehicle/screens/vehicle_playback_screen.dart';
import '../../features/vehicle/screens/vehicle_info_screen.dart';
import '../../features/vehicle/screens/vehicle_alerts_screen.dart';
import '../../features/vehicle/screens/vehicle_settings_screen.dart';
import '../../features/vehicle/screens/fitment_certificate_screen.dart';
import '../../providers/auth_provider.dart';

// ── Stable navigator keys (top-level singletons — never recreated) ───────────
// These must NEVER be created inside a function/provider, or hot-reload
// and Riverpod rebuilds will instantiate duplicate keys that GoRouter places
// into the same widget-child list, causing !keyReservation assertion failures.
final GlobalKey<NavigatorState> _rootKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

// ── Auth-change notifier (used only as GoRouter.refreshListenable) ────────────
// Decoupled from Riverpod rebuilds so that authProvider changes only trigger
// GoRouter's internal redirect logic — NOT a rebuild of MaterialApp.
final _AuthNotifier _authNotifier = _AuthNotifier();

class _AuthNotifier extends ChangeNotifier {
  AuthStage _stage = AuthStage.unknown;
  AuthStage get stage => _stage;

  void update(AuthStage stage) {
    if (_stage == stage) return;
    _stage = stage;
    notifyListeners();
  }
}

// ── Riverpod provider that wires auth → notifier (no GoRouter recreation) ─────
// routerProvider is read ONCE in main.dart (ref.read, not ref.watch).
// This means MaterialApp.router is never rebuilt by Riverpod.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  ref.keepAlive();

  // Keep the singleton notifier in sync with Riverpod auth state.
  ref.listen<AuthState>(authProvider, (AuthState? _, AuthState next) {
    _authNotifier.update(next.stage);
  });

  // Seed current stage immediately (in case provider is read after login).
  _authNotifier.update(ref.read(authProvider).stage);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    refreshListenable: _authNotifier,

    redirect: (BuildContext context, GoRouterState state) {
      final AuthStage current = _authNotifier.stage;
      final String path = state.matchedLocation;

      const Set<String> publicPaths = <String>{
        '/login',
        '/forgot-password',
        '/reset-password',
      };
      final bool isPublic = publicPaths.any(path.startsWith);

      if (current == AuthStage.unknown) {
        return path == '/splash' ? null : '/splash';
      }

      if (current == AuthStage.unauthenticated) {
        return isPublic ? null : '/login';
      }

      if (path == '/splash' || path == '/login') return '/dashboard';

      return null;
    },

    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (BuildContext c, GoRouterState s) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (BuildContext c, GoRouterState s) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (BuildContext c, GoRouterState s) =>
            const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (BuildContext c, GoRouterState s) => ResetPasswordScreen(
          token: s.uri.queryParameters['token'] ?? (s.extra as String? ?? ''),
        ),
      ),

      // ── Authenticated shell (bottom navigation) ──────────────────
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) =>
            AppShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/dashboard',
                builder: (BuildContext c, GoRouterState s) =>
                    const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/map',
                builder: (BuildContext c, GoRouterState s) => LiveMapScreen(
                  focusVehicleId: s.uri.queryParameters['focus'],
                  showTrail: s.uri.queryParameters['trail'] == 'true',
                ),
              ),
            ],
          ),

          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/reports',
                builder: (BuildContext c, GoRouterState s) {
                  final String? typeRaw = s.uri.queryParameters['type'];
                  ReportType? matchedType;
                  if (typeRaw != null && typeRaw.isNotEmpty) {
                    matchedType = ReportType.values.where(
                      (ReportType t) =>
                          t.name.toLowerCase() == typeRaw.toLowerCase() ||
                          t.name.toLowerCase() ==
                              typeRaw.replaceAll('-', '').toLowerCase(),
                    ).firstOrNull;
                  }
                  return ReportsHubScreen(
                    initialVehicleId: s.uri.queryParameters['vehicle'] ??
                        s.uri.queryParameters['vehicleId'],
                    initialType: matchedType,
                    initialFromGeofenceId: s.uri.queryParameters['from'] ??
                        s.uri.queryParameters['fromGeofenceId'],
                    initialToGeofenceId: s.uri.queryParameters['to'] ??
                        s.uri.queryParameters['toGeofenceId'],
                    initialMode: s.uri.queryParameters['mode'],
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/trips',
                builder: (BuildContext c, GoRouterState s) =>
                    const TripsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (BuildContext c, GoRouterState s) =>
                    const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Full-screen routes above the shell ───────────────────────
      GoRoute(
        path: '/vehicle/:id',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => VehicleMenuScreen(
          vehicleId: s.pathParameters['id'] ?? '',
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'detail',
            builder: (BuildContext c, GoRouterState s) => VehicleDetailScreen(
              vehicleId: s.pathParameters['id'] ?? '',
              initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
            path: 'live',
            builder: (BuildContext c, GoRouterState s) =>
                VehicleLiveScreen(vehicleId: s.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: 'history',
            builder: (BuildContext c, GoRouterState s) =>
                VehiclePlaybackScreen(vehicleId: s.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: 'info',
            builder: (BuildContext c, GoRouterState s) =>
                VehicleInfoScreen(vehicleId: s.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: 'alerts',
            builder: (BuildContext c, GoRouterState s) =>
                VehicleAlertsScreen(
                  vehicleId: s.pathParameters['id'] ?? '',
                  alertId: s.uri.queryParameters['alertId'],
                ),
          ),
          GoRoute(
            path: 'settings',
            builder: (BuildContext c, GoRouterState s) =>
                VehicleSettingsScreen(vehicleId: s.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: 'geofences',
            builder: (BuildContext c, GoRouterState s) =>
                GeofencesScreen(vehicleId: s.pathParameters['id']),
          ),
          GoRoute(
            path: 'engine-on',
            builder: (BuildContext c, GoRouterState s) =>
                PrimaryEngineOnScreen(vehicleId: s.pathParameters['id']),
          ),
          GoRoute(
            path: 'fitment-certificate',
            builder: (BuildContext c, GoRouterState s) =>
                FitmentCertificateScreen(
              vehicleId: s.pathParameters['id'] ?? '',
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/fitment-certificate',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => FitmentCertificateScreen(
          vehicleId: s.uri.queryParameters['vehicle'] ??
              s.uri.queryParameters['vehicleId'] ??
              '',
        ),
      ),
      GoRoute(
        path: '/engine-on',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => PrimaryEngineOnScreen(
          vehicleId: s.uri.queryParameters['vehicle'] ??
              s.uri.queryParameters['vehicleId'],
        ),
      ),
      GoRoute(
        path: '/alerts',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => AlertsScreen(
          vehicleId: s.uri.queryParameters['vehicleId'],
          alertId: s.uri.queryParameters['alertId'],
          typeFilter: s.uri.queryParameters['type'],
        ),
      ),
      GoRoute(
        path: '/geofences',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) =>
            GeofencesScreen(vehicleId: s.uri.queryParameters['vehicleId']),
      ),
      GoRoute(
        path: '/renewals',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => const RenewalsScreen(),
      ),
      GoRoute(
        path: '/routes',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => const RoutesScreen(),
      ),
      GoRoute(
        path: '/report-detail/:type',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) {
          final String raw = s.pathParameters['type'] ?? '';
          final ReportType type = ReportType.values.firstWhere(
            (ReportType t) =>
                t.name.toLowerCase() == raw.toLowerCase() ||
                t.name.toLowerCase() == raw.replaceAll('-', '').toLowerCase(),
            orElse: () => ReportType.trip,
          );
          return ReportDetailScreen(
            type: type,
            initialVehicleId: s.uri.queryParameters['vehicle'] ??
                s.uri.queryParameters['vehicleId'],
            initialFromGeofenceId: s.uri.queryParameters['from'] ??
                s.uri.queryParameters['fromGeofenceId'],
            initialToGeofenceId: s.uri.queryParameters['to'] ??
                s.uri.queryParameters['toGeofenceId'],
            initialMode: s.uri.queryParameters['mode'],
          );
        },
      ),
      // Dedicated push-able profile & settings route from dashboard
      GoRoute(
        path: '/profile-settings',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => const ProfileScreen(),
      ),
      // Dedicated push-able map route for vehicle menu (avoids shell GlobalKey conflict)
      GoRoute(
        path: '/vehicle-map',
        parentNavigatorKey: _rootKey,
        builder: (BuildContext c, GoRouterState s) => LiveMapScreen(
          focusVehicleId: s.uri.queryParameters['focus'],
          showTrail: s.uri.queryParameters['trail'] == 'true',
        ),
      ),
    ],

    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.explore_off_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                state.uri.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Back to fleet'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

/// Maps an FCM payload to an in-app destination.
String routeForNotification(Map<String, dynamic> data) {
  final String type = (data['type'] ?? data['alertType'] ?? data['alert_type'] ?? data['event_type'] ?? '').toString().toLowerCase();
  final String? vehicleId =
      (data['vehicleId'] ?? data['vehicle_id'])?.toString();
  final String? alertId =
      (data['alertId'] ?? data['id'])?.toString();

  if (type.contains('renewal') || type.contains('billing')) return '/renewals';
  if (type == 'route_deviation') return '/routes';

  final Map<String, String> query = <String, String>{};
  if (vehicleId != null && vehicleId.isNotEmpty) query['vehicleId'] = vehicleId;
  if (alertId != null && alertId.isNotEmpty) query['alertId'] = alertId;

  if (query.isNotEmpty) {
    return Uri(path: '/alerts', queryParameters: query).toString();
  }
  return '/alerts';
}
