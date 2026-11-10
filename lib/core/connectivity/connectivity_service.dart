import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Wraps `connectivity_plus` into a simple online/offline boolean stream.
///
/// Note: `connectivity_plus` reports *interface* availability, not true
/// reachability (captive portals lie). The app therefore treats this as a
/// hint for the banner, while the real source of truth for a failed call
/// remains the Dio error itself.
class ConnectivityService {
  ConnectivityService([Connectivity? c]) : _connectivity = c ?? Connectivity();

  final Connectivity _connectivity;

  final StreamController<bool> _ctrl = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  Stream<bool> get onStatusChange => _ctrl.stream;

  Future<void> initialize() async {
    try {
      final List<ConnectivityResult> initial =
          await _connectivity.checkConnectivity();
      _update(initial, emit: false);
    } catch (e) {
      debugPrint('[connectivity] initial check failed: $e');
      _isOnline = true; // fail open — never block the UI on a plugin error
    }

    _sub = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> r) => _update(r),
      onError: (Object e) => debugPrint('[connectivity] stream error: $e'),
    );
  }

  void _update(List<ConnectivityResult> results, {bool emit = true}) {
    final bool online = results.isNotEmpty &&
        results.any((ConnectivityResult r) => r != ConnectivityResult.none);

    if (online == _isOnline) return;
    _isOnline = online;
    if (emit && !_ctrl.isClosed) _ctrl.add(online);
    debugPrint('[connectivity] ${online ? 'ONLINE' : 'OFFLINE'}');
  }

  Future<bool> check() async {
    try {
      final List<ConnectivityResult> r = await _connectivity.checkConnectivity();
      _update(r);
      return _isOnline;
    } catch (_) {
      return _isOnline;
    }
  }

  void dispose() {
    _sub?.cancel();
    _ctrl.close();
  }
}
