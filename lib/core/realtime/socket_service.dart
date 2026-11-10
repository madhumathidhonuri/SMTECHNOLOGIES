import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';

/// Connection state surfaced to the UI (the small "Live / Reconnecting" pill).
enum SocketStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  error
}

/// A parsed real-time frame.
class SocketEvent {
  const SocketEvent(this.name, this.payload);
  final String name;
  final Map<String, dynamic> payload;
}

/// ─────────────────────────────────────────────────────────────────────
///  BATTERY-AWARE SOCKET.IO SERVICE
/// ─────────────────────────────────────────────────────────────────────
///
/// Hard rules enforced here (per the production spec):
///
///  1. **Never connected in the background.** [pauseForBackground] is called
///     by the lifecycle observer the moment the app is paused/detached and
///     tears the transport down immediately — no lingering pings, no wake
///     locks, no battery drain. Background alerts arrive via FCM instead.
///  2. **Foreground resume is REST-first.** The app re-fetches vehicle state
///     over HTTP (so we never render a stale map) and only then reconnects.
///  3. **Rooms are re-joined idempotently** after every (re)connect, because
///     Socket.io room membership is per-connection and is lost on drop.
///
/// The service owns no UI and no models — it emits raw maps that repositories
/// and providers translate. That keeps it trivially unit-testable.
class SocketService {
  SocketService({required Future<String?> Function() tokenProvider})
      : _tokenProvider = tokenProvider;

  final Future<String?> Function() _tokenProvider;

  io.Socket? _socket;

  final StreamController<SocketStatus> _statusCtrl =
      StreamController<SocketStatus>.broadcast();
  final StreamController<SocketEvent> _eventCtrl =
      StreamController<SocketEvent>.broadcast();

  Stream<SocketStatus> get status$ => _statusCtrl.stream;
  Stream<SocketEvent> get events$ => _eventCtrl.stream;

  SocketStatus _status = SocketStatus.idle;
  SocketStatus get status => _status;
  bool get isConnected => _socket?.connected ?? false;

  /// Rooms we should be in. Survives disconnects so we can re-join on connect.
  final Set<String> _orgRooms = <String>{};
  final Set<String> _vehicleRooms = <String>{};

  /// True while the app is backgrounded — blocks accidental reconnects
  /// triggered by late-arriving async callbacks.
  bool _suspended = false;
  bool get isSuspended => _suspended;

  /// Events the customer app cares about.
  static const List<String> _listenEvents = <String>[
    'fleet:update',
    'vehicle:update',
    'location:update',
    'position:update',
    'positions',
    'alert:new',
    'geofence:event',
    'vehicle:safety_park',
    'vehicle:status',
    'vehicle:state',
    'data:update',
    'device:status',
  ];

  void _setStatus(SocketStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_statusCtrl.isClosed) _statusCtrl.add(s);
    _log('status → ${s.name}');
  }

  // ── Lifecycle ────────────────────────────────────────────────────

  /// Connects (or reuses) the socket. Safe to call repeatedly.
  Future<void> connect() async {
    if (_suspended) {
      _log('connect() ignored — app is backgrounded');
      return;
    }
    if (_socket != null && _socket!.connected) {
      _setStatus(SocketStatus.connected);
      return;
    }

    final String? token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      _log('connect() aborted — no JWT');
      _setStatus(SocketStatus.disconnected);
      return;
    }

    // Dispose any half-dead instance before building a new one.
    _teardown();
    _setStatus(SocketStatus.connecting);

    final io.Socket socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          // Socket.io is mounted at the server root, NOT under /api.
          .setPath(AppConfig.socketPath)
          .setAuth(<String, dynamic>{'token': token})
          .setExtraHeaders(<String, dynamic>{'Authorization': 'Bearer $token'})
          .setQuery(<String, dynamic>{
            'token': token,
            'auth': token,
          })
          .setTransports(<String>['websocket', 'polling'])
          .enableForceNew()
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(AppConfig.socketReconnectAttempts)
          .setReconnectionDelay(AppConfig.socketReconnectDelay.inMilliseconds)
          .setReconnectionDelayMax(
              AppConfig.socketReconnectDelayMax.inMilliseconds)
          .setTimeout(15000)
          .build(),
    );

    _socket = socket;
    _wire(socket);
    socket.connect();
  }

  void _wire(io.Socket socket) {
    socket.onConnect((dynamic _) {
      _log('connected (${socket.id})');
      _setStatus(SocketStatus.connected);
      _rejoinRooms();
    });

    socket.onDisconnect((dynamic reason) {
      _log('disconnected: $reason');
      if (!_suspended) _setStatus(SocketStatus.disconnected);
    });

    socket.onConnectError((dynamic err) {
      _log('connect_error: $err');
      if (!_suspended) _setStatus(SocketStatus.error);
    });

    socket.onError((dynamic err) => _log('error: $err'));

    socket.onReconnect((dynamic _) {
      _log('reconnected');
      _setStatus(SocketStatus.connected);
      _rejoinRooms();
    });

    socket.onReconnectAttempt((dynamic n) {
      if (!_suspended) _setStatus(SocketStatus.reconnecting);
    });

    socket.onReconnectFailed((dynamic _) {
      _log('reconnect failed — giving up until next foreground');
      _setStatus(SocketStatus.error);
    });

    for (final String event in _listenEvents) {
      socket.on(event, (dynamic data) => _emit(event, data));
    }
  }

  void _emit(String name, dynamic data) {
    if (_eventCtrl.isClosed) return;

    Map<String, dynamic>? payload;
    if (data is Map<String, dynamic>) {
      payload = data;
    } else if (data is Map) {
      payload = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty) {
      // Some servers emit `[payload]` or `[payload, ack]`.
      final Object? first = data.first;
      if (first is Map) payload = Map<String, dynamic>.from(first);
    }

    if (payload == null) return;
    _eventCtrl.add(SocketEvent(name, payload));
  }

  // ── Rooms ────────────────────────────────────────────────────────

  final Set<String> _userRooms = <String>{};

  /// Joins `org:{orgId}` — the firehose of updates for the whole fleet.
  void joinOrg(String orgId) {
    if (orgId.isEmpty) return;
    _orgRooms.add(orgId);
    if (isConnected) {
      _socket!
        ..emit('join:org', <String, dynamic>{'orgId': orgId})
        ..emit('join', <String, dynamic>{'room': 'org:$orgId'});
      _log('joined org:$orgId');
    }
  }

  void joinUser(String userId) {
    if (userId.isEmpty) return;
    _userRooms.add(userId);
    if (isConnected) {
      _socket!
        ..emit('join:user', <String, dynamic>{'userId': userId})
        ..emit('join', <String, dynamic>{'room': 'user:$userId'});
      _log('joined user:$userId');
    }
  }

  /// Joins `vehicle:{vehicleId}` for high-frequency single-vehicle follow.
  void joinVehicle(String vehicleId) {
    if (vehicleId.isEmpty) return;
    _vehicleRooms.add(vehicleId);
    if (isConnected) {
      _socket!
        ..emit('join:vehicle', <String, dynamic>{'vehicleId': vehicleId})
        ..emit('join', <String, dynamic>{'room': 'vehicle:$vehicleId'});
      _log('joined vehicle:$vehicleId');
    }
  }

  /// Leaves a vehicle room when the detail screen is popped, so the server
  /// stops pushing 1Hz frames we no longer render.
  void leaveVehicle(String vehicleId) {
    _vehicleRooms.remove(vehicleId);
    if (isConnected) {
      _socket!
        ..emit('leave:vehicle', <String, dynamic>{'vehicleId': vehicleId})
        ..emit('leave', <String, dynamic>{'room': 'vehicle:$vehicleId'});
      _log('left vehicle:$vehicleId');
    }
  }

  void _rejoinRooms() {
    for (final String org in _orgRooms) {
      joinOrg(org);
    }
    for (final String u in _userRooms) {
      joinUser(u);
    }
    for (final String v in _vehicleRooms) {
      joinVehicle(v);
    }
  }

  // ── Background / foreground ──────────────────────────────────────

  void pauseForBackground() {
    if (_suspended) return;
    _log('pausing socket for background');
    _suspended = true;
    _teardown();
  }

  /// Called from `AppLifecycleState.resumed`, *after* the REST re-sync.
  Future<void> resumeFromForeground() async {
    if (!_suspended && isConnected) return;
    _suspended = false;
    _log('resuming socket');
    await connect();
  }

  // ── Teardown ─────────────────────────────────────────────────────

  void _teardown() {
    final io.Socket? s = _socket;
    _socket = null;
    if (s == null) return;
    try {
      s.clearListeners();
      s.dispose();
    } catch (_) {/* already gone */}
  }

  /// Full shutdown on logout: rooms are forgotten too.
  void disconnect() {
    _orgRooms.clear();
    _userRooms.clear();
    _vehicleRooms.clear();
    _teardown();
    _setStatus(SocketStatus.idle);
  }

  void dispose() {
    _teardown();
    _statusCtrl.close();
    _eventCtrl.close();
  }

  void _log(String msg) {
    if (AppConfig.isDebugLoggingEnabled) debugPrint('[socket] $msg');
  }
}
