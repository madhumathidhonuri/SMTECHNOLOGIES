import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/realtime/socket_service.dart';
import 'auth_provider.dart';
import 'core_providers.dart';
import 'fleet_provider.dart';

/// ─────────────────────────────────────────────────────────────────────
///  APP LIFECYCLE — THE BATTERY CONTRACT
/// ─────────────────────────────────────────────────────────────────────
///
/// This widget is the single place where the background/foreground rule is
/// enforced. Mount it once, above the router.
///
///   paused / detached / hidden →  socket.pauseForBackground()
///                                 (transport closed, reconnection disabled)
///
///   resumed                    →  1. GET /api/vehicles   (authoritative sync)
///                                 2. socket.resumeFromForeground()
///                                 3. re-join org / vehicle rooms
///
/// Ordering matters: reconnecting first would race the REST response and can
/// leave a vehicle rendered at a stale position if a frame lands mid-flight.
class AppLifecycleObserver extends ConsumerStatefulWidget {
  const AppLifecycleObserver({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLifecycleObserver> createState() =>
      _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends ConsumerState<AppLifecycleObserver>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _resyncing = false;

  /// Brief app switches (< 2s) skip the full REST resync — the data cannot
  /// have meaningfully changed and the round-trip would just cost battery.
  static const Duration _resyncThreshold = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _onForeground();
      case AppLifecycleState.inactive:
        // Transient (call overlay, app switcher preview) — do nothing, or we
        // would thrash the socket every time a notification shade opens.
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _onBackground();
    }
  }

  void _onBackground() {
    if (_backgroundedAt != null) return;
    _backgroundedAt = DateTime.now();

    debugPrint('[lifecycle] → background: pausing socket');
    ref.read(socketServiceProvider).pauseForBackground();
    ref.read(fleetProvider.notifier).detachSocket();
  }

  Future<void> _onForeground() async {
    final DateTime? since = _backgroundedAt;
    _backgroundedAt = null;

    if (since == null) return;
    if (_resyncing) return;

    final bool authenticated = ref.read(authProvider).isAuthenticated;
    if (!authenticated) return;

    final Duration away = DateTime.now().difference(since);
    debugPrint('[lifecycle] → foreground after ${away.inSeconds}s');

    _resyncing = true;
    try {
      final bool online = ref.read(isOnlineProvider);

      if (!online) {
        debugPrint('[lifecycle] offline — deferring socket reconnect');
        return;
      }

      if (away > _resyncThreshold) {
        // 1 ─ Authoritative REST sync. Use silent=false so isRefreshing=true
        // is set immediately — the UI shows a subtle refresh indicator rather
        // than a blank/empty screen while we wait for the response.
        await ref.read(fleetProvider.notifier).load(silent: false);
      }

      // 2 ─ Reconnect and 3 ─ re-join rooms (handled inside the service).
      final SocketService socket = ref.read(socketServiceProvider);
      await socket.resumeFromForeground();
      ref.read(fleetProvider.notifier).attachSocket();
    } finally {
      _resyncing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Reconnects automatically when connectivity is restored while foregrounded.
class ConnectivityReconnector extends ConsumerStatefulWidget {
  const ConnectivityReconnector({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<ConnectivityReconnector> createState() =>
      _ConnectivityReconnectorState();
}

class _ConnectivityReconnectorState
    extends ConsumerState<ConnectivityReconnector> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(connectivityProvider,
        (AsyncValue<bool>? prev, AsyncValue<bool> next) {
      final bool? online = next.value;
      if (online == null || !online) {
        _debounce?.cancel();
        return;
      }

      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (ref.read(authProvider).isAuthenticated) {
          final SocketService socket = ref.read(socketServiceProvider);
          if (!socket.isSuspended) {
            unawaited(socket.connect());
            unawaited(ref.read(fleetProvider.notifier).load(silent: true));
          }
        }
      });
    });

    return widget.child;
  }
}
