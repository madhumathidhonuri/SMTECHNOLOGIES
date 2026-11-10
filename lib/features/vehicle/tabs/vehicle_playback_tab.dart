import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as dart_ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/geocoder.dart';
import '../../../data/models/trip.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/fleet_provider.dart';
import '../../../providers/route_provider.dart';
import '../../../providers/trip_provider.dart';
import '../../../data/models/user_trip.dart';
import '../../../shared/widgets/app_states.dart';
import '../../live_map/widgets/map_tiles.dart';
import '../../../core/utils/gps_filter.dart';
import '../../../core/utils/polyline_simplifier.dart';
import '../../../data/models/route.dart';


/// Stoppage / parking event along a historical route.
class StoppageEvent {
  const StoppageEvent({
    required this.lat,
    required this.lng,
    required this.startTime,
    required this.endTime,
    required this.duration,
    this.address,
    this.isOngoing = false,
  });

  final double lat;
  final double lng;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final String? address;
  final bool isOngoing;

  String get durationString => Fmt.durationHms(duration);

  String get compactDuration => Fmt.durationHms(duration);
}

/// Convert any local or UTC DateTime to IST and represent as a UTC DateTime
/// so standard formatters format the IST calendar values directly.
String _toIstString(DateTime? d, String Function(DateTime) formatter) {
  if (d == null) return '—';
  final DateTime utc = d.toUtc();
  final DateTime ist = utc.add(const Duration(hours: 5, minutes: 30));
  final DateTime formatTarget = DateTime.utc(
    ist.year,
    ist.month,
    ist.day,
    ist.hour,
    ist.minute,
    ist.second,
    ist.millisecond,
    ist.microsecond,
  );
  return formatter(formatTarget);
}

String _formatTime(DateTime? d) => _toIstString(d, Fmt.time);
String _formatDateShort(DateTime? d) => _toIstString(d, Fmt.dateShort);

/// Historical route playback.
///
/// The scrubber drives a single index into the point list; the marker,
/// travelled polyline and readouts are all pure functions of that index,
/// which keeps replay smooth and makes scrubbing feel instant.
class VehiclePlaybackTab extends ConsumerStatefulWidget {
  const VehiclePlaybackTab({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  ConsumerState<VehiclePlaybackTab> createState() =>
      _VehiclePlaybackTabState();
}

class _VehiclePlaybackTabState extends ConsumerState<VehiclePlaybackTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  bool _ready = false;

  List<TrackPoint> _points = <TrackPoint>[];
  List<LatLng> _allLatLng = <LatLng>[];
  List<Polyline<Object>> _cachedGhostSegments = <Polyline<Object>>[];
  List<bool> _pointGaps = <bool>[];
  List<double> _cumulativeDistances = <double>[];
  List<StoppageEvent> _stoppages = <StoppageEvent>[];
  bool _loading = false;
  String? _error;

  double _playbackProgress = 0.0;
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);
  Widget? _tileLayer;
  Widget? _ghostPolylineLayer;
  bool _playing = false;
  bool _hasStartedPlayback = false;
  double _speedMultiplier = 1;
  late AnimationController _animController;
  DateTime? _lastTickTime;
  StoppageEvent? _lastEncounteredStoppage;
  double _stoppagePauseRemaining = 0.0;

  static List<StoppageEvent> _computeStoppages(List<TrackPoint> points) {
    if (points.isEmpty) return <StoppageEvent>[];
    final List<StoppageEvent> stops = <StoppageEvent>[];
    TrackPoint? stopStart;
    TrackPoint? stopEnd;
    List<TrackPoint> currentStopPoints = <TrackPoint>[];

    for (int i = 0; i < points.length; i++) {
      final TrackPoint p = points[i];
      if (p.speed <= 3) {
        stopStart ??= p;
        stopEnd = p;
        currentStopPoints.add(p);
      } else {
        if (stopStart != null && stopEnd != null) {
          final Duration diff = stopEnd.timestamp.difference(stopStart.timestamp);
          if (diff.inMinutes >= 5 && stopStart.timestamp != points.first.timestamp) {
            TrackPoint bestPt = stopStart;
            if (currentStopPoints.isNotEmpty) {
              final List<TrackPoint> zeroPts =
                  currentStopPoints.where((TrackPoint tp) => tp.speed == 0).toList();
              if (zeroPts.isNotEmpty) {
                bestPt = zeroPts[zeroPts.length ~/ 2];
              } else {
                bestPt = currentStopPoints.reduce((TrackPoint a, TrackPoint b) =>
                    a.speed <= b.speed ? a : b);
              }
            }
            stops.add(StoppageEvent(
              lat: bestPt.latitude,
              lng: bestPt.longitude,
              startTime: stopStart.timestamp,
              endTime: stopEnd.timestamp,
              duration: diff,
              address: bestPt.address ?? stopStart.address,
            ));
          }
          stopStart = null;
          stopEnd = null;
          currentStopPoints = <TrackPoint>[];
        }
      }
    }

    if (stopStart != null && stopEnd != null) {
      final Duration diff = stopEnd.timestamp.difference(stopStart.timestamp);
      if (diff.inMinutes >= 5 && stopStart.timestamp != points.first.timestamp) {
        TrackPoint bestPt = stopStart;
        if (currentStopPoints.isNotEmpty) {
          final List<TrackPoint> zeroPts =
              currentStopPoints.where((TrackPoint tp) => tp.speed == 0).toList();
          if (zeroPts.isNotEmpty) {
            bestPt = zeroPts[zeroPts.length ~/ 2];
          } else {
            bestPt = currentStopPoints.reduce((TrackPoint a, TrackPoint b) =>
                a.speed <= b.speed ? a : b);
          }
        }
        stops.add(StoppageEvent(
          lat: bestPt.latitude,
          lng: bestPt.longitude,
          startTime: stopStart.timestamp,
          endTime: stopEnd.timestamp,
          duration: diff,
          address: bestPt.address ?? stopStart.address,
          isOngoing: true,
        ));
      }
    }

    return stops;
  }

  StoppageEvent? get _currentStoppage {
    if (_points.isEmpty) return null;
    final TrackPoint cursor = _currentPoint;
    for (final StoppageEvent s in _stoppages) {
      if (!cursor.timestamp.isBefore(s.startTime) &&
          !cursor.timestamp.isAfter(s.endTime)) {
        return s;
      }
    }
    return null;
  }

  TrackPoint get _currentPoint {
    if (_points.isEmpty) {
      return TrackPoint(
        latitude: 0,
        longitude: 0,
        timestamp: DateTime.now(),
      );
    }
    final int idx = _playbackProgress.floor().clamp(0, _points.length - 1);
    if (idx >= _points.length - 1) return _points.last;

    final double t = (_playbackProgress - idx).clamp(0.0, 1.0);
    final TrackPoint a = _points[idx];
    final TrackPoint b = _points[idx + 1];

    final DateTime currentTimestamp = a.timestamp.add(
      Duration(
        milliseconds: (b.timestamp.difference(a.timestamp).inMilliseconds * t).round(),
      ),
    );

    return TrackPoint(
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: a.longitude + (b.longitude - a.longitude) * t,
      timestamp: currentTimestamp,
      speed: a.speed + (b.speed - a.speed) * t,
      heading: a.heading + (b.heading - a.heading) * t,
      ignition: t < 0.5 ? a.ignition : b.ignition,
      address: t < 0.5 ? a.address : b.address,
    );
  }

  /// Only show the stopped card when the stoppage is >= 5 minutes.
  bool get _isCurrentlyStopped {
    if (_points.isEmpty) return false;
    final StoppageEvent? s = _currentStoppage;
    return s != null && s.duration.inMinutes >= 5;
  }

  late DateTimeRange _range = _todayRange();

  @override
  bool get wantKeepAlive => true;

  static DateTimeRange _todayRange() {
    final DateTime now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: now,
    );
  }

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController.unbounded(vsync: this);
    _animController.addListener(_onAnimationTick);
    // REMOVED automatic _load() on init to allow initial selection screen
  }

  @override
  void dispose() {
    _animController.stop();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _load({bool autoPlay = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _playing = false;
      _animController.stop();
      _lastTickTime = null;
    });

    try {
      final DateTime startLocal = _range.start;
      final DateTime endLocal = _range.end;

      final DateTime startIstUtc = DateTime.utc(
        startLocal.year, startLocal.month, startLocal.day,
        startLocal.hour, startLocal.minute, startLocal.second,
      );
      final DateTime endIstUtc = DateTime.utc(
        endLocal.year, endLocal.month, endLocal.day,
        endLocal.hour, endLocal.minute, endLocal.second,
      );

      final DateTime startQuery = startIstUtc.subtract(const Duration(hours: 5, minutes: 30));
      final DateTime endQuery = endIstUtc.subtract(const Duration(hours: 5, minutes: 30));

      final List<TrackPoint> pts =
          await ref.read(vehicleRepositoryProvider).getHistory(
                vehicleId: widget.vehicleId,
                start: startQuery,
                end: endQuery,
              );

      if (!mounted) return;

      // Sort chronologically — the API does not guarantee order.
      pts.sort((TrackPoint a, TrackPoint b) =>
          a.timestamp.compareTo(b.timestamp));

      // Filter strictly within selected UTC query range
      final List<TrackPoint> inRangePoints = pts.where((TrackPoint p) {
        final DateTime utcTime = p.timestamp.toUtc();
        return !utcTime.isBefore(startQuery) && !utcTime.isAfter(endQuery);
      }).toList();

      // Compute actual stoppages from full in-range points before downsampling
      final List<StoppageEvent> computedStops = _computeStoppages(inRangePoints);

      // Filter consecutive duplicates & stationary GPS drift / jitter
      final List<TrackPoint> cleanPoints =
          GpsFilter.filterStationaryDrift(inRangePoints);

      final List<LatLng> cachedLatLng = cleanPoints.map((TrackPoint p) => p.latLng).toList(growable: false);
      const Distance distanceCalc = Distance();
      
      final List<bool> gaps = List<bool>.filled(cachedLatLng.length, false);
      for (int i = 1; i < cachedLatLng.length; i++) {
        final double dist = distanceCalc(cachedLatLng[i - 1], cachedLatLng[i]);
        final Duration timeDiff = cleanPoints[i].timestamp.difference(cleanPoints[i - 1].timestamp).abs();
        // Missing data gap: distance jump > 1000m, or time gap >= 5 minutes with movement > 250m
        if (dist > 1000 || (timeDiff.inMinutes >= 5 && dist > 250)) {
          gaps[i] = true;
        }
      }

      final List<Polyline<Object>> ghostSegs = _buildGhostSegments(
        points: cachedLatLng,
        gaps: gaps,
        normalColor: const Color(0xFF2563EB).withValues(alpha: 0.7),
        gapColor: const Color(0xFFEF4444),
        strokeWidth: 4.0,
      );

      final List<double> dists = List<double>.filled(cachedLatLng.length, 0.0);
      double currentDist = 0.0;
      for (int i = 1; i < cachedLatLng.length; i++) {
        currentDist += distanceCalc(cachedLatLng[i - 1], cachedLatLng[i]);
        dists[i] = currentDist;
      }

      setState(() {
        _points = cleanPoints;
        _allLatLng = cachedLatLng;
        _cachedGhostSegments = ghostSegs;
        _ghostPolylineLayer = null;
        _pointGaps = gaps;
        _cumulativeDistances = dists;
        _stoppages = computedStops;
        _playbackProgress = 0.0;
      });

      // Pre-populate geocoder cache along route checkpoints in background
      if (cleanPoints.isNotEmpty) {
        unawaited(Future<void>.microtask(() async {
          try {
            unawaited(Geocoder.getAddress(cleanPoints.first.latitude, cleanPoints.first.longitude));
            unawaited(Geocoder.getAddress(cleanPoints.last.latitude, cleanPoints.last.longitude));
            for (final StoppageEvent s in computedStops) {
              unawaited(Geocoder.getAddress(s.lat, s.lng));
            }
            final int step = (cleanPoints.length / 25).ceil().clamp(5, 50);
            for (int i = 0; i < cleanPoints.length; i += step) {
              unawaited(Geocoder.getAddress(cleanPoints[i].latitude, cleanPoints[i].longitude));
            }
          } catch (_) {}
        }));
      }

      if (cleanPoints.isNotEmpty) {
        await _fitRoute();
        // Allow time for map tiles to load at the new camera bounds 
        // before removing the loading overlay.
        await Future.delayed(const Duration(milliseconds: 600));
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
        if (autoPlay && cleanPoints.isNotEmpty) {
          _togglePlay();
        }
      }
    } catch (e, stack) {
      debugPrint('Error in _load: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fitRoute() async {
    if (_points.isEmpty || !_ready) return;

    if (_points.length == 1) {
      _map.move(_points.first.latLng, 13);
      return;
    }

    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(
          _points.map((TrackPoint p) => p.latLng).toList(),
        ),
        padding: const EdgeInsets.all(48),
        maxZoom: 17,
      ),
    );
  }

  void _togglePlay() {
    if (!_hasStartedPlayback) setState(() => _hasStartedPlayback = true);
    if (_playing) {
      _animController.stop();
      _lastTickTime = null;
      setState(() => _playing = false);
      return;
    }

    if (_playbackProgress >= _points.length - 1) {
      _playbackProgress = 0.0;
      _lastEncounteredStoppage = null;
      _stoppagePauseRemaining = 0.0;
    }

    _lastTickTime = DateTime.now();
    setState(() => _playing = true);
    _animController.repeat(min: 0.0, max: 1.0, period: const Duration(seconds: 1));
  }

  double get _effectiveSpeedMultiplier {
    switch (_speedMultiplier.round()) {
      case 1:
        return 1.0;
      case 2:
        return 4.0;
      case 3:
        return 12.0;
      case 4:
        return 36.0; // Blazing fast for rapid route playback
      default:
        return _speedMultiplier;
    }
  }

  void _onAnimationTick() {
    if (!_playing || _points.isEmpty || !mounted) return;

    final DateTime now = DateTime.now();
    if (_lastTickTime == null) {
      _lastTickTime = now;
      return;
    }

    final double deltaSec = now.difference(_lastTickTime!).inMicroseconds / 1000000.0;
    _lastTickTime = now;

    if (_stoppagePauseRemaining > 0) {
      _stoppagePauseRemaining -= deltaSec;
      if (_stoppagePauseRemaining > 0) {
        _followCamera();
        return;
      }
    }

    // Progression step per VSYNC frame:
    // If transitioning across a missing telemetry gap, glide slowly and smoothly across the red line.
    final int currentIdx = _playbackProgress.floor().clamp(0, _points.length - 1);
    double step;
    if (currentIdx < _points.length - 1 &&
        currentIdx + 1 < _pointGaps.length &&
        _pointGaps[currentIdx + 1]) {
      final double gapDist = (_cumulativeDistances.length > currentIdx + 1)
          ? (_cumulativeDistances[currentIdx + 1] - _cumulativeDistances[currentIdx])
          : 1000.0;
      final double gapDurationSec = (gapDist / 400.0).clamp(4.0, 7.0);
      step = (deltaSec / gapDurationSec) * _effectiveSpeedMultiplier;
    } else {
      step = deltaSec * 1.2 * _effectiveSpeedMultiplier;
    }

    _playbackProgress += step;
    if (_playbackProgress >= _points.length - 1) {
      _playbackProgress = (_points.length - 1).toDouble();
      setState(() {
        _playing = false;
        _animController.stop();
        _lastTickTime = null;
      });
    }
    _progressNotifier.value = _playbackProgress;

    if (_isCurrentlyStopped) {
      final StoppageEvent? s = _currentStoppage;
      if (s != null && s != _lastEncounteredStoppage) {
        _lastEncounteredStoppage = s;
        _stoppagePauseRemaining = 3.5; // Pause for 3.5 seconds so user can read card
      }
    }

    _followCamera();
  }

  void _followCamera({bool force = false}) {
    if (!_ready || _points.isEmpty) return;
    final LatLng current = _currentPoint.latLng;
    final double zoom = _map.camera.zoom < 15.0 ? 16.0 : _map.camera.zoom;
    _map.move(current, zoom);
  }

  /// Bearing in radians (clockwise from north) with smooth angle interpolation
  /// across corners for continuous Rapido-like vehicle motion.
  double get _currentBearing {
    if (_points.length < 2) return 0;
    final int idx = _playbackProgress.floor().clamp(0, _points.length - 1);
    if (idx >= _points.length - 1) {
      final LatLng p1 = _points[_points.length - 2].latLng;
      final LatLng p2 = _points.last.latLng;
      return _calculateBearing(p1, p2);
    }

    final LatLng from = _points[idx].latLng;
    final LatLng to = _points[idx + 1].latLng;

    if (from.latitude == to.latitude && from.longitude == to.longitude) {
      return _points[idx].heading * math.pi / 180;
    }

    final double currentSegBearing = _calculateBearing(from, to);

    // Smooth angle interpolation across corners when approaching next point
    if (idx < _points.length - 2) {
      final LatLng nextTo = _points[idx + 2].latLng;
      if (to.latitude != nextTo.latitude || to.longitude != nextTo.longitude) {
        final double nextSegBearing = _calculateBearing(to, nextTo);
        final double t = (_playbackProgress - idx).clamp(0.0, 1.0);

        // Shortest path angle diff in radians
        double diff = (nextSegBearing - currentSegBearing) % (2 * math.pi);
        if (diff > math.pi) diff -= 2 * math.pi;
        if (diff < -math.pi) diff += 2 * math.pi;

        return currentSegBearing + (diff * t);
      }
    }

    return currentSegBearing;
  }

  static double _calculateBearing(LatLng from, LatLng to) {
    final double lat1 = from.latitude * math.pi / 180;
    final double lat2 = to.latitude * math.pi / 180;
    final double dLng = (to.longitude - from.longitude) * math.pi / 180;

    final double y = math.sin(dLng) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    return math.atan2(y, x);
  }

  /// Cumulative distance in km from first point to current progress.
  double get _distanceCovered {
    if (_points.length < 2 || _playbackProgress == 0) return 0;
    final int idx = _playbackProgress.floor().clamp(0, _points.length - 1);
    
    // O(1) lookup from precalculated array
    double totalMeters = idx < _cumulativeDistances.length ? _cumulativeDistances[idx] : 0;
    
    // Add the interpolated fraction
    if (idx < _points.length - 1) {
      const Distance calc = Distance();
      totalMeters += calc(
        _points[idx].latLng,
        _currentPoint.latLng,
      );
    }
    return totalMeters / 1000.0;
  }

  /// Total cumulative distance of the selected history route in km.
  double get _totalRouteDistanceKm {
    if (_cumulativeDistances.isEmpty) return 0.0;
    return _cumulativeDistances.last / 1000.0;
  }

  /// Total overspeeds across the entire route.
  int get _totalOverspeedCount {
    if (_points.isEmpty) return 0;
    int count = 0;
    bool wasOver = false;
    for (int i = 0; i < _points.length; i++) {
      if (_points[i].speed > 80 && !wasOver) {
        count++;
        wasOver = true;
      } else if (_points[i].speed <= 80) {
        wasOver = false;
      }
    }
    return count;
  }

  /// Current stoppages reached up to current playback progress.
  int get _currentStoppageCount {
    if (_stoppages.isEmpty || _points.isEmpty) return 0;
    final DateTime currentTime = _currentPoint.timestamp;
    return _stoppages.where((s) => !s.startTime.isAfter(currentTime)).length;
  }

  /// Current overspeeds occurred up to current playback progress.
  int get _currentOverspeedCount {
    if (_points.isEmpty) return 0;
    final int currentIdx = _playbackProgress.floor().clamp(0, _points.length - 1);
    int count = 0;
    bool wasOver = false;
    for (int i = 0; i <= currentIdx; i++) {
      if (_points[i].speed > 80 && !wasOver) {
        count++;
        wasOver = true;
      } else if (_points[i].speed <= 80) {
        wasOver = false;
      }
    }
    return count;
  }

  Future<void> _pickStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _range.start,
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now(),
      builder: (BuildContext context, Widget? child) => Theme(
        data: Theme.of(context),
        child: child!,
      ),
    );
    if (picked == null) return;

    final DateTime newStart = DateTime(
      picked.year, picked.month, picked.day,
      _range.start.hour, _range.start.minute, 0,
    );

    if (newStart.isAfter(_range.end)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('From date must be before end time')),
        );
      }
      return;
    }

    setState(() => _range = DateTimeRange(start: newStart, end: _range.end));
    if (_isInitialized) await _load();
  }

  Future<void> _pickEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _range.end,
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now(),
      builder: (BuildContext context, Widget? child) => Theme(
        data: Theme.of(context),
        child: child!,
      ),
    );
    if (picked == null) return;

    final DateTime now = DateTime.now();
    final bool isEndToday = picked.year == now.year &&
        picked.month == now.month &&
        picked.day == now.day;

    // Use 23:59:59 if a past day was selected, or "now" if today was selected
    DateTime newEnd = isEndToday
        ? now
        : DateTime(picked.year, picked.month, picked.day, 23, 59, 59);

    // Maintain the old hour/minute if they just tapped End Date
    // Actually, no, if it's today we use 'now', otherwise 23:59 is fine for end of day.
    // However, if the user explicitly picked an end time previously, let's just keep the time:
    newEnd = DateTime(picked.year, picked.month, picked.day, _range.end.hour, _range.end.minute, 59);
    
    if (newEnd.isBefore(_range.start)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('To date must be after start time')),
        );
      }
      return;
    }

    setState(() => _range = DateTimeRange(start: _range.start, end: newEnd));
    if (_isInitialized) await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ThemeData theme = Theme.of(context);
    final String mapTypeKey = ref.watch(secureStoreProvider).mapType;
    final MapStyle mapType = MapStyleX.fromKey(mapTypeKey);
    final bool isDarkMap = mapType == MapStyle.satellite;

    final vehicle = ref.watch(vehicleByIdProvider(widget.vehicleId));
    
    _tileLayer = buildTileLayer(
      MapStyleX.fromKey(mapTypeKey),
      apiKey: ref.read(authProvider).user?.apiKey,
      isDark: theme.brightness == Brightness.dark,
    );

    return Stack(
      children: <Widget>[
        // MAP
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: const LatLng(17.385, 78.4867),
            initialZoom: 11,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: theme.colorScheme.surface,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _ready = true);
                    if (_points.isNotEmpty) {
                      _fitRoute();
                    }
                  }
                });
              }
            },
          ),
          children: <Widget>[
            _tileLayer!,
            ValueListenableBuilder<double>(
              valueListenable: _progressNotifier,
              builder: (context, _, __) {
                return RepaintBoundary(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_points.length >= 2) ..._routeLayers(theme),
                      MarkerLayer(markers: _routeMarkers(theme)),
                    ],
                  ),
                );
              },
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: OsmAttribution(
                style: MapStyleX.fromKey(ref.read(secureStoreProvider).mapType),
                compact: true,
              ),
            ),
          ],
        ),

        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x99070B16),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_error != null)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: ErrorState(message: _error!, onRetry: _load),
            ),
          )
        else if (_points.isEmpty)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: EmptyState(
                icon: Icons.timeline_rounded,
                title: 'No route data',
                message: 'This vehicle did not report any positions in '
                    'the selected period.',
                actionLabel: 'Choose another date',
                onAction: () => setState(() => _isInitialized = false),
              ),
            ),
          ),

        // TOP FLOATING BAR (Back, Name)
        Positioned(
          top: MediaQuery.of(context).padding.top + Gap.md,
          left: Gap.md,
          right: Gap.md,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // BACK BUTTON PILL (Left)
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: BackdropFilter(
                  filter: dart_ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMap ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDarkMap ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: isDarkMap ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF1E293B),
                      ),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                ),
              ),
              
              const Spacer(),
              
              // VEHICLE NAME PILL (Center)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF00E5FF),
                    width: 1.5,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    vehicle?.displayName.toUpperCase() ?? 'VEHICLE',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              
              const Spacer(),

              // SET AS ROUTE BUTTON PILL (Right-Center)
              if (_points.isNotEmpty && !_loading)
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: BackdropFilter(
                    filter: dart_ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isDarkMap ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDarkMap ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.route_rounded,
                          color: isDarkMap ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF1E293B),
                        ),
                        tooltip: 'Set as Route',
                        onPressed: _showSaveRouteDialog,
                      ),
                    ),
                  ),
                ),
              
              // CALENDAR BUTTON PILL (Right)
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: BackdropFilter(
                  filter: dart_ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMap ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDarkMap ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.calendar_month_rounded,
                        color: isDarkMap ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF1E293B),
                      ),
                      onPressed: () {
                        setState(() => _isInitialized = false);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // DYNAMIC FLOATING UI ELEMENTS (Wrapped in ValueListenableBuilder for 60fps)
        if (_points.isNotEmpty && !_loading)
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _progressNotifier,
              builder: (context, _, __) {
                return Stack(
                  children: [
                    // FLOATING INFO CARD
                    Positioned(
                      top: MediaQuery.of(context).padding.top + Gap.md + 64 + Gap.md,
                      left: Gap.md,
                      right: Gap.md,
                      child: _PlaybackFloatingCard(
                        key: const ValueKey('playback_floating_card'),
                        point: _currentPoint,
                        distKm: _distanceCovered,
                        totalDistKm: _totalRouteDistanceKm,
                        playing: _playing,
                        overspeedCount: _currentOverspeedCount,
                        totalOverspeedCount: _totalOverspeedCount,
                        stoppageCount: _currentStoppageCount,
                        totalStoppageCount: _stoppages.length,
                        hasStarted: _hasStartedPlayback,
                      ),
                    ),
                    
                    // SPEEDOMETER (Animated Reveal)
                    Positioned(
                      bottom: Gap.md + 80 + Gap.md, // Above the playback controls
                      left: Gap.md,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 500),
                        opacity: _hasStartedPlayback ? 1.0 : 0.0,
                        child: _SpeedGauge(
                          key: const ValueKey('playback_speed_gauge'),
                          speed: _currentPoint.speed,
                        ),
                      ),
                    ),

                    // BOTTOM CONTROLS & STOPPAGE
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        bottom: true,
                        top: false,
                        left: false,
                        right: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isCurrentlyStopped)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                              child: _ActiveStoppageBottomCard(
                                key: const ValueKey('active_stoppage_card'),
                                point: _currentPoint,
                                stoppage: _currentStoppage,
                              ),
                            ),
                          if (_isCurrentlyStopped)
                            const SizedBox(height: Gap.md),
                          _PlaybackControls(
                            key: const ValueKey('playback_controls_bar'),
                            index: _playbackProgress.round().clamp(0, _points.length - 1),
                            total: _points.length,
                            playing: _playing,
                            speed: _speedMultiplier,
                            isDarkMap: isDarkMap,
                            points: _points,
                            onSeek: (double v) {
                              _playbackProgress = v;
                              _lastEncounteredStoppage = null;
                              _stoppagePauseRemaining = 0.0;
                              _progressNotifier.value = _playbackProgress;
                            },
                            onSeekEnd: _followCamera,
                            onTogglePlay: _togglePlay,
                            onSpeedChange: (double s) {
                              setState(() => _speedMultiplier = s);
                            },
                            onRestart: () {
                              setState(() {
                                _playbackProgress = 0.0;
                                _playing = false;
                                _progressNotifier.value = _playbackProgress;
                              });
                            },
                          ),
                        ],
                      ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        // SELECTION SCREEN OVERLAY
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Curves.easeInOutCubic,
          switchOutCurve: Curves.easeInOutCubic,
          child: !_isInitialized
              ? KeyedSubtree(
                  key: const ValueKey('SelectionScreen'),
                  child: _buildInitialSelectionScreen(theme),
                )
              : const SizedBox.shrink(key: ValueKey('Empty')),
        ),
      ],
    );
  }

  Future<void> _pickStartTime() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_range.start),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null) return;

    final DateTime newStart = DateTime(
      _range.start.year,
      _range.start.month,
      _range.start.day,
      time.hour,
      time.minute,
    );

    // Guard: start must be before end
    if (!newStart.isBefore(_range.end)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start time must be before end time')),
        );
      }
      return;
    }

    setState(() {
      _range = DateTimeRange(start: newStart, end: _range.end);
    });
    if (_isInitialized) await _load();
  }

  Future<void> _pickEndTime() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_range.end),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (time == null) return;

    final DateTime newEnd = DateTime(
      _range.end.year,
      _range.end.month,
      _range.end.day,
      time.hour,
      time.minute,
      59,
    );

    // Guard: end must be after start
    if (!newEnd.isAfter(_range.start)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time')),
        );
      }
      return;
    }

    setState(() {
      _range = DateTimeRange(start: _range.start, end: newEnd);
    });
    if (_isInitialized) await _load();
  }

  /// Full route dimmed underneath, travelled portion highlighted on top with status colors.
  /// Gaps with no GPS data are drawn in red (both underneath and when travelled).
  List<Widget> _routeLayers(ThemeData theme) {
    if (_allLatLng.isEmpty) return const <Widget>[];

    final int idx = _playbackProgress.floor().clamp(0, _allLatLng.length - 1);
    final List<Polyline<Object>> travelledSegments = <Polyline<Object>>[];

    int normalStart = 0;
    for (int i = 1; i <= idx; i++) {
      if (i < _pointGaps.length && _pointGaps[i]) {
        // Normal connected segment before the gap
        if (i - 1 > normalStart) {
          travelledSegments.add(Polyline<Object>(
            points: _allLatLng.sublist(normalStart, i),
            color: const Color(0xFF00E5FF),
            strokeWidth: 5,
          ));
        }
        // Completed red gap segment (No Data)
        travelledSegments.add(Polyline<Object>(
          points: <LatLng>[_allLatLng[i - 1], _allLatLng[i]],
          color: const Color(0xFFEF4444),
          strokeWidth: 5,
        ));
        normalStart = i;
      }
    }

    // Active segment where vehicle is currently progressing
    final bool hasFraction = _playbackProgress > idx && idx < _allLatLng.length - 1;
    final bool nextIsGap = (idx + 1 < _pointGaps.length) && _pointGaps[idx + 1];

    if (hasFraction && nextIsGap) {
      // Flush preceding normal segment up to idx
      if (idx > normalStart) {
        travelledSegments.add(Polyline<Object>(
          points: _allLatLng.sublist(normalStart, idx + 1),
          color: const Color(0xFF00E5FF),
          strokeWidth: 5,
        ));
      }
      // Vehicle is moving through the missing data gap: draw active red segment up to vehicle marker
      travelledSegments.add(Polyline<Object>(
        points: <LatLng>[_allLatLng[idx], _currentPoint.latLng],
        color: const Color(0xFFEF4444),
        strokeWidth: 5,
      ));
    } else {
      // Normal segment continuing up to idx, plus fractional progress to currentPoint
      List<LatLng> currentNormal = _allLatLng.sublist(normalStart, idx + 1);
      if (hasFraction) {
        currentNormal = List<LatLng>.of(currentNormal)..add(_currentPoint.latLng);
      }
      if (currentNormal.length >= 2) {
        travelledSegments.add(Polyline<Object>(
          points: currentNormal,
          color: const Color(0xFF00E5FF),
          strokeWidth: 5,
        ));
      }
    }

    _ghostPolylineLayer ??= PolylineLayer<Object>(polylines: _cachedGhostSegments);

    return <Widget>[
      _ghostPolylineLayer!,
      PolylineLayer<Object>(polylines: travelledSegments),
    ];
  }

  /// Builds ghost route segments: normal telemetry segments in [normalColor],
  /// and missing data gaps in [gapColor] (Red).
  static List<Polyline<Object>> _buildGhostSegments({
    required List<LatLng> points,
    required List<bool> gaps,
    required Color normalColor,
    required Color gapColor,
    double strokeWidth = 3.5,
  }) {
    if (points.length < 2) return const <Polyline<Object>>[];

    final List<Polyline<Object>> segments = <Polyline<Object>>[];
    List<LatLng> currentNormal = <LatLng>[points.first];

    for (int i = 1; i < points.length; i++) {
      final bool isGap = i < gaps.length && gaps[i];
      if (isGap) {
        if (currentNormal.length >= 2) {
          segments.add(Polyline<Object>(
            points: List<LatLng>.of(currentNormal),
            color: normalColor,
            strokeWidth: strokeWidth,
          ));
        }
        currentNormal = <LatLng>[points[i]];

        // Missing data gap segment in RED
        segments.add(Polyline<Object>(
          points: <LatLng>[points[i - 1], points[i]],
          color: gapColor,
          strokeWidth: strokeWidth,
        ));
      } else {
        currentNormal.add(points[i]);
      }
    }

    if (currentNormal.length >= 2) {
      segments.add(Polyline<Object>(
        points: currentNormal,
        color: normalColor,
        strokeWidth: strokeWidth,
      ));
    }

    return segments;
  }


  List<Marker> _routeMarkers(ThemeData theme) {
    if (_points.isEmpty) return const <Marker>[];

    final TrackPoint cursor = _currentPoint;

    return <Marker>[
      Marker(
        point: _points.first.latLng,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: const _FlagPin(color: AppColors.moving),
      ),
      Marker(
        point: _points.last.latLng,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: const _FlagPin(color: AppColors.danger),
      ),
      // Stoppage Markers
      for (int i = 0; i < _stoppages.length; i++)
        Marker(
          point: LatLng(_stoppages[i].lat, _stoppages[i].lng),
          width: 26,
          height: 26,
          child: GestureDetector(
            onTap: () {
              final int pIdx = _points.indexWhere((TrackPoint pt) =>
                  pt.timestamp.isAfter(_stoppages[i].startTime) ||
                  pt.timestamp.isAtSameMomentAs(_stoppages[i].startTime));
              if (pIdx != -1) {
                setState(() => _playbackProgress = pIdx.toDouble());
                _followCamera();
              }
            },
            child: _StoppagePin(duration: _stoppages[i].duration, number: i + 1),
          ),
        ),
      Marker(
        point: cursor.latLng,
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: _PlaybackVehicleMarker(
          speed: cursor.speed,
          bearingRad: _currentBearing,
          playing: _playing,
        ),
      ),
    ];
  }

  // ── Initial Selection Screen ──────────────────────────────────────────

  Widget _buildInitialSelectionScreen(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28.0),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: theme.colorScheme.shadow.withOpacity(0.06),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.history_rounded, size: 48, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Playback & History',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Select a precise date and time range to load the vehicle\'s historical route, path, and stoppages.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),
              
              // From Date and Start Time row
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildSelectionButton(
                      icon: Icons.calendar_today_rounded,
                      label: 'From Date',
                      value: _formatDateShort(_range.start),
                      onTap: _pickStartDate,
                      theme: theme,
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSelectionButton(
                      icon: Icons.access_time_rounded,
                      label: 'Start Time',
                      value: _formatTime(_range.start),
                      onTap: _pickStartTime,
                      theme: theme,
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade400, Colors.orange.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // To Date and End Time row
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildSelectionButton(
                      icon: Icons.event_rounded,
                      label: 'To Date',
                      value: _formatDateShort(_range.end),
                      onTap: _pickEndDate,
                      theme: theme,
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade400, Colors.purple.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSelectionButton(
                      icon: Icons.access_time_filled_rounded,
                      label: 'End Time',
                      value: _formatTime(_range.end),
                      onTap: _pickEndTime,
                      theme: theme,
                      gradient: LinearGradient(
                        colors: [Colors.pink.shade400, Colors.pink.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() => _isInitialized = true);
                    _load(autoPlay: true);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: const Text('Play History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _showSaveRouteDialog() {
    final TextEditingController nameCtrl = TextEditingController(text: 'History Route - ${_formatDateShort(_range.start)}');
    double tolerance = 100;
    int selectedScope = 0; // 0: Full, 1: Outbound, 2: Return

    int turnaroundIdx = _allLatLng.length ~/ 2;
    if (_allLatLng.length >= 3) {
      const Distance dist = Distance();
      final LatLng s = _allLatLng.first;
      double maxD = 0;
      for (int i = 0; i < _allLatLng.length; i++) {
        final double d = dist(s, _allLatLng[i]);
        if (d > maxD) {
          maxD = d;
          turnaroundIdx = i;
        }
      }
    }

    String startName = 'Start';
    String endName = 'End';
    String turnName = 'Turnaround';

    void updateSuggestedName(StateSetter setDialogState) {
      if (selectedScope == 1) {
        nameCtrl.text = '$startName – $turnName';
      } else if (selectedScope == 2) {
        nameCtrl.text = '$turnName – $endName';
      } else {
        nameCtrl.text = startName == endName
            ? '$startName (Round Trip Loop)'
            : '$startName – $endName';
      }
      setDialogState(() {});
    }

    // Automatically resolve start, turnaround & end place
    if (_allLatLng.length >= 2) {
      final LatLng sPt = _allLatLng.first;
      final LatLng ePt = _allLatLng.last;
      final LatLng tPt = _allLatLng[turnaroundIdx];
      Future.wait(<Future<String>>[
        Geocoder.getAddress(sPt.latitude, sPt.longitude),
        Geocoder.getAddress(ePt.latitude, ePt.longitude),
        Geocoder.getAddress(tPt.latitude, tPt.longitude),
      ]).then((List<String> addrs) {
        startName = Geocoder.cleanPlaceName(addrs[0]);
        endName = Geocoder.cleanPlaceName(addrs[1]);
        turnName = Geocoder.cleanPlaceName(addrs[2]);
        if (nameCtrl.text.startsWith('History Route')) {
          nameCtrl.text = startName == endName
              ? '$startName (Round Trip Loop)'
              : '$startName – $endName';
        }
      }).catchError((_) {});
    }
    
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Set as Route (Compressed)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Compresses history using Douglas-Peucker algorithm to guarantee zero server lag.'),
                    if (_allLatLng.length >= 4) ...[
                      const SizedBox(height: 14),
                      const Text('Route Scope / Section:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text('Full Trip (Loop)', style: TextStyle(fontSize: 11)),
                            selected: selectedScope == 0,
                            onSelected: (bool sel) {
                              if (sel) {
                                selectedScope = 0;
                                updateSuggestedName(setDialogState);
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Outbound (Start ➔ Turn)', style: TextStyle(fontSize: 11)),
                            selected: selectedScope == 1,
                            onSelected: (bool sel) {
                              if (sel) {
                                selectedScope = 1;
                                updateSuggestedName(setDialogState);
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Return (Turn ➔ End)', style: TextStyle(fontSize: 11)),
                            selected: selectedScope == 2,
                            onSelected: (bool sel) {
                              if (sel) {
                                selectedScope = 2;
                                updateSuggestedName(setDialogState);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Route Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Deviation Tolerance: ${tolerance.round()} meters'),
                    Slider(
                      value: tolerance,
                      min: 100,
                      max: 1000,
                      divisions: 9,
                      label: '${tolerance.round()} m',
                      onChanged: (double val) => setDialogState(() => tolerance = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    Navigator.pop(context);
                    
                    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
                    try {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Compressing route...')),
                      );
                      
                      // 1. Extract GPS coordinates based on scope
                      List<LatLng> targetPts = _allLatLng;
                      if (selectedScope == 1 && turnaroundIdx >= 1) {
                        targetPts = _allLatLng.sublist(0, turnaroundIdx + 1);
                      } else if (selectedScope == 2 && _allLatLng.length - turnaroundIdx >= 2) {
                        targetPts = _allLatLng.sublist(turnaroundIdx);
                      }

                      final List<List<double>> rawCoords = targetPts
                          .map((LatLng pt) => <double>[pt.latitude, pt.longitude])
                          .toList(growable: false);
                          
                      // 2. Compress via PolylineSimplifier (10 meters epsilon is perfect for highways)
                      final List<List<double>> compressedCoords = PolylineSimplifier.simplify(rawCoords, 10.0);
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Compressed ${rawCoords.length} points to ${compressedCoords.length} points! Saving...')),
                      );
                      
                      // 3. Save to backend and local storage via routeProvider
                      final AppRoute newRoute = AppRoute(
                        id: 'temp_${DateTime.now().millisecondsSinceEpoch}', 
                        name: nameCtrl.text.trim(),
                        coordinates: compressedCoords.map((c) => LatLng(c[0], c[1])).toList(),
                        toleranceMeters: tolerance,
                        isActive: true,
                        vehicleIds: <String>[widget.vehicleId],
                        createdAt: DateTime.now(),
                      );
                      
                      final AppRoute? createdRoute = await ref.read(routeProvider.notifier).create(
                            newRoute,
                            vehicleIds: <String>[widget.vehicleId],
                          );
                      
                      // 4. Record and store the trip run with start time, end time, duration, and stoppages
                      int startIdx = 0;
                      int endIdx = _points.isNotEmpty ? _points.length - 1 : 0;
                      if (selectedScope == 1 && turnaroundIdx >= 1) {
                        endIdx = turnaroundIdx.clamp(0, _points.length - 1);
                      } else if (selectedScope == 2 && _points.length - turnaroundIdx >= 2) {
                        startIdx = turnaroundIdx.clamp(0, _points.length - 1);
                      }

                      DateTime tripStart = _range.start;
                      DateTime tripEnd = _range.end;
                      if (_points.isNotEmpty && startIdx <= endIdx && endIdx < _points.length) {
                        tripStart = _points[startIdx].timestamp;
                        tripEnd = _points[endIdx].timestamp;
                      }

                      double tripDistKm = 0.0;
                      if (_cumulativeDistances.isNotEmpty &&
                          startIdx < _cumulativeDistances.length &&
                          endIdx < _cumulativeDistances.length) {
                        tripDistKm = (_cumulativeDistances[endIdx] - _cumulativeDistances[startIdx]).abs() / 1000.0;
                      }
                      if (tripDistKm <= 0.0) {
                        tripDistKm = newRoute.approxLengthKm;
                      }

                      final int stopCount = _stoppages.where((StoppageEvent s) {
                        return !s.startTime.isBefore(tripStart) && !s.endTime.isAfter(tripEnd);
                      }).length;

                      double maxSpd = 0;
                      double sumSpd = 0;
                      int countSpd = 0;
                      for (int i = startIdx; i <= endIdx && i < _points.length; i++) {
                        final double spd = _points[i].speed;
                        if (spd > maxSpd) maxSpd = spd;
                        if (spd > 0) {
                          sumSpd += spd;
                          countSpd++;
                        }
                      }
                      final double avgSpd = countSpd > 0 ? (sumSpd / countSpd) : 0.0;

                      final Vehicle? veh = ref
                          .read(fleetProvider)
                          .vehicles
                          .where((Vehicle item) => item.id == widget.vehicleId)
                          .firstOrNull;

                      final UserTrip recordedTrip = UserTrip(
                        id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
                        vehicleId: widget.vehicleId,
                        name: '${newRoute.name} - Playback Run',
                        status: 'completed',
                        routeId: createdRoute?.id ?? newRoute.id,
                        routeName: newRoute.name,
                        vehicleName: veh?.displayName ?? widget.vehicleId,
                        plate: veh?.registrationNumber ?? widget.vehicleId,
                        startTime: tripStart,
                        endTime: tripEnd,
                        durationSecs: tripEnd.difference(tripStart).inSeconds,
                        distanceKm: tripDistKm,
                        stoppageCount: stopCount > 0 ? stopCount : _stoppages.length,
                        maxSpeed: maxSpd.round(),
                        avgSpeed: avgSpd,
                        createdAt: DateTime.now(),
                      );

                      await ref.read(tripProvider.notifier).create(recordedTrip);
                      
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Route "${newRoute.name}" created with trip details & ${_stoppages.length} stops!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Save & Compress'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSelectionButton({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    required ThemeData theme,
    required Gradient gradient,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradient.colors.last.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 20, color: Colors.white.withOpacity(0.9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label, 
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value, 
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackVehicleMarker extends StatelessWidget {
  const _PlaybackVehicleMarker({
    required this.speed,
    required this.bearingRad,
    required this.playing,
  });

  final double speed;
  final double bearingRad;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final bool isMoving = speed > 3;
    final bool isIdle = speed > 0 && speed <= 3;
    final Color markerColor = isMoving
        ? const Color(0xFF00C853) // Green (Moving)
        : isIdle
            ? const Color(0xFFFFAB00) // Amber (Idle)
            : const Color(0xFF2979FF); // Blue (Stopped)

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        if (playing && isMoving)
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: markerColor.withOpacity(0.25),
            ),
          ),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: markerColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Transform.rotate(
            angle: bearingRad,
            child: const Icon(
              Icons.navigation_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

class _StoppagePin extends StatelessWidget {
  const _StoppagePin({required this.duration, required this.number});

  final Duration duration;
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.danger,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.danger.withOpacity(0.55),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          number.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: number > 9 ? 10.5 : 12.0,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Start / end pin.
class _RouteEndpoint extends StatelessWidget {
  const _RouteEndpoint({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.2),
          boxShadow: <BoxShadow>[
            BoxShadow(color: color.withOpacity(0.5), blurRadius: 8),
          ],
        ),
        child: Icon(icon, size: 13, color: Colors.white),
      );
}


/// Circular speed gauge — mirrors the web app's bottom-left speedometer.
class _SpeedGauge extends StatelessWidget {
  const _SpeedGauge({super.key, required this.speed});

  final double speed;

  @override
  Widget build(BuildContext context) {
    final int spd = speed.round();
    // max on gauge is 120 km/h
    final double fraction = (spd / 120).clamp(0.0, 1.0);
    final Color arcColor = spd > 80
        ? AppColors.danger
        : spd > 40
            ? AppColors.idle
            : AppColors.moving;

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: 80,
            height: 80,
            child: CustomPaint(
              painter: _ArcPainter(fraction: fraction, color: arcColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'SPEED',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF888888),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$spd',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: arcColor,
                  height: 1,
                ),
              ),
              const Text(
                'Km/h',
                style: TextStyle(
                  fontSize: 8,
                  color: Color(0xFF888888),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const double startAngle = math.pi * 0.75;
    const double sweepFull = math.pi * 1.5;
    final Rect rect = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);

    // Background track
    canvas.drawArc(
      rect,
      startAngle,
      sweepFull,
      false,
      Paint()
        ..color = const Color(0xFFEEEEEE)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (fraction > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        sweepFull * fraction,
        false,
        Paint()
          ..color = color
          ..strokeWidth = 7
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// Combined vehicle dot + floating "Current Position" info card —
/// renders as a single tall Marker so the card hovers above the dot.
class _PlaybackMarker extends StatefulWidget {
  const _PlaybackMarker({required this.point, required this.distKm});

  final TrackPoint point;
  final double distKm;

  @override
  State<_PlaybackMarker> createState() => _PlaybackMarkerState();
}

class _PlaybackMarkerState extends State<_PlaybackMarker> {
  String? _address;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PlaybackMarker old) {
    super.didUpdateWidget(old);
    if (old.point.latitude != widget.point.latitude ||
        old.point.longitude != widget.point.longitude) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 700), () {
        if (mounted) _resolveAddress();
      });
    }
  }

  void _resolveAddress() {
    if (widget.point.address != null && widget.point.address!.trim().isNotEmpty) {
      if (!widget.point.address!.endsWith('...') && !widget.point.address!.endsWith('…')) {
        setState(() => _address = widget.point.address);
        return;
      }
    }
    
    String? cleanAddr = widget.point.address?.replaceAll('...', '').replaceAll('…', '').trim();
    if (cleanAddr != null && cleanAddr.isEmpty) cleanAddr = null;
    
    if (cleanAddr != null) {
      setState(() => _address = cleanAddr);
    }

    final TrackPoint snap = widget.point;
    Geocoder.getAddress(snap.latitude, snap.longitude).then((String a) {
      if (mounted && widget.point == snap && a != 'Location unavailable') {
        setState(() => _address = a);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final int spd = widget.point.speed.round();
    final double dist = widget.distKm;
    final String time =
        '${widget.point.timestamp.day.toString().padLeft(2, '0')}-'
        '${widget.point.timestamp.month.toString().padLeft(2, '0')}-'
        '${widget.point.timestamp.year} '
        '${widget.point.timestamp.hour.toString().padLeft(2, '0')}:'
        '${widget.point.timestamp.minute.toString().padLeft(2, '0')}:'
        '${widget.point.timestamp.second.toString().padLeft(2, '0')}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // ── Info card (mirrors web app "Current Position" popup) ──────
        Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Header
              const Text(
                'Current Position',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A237E),
                  letterSpacing: 0.3,
                ),
              ),
              const Divider(height: 8, thickness: 0.5),
              // LocTime
              _InfoRow(label: 'LocTime', value: time),
              // Speed
              _InfoRow(
                label: 'Speed',
                value: '$spd km/h',
                valueColor: spd > 80
                    ? AppColors.danger
                    : spd > 40
                        ? AppColors.idle
                        : AppColors.moving,
              ),
              // Distance covered
              _InfoRow(
                label: 'DistCov',
                value: dist < 1
                    ? '${(dist * 1000).round()} m'
                    : '${dist.toStringAsFixed(1)} km',
              ),
              // Address
              if (_address != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.location_on_outlined,
                          size: 11, color: Color(0xFF888888)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _address!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF444444),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // ── Pointer triangle ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: CustomPaint(
            size: const Size(14, 8),
            painter: _TrianglePainter(),
          ),
        ),

        // ── Vehicle dot ───────────────────────────────────────────────
        Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.signal.withOpacity(0.22),
              ),
            ),
            Transform.rotate(
              angle: widget.point.heading * math.pi / 180,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.signal,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.signal.withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.navigation_rounded,
                    size: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 58,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF888888),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? const Color(0xFF1565C0),
                ),
              ),
            ),
          ],
        ),
      );
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = Colors.white;
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, p);
    // Subtle shadow on triangle
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withOpacity(0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_TrianglePainter _) => false;
}

class _PlaybackControls extends StatefulWidget {
  const _PlaybackControls({
    super.key,
    required this.index,
    required this.total,
    required this.playing,
    required this.speed,
    required this.points,
    required this.onSeek,
    required this.onSeekEnd,
    required this.onTogglePlay,
    required this.onSpeedChange,
    required this.onRestart,
    required this.isDarkMap,
  });

  final int index;
  final int total;
  final bool playing;
  final double speed;
  final List<TrackPoint> points;
  final ValueChanged<double> onSeek;
  final VoidCallback onSeekEnd;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSpeedChange;
  final VoidCallback onRestart;
  final bool isDarkMap;

  @override
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<_PlaybackControls> {
  late bool _isExpanded = widget.playing;

  @override
  void didUpdateWidget(covariant _PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !oldWidget.playing && !_isExpanded) {
      _isExpanded = true;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDarkMap = widget.isDarkMap;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: dart_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            width: _isExpanded ? MediaQuery.of(context).size.width - 32 : 220,
            decoration: BoxDecoration(
              color: isDarkMap ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDarkMap ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isExpanded ? _buildExpandedControls(isDarkMap, theme) : _buildCollapsedButton(isDarkMap, theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedButton(bool isDark, ThemeData theme) {
    return InkWell(
      key: const ValueKey('collapsed'),
      onTap: () {
        setState(() => _isExpanded = true);
        widget.onTogglePlay(); // Start playing immediately
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'Play History',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedControls(bool isDark, ThemeData theme) {
    return Padding(
      key: const ValueKey('expanded'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: MediaQuery.of(context).size.width - 64,
          child: Row(
            children: <Widget>[
          // Play/Pause Button
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFF3B82F6),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: widget.onTogglePlay,
              icon: Icon(
                widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Slider
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(widget.points[widget.index].timestamp),
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                    ),
                    Text(
                      _formatTime(widget.points.last.timestamp),
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                    ),
                  ],
                ),
                SizedBox(
                  height: 24,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: const Color(0xFF38BDF8),
                      inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
                      thumbColor: Colors.orange,
                    ),
                    child: Slider(
                      value: widget.index.toDouble(),
                      min: 0,
                      max: (widget.total - 1).toDouble().clamp(1, double.infinity),
                      onChanged: widget.onSeek,
                      onChangeEnd: (_) => widget.onSeekEnd(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          
          // Speed Dropdown
          DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: [1.0, 2.0, 4.0].contains(widget.speed) ? widget.speed : 1.0,
              icon: const Icon(Icons.arrow_drop_down, size: 20),
              isDense: true,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: const [
                DropdownMenuItem(value: 1.0, child: Text('1x')),
                DropdownMenuItem(value: 2.0, child: Text('2x')),
                DropdownMenuItem(value: 4.0, child: Text('4x')),
              ],
              onChanged: (v) {
                if (v != null) widget.onSpeedChange(v);
              },
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}

class _FlagPin extends StatelessWidget {
  const _FlagPin({required this.color});
  final Color color;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_on, color: color, size: 40),
        const Positioned(
          top: 6,
          child: Icon(Icons.flag_rounded, color: Colors.white, size: 16),
        ),
      ],
    );
  }
}

class _PlaybackFloatingCard extends StatefulWidget {
  const _PlaybackFloatingCard({
    super.key,
    required this.point,
    required this.distKm,
    required this.totalDistKm,
    required this.playing,
    required this.overspeedCount,
    required this.totalOverspeedCount,
    required this.stoppageCount,
    required this.totalStoppageCount,
    this.hasStarted = false,
  });

  final TrackPoint point;
  final double distKm;
  final double totalDistKm;
  final bool playing;
  final int overspeedCount;
  final int totalOverspeedCount;
  final int stoppageCount;
  final int totalStoppageCount;
  final bool hasStarted;

  @override
  State<_PlaybackFloatingCard> createState() => _PlaybackFloatingCardState();
}

class _PlaybackFloatingCardState extends State<_PlaybackFloatingCard> {
  String? _address;
  Timer? _debounce;
  int _lastRequestId = 0;
  DateTime? _lastFetchTime;
  double _lastFetchedLat = 0.0;
  double _lastFetchedLng = 0.0;

  @override
  void initState() {
    super.initState();
    _checkAddress(forceImmediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PlaybackFloatingCard old) {
    super.didUpdateWidget(old);
    _checkAddress(forceImmediate: !widget.playing);
  }

  void _checkAddress({bool forceImmediate = false}) {
    // 1. Show backend address as TEMPORARY placeholder (don't return — always geocode!)
    if (widget.point.address != null && widget.point.address!.trim().isNotEmpty) {
      final String clean = widget.point.address!.replaceAll('...', '').replaceAll('…', '').trim();
      if (clean.isNotEmpty && _address == null) {
        setState(() => _address = clean);
      }
    }

    // 2. Instant proximity cache check (0ms latency, updates while scrubbing!)
    final String? cached = Geocoder.getCachedAddress(widget.point.latitude, widget.point.longitude);
    if (cached != null && cached != _address) {
      setState(() => _address = cached);
    }

    // 3. Network fetch — aggressively update during scrubbing
    //    50m threshold + 400ms throttle ensures address changes frequently
    //    along the route instead of sticking for 10+ km.
    final DateTime now = DateTime.now();
    const Distance calc = Distance();
    final double distMoved = calc(
      LatLng(_lastFetchedLat, _lastFetchedLng),
      LatLng(widget.point.latitude, widget.point.longitude),
    );

    final bool timeElapsed = _lastFetchTime == null || now.difference(_lastFetchTime!).inMilliseconds > 400;
    final bool movedFarEnough = distMoved > 50.0;

    if (forceImmediate || (timeElapsed && movedFarEnough)) {
      _lastFetchTime = now;
      _lastFetchedLat = widget.point.latitude;
      _lastFetchedLng = widget.point.longitude;
      _fetchNetworkAddress();
    } else if (_debounce == null || !_debounce!.isActive) {
      _debounce = Timer(const Duration(milliseconds: 200), () {
        if (mounted) _fetchNetworkAddress();
      });
    }
  }

  void _fetchNetworkAddress() {
    final int currentId = ++_lastRequestId;
    final TrackPoint snap = widget.point;
    Geocoder.getAddress(snap.latitude, snap.longitude).then((String a) {
      if (mounted && currentId == _lastRequestId && a != 'Location unavailable') {
        setState(() => _address = a);
      }
    });
  }

  String _getDirection(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading >= 22.5 && heading < 67.5) return 'NE';
    if (heading >= 67.5 && heading < 112.5) return 'E';
    if (heading >= 112.5 && heading < 157.5) return 'SE';
    if (heading >= 157.5 && heading < 202.5) return 'S';
    if (heading >= 202.5 && heading < 247.5) return 'SW';
    if (heading >= 247.5 && heading < 292.5) return 'W';
    if (heading >= 292.5 && heading < 337.5) return 'NW';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final TrackPoint p = widget.point;
    final int spd = p.speed.round();

    final String timeStr = _toIstString(p.timestamp, Fmt.timeSec);
    final String dateStr = _toIstString(p.timestamp, Fmt.dateShort);

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.08),
                offset: Offset(0, 12),
                blurRadius: 32,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        // Time & Date
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 30,
                          color: const Color.fromRGBO(0, 0, 0, 0.12),
                        ),
                        const SizedBox(width: 10),
                        // Speed & Direction
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            RichText(
                              text: TextSpan(
                                children: <TextSpan>[
                                  TextSpan(
                                    text: '$spd ',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                      height: 1.2,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: 'km/h',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF64748B),
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getDirection(p.heading),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 30,
                          color: const Color.fromRGBO(0, 0, 0, 0.12),
                        ),
                        const SizedBox(width: 10),
                        // Total Day Distance Metric (Matching Web "Total Dist: X.XX Kms")
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '${widget.totalDistKm.toStringAsFixed(2)} km',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0284C7),
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Total Dist',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Navigation Arrow
                        Transform.rotate(
                          angle: p.heading * math.pi / 180,
                          child: const Icon(
                            Icons.navigation,
                            color: Color(0xFF0284C7),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Location Address
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.location_on,
                            size: 16,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _address ?? '...',
                            maxLines: null,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Vehicle Info
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        const Icon(
                          Icons.speed,
                          size: 14,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.hasStarted && widget.distKm > 0.05
                                ? 'Covered: ${widget.distKm.toStringAsFixed(2)} / ${widget.totalDistKm.toStringAsFixed(2)} km  •  ${widget.totalStoppageCount} stops'
                                : 'Total: ${widget.totalDistKm.toStringAsFixed(2)} km  •  ${widget.totalStoppageCount} stops  •  ${widget.totalOverspeedCount} overspeeds',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

/// Active Stoppage Bottom Card (Full width bottom sheet style)
class _ActiveStoppageBottomCard extends StatefulWidget {
  const _ActiveStoppageBottomCard({
    super.key,
    required this.point,
    this.stoppage,
  });

  final TrackPoint point;
  final StoppageEvent? stoppage;

  @override
  State<_ActiveStoppageBottomCard> createState() => _ActiveStoppageBottomCardState();
}

class _ActiveStoppageBottomCardState extends State<_ActiveStoppageBottomCard> {
  String? _address;
  int _lastReqId = 0;

  @override
  void initState() {
    super.initState();
    _fetchAddress();
  }

  @override
  void didUpdateWidget(covariant _ActiveStoppageBottomCard old) {
    super.didUpdateWidget(old);
    if (old.point.latitude != widget.point.latitude ||
        old.point.longitude != widget.point.longitude) {
      _fetchAddress();
    }
  }

  void _fetchAddress() {
    bool needsFetch = true;
    if (widget.point.address != null && widget.point.address!.trim().isNotEmpty) {
      if (!widget.point.address!.endsWith('...') && !widget.point.address!.endsWith('…')) {
        needsFetch = false;
      }
    }
    
    String? cleanAddr = widget.point.address?.replaceAll('...', '').replaceAll('…', '').trim();
    if (cleanAddr != null && cleanAddr.isEmpty) cleanAddr = null;
    
    if (cleanAddr != null) {
      setState(() => _address = cleanAddr);
    }

    if (!needsFetch) return;

    final int req = ++_lastReqId;
    Geocoder.getAddress(widget.point.latitude, widget.point.longitude).then((String addr) {
      if (mounted && req == _lastReqId && addr != 'Location unavailable') {
        setState(() => _address = addr);
      }
    });
  }

  Future<void> _openGoogleMaps() async {
    final double lat = widget.point.latitude;
    final double lng = widget.point.longitude;
    final Uri uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final StoppageEvent? stop = widget.stoppage;
    final Duration dur = stop?.duration ?? Duration.zero;
    final String formattedDur = Fmt.durationHms(dur);

    final String stoppedAt = stop != null ? _toIstString(stop.startTime, Fmt.time) : '—';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Header Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Blue circle location pin
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF2563EB), // Blue
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    // Titles
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text(
                                  'Vehicle Stopped',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              // Red Stopped Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2), // Light red
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const <Widget>[
                                    Icon(Icons.pan_tool_rounded, size: 12, color: Color(0xFFDC2626)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Stopped',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.location_on, size: 14, color: Colors.black54),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _address ?? '...',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                
                // Stopped For
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.timer_outlined, size: 20, color: Colors.black87),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Stopped For',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                        ),
                      ),
                      Text(
                        formattedDur,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB), // Blue
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                
                // Stopped At
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.access_time_rounded, size: 20, color: Colors.black87),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Stopped At',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                        ),
                      ),
                      Text(
                        stoppedAt,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                
                // Address Action
                InkWell(
                  onTap: _openGoogleMaps,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: const <Widget>[
                        Icon(Icons.map_outlined, size: 20, color: Colors.black87),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Address',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 20, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



class _GlassContainer extends StatelessWidget {
  const _GlassContainer({super.key, required this.child, this.borderRadius, this.shape});
  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final BoxShape? shape;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(100),
      child: BackdropFilter(
        filter: dart_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.4),
            borderRadius: borderRadius,
            shape: shape ?? BoxShape.rectangle,
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
