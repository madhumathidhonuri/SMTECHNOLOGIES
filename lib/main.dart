import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/config/app_config.dart';
import 'core/config/brand_config.dart';
import 'core/crashlytics/crash_reporter.dart';
import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/secure_store.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/core_providers.dart';
import 'providers/fleet_provider.dart';
import 'providers/lifecycle_provider.dart';
import 'providers/safety_parking_provider.dart';
import 'shared/widgets/connectivity_banner.dart';
import 'shared/widgets/safety_parking_theft_overlay.dart';

Future<void> main() async {
  final WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    try {
      FlutterNativeSplash.preserve(widgetsBinding: binding);
    } catch (_) {}
  }

  // Portrait-only: a fleet map in landscape on a phone is worse, not better,
  // and it doubles the layout surface we have to QA.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  // ── Firebase + Crashlytics ───────────────────────────────────────────────
  // Firebase must be fully initialised before we attach any error handlers,
  // otherwise recordError() calls will silently fail.
  try {
    if (!kIsWeb) {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      // Init Crashlytics: enables collection only in production, sets the
      // app_environment custom key so every report is labelled correctly.
      await CrashReporter.init();
    }
  } catch (e) {
    debugPrint('[main] Firebase init failed: $e');
  }

  final SecureStore store = await SecureStore.create();
  AppConfig.noDataThresholdHours = store.nodataThresholdHours;

  // ── Flutter framework errors ─────────────────────────────────────────────
  // FlutterError.onError captures errors thrown inside the Flutter widget
  // framework: build(), layout, paint, and gesture-recogniser errors.
  FlutterError.onError = (FlutterErrorDetails details) {
    final String msg = details.exceptionAsString();
    // In Flutter Web / Riverpod transitions, defunct element assertions are
    // non-fatal debug framework assertions that can occur during route popping.
    if (msg.contains('_lifecycleState != _ElementLifecycle.defunct') ||
        msg.contains('defunct') ||
        msg.contains('_dependents.isEmpty') ||
        msg.contains('Cannot hit test a render box')) {
      return;
    }
    FlutterError.presentError(details);
    if (!kIsWeb) {
      CrashReporter.recordError(
        details.exception,
        details.stack,
        reason: 'Flutter framework error: ${details.library ?? "unknown"}',
        fatal: true,
      );
    }
  };

  // ── Dart async / platform channel errors ────────────────────────────────
  // PlatformDispatcher.onError catches every Dart error that escapes a
  // Zone — async gaps, Future chains, isolate errors routed to the main
  // isolate. This is the modern replacement for runZonedGuarded().
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final String errorStr = error.toString();
    if (errorStr.contains('_lifecycleState != _ElementLifecycle.defunct') ||
        errorStr.contains('defunct') ||
        errorStr.contains('_dependents.isEmpty') ||
        errorStr.contains('Cannot hit test a render box')) {
      return true;
    }
    if (!kIsWeb) {
      CrashReporter.recordError(
        error,
        stack,
        reason: 'Unhandled platform/async error',
        fatal: true,
      );
    }
    return true; // Returning true suppresses the default uncaught-error log.
  };

  if (!kIsWeb) {
    try {
      FlutterNativeSplash.remove();
    } catch (_) {}
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        secureStoreProvider.overrideWithValue(store),
      ],
      child: const DealerFleetApp(),
    ),
  );
}

class DealerFleetApp extends ConsumerStatefulWidget {
  const DealerFleetApp({super.key});

  @override
  ConsumerState<DealerFleetApp> createState() => _DealerFleetAppState();
}

class _DealerFleetAppState extends ConsumerState<DealerFleetApp> {
  PushService? _push;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // 1 ─ Connectivity watcher (drives the offline banner).
    await ref.read(connectivityServiceProvider).initialize();

    // 2 ─ Resolve the session: cached user renders instantly, /auth/me confirms.
    await ref.read(authProvider.notifier).bootstrap();

    // 3 ─ Push notifications — the only channel while backgrounded.
    if (!kIsWeb) {
      unawaited(_initPush());
    }
  }

  Future<void> _initPush() async {
    if (kIsWeb) {
      debugPrint('[main] Skipping push notifications on Web (no Firebase config)');
      return;
    }
    
    try {
      final PushService push = PushService(
        onTokenRefresh: (String token) async {
          await ref.read(secureStoreProvider).writeFcmToken(token);
          if (ref.read(authProvider).isAuthenticated) {
            await ref.read(authRepositoryProvider).registerDevice(
                  fcmToken: token,
                  platform: defaultTargetPlatform == TargetPlatform.iOS
                      ? 'ios'
                      : 'android',
                );
          }
        },
        onNotificationTap: _handleNotificationTap,
        onForegroundMessage: _handleForegroundMessage,
        isNotificationEnabled: (String type) {
          final NotificationPreferences prefs =
              ref.read(notificationPreferencesProvider);
          return switch (type.toLowerCase()) {
            'sos' ||
            'panic' ||
            'crash' ||
            'accident' ||
            'tow' ||
            'power_cut' =>
              prefs.sos,
            'theft' || 'theft_alarm' || 'safety_park' || 'tamper' => prefs.theft,
            'overspeed' || 'overspeeding' => prefs.overspeed,
            'geofence_enter' ||
            'geofenceenter' ||
            'geofence_exit' ||
            'geofenceexit' =>
              prefs.geofence,
            'ignition_on' ||
            'ignition_off' ||
            'moving' ||
            'start_moving' ||
            'trip_started' ||
            'trip_start' ||
            'trip' ||
            'stopped' ||
            'idle' ||
            'stoppage' =>
              prefs.ignition,
            'harsh_braking' || 'harsh_acceleration' || 'harsh_driving' || 'harsh' => false,
            _ => true,
          };
        },
      );

      await push.initialize();
      _push = push;

      // Ask for notification permissions so Android 13+ users actually receive them
      final bool hasPerm = await push.requestPermission();
      if (hasPerm) {
        await push.syncToken();
      }

      final String? orgId = ref.read(authProvider).user?.orgId;
      if (orgId != null && orgId.isNotEmpty) {
        await push.subscribeToOrg(orgId);
      }
    } catch (e) {
      debugPrint('[main] push init failed: $e');
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    if (!mounted) return;
    final String type = (data['type'] ?? data['alertType'] ?? data['alert_type'] ?? '').toString().toLowerCase();
    final bool isTheft = data['isTheft'] == 'true' ||
        data['isTheft'] == true ||
        type == 'safety_park' ||
        type == 'theft_alarm' ||
        type == 'theft';
    if (isTheft) {
      ref.read(safetyParkingProvider.notifier).handleAlertJson(data);
    }
    final String route = routeForNotification(data);
    try {
      ref.read(routerProvider).go(route);
    } catch (e) {
      debugPrint('[main] notification deep link failed: $e');
    }
  }

  void _handleForegroundMessage(Map<String, dynamic> data) {
    final String type = (data['type'] ?? data['alertType'] ?? data['alert_type'] ?? '').toString().toLowerCase();
    final bool isTheft = data['isTheft'] == 'true' ||
        data['isTheft'] == true ||
        type == 'safety_park' ||
        type == 'theft_alarm' ||
        type == 'theft';
    if (isTheft) {
      ref.read(safetyParkingProvider.notifier).handleAlertJson(data);
    }
    // A push may indicate state we have not seen yet.
    if (ref.read(authProvider).isAuthenticated) {
      unawaited(ref.read(fleetProvider.notifier).load(silent: true));
    }
  }

  @override
  void dispose() {
    _push?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT: Use ref.read (not ref.watch) so MaterialApp.router is never
    // rebuilt by Riverpod state changes. Auth-driven redirects are handled
    // internally by GoRouter's refreshListenable (_authNotifier), which does
    // NOT trigger a widget rebuild — only GoRouter's own redirect logic runs.
    final GoRouter router = ref.read(routerProvider);

    return MaterialApp.router(
      title: BrandConfig.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.light(),
      themeMode: ThemeMode.light,
      builder: (BuildContext context, Widget? child) {
        // Order matters:
        //   AppLifecycleObserver  → enforces the socket battery contract
        //   ConnectivityReconnector → resumes real-time when the net returns
        //   ConnectivityBanner    → persistent offline indicator on top
        return AppLifecycleObserver(
          child: ConnectivityReconnector(
            child: ConnectivityBanner(
              child: SafetyParkingTheftOverlay(
                child: MediaQuery.withClampedTextScaling(
                  minScaleFactor: 0.85,
                  maxScaleFactor: 1.35,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
