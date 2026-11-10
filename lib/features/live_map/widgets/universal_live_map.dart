import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/report_models.dart';
import '../../../data/models/trip.dart';
import '../../../data/models/vehicle.dart';
import 'animated_vehicle_marker.dart';
import 'map_tiles.dart';
import 'vehicle_marker.dart';

// ── Widget ────────────────────────────────────────────────────────────────────

class UniversalLiveMap extends StatefulWidget {
  const UniversalLiveMap({
    super.key,
    required this.mapController,
    required this.vehicles,
    required this.style,
    this.apiKey,
    required this.fallbackCenter,
    required this.selectedId,
    required this.followingId,
    this.isFollowPaused = false,
    this.onFollowPausedChanged,
    required this.onMapReady,
    required this.onUserInteracting,
    required this.onTapMap,
    required this.onSelectVehicle,
    this.pendingFocusId,
    this.route = const <TrackPoint>[],
    this.stoppages = const <ReportRow>[],
    this.showTrail = false,
    this.showFullTrail = false,
    this.onTapStoppage,
  });

  final MapController mapController;
  final List<Vehicle> vehicles;
  final MapStyle style;
  final String? apiKey;
  final LatLng fallbackCenter;
  final String? selectedId;
  final String? followingId;
  final bool isFollowPaused;
  final ValueChanged<bool>? onFollowPausedChanged;
  final String? pendingFocusId;
  final VoidCallback onMapReady;
  final ValueChanged<bool> onUserInteracting;
  final VoidCallback onTapMap;
  final ValueChanged<Vehicle> onSelectVehicle;
  final List<TrackPoint> route;
  final List<ReportRow> stoppages;
  final bool showTrail;
  final bool showFullTrail;
  final void Function(ReportRow, int)? onTapStoppage;

  @override
  State<UniversalLiveMap> createState() => _UniversalLiveMapState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _UniversalLiveMapState extends State<UniversalLiveMap> {
  // Current animated visual position of the focused vehicle.
  // Updated by _onVisualPosUpdate on every animation tick.
  LatLng? _activeVisualPos;

  // ── CONFIRMED TRAIL ARCHITECTURE ──────────────────────────────────────────
  //
  // _confirmedTrails[vehicleId] stores ONLY positions that the animated marker
  // has PHYSICALLY REACHED — i.e., the glide animation to that GPS point has
  // completed and onPositionConfirmed fired.
  //
  // This guarantees the trail can NEVER be drawn ahead of the marker.
  //
  // Trail rendered as:  [p0, p1, ..., p_confirmed_last] + [activeVisualPos]
  //  - [p0..p_last] = GPS positions the marker has already arrived at
  //  - [activeVisualPos] = current live position (glide interpolation or
  //    dead-reckoning coast — always at or behind the visual marker)
  final Map<String, List<LatLng>> _confirmedTrails = {};

  bool _isUserInteracting = false;
  Timer? _autoResumeTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    const Distance dist = Distance();
    // Seed each vehicle with its current GPS as the start of the confirmed trail.
    for (final v in widget.vehicles) {
      if (v.hasLocation) {
        _confirmedTrails[v.id] = <LatLng>[LatLng(v.latitude!, v.longitude!)];
      }
    }

    final String? activeId = _resolvedActiveId;
    if (activeId != null && widget.route.isNotEmpty) {
      final List<LatLng> routePoints = [];
      for (final TrackPoint tp in widget.route) {
        if (!tp.isValid) continue;
        if (routePoints.isEmpty || dist(routePoints.last, tp.latLng) >= 2.0) {
          routePoints.add(tp.latLng);
        }
      }
      if (routePoints.isNotEmpty) {
        _confirmedTrails[activeId] = routePoints;
      }
    }
  }

  @override
  void didUpdateWidget(UniversalLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    const Distance dist = Distance();

    // Ensure newly-visible vehicles get a seed position and append verified GPS fixes
    for (final v in widget.vehicles) {
      if (!v.hasLocation) continue;
      final LatLng pt = LatLng(v.latitude!, v.longitude!);
      final List<LatLng> trail =
          _confirmedTrails.putIfAbsent(v.id, () => <LatLng>[pt]);
      if (trail.isEmpty) {
        trail.add(pt);
      } else if (v.id != _resolvedActiveId) {
        final double d = dist(trail.last, pt);
        final bool isStationary =
            v.speed <= 2.0 || v.status != VehicleStatus.moving;
        final double minMoveDist = isStationary ? 25.0 : 3.0;
        // Append if moved at least minMoveDist and not an impossible teleport jump (>2km)
        // (Active vehicle trail points are confirmed exclusively via _onPositionConfirmed when reached)
        if (d >= minMoveDist && d < 2000.0) {
          trail.add(pt);
        }
      }
    }

    // Seed/sync active vehicle trail from widget.route when route arrives or expands
    final String? activeId = _resolvedActiveId;
    if (activeId != null && widget.route.isNotEmpty) {
      final List<LatLng> trail =
          _confirmedTrails.putIfAbsent(activeId, () => <LatLng>[]);
      if (trail.length <= 1) {
        final List<LatLng> routePoints = [];
        for (final TrackPoint tp in widget.route) {
          if (!tp.isValid) continue;
          if (routePoints.isEmpty || dist(routePoints.last, tp.latLng) >= 2.0) {
            routePoints.add(tp.latLng);
          }
        }
        if (routePoints.isNotEmpty) {
          trail.clear();
          trail.addAll(routePoints);
        }
      }
    }

    if (widget.followingId != oldWidget.followingId) {
      _autoResumeTimer?.cancel();
      _autoResumeTimer = null;
      if (widget.followingId != null) {
        widget.onFollowPausedChanged?.call(false);
      }
    } else if (oldWidget.isFollowPaused && !widget.isFollowPaused) {
      _autoResumeTimer?.cancel();
      _autoResumeTimer = null;
    }
  }

  @override
  void dispose() {
    _autoResumeTimer?.cancel();
    super.dispose();
  }

  String? get _resolvedActiveId =>
      widget.selectedId ??
      widget.followingId ??
      widget.pendingFocusId ??
      (widget.vehicles.isNotEmpty ? widget.vehicles.first.id : null);

  // ── Camera Follow Logic ───────────────────────────────────────────────────

  void _pauseFollow() {
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
    if (widget.followingId != null && !widget.isFollowPaused) {
      widget.onFollowPausedChanged?.call(true);
    }
  }

  void _resumeFollow() {
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
    if (widget.followingId != null && widget.isFollowPaused) {
      widget.onFollowPausedChanged?.call(false);
    }

    final LatLng? target = _activeVisualPos;
    if (target != null) {
      final double currentZoom = widget.mapController.camera.zoom;
      final double targetZoom = currentZoom < 14.0 ? 15.5 : currentZoom;
      widget.mapController.move(target, targetZoom);
    }
  }

  // ── Callbacks from AnimatedVehicleMarker ───────────────────────────────────

  /// Called when the glide animation completes — marker physically reached [pos].
  /// Safe to call setState: animation status listeners fire in
  /// SchedulerPhase.animating (transient callbacks), before the build phase.
  void _onPositionConfirmed(LatLng pos) {
    final String? activeId = _resolvedActiveId;
    if (activeId == null) return;
    final List<LatLng> trail =
        _confirmedTrails.putIfAbsent(activeId, () => <LatLng>[pos]);
    const Distance d = Distance();

    // Suppress drift if vehicle is stationary / parked
    Vehicle? v;
    try {
      v = widget.vehicles.firstWhere((x) => x.id == activeId);
    } catch (_) {}

    final bool isStationary =
        v != null && (v.speed <= 2.0 || v.status != VehicleStatus.moving);
    final double minMoveThreshold = isStationary ? 25.0 : 1.5;

    if (trail.isEmpty || d(trail.last, pos) >= minMoveThreshold) {
      trail.add(pos);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// Called every animation tick (glide + smooth line pouring).
  /// Animation ticks fire in SchedulerPhase.animating (before build) —
  /// setState is safe and keeps the trail tip in the same frame as the marker.
  void _onVisualPosUpdate(LatLng pos) {
    final String? activeId = _resolvedActiveId;
    if (activeId == null) return;

    // Debounce: skip rebuilds only for imperceptible micro-jitter (<0.02m)
    if (_activeVisualPos != null) {
      const Distance d = Distance();
      if (d(_activeVisualPos!, pos) < 0.02) return;
    }

    setState(() => _activeVisualPos = pos);

    if (widget.followingId != null) {
      if (!_isUserInteracting && !widget.isFollowPaused) {
        if (widget.mapController.camera.rotation != 0) {
          widget.mapController.moveAndRotate(
            pos,
            widget.mapController.camera.zoom,
            0.0,
          );
        } else {
          widget.mapController.move(pos, widget.mapController.camera.zoom);
        }
      } else if (!_isUserInteracting && widget.isFollowPaused) {
        // Vehicle is moving while camera follow is paused.
        // If vehicle approaches within 15% margin of screen boundaries, auto-resume follow!
        try {
          final camera = widget.mapController.camera;
          final math.Point<double> screenPoint =
              camera.latLngToScreenPoint(pos);
          final math.Point<double> size = camera.nonRotatedSize;
          if (size.x > 50 && size.y > 50) {
            final double marginX = size.x * 0.15;
            final double marginY = size.y * 0.15;
            final bool nearEdge = screenPoint.x < marginX ||
                screenPoint.x > (size.x - marginX) ||
                screenPoint.y < marginY ||
                screenPoint.y > (size.y - marginY);

            if (nearEdge) {
              _resumeFollow();
            }
          }
        } catch (_) {}
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final String? activeId = _resolvedActiveId;

    // Active vehicle lookup
    Vehicle? activeV;
    if (activeId != null && activeId.isNotEmpty) {
      activeV = widget.vehicles.cast<Vehicle?>().firstWhere(
            (v) => v?.id == activeId,
            orElse: () => null,
          );
    }

    // activeVisualPos: the animated position fed back from AnimatedVehicleMarker.
    // Falls back to latest GPS only until the first animation tick fires —
    // this is correct because the vehicle IS at its last GPS position initially.
    final LatLng? activeVisualPos = (activeV != null && activeV.hasLocation)
        ? (_activeVisualPos ?? LatLng(activeV.latitude!, activeV.longitude!))
        : null;

    // ── Trail polylines ──────────────────────────────────────────────────────
    final List<Polyline> allPolylines = [];

    if (widget.showTrail && activeV != null) {
      const Distance dist = Distance();

      // 1. Gather all base trail points in chronological order
      final List<LatLng> basePoints = [];

      if (widget.route.isNotEmpty) {
        for (final TrackPoint tp in widget.route) {
          if (!tp.isValid) continue;
          if (basePoints.isEmpty || dist(basePoints.last, tp.latLng) >= 1.0) {
            basePoints.add(tp.latLng);
          }
        }
      }

      // If widget.route is empty, use confirmed live trail fixes
      if (basePoints.isEmpty && activeId != null) {
        final List<LatLng>? confirmed = _confirmedTrails[activeId];
        if (confirmed != null && confirmed.isNotEmpty) {
          for (final LatLng pt in confirmed) {
            if (basePoints.isEmpty || dist(basePoints.last, pt) >= 1.0) {
              basePoints.add(pt);
            }
          }
        }
      }

      // Also append any newly confirmed points from _confirmedTrails that extend beyond widget.route
      if (activeId != null &&
          _confirmedTrails.containsKey(activeId) &&
          basePoints.isNotEmpty) {
        final List<LatLng> confirmed = _confirmedTrails[activeId]!;
        final LatLng lastBase = basePoints.last;
        bool isAhead = false;
        for (final LatLng pt in confirmed) {
          if (!isAhead) {
            if (dist(lastBase, pt) < 5.0) {
              isAhead = true;
            }
          } else {
            final bool isStationary =
                (activeV?.speed ?? 0) <= 2.0 || activeV?.status != VehicleStatus.moving;
            final double minAppendDist = isStationary ? 25.0 : 3.0;
            if (dist(basePoints.last, pt) >= minAppendDist &&
                dist(basePoints.last, pt) < 2000.0) {
              basePoints.add(pt);
            }
          }
        }
      }

      // 2. CRITICAL: Strictly truncate basePoints so NO POINT can ever exist ahead of activeVisualPos.
      // The trail MUST terminate exactly at activeVisualPos (the vehicle marker tip).
      if (activeVisualPos != null && basePoints.isNotEmpty) {
        final LatLng V = activeVisualPos;
        const double metersPerDeg = 111319.9;
        final double cosLat = math.cos(V.latitude * math.pi / 180.0);

        int bestSegmentIdx = -1;
        double bestT = 1.0;
        double minPerpDistSq = double.infinity;

        // Search segments from newest (end of route) backwards.
        final int startIdx = math.max(0, basePoints.length - 250);
        for (int i = basePoints.length - 2; i >= startIdx; i--) {
          final LatLng A = basePoints[i];
          final LatLng B = basePoints[i + 1];

          final double abX = (B.longitude - A.longitude) * cosLat * metersPerDeg;
          final double abY = (B.latitude - A.latitude) * metersPerDeg;
          final double abLenSq = abX * abX + abY * abY;
          if (abLenSq < 0.25) continue; // skip sub-meter / identical points

          final double avX = (V.longitude - A.longitude) * cosLat * metersPerDeg;
          final double avY = (V.latitude - A.latitude) * metersPerDeg;

          final double t = (avX * abX + avY * abY) / abLenSq;
          final double clampedT = t.clamp(0.0, 1.0);
          final double projX = clampedT * abX;
          final double projY = clampedT * abY;
          final double distSq = (avX - projX) * (avX - projX) + (avY - projY) * (avY - projY);

          if (distSq < minPerpDistSq) {
            minPerpDistSq = distSq;
            bestSegmentIdx = i;
            bestT = t;
            // If right on top of segment (< 10m) and within segment bounds, match found
            if (distSq < 100.0 && t >= -0.05 && t <= 1.05) {
              break;
            }
          }
        }

        if (bestSegmentIdx != -1 && minPerpDistSq < 10000.0) { // within 100m of road segment
          // Point (bestSegmentIdx + 1) or (bestSegmentIdx + 2) is the cut boundary.
          // Any points after the vehicle's projection must be strictly removed so
          // the green trail NEVER appears ahead of the vehicle marker!
          final int cutIdx =
              (bestT >= 1.0) ? bestSegmentIdx + 2 : bestSegmentIdx + 1;
          if (cutIdx < basePoints.length) {
            basePoints.removeRange(cutIdx, basePoints.length);
          }
        } else {
          // Fallback: if off-road or telemetric jump, find closest single point
          int closestIdx = basePoints.length - 1;
          double minDist = dist(basePoints.last, V);
          final int fallbackStart = math.max(0, basePoints.length - 80);
          for (int i = basePoints.length - 1; i >= fallbackStart; i--) {
            final double d = dist(basePoints[i], V);
            if (d < minDist) {
              minDist = d;
              closestIdx = i;
            }
          }
          if (closestIdx < basePoints.length - 1) {
            basePoints.removeRange(closestIdx + 1, basePoints.length);
          }
        }

        // Attach the live vehicle marker position as the absolute tip of the trail
        if (basePoints.isEmpty) {
          basePoints.add(V);
        } else if (dist(basePoints.last, V) >= 0.5) {
          final bool isStationary =
              (activeV?.speed ?? 0) <= 2.0 || activeV?.status != VehicleStatus.moving;
          if (!isStationary || dist(basePoints.last, V) >= 25.0) {
            basePoints.add(V);
          }
        }
      } else if (activeVisualPos != null) {
        basePoints.add(activeVisualPos);
      }

      // 3. Now split basePoints by large telemetry gaps (>2000m = offline / overnight)
      // and create polylines. Since basePoints was already pruned to terminate at activeVisualPos,
      // no segment can ever extend ahead of the marker!
      final List<LatLng> currentSegment = [];
      LatLng? prevPt;
      for (final LatLng pt in basePoints) {
        if (prevPt != null && dist(prevPt, pt) > 2000.0) {
          if (currentSegment.length >= 2) {
            allPolylines.addAll(_splitPolyline(
              points: List<LatLng>.from(currentSegment),
              color: const Color(0xFF10B981),
              strokeWidth: 4.5,
            ));
          }
          currentSegment.clear();
        }
        currentSegment.add(pt);
        prevPt = pt;
      }
      if (currentSegment.length >= 2) {
        allPolylines.addAll(_splitPolyline(
          points: currentSegment,
          color: const Color(0xFF10B981),
          strokeWidth: 4.5,
        ));
      }
    }

    // ── Stoppage markers ─────────────────────────────────────────────────────
    final List<Marker> pointMarkers = [];
    final Map<String, int> overlapCounts = {};
    for (int i = 0; i < widget.stoppages.length; i++) {
      final stop = widget.stoppages[i];
      final lat = stop.startLat ?? stop.endLat;
      final lng = stop.startLng ?? stop.endLng;
      if (lat == null || lng == null) continue;
      final String overlapKey =
          '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';
      overlapCounts[overlapKey] = (overlapCounts[overlapKey] ?? 0) + 1;
      pointMarkers.add(Marker(
        point: LatLng(lat, lng),
        width: 24,
        height: 30,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onTapStoppage?.call(stop, i + 1),
          child: Center(
            child: CustomPaint(
              size: const Size(24, 30),
              painter: _MessageBubblePainter(
                  number: i + 1, color: const Color(0xFFFF6B6B)),
            ),
          ),
        ),
      ));
    }

    // ── Vehicle markers ──────────────────────────────────────────────────────
    final List<Marker> vehicleMarkers = [];
    for (final Vehicle v in widget.vehicles) {
      if (!v.hasLocation) continue;
      final bool isActive = (v.id == activeId);
      final LatLng markerPos = isActive
          ? (activeVisualPos ?? LatLng(v.latitude!, v.longitude!))
          : LatLng(v.latitude!, v.longitude!);

      vehicleMarkers.add(
        Marker(
          key: ValueKey<String>('marker_${v.id}'),
          point: markerPos,
          width: 44,
          height: 48,
          alignment: const Alignment(0.0,
              -0.89), // Inverted y-axis: sharp needle tip rests directly on GPS road coordinate
          child: AnimatedVehicleMarker(
            point: LatLng(v.latitude!, v.longitude!),
            heading: v.heading,
            status: v.status,
            speed: v.speed,
            onVisualPositionUpdate: isActive ? _onVisualPosUpdate : null,
            onPositionConfirmed: isActive ? _onPositionConfirmed : null,
            builder: (BuildContext context, double heading) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelectVehicle(v),
              child: VehicleMarkerPin(
                vehicle: v,
                selected: v.id == widget.selectedId,
                showLabel: false,
                useSprite: true,
                headingOverride: heading,
              ),
            ),
          ),
        ),
      );
    }

    // ── Resolve initial center directly on active vehicle on frame 0 ─────────
    LatLng resolvedCenter = widget.fallbackCenter;
    if (activeV != null && activeV.hasLocation) {
      resolvedCenter = LatLng(activeV.latitude!, activeV.longitude!);
    } else {
      for (final v in widget.vehicles) {
        if (v.hasLocation) {
          resolvedCenter = LatLng(v.latitude!, v.longitude!);
          break;
        }
      }
    }

    // ── Render ───────────────────────────────────────────────────────────────
    final Widget mapWidget = FlutterMap(
      mapController: widget.mapController,
      options: MapOptions(
        initialCenter: resolvedCenter,
        initialZoom: 16.0,
        minZoom: 2,
        maxZoom: 22.0,
        backgroundColor: widget.style == MapStyle.satellite
            ? const Color(0xFF1D262B)
            : const Color(0xFFE5E9EC),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onMapReady: widget.onMapReady,
        onPointerDown: (_, __) {
          _autoResumeTimer?.cancel();
          _autoResumeTimer = null;
          _isUserInteracting = true;
          widget.onUserInteracting(true);
        },
        onPointerUp: (_, __) {
          _isUserInteracting = false;
          widget.onUserInteracting(false);
          if (widget.followingId != null && widget.isFollowPaused) {
            _autoResumeTimer?.cancel();
            _autoResumeTimer = Timer(const Duration(seconds: 5), () {
              if (mounted &&
                  widget.followingId != null &&
                  widget.isFollowPaused) {
                _resumeFollow();
              }
            });
          }
        },
        onPointerCancel: (_, __) {
          _isUserInteracting = false;
          widget.onUserInteracting(false);
        },
        onPositionChanged: (MapCamera camera, bool hasGesture) {
          if (hasGesture &&
              widget.followingId != null &&
              !widget.isFollowPaused) {
            _pauseFollow();
          }
        },
        onTap: (_, __) => widget.onTapMap(),
      ),
      children: <Widget>[
        buildTileLayer(widget.style, apiKey: widget.apiKey, retina: false),
        if (allPolylines.isNotEmpty) PolylineLayer(polylines: allPolylines),
        if (widget.showTrail && widget.showFullTrail && pointMarkers.isNotEmpty)
          MarkerLayer(markers: pointMarkers),
        MarkerLayer(markers: vehicleMarkers),
      ],
    );

    return mapWidget;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Helper: build a Polyline with round caps/joins
// ─────────────────────────────────────────────────────────────────────────────
List<Polyline> _splitPolyline({
  required List<LatLng> points,
  required Color color,
  double strokeWidth = 4.5,
}) {
  if (points.length < 2) return const <Polyline>[];
  return <Polyline>[
    Polyline(
      points: points,
      strokeWidth: strokeWidth,
      color: color,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stoppage pin painter — teardrop with numbered inner circle
// ─────────────────────────────────────────────────────────────────────────────
class _MessageBubblePainter extends CustomPainter {
  final int number;
  final Color color;
  const _MessageBubblePainter(
      {required this.number, this.color = const Color(0xFFE53935)});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    final ui.Path path = ui.Path();
    final double radius = w / 2;
    path.moveTo(w / 2, h);
    path.quadraticBezierTo(0, h * 0.7, 0, radius);
    path.arcToPoint(Offset(w, radius),
        radius: Radius.circular(radius), clockwise: true);
    path.quadraticBezierTo(w, h * 0.7, w / 2, h);
    path.close();

    canvas.drawPath(path.shift(const Offset(0, 3)), shadowPaint);
    canvas.drawPath(path, paint);

    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);

    final double cx = w / 2;
    final double cy = radius;
    canvas.drawCircle(
        Offset(cx, cy),
        radius * 0.75,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill);

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: number > 9 ? w * 0.40 : w * 0.50,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2.2));
  }

  @override
  bool shouldRepaint(_MessageBubblePainter old) => old.number != number;
}
