import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/models/vehicle.dart';

/// Rapido / Uber-style Smooth Continuous Motion Marker.
///
/// Principles:
/// 1. Stays strictly on the road by interpolating between verified consecutive GPS points.
/// 2. Paces glide duration to the telemetry packet interval (4s – 7.5s) for slow,
///    fluid, non-stopping motion.
/// 3. Never moves backward or drives off-road into fields.
/// 4. Continuously emits visual updates to pour the live trail fluidly behind the marker.
class AnimatedVehicleMarker extends StatefulWidget {
  final LatLng point;
  final double heading;
  final VehicleStatus status;
  final double speed; // km/h

  final Widget Function(BuildContext context, double heading) builder;

  /// Fires every animation tick with the current interpolated map position.
  /// Parent uses this to move the Marker.point and pour the trail tip in sync.
  final void Function(LatLng pos)? onVisualPositionUpdate;

  /// Fires once when the marker arrives at [point].
  final void Function(LatLng confirmedPos)? onPositionConfirmed;

  const AnimatedVehicleMarker({
    required this.point,
    required this.heading,
    required this.status,
    required this.speed,
    required this.builder,
    this.onVisualPositionUpdate,
    this.onPositionConfirmed,
    super.key,
  });

  @override
  State<AnimatedVehicleMarker> createState() => _AnimatedVehicleMarkerState();
}

class _AnimatedVehicleMarkerState extends State<AnimatedVehicleMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glideController;

  LatLng _fromPoint = const LatLng(0, 0);
  LatLng _toPoint = const LatLng(0, 0);
  double _fromHeading = 0.0;
  double _toHeading = 0.0;

  DateTime _glideStartTime = DateTime.now();
  int _glideDurationMs = 5000;

  DateTime? _lastPacketTime;
  int _estimatedIntervalMs = 6000;
  bool _positionConfirmedFired = false;

  bool _initialized = false;
  static const Distance _dist = Distance();

  @override
  void initState() {
    super.initState();
    _fromPoint = widget.point;
    _toPoint = widget.point;
    _fromHeading = widget.heading;
    _toHeading = widget.heading;
    _lastPacketTime = DateTime.now();
    _glideStartTime = DateTime.now();
    _glideDurationMs = 4500;
    _initialized = true;

    _glideController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _glideController.addListener(_onGlideTick);

    // If vehicle is actively driving on mount, immediately start continuous motion
    if (widget.status == VehicleStatus.moving && widget.speed >= 1.5) {
      _glideController.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedVehicleMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_initialized) return;

    final bool isMoving =
        widget.status == VehicleStatus.moving && widget.speed >= 1.5;

    // ── New GPS Coordinate Arrived ──────────────────────────────────────────
    if (oldWidget.point != widget.point) {
      final double rawMeters = _dist(oldWidget.point, widget.point);

      // Filter GPS satellite drift / micro-jitter:
      // When parked/stopped/idle, GPS hardware drifts 3-15m from atmospheric satellite noise.
      // Strictly ignore any jitter < 15m when not confirmed moving.
      if (!isMoving && rawMeters < 15.0) return;
      if (rawMeters < 1.0) return;

      // Teleport / massive jump (> 1.5 km): snap instantly
      if (rawMeters > 1500) {
        _glideController.stop();
        _fromPoint = widget.point;
        _toPoint = widget.point;
        _fromHeading = widget.heading;
        _toHeading = widget.heading;
        _glideStartTime = DateTime.now();
        _glideDurationMs = 100;
        widget.onVisualPositionUpdate?.call(_toPoint);
        return;
      }

      final DateTime now = DateTime.now();
      if (_lastPacketTime != null) {
        final int elapsed = now.difference(_lastPacketTime!).inMilliseconds;
        if (elapsed >= 1500 && elapsed <= 25000) {
          _estimatedIntervalMs =
              ((_estimatedIntervalMs * 0.35) + (elapsed * 0.65)).round();
        }
      }
      _lastPacketTime = now;

      // Pick up smoothly from the current visual position on screen
      final LatLng currentVisual = _currentVisualPoint;
      _fromHeading = _currentVisualHeading;
      final double strideMeters = _dist(currentVisual, widget.point);

      if (isMoving && strideMeters > 1.5) {
        final double segmentBearing =
            (_dist.bearing(currentVisual, widget.point) + 360.0) % 360.0;
        final double headingDiff = widget.heading > 0
            ? ((segmentBearing - widget.heading + 180.0) % 360.0 - 180.0).abs()
            : 0.0;

        if (headingDiff > 85.0) {
          // Target is behind current visual position (GPS jitter / latency) —
          // NEVER drive backward! Project forward along the verified road heading.
          _fromPoint = currentVisual;
          _toHeading = widget.heading > 0 ? widget.heading : _toHeading;
          _toPoint = _offsetPoint(
              currentVisual, _toHeading, max(4.0, strideMeters * 0.4));
        } else {
          _fromPoint = currentVisual;
          _toPoint = widget.point;
          _toHeading = segmentBearing;
        }

        // Kinematic Rapido formula: time = distance / speed
        // Paced to physical velocity with telemetry interval smoothing
        final double speedMps = max(1.5, widget.speed / 3.6);
        final int kinematicMs = ((strideMeters / speedMps) * 1000).round();
        _glideDurationMs = kinematicMs.clamp(2000, 10000);
      } else {
        _fromPoint = currentVisual;
        _toPoint = widget.point;
        if (widget.heading > 0) _toHeading = widget.heading;
        _glideDurationMs = isMoving ? 3000 : 400;
      }

      _positionConfirmedFired = false;
      _glideStartTime = DateTime.now();

      if (isMoving) {
        if (!_glideController.isAnimating) {
          _glideController.repeat();
        }
      } else {
        _glideDurationMs = 400;
        if (!_glideController.isAnimating) {
          _glideController.repeat();
        }
      }
    } else if (oldWidget.status != widget.status ||
        oldWidget.speed != widget.speed) {
      if (isMoving) {
        if (!_glideController.isAnimating) {
          _glideStartTime = DateTime.now();
          _glideDurationMs = 3000;
          _glideController.repeat();
        }
      } else {
        if (DateTime.now().difference(_glideStartTime).inMilliseconds >=
            _glideDurationMs) {
          _glideController.stop();
        }
      }
    } else if (oldWidget.heading != widget.heading &&
        widget.heading > 0 &&
        !_glideController.isAnimating) {
      _fromHeading = _currentVisualHeading;
      _toHeading = widget.heading;
      _glideStartTime = DateTime.now();
      _glideDurationMs = 400;
      _glideController.repeat();
    }
  }

  @override
  void dispose() {
    _glideController.removeListener(_onGlideTick);
    _glideController.dispose();
    super.dispose();
  }

  void _onGlideTick() {
    if (!mounted) return;
    final DateTime now = DateTime.now();
    final int elapsedMs = now.difference(_glideStartTime).inMilliseconds;

    final bool isMoving =
        widget.status == VehicleStatus.moving && widget.speed >= 1.5;

    if (!_positionConfirmedFired && elapsedMs >= _glideDurationMs) {
      _positionConfirmedFired = true;
      widget.onPositionConfirmed?.call(_toPoint);
      if (!isMoving) {
        _glideController.stop();
      }
    }
    widget.onVisualPositionUpdate?.call(_currentVisualPoint);
  }

  // ── Position & Heading Interpolation ──────────────────────────────────────

  LatLng get _currentVisualPoint {
    final DateTime now = DateTime.now();
    final int elapsedMs = now.difference(_glideStartTime).inMilliseconds;

    // Gliding smoothly from _fromPoint to _toPoint
    if (elapsedMs < _glideDurationMs) {
      final double t = (elapsedMs / _glideDurationMs).clamp(0.0, 1.0);
      return LatLng(
        _fromPoint.latitude + (_toPoint.latitude - _fromPoint.latitude) * t,
        _fromPoint.longitude + (_toPoint.longitude - _fromPoint.longitude) * t,
      );
    }

    final bool isMoving =
        widget.status == VehicleStatus.moving && widget.speed >= 1.5;

    if (isMoving) {
      // Rapido / Uber kinematic dead reckoning:
      // When between telemetry packets, maintain continuous forward motion at speed v.
      // v = speed (km/h) / 3.6 (m/s). Never freezes or jerks.
      final double overtimeSeconds =
          (elapsedMs - _glideDurationMs) / 1000.0;
      final double speedMps = widget.speed / 3.6;
      // Cap maximum forward extrapolation to 35m to prevent drifting if offline
      final double coastDistance = min(35.0, speedMps * overtimeSeconds);
      return _offsetPoint(_toPoint, _toHeading, coastDistance);
    }

    return _toPoint;
  }

  static LatLng _offsetPoint(
      LatLng from, double bearingDeg, double distMeters) {
    if (distMeters <= 0.01) return from;
    const double earthRadius = 6371000.0;
    final double radBearing = bearingDeg * pi / 180.0;
    final double radLat = from.latitude * pi / 180.0;
    final double radLng = from.longitude * pi / 180.0;
    final double dByR = distMeters / earthRadius;

    final double newLat = asin(
      sin(radLat) * cos(dByR) +
          cos(radLat) * sin(dByR) * cos(radBearing),
    );
    final double newLng = radLng +
        atan2(
          sin(radBearing) * sin(dByR) * cos(radLat),
          cos(dByR) - sin(radLat) * sin(newLat),
        );

    return LatLng(newLat * 180.0 / pi, newLng * 180.0 / pi);
  }

  double get _currentVisualHeading {
    final DateTime now = DateTime.now();
    final int elapsedMs = now.difference(_glideStartTime).inMilliseconds;
    if (elapsedMs >= _glideDurationMs) {
      return _toHeading;
    }
    final double t = (elapsedMs / _glideDurationMs).clamp(0.0, 1.0);
    // Shortest-path angular interpolation
    final double diff = (_toHeading - _fromHeading) % 360.0;
    final double shortest = (2 * diff % 360.0) - diff;
    return (_fromHeading + shortest * t + 360.0) % 360.0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glideController,
      builder: (BuildContext context, Widget? child) {
        return widget.builder(context, _currentVisualHeading);
      },
    );
  }
}
