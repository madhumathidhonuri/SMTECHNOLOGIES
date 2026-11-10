import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/route.dart';
import '../../data/models/vehicle.dart';
import '../../features/live_map/widgets/map_tiles.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/route_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/auth_provider.dart';

import '../../shared/map/app_map.dart';
import '../../shared/map/app_map_controller.dart';
import '../../shared/map/app_map_models.dart';
import '../../core/utils/geocoder.dart';
import '../../core/utils/routing_service.dart';

/// Full-screen sheet for drawing a route on the map and assigning it
/// to one or more vehicles. Opened from [RoutesScreen].
class RouteEditorSheet extends ConsumerStatefulWidget {
  const RouteEditorSheet({this.existing, super.key});

  /// When non-null, the editor pre-loads this route for editing.
  final AppRoute? existing;

  @override
  ConsumerState<RouteEditorSheet> createState() => _RouteEditorSheetState();
}

class _RouteEditorSheetState extends ConsumerState<RouteEditorSheet> {
  final AppMapControllerWrapper _mapCtrl = AppMapControllerWrapper();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _placeSearchCtrl = TextEditingController();

  // ── Start & Destination Search Controllers & State ─────────────────
  TextEditingController? _startLocationCtrlField;
  TextEditingController get _startLocationCtrl =>
      _startLocationCtrlField ??= TextEditingController();

  TextEditingController? _endLocationCtrlField;
  TextEditingController get _endLocationCtrl =>
      _endLocationCtrlField ??= TextEditingController();

  Timer? _startDebounce;
  Timer? _endDebounce;

  List<GeocodeSearchResult>? _startSuggestionsField;
  List<GeocodeSearchResult> get _startSuggestions =>
      _startSuggestionsField ??= <GeocodeSearchResult>[];
  set _startSuggestions(List<GeocodeSearchResult> val) =>
      _startSuggestionsField = val;

  List<GeocodeSearchResult>? _endSuggestionsField;
  List<GeocodeSearchResult> get _endSuggestions =>
      _endSuggestionsField ??= <GeocodeSearchResult>[];
  set _endSuggestions(List<GeocodeSearchResult> val) =>
      _endSuggestionsField = val;

  bool? _isSearchingStartField;
  bool get _isSearchingStart => _isSearchingStartField ?? false;
  set _isSearchingStart(bool val) => _isSearchingStartField = val;

  bool? _isSearchingEndField;
  bool get _isSearchingEnd => _isSearchingEndField ?? false;
  set _isSearchingEnd(bool val) => _isSearchingEndField = val;

  bool? _isSearchCardExpandedField;
  bool get _isSearchCardExpanded => _isSearchCardExpandedField ?? true;
  set _isSearchCardExpanded(bool val) => _isSearchCardExpandedField = val;

  LatLng? _startLocation;
  LatLng? _endLocation;

  bool? _isRoutingField;
  bool get _isRouting => _isRoutingField ?? false;
  set _isRouting(bool val) => _isRoutingField = val;

  String? _routeDurationText;
  String? _routingSource;

  final List<LatLng> _waypoints = <LatLng>[];
  final List<LatLng> _initialWaypoints = <LatLng>[];
  List<LatLng> _sourceWaypoints = <LatLng>[];
  RangeValues _trimRange = const RangeValues(0, 1);
  bool _canEditTrail = false;
  double _tolerance = 150; // metres
  final Set<String> _selectedVehicleIds = <String>{};
  String _searchQuery = '';

  bool _showPlaceSearch = false;
  bool _isSearchingPlace = false;
  List<_RouteStopMatch> _searchResults = <_RouteStopMatch>[];
  List<_RouteQuickStop> _detectedStops = <_RouteQuickStop>[];

  bool _saving = false;
  bool _isAutoNaming = false;
  String _startPlace = '';
  String _endPlace = '';

  @override
  void reassemble() {
    super.reassemble();
    _startLocationCtrlField ??= TextEditingController();
    _endLocationCtrlField ??= TextEditingController();
    _startSuggestionsField ??= <GeocodeSearchResult>[];
    _endSuggestionsField ??= <GeocodeSearchResult>[];
    _isSearchingStartField ??= false;
    _isSearchingEndField ??= false;
    _isSearchCardExpandedField ??= true;
    _isRoutingField ??= false;
  }

  @override
  void initState() {
    super.initState();
    _startLocationCtrlField ??= TextEditingController();
    _endLocationCtrlField ??= TextEditingController();
    _startSuggestionsField ??= <GeocodeSearchResult>[];
    _endSuggestionsField ??= <GeocodeSearchResult>[];
    _isSearchingStartField ??= false;
    _isSearchingEndField ??= false;
    _isSearchCardExpandedField ??= true;
    _isRoutingField ??= false;

    final AppRoute? ex = widget.existing;
    if (ex != null) {
      _nameCtrl.text = ex.name;
      _waypoints.addAll(ex.coordinates);
      _initialWaypoints.addAll(ex.coordinates);
      _sourceWaypoints = List<LatLng>.from(ex.coordinates);
      _tolerance = ex.toleranceMeters;
      _selectedVehicleIds.addAll(ex.vehicleIds);
      _canEditTrail = false; // Existing routes are locked by default so clicks won't move the trail
      if (ex.coordinates.isNotEmpty) {
        _startLocation = ex.coordinates.first;
        _endLocation = ex.coordinates.last;
        _initExistingPlaceNames();
      }
    } else {
      _sourceWaypoints = List<LatLng>.from(_waypoints);
      _canEditTrail = true;
    }
    if (_sourceWaypoints.length >= 2) {
      _trimRange = RangeValues(0, (_sourceWaypoints.length - 1).toDouble());
    }
    if (_waypoints.length >= 2) {
      _autoNameFromPlaces();
    }
    if (_sourceWaypoints.length >= 10) {
      _detectMajorStops();
    }
  }

  Future<void> _initExistingPlaceNames() async {
    if (_waypoints.length < 2) return;
    try {
      final List<String> addrs = await Future.wait(<Future<String>>[
        Geocoder.getAddress(_waypoints.first.latitude, _waypoints.first.longitude),
        Geocoder.getAddress(_waypoints.last.latitude, _waypoints.last.longitude),
      ]);
      if (mounted) {
        setState(() {
          _startLocationCtrl.text = Geocoder.cleanPlaceName(addrs[0]);
          _endLocationCtrl.text = Geocoder.cleanPlaceName(addrs[1]);
        });
      }
    } catch (_) {}
  }

  bool get _isLoop {
    if (_waypoints.length < 3) return false;
    const Distance dist = Distance();
    return dist(_waypoints.first, _waypoints.last) < 200;
  }

  int _findTurnaroundIndex(List<LatLng> pts) {
    if (pts.length < 3) return pts.length - 1;
    const Distance dist = Distance();
    final LatLng start = pts.first;
    double maxDist = 0;
    int idx = pts.length ~/ 2;
    for (int i = 0; i < pts.length; i++) {
      final double d = dist(start, pts[i]);
      if (d > maxDist) {
        maxDist = d;
        idx = i;
      }
    }
    return idx;
  }

  bool get _isSectionSelected {
    if (_sourceWaypoints.length < 2) return false;
    return _trimRange.start.round() > 0 ||
        _trimRange.end.round() < _sourceWaypoints.length - 1;
  }

  void _onTrimChanged(RangeValues values) {
    final int startIdx = values.start.round();
    final int endIdx = values.end.round();
    if (endIdx - startIdx < 1) return;
    setState(() {
      _trimRange = values;
      _waypoints.clear();
      _waypoints.addAll(_sourceWaypoints.sublist(startIdx, endIdx + 1));
    });
    _autoNameFromPlaces();
  }

  void _selectOutbound() {
    final int turn = _findTurnaroundIndex(_sourceWaypoints);
    if (turn >= 1) {
      _onTrimChanged(RangeValues(0, turn.toDouble()));
      _fitFullRoute();
    }
  }

  void _selectReturn() {
    final int turn = _findTurnaroundIndex(_sourceWaypoints);
    final int last = _sourceWaypoints.length - 1;
    if (last - turn >= 1) {
      _onTrimChanged(RangeValues(turn.toDouble(), last.toDouble()));
      _fitFullRoute();
    }
  }

  void _selectFull() {
    _onTrimChanged(RangeValues(0, (_sourceWaypoints.length - 1).toDouble()));
    _fitFullRoute();
  }

  void _revertToOriginal() {
    setState(() {
      _waypoints.clear();
      _waypoints.addAll(_initialWaypoints);
      _sourceWaypoints = List<LatLng>.from(_initialWaypoints);
      if (_sourceWaypoints.length >= 2) {
        _trimRange = RangeValues(0, (_sourceWaypoints.length - 1).toDouble());
      }
      _canEditTrail = false;
    });
    _showSnack('Reverted to original route.');
    _autoNameFromPlaces();
    if (_waypoints.length >= 2) {
      _fitFullRoute();
    }
  }

  Future<void> _searchPlaceAlongRoute() async {
    final String query = _placeSearchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearchingPlace = true;
      _searchResults.clear();
    });

    try {
      final List<GeocodeSearchResult> geoResults =
          await Geocoder.searchPlaces(query);

      const Distance dist = Distance();
      final List<_RouteStopMatch> matches = <_RouteStopMatch>[];

      for (final GeocodeSearchResult geo in geoResults) {
        final LatLng target = LatLng(geo.lat, geo.lon);
        int nearestIdx = 0;
        double minD = double.infinity;

        for (int i = 0; i < _sourceWaypoints.length; i++) {
          final double d = dist(target, _sourceWaypoints[i]);
          if (d < minD) {
            minD = d;
            nearestIdx = i;
          }
        }

        // Calculate approximate distance along route from start to this point
        double distFromStartKm = 0;
        for (int i = 0; i < nearestIdx; i++) {
          distFromStartKm += dist(_sourceWaypoints[i], _sourceWaypoints[i + 1]);
        }
        distFromStartKm /= 1000;

        matches.add(_RouteStopMatch(
          name: geo.name,
          address: geo.address,
          pointIndex: nearestIdx,
          distanceKmFromStart: distFromStartKm,
          distanceMetersFromTrail: minD,
        ));
      }

      if (mounted) {
        setState(() {
          _searchResults = matches;
          _isSearchingPlace = false;
        });
        if (matches.isEmpty) {
          _showSnack('No locations matching "$query" found.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingPlace = false);
        _showSnack('Search failed: $e');
      }
    }
  }

  void _trimUpTo(int pointIndex, String placeName) {
    if (pointIndex < 1) {
      _showSnack('Selected stop is at the start of the route.');
      return;
    }
    _onTrimChanged(RangeValues(0, pointIndex.toDouble()));
    _nameCtrl.text = '$_startPlace – $placeName';
    _showSnack('Trimmed route up to $placeName (Point ${pointIndex + 1})');
    _fitFullRoute();
  }

  void _trimFromHere(int pointIndex, String placeName) {
    if (pointIndex >= _sourceWaypoints.length - 1) {
      _showSnack('Selected stop is at the end of the route.');
      return;
    }
    _onTrimChanged(RangeValues(pointIndex.toDouble(), (_sourceWaypoints.length - 1).toDouble()));
    _nameCtrl.text = '$placeName – $_endPlace';
    _showSnack('Set start from $placeName (Point ${pointIndex + 1})');
    _fitFullRoute();
  }

  Future<void> _detectMajorStops() async {
    if (_sourceWaypoints.length < 10) return;
    try {
      final List<int> sampleIndices = <int>[
        (_sourceWaypoints.length * 0.25).round(),
        (_sourceWaypoints.length * 0.50).round(),
        (_sourceWaypoints.length * 0.75).round(),
      ];

      final List<_RouteQuickStop> stops = <_RouteQuickStop>[];
      for (final int idx in sampleIndices) {
        final LatLng pt = _sourceWaypoints[idx];
        final String addr = await Geocoder.getAddress(pt.latitude, pt.longitude);
        final String name = Geocoder.cleanPlaceName(addr);
        if (name != 'Place' && !stops.any((_RouteQuickStop s) => s.name == name)) {
          stops.add(_RouteQuickStop(name: name, pointIndex: idx));
        }
      }
      if (mounted && stops.isNotEmpty) {
        setState(() => _detectedStops = stops);
      }
    } catch (_) {}
  }

  double get _approxLengthKm {
    if (_waypoints.length < 2) return 0;
    const Distance haversine = Distance();
    double total = 0;
    for (int i = 0; i < _waypoints.length - 1; i++) {
      total += haversine(_waypoints[i], _waypoints[i + 1]);
    }
    return total / 1000;
  }

  void _fitFullRoute() {
    if (_waypoints.length >= 2) {
      _mapCtrl.fitBounds(_waypoints, padding: 50.0);
    } else if (_waypoints.isNotEmpty) {
      _mapCtrl.move(_waypoints.first, 14.0);
    }
  }

  Future<void> _autoNameFromPlaces({bool force = false}) async {
    if (_waypoints.length < 2) return;
    if (mounted) setState(() => _isAutoNaming = true);
    try {
      final LatLng startPt = _waypoints.first;
      final LatLng endPt = _waypoints.last;

      final List<String> addresses = await Future.wait(<Future<String>>[
        Geocoder.getAddress(startPt.latitude, startPt.longitude),
        Geocoder.getAddress(endPt.latitude, endPt.longitude),
      ]);

      final String start = Geocoder.cleanPlaceName(addresses[0]);
      final String end = Geocoder.cleanPlaceName(addresses[1]);

      if (mounted) {
        setState(() {
          _startPlace = start;
          _endPlace = end;
        });
      }

      final String suggested =
          start == end ? '$start (Round Trip Loop)' : '$start – $end';

      if (force ||
          _isSectionSelected ||
          _nameCtrl.text.trim().isEmpty ||
          _nameCtrl.text.trim().startsWith('History Route') ||
          _nameCtrl.text.trim().endsWith('(Round Trip Loop)') ||
          _nameCtrl.text.trim() == 'Unnamed Route') {
        _nameCtrl.text = suggested;
      }
    } catch (_) {}
    if (mounted) setState(() => _isAutoNaming = false);
  }

  Widget _buildEndpointBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 12),
              const SizedBox(width: 3),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(6, 4),
          painter: _TrianglePainter(color: color),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _startDebounce?.cancel();
    _endDebounce?.cancel();
    _startLocationCtrlField?.dispose();
    _endLocationCtrlField?.dispose();
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _placeSearchCtrl.dispose();
    super.dispose();
  }

  // ── Start & Destination Search & Road Routing Logic ────────────────

  void _onStartChanged(String val) {
    _startDebounce?.cancel();
    final String q = val.trim();
    if (q.isEmpty) {
      setState(() {
        _startSuggestions = <GeocodeSearchResult>[];
        _isSearchingStart = false;
        _startLocation = null;
      });
      return;
    }
    setState(() => _isSearchingStart = true);
    _startDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final List<GeocodeSearchResult> results = await Geocoder.searchPlaces(q);
        if (mounted) {
          setState(() {
            _startSuggestions = results;
            _isSearchingStart = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingStart = false);
      }
    });
  }

  void _onEndChanged(String val) {
    _endDebounce?.cancel();
    final String q = val.trim();
    if (q.isEmpty) {
      setState(() {
        _endSuggestions = <GeocodeSearchResult>[];
        _isSearchingEnd = false;
        _endLocation = null;
      });
      return;
    }
    setState(() => _isSearchingEnd = true);
    _endDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final List<GeocodeSearchResult> results = await Geocoder.searchPlaces(q);
        if (mounted) {
          setState(() {
            _endSuggestions = results;
            _isSearchingEnd = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingEnd = false);
      }
    });
  }

  void _selectStartPlace(GeocodeSearchResult place) {
    FocusScope.of(context).unfocus();
    final LatLng pos = LatLng(place.lat, place.lon);
    setState(() {
      _startLocation = pos;
      _startLocationCtrl.text = place.name;
      _startSuggestions = <GeocodeSearchResult>[];
      _isSearchingStart = false;
    });
    _mapCtrl.move(pos, 14.5);
    if (_endLocation != null) {
      _calculateRoadRoute();
    }
  }

  void _selectEndPlace(GeocodeSearchResult place) {
    FocusScope.of(context).unfocus();
    final LatLng pos = LatLng(place.lat, place.lon);
    setState(() {
      _endLocation = pos;
      _endLocationCtrl.text = place.name;
      _endSuggestions = <GeocodeSearchResult>[];
      _isSearchingEnd = false;
    });
    _mapCtrl.move(pos, 14.5);
    if (_startLocation != null) {
      _calculateRoadRoute();
    }
  }

  void _swapStartAndEnd() {
    if (_startLocation == null && _endLocation == null) return;
    setState(() {
      final LatLng? tempLoc = _startLocation;
      _startLocation = _endLocation;
      _endLocation = tempLoc;

      final String tempText = _startLocationCtrl.text;
      _startLocationCtrl.text = _endLocationCtrl.text;
      _endLocationCtrl.text = tempText;

      _startSuggestions = <GeocodeSearchResult>[];
      _endSuggestions = <GeocodeSearchResult>[];
    });

    if (_startLocation != null && _endLocation != null) {
      _calculateRoadRoute();
    }
  }

  void _clearStart() {
    setState(() {
      _startLocation = null;
      _startLocationCtrl.clear();
      _startSuggestions = <GeocodeSearchResult>[];
      _isSearchingStart = false;
    });
  }

  void _clearEnd() {
    setState(() {
      _endLocation = null;
      _endLocationCtrl.clear();
      _endSuggestions = <GeocodeSearchResult>[];
      _isSearchingEnd = false;
    });
  }

  Future<void> _calculateRoadRoute() async {
    if (_startLocation == null || _endLocation == null) return;
    setState(() => _isRouting = true);

    try {
      final RouteResult? result = await RoutingService.getDirections(
        origin: _startLocation!,
        destination: _endLocation!,
        customApiKey: ref.read(authProvider).user?.apiKey,
      );

      if (!mounted) return;

      if (result != null && result.points.length >= 2) {
        setState(() {
          _waypoints.clear();
          _waypoints.addAll(result.points);
          _sourceWaypoints = List<LatLng>.from(result.points);
          _trimRange = RangeValues(0, (_sourceWaypoints.length - 1).toDouble());
          _routeDurationText = result.durationText;
          _routingSource = result.source;
          _isRouting = false;
        });

        final String sName = _startLocationCtrl.text.trim();
        final String eName = _endLocationCtrl.text.trim();
        if (sName.isNotEmpty && eName.isNotEmpty && (_nameCtrl.text.trim().isEmpty || _nameCtrl.text.contains('–'))) {
          _nameCtrl.text = '$sName – $eName';
        }

        _fitFullRoute();
        _showSnack('Road route: ${result.distanceKm.toStringAsFixed(1)} km (${result.durationText})');
      } else {
        // Fallback: direct connection
        setState(() {
          _waypoints.clear();
          _waypoints.addAll(<LatLng>[_startLocation!, _endLocation!]);
          _sourceWaypoints = List<LatLng>.from(_waypoints);
          _trimRange = const RangeValues(0, 1);
          _isRouting = false;
        });
        _fitFullRoute();
        _showSnack('Road network unavailable. Connected directly.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRouting = false);
        _showSnack('Route calculation error: $e');
      }
    }
  }

  Future<void> _save() async {
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('Please enter a route name.');
      return;
    }
    if (_waypoints.length < 2) {
      _showSnack('Please set start and destination locations or add waypoints.');
      return;
    }
    setState(() => _saving = true);

    final AppRoute route = AppRoute(
      id: widget.existing?.id ?? '',
      name: name,
      coordinates: List<LatLng>.from(_waypoints),
      toleranceMeters: _tolerance,
      vehicleIds: _selectedVehicleIds.toList(),
    );

    final RouteController ctrl = ref.read(routeProvider.notifier);
    AppRoute? saved;
    try {
      if (widget.existing == null) {
        saved = await ctrl.create(route, vehicleIds: _selectedVehicleIds.toList());
      } else {
        saved = await ctrl.update(route, vehicleIds: _selectedVehicleIds.toList());
      }

      if (saved == null) {
        setState(() => _saving = false);
        _showSnack(ref.read(routeProvider).error ?? 'Failed to save route.');
        return;
      }

      final AppRoute result = saved.copyWith(vehicleIds: _selectedVehicleIds.toList());

      // Refresh list in provider so changes immediately reflect everywhere
      await ctrl.load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedVehicleIds.isEmpty
                  ? 'Route "${result.name}" saved.'
                  : 'Route "${result.name}" saved and assigned to ${_selectedVehicleIds.length} vehicle${_selectedVehicleIds.length == 1 ? '' : 's'}.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      setState(() => _saving = false);
      _showSnack('Failed to save route: $e');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Map tap → smart start/destination or waypoint ──────────────────────────

  void _onTap(LatLng point) async {
    if (_saving || !_canEditTrail) return;

    // If start is empty, tap sets start
    if (_startLocation == null) {
      setState(() {
        _startLocation = point;
        _startLocationCtrl.text = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
      });
      _showSnack('Start point set. Tap map or search for destination.');
      try {
        final String addr = await Geocoder.getAddress(point.latitude, point.longitude);
        if (mounted) {
          setState(() => _startLocationCtrl.text = Geocoder.cleanPlaceName(addr));
        }
      } catch (_) {}
      return;
    }

    // If destination is empty, tap sets destination and triggers road route!
    if (_endLocation == null) {
      setState(() {
        _endLocation = point;
        _endLocationCtrl.text = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
      });
      try {
        final String addr = await Geocoder.getAddress(point.latitude, point.longitude);
        if (mounted) {
          setState(() => _endLocationCtrl.text = Geocoder.cleanPlaceName(addr));
        }
      } catch (_) {}
      await _calculateRoadRoute();
      return;
    }

    // Both set: tap appends detour point
    setState(() {
      _waypoints.add(point);
      _sourceWaypoints = List<LatLng>.from(_waypoints);
      _trimRange = RangeValues(0, (_sourceWaypoints.length - 1).toDouble());
    });
    if (_waypoints.length >= 2) {
      await _autoNameFromPlaces();
    }
  }


  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final List<Vehicle> vehicles = ref.watch(fleetProvider).vehicles;

    final List<Vehicle> filteredVehicles = vehicles.where((Vehicle v) {
      if (_searchQuery.isEmpty) return true;
      final String q = _searchQuery.toLowerCase();
      return v.displayName.toLowerCase().contains(q) ||
          v.name.toLowerCase().contains(q) ||
          v.registrationNumber.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: Text(
          widget.existing == null ? 'Draw Route' : 'Edit Route',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                      minimumSize: const Size(60, 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // ── Map ────────────────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              children: <Widget>[
                AppMap(
                  mapType: MapStyleX.fromKey(ref.read(secureStoreProvider).mapType).name,
                  apiKey: ref.read(authProvider).user?.apiKey,
                  initialCenter: _waypoints.isNotEmpty
                      ? _waypoints.first
                      : const LatLng(17.385, 78.4867),
                  initialZoom: 13,
                  onMapCreated: (AppMapController controller) {
                    _mapCtrl.setInner(controller);
                    Future<void>.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) _fitFullRoute();
                    });
                  },
                  onTap: _onTap,
                  polylines: [
                    if (_waypoints.length >= 2) ...<AppPolyline>[
                      // Outer casing for contrast on dark and light maps
                      AppPolyline(
                        id: 'route_trail_casing',
                        points: _waypoints,
                        color: Colors.black.withOpacity(0.55),
                        strokeWidth: 7,
                      ),
                      // Core radiant trail
                      AppPolyline(
                        id: 'route_trail_core',
                        points: _waypoints,
                        color: const Color(0xFF00C6FF),
                        strokeWidth: 4.5,
                      ),
                    ],
                  ],
                  markers: [
                    if (_waypoints.isNotEmpty)
                      AppMarker(
                        id: 'route_start',
                        position: _waypoints.first,
                        width: _isLoop ? 125 : 80,
                        height: 40,
                        alignment: Alignment.topCenter,
                        widget: _buildEndpointBadge(
                          label: _isLoop ? 'START & FINISH' : 'START',
                          icon: _isLoop
                              ? Icons.all_inclusive_rounded
                              : Icons.play_arrow_rounded,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    if (_waypoints.length >= 2 && !_isLoop)
                      AppMarker(
                        id: 'route_end',
                        position: _waypoints.last,
                        width: 80,
                        height: 40,
                        alignment: Alignment.topCenter,
                        widget: _buildEndpointBadge(
                          label: 'END',
                          icon: Icons.flag_rounded,
                          color: const Color(0xFFEF4444),
                        ),
                      ),
                    if (_isLoop && _waypoints.length >= 4)
                      AppMarker(
                        id: 'route_turnaround',
                        position: _waypoints[_findTurnaroundIndex(_waypoints)],
                        width: 115,
                        height: 40,
                        alignment: Alignment.topCenter,
                        widget: _buildEndpointBadge(
                          label: 'TURNAROUND',
                          icon: Icons.sync_alt_rounded,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                  ],
                ),
                // ── Start & Destination Search Panel (Floating on Map) ─────
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: _buildLocationSearchCard(isDark, theme),
                ),

                // Hint overlay
                if (_waypoints.isEmpty && !_isSearchCardExpanded)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: Corners.rPill,
                        ),
                        child: const Text(
                          'Search locations above or tap map to set route',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),

                // Map control buttons (Fit Full Route, Lock/Edit, Undo, Revert)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (_waypoints.length >= 2)
                        FloatingActionButton.small(
                          heroTag: 'fit_bounds',
                          tooltip: 'Fit Full Route',
                          onPressed: _fitFullRoute,
                          backgroundColor: scheme.surface,
                          foregroundColor: scheme.onSurface,
                          child: const Icon(Icons.fit_screen_rounded, size: 20),
                        ),
                      if (_waypoints.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'lock_trail',
                          tooltip: _canEditTrail
                              ? 'Trail editing active (Tap to lock trail)'
                              : 'Trail locked (Tap to edit/add points)',
                          onPressed: () {
                            setState(() => _canEditTrail = !_canEditTrail);
                            _showSnack(_canEditTrail
                                ? 'Trail editing enabled: Click map to add points'
                                : 'Trail locked: Map clicks will not modify trail');
                          },
                          backgroundColor: _canEditTrail
                              ? const Color(0xFFF59E0B)
                              : scheme.surface,
                          foregroundColor:
                              _canEditTrail ? Colors.black : scheme.onSurface,
                          child: Icon(
                            _canEditTrail
                                ? Icons.edit_road_rounded
                                : Icons.lock_rounded,
                            size: 19,
                          ),
                        ),
                      ],
                      if (_canEditTrail && _waypoints.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'undo',
                          tooltip: 'Undo last point',
                          onPressed: () {
                            setState(() => _waypoints.removeLast());
                            if (_waypoints.length >= 2) {
                              _autoNameFromPlaces();
                            }
                          },
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.onErrorContainer,
                          child: const Icon(Icons.undo_rounded, size: 18),
                        ),
                      ],
                      if (_initialWaypoints.isNotEmpty &&
                          (_waypoints.length != _initialWaypoints.length || _isSectionSelected)) ...<Widget>[
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'revert_trail',
                          tooltip:
                              'Revert to original route (${_initialWaypoints.length} points)',
                          onPressed: _revertToOriginal,
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          child: const Icon(Icons.restore_rounded, size: 19),
                        ),
                      ],
                    ],
                  ),
                ),
                // Floating distance & points info badge
                if (_waypoints.length >= 2)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.route_rounded,
                              size: 13, color: Color(0xFF00C6FF)),
                          const SizedBox(width: 4),
                          Text(
                            '${_approxLengthKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•  ${_waypoints.length} points',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Settings panel ─────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.md, Gap.sm, Gap.md, Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: Gap.sm),
                  // ── Route Section Trimmer / Loop Selector ─────────────────
                  if (_sourceWaypoints.length >= 4)
                    Container(
                      margin: const EdgeInsets.only(bottom: Gap.sm),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isSectionSelected
                              ? const Color(0xFF00C6FF)
                              : scheme.outlineVariant.withOpacity(0.4),
                          width: _isSectionSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Icon(Icons.linear_scale_rounded,
                                  size: 16, color: Color(0xFF00C6FF)),
                              const SizedBox(width: 6),
                              const Text(
                                'Select Route Section / Trim Trail',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_waypoints.length} / ${_sourceWaypoints.length} points',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Quick selection presets for Round Trips / Loops & Search
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              ActionChip(
                                avatar: const Icon(Icons.all_inclusive_rounded,
                                    size: 13),
                                label: const Text('Full Trip (100%)',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                onPressed: _selectFull,
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.arrow_forward_rounded,
                                    size: 13, color: Color(0xFF10B981)),
                                label: const Text('Outbound (Start ➔ Turn)',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                onPressed: _selectOutbound,
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.arrow_back_rounded,
                                    size: 13, color: Color(0xFFEF4444)),
                                label: const Text('Return (Turn ➔ End)',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                                onPressed: _selectReturn,
                              ),
                              ActionChip(
                                avatar: Icon(
                                  _showPlaceSearch
                                      ? Icons.close_rounded
                                      : Icons.search_rounded,
                                  size: 13,
                                  color: const Color(0xFF00C6FF),
                                ),
                                label: Text(
                                  _showPlaceSearch
                                      ? 'Close Search'
                                      : 'Search Stop / Town',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF00C6FF),
                                      fontWeight: FontWeight.w600),
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  setState(() {
                                    _showPlaceSearch = !_showPlaceSearch;
                                    if (!_showPlaceSearch) {
                                      _searchResults.clear();
                                      _placeSearchCtrl.clear();
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                          // Quick detected stops along the route
                          if (_detectedStops.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                const Text('Stops: ',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white54,
                                        fontWeight: FontWeight.w600)),
                                for (final _RouteQuickStop qs in _detectedStops)
                                  InkWell(
                                    onTap: () =>
                                        _trimUpTo(qs.pointIndex, qs.name),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.08),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border:
                                            Border.all(color: Colors.white12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          const Icon(Icons.location_on_rounded,
                                              size: 10,
                                              color: Color(0xFF00C6FF)),
                                          const SizedBox(width: 3),
                                          Text(
                                            'Up to ${qs.name}',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          // Place Search Bar & Results
                          if (_showPlaceSearch) ...<Widget>[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: const Color(0xFF00C6FF)
                                        .withOpacity(0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: TextField(
                                          controller: _placeSearchCtrl,
                                          autofocus: true,
                                          style:
                                              const TextStyle(fontSize: 12),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText:
                                                'Search city or town (e.g. Vijayawada, Kondapalli)...',
                                            hintStyle: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white54),
                                            prefixIcon: const Icon(
                                                Icons.search_rounded,
                                                size: 16,
                                                color: Color(0xFF00C6FF)),
                                            suffixIcon: _placeSearchCtrl
                                                    .text.isNotEmpty
                                                ? IconButton(
                                                    icon: const Icon(
                                                        Icons.clear,
                                                        size: 14),
                                                    onPressed: () {
                                                      _placeSearchCtrl.clear();
                                                      setState(() =>
                                                          _searchResults
                                                              .clear());
                                                    },
                                                  )
                                                : null,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 6),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              borderSide: const BorderSide(
                                                  color: Colors.white24),
                                            ),
                                          ),
                                          onSubmitted: (_) =>
                                              _searchPlaceAlongRoute(),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          visualDensity:
                                              VisualDensity.compact,
                                        ),
                                        onPressed: _isSearchingPlace
                                            ? null
                                            : _searchPlaceAlongRoute,
                                        child: _isSearchingPlace
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white),
                                              )
                                            : const Text('Search',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  if (_searchResults.isNotEmpty) ...<Widget>[
                                    const SizedBox(height: 6),
                                    for (final _RouteStopMatch match
                                        in _searchResults)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.06),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.white12),
                                        ),
                                        child: Row(
                                          children: <Widget>[
                                            const Icon(
                                                Icons.location_on_rounded,
                                                size: 14,
                                                color: Color(0xFF00C6FF)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Text(
                                                    match.name,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Colors.white),
                                                  ),
                                                  Text(
                                                    'Point #${match.pointIndex + 1} • ~${match.distanceKmFromStart.toStringAsFixed(1)} km from start',
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color:
                                                            Colors.white70),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            FilledButton.tonal(
                                              style: FilledButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8),
                                              ),
                                              onPressed: () => _trimUpTo(
                                                  match.pointIndex, match.name),
                                              child: const Text(
                                                  'Trim up to here 🏁',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                            const SizedBox(width: 4),
                                            OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6),
                                              ),
                                              onPressed: () => _trimFromHere(
                                                  match.pointIndex, match.name),
                                              child: const Text('Start here 🟢',
                                                  style: TextStyle(fontSize: 10)),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          RangeSlider(
                            values: _trimRange,
                            min: 0,
                            max: (_sourceWaypoints.length - 1).toDouble(),
                            divisions: (_sourceWaypoints.length - 1).clamp(1, 200),
                            labels: RangeLabels(
                              'Start (#${_trimRange.start.round() + 1})',
                              'End (#${_trimRange.end.round() + 1})',
                            ),
                            onChanged: _onTrimChanged,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                '🟢 Start: Point ${_trimRange.start.round() + 1}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w600),
                              ),
                              if (_isSectionSelected)
                                InkWell(
                                  onTap: _selectFull,
                                  child: const Text(
                                    'Reset to Full',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF00C6FF),
                                        decoration: TextDecoration.underline),
                                  ),
                                ),
                              Text(
                                '🔴 End: Point ${_trimRange.end.round() + 1}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFEF4444),
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  // Places strip
                  if (_startPlace.isNotEmpty || _endPlace.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      margin: const EdgeInsets.only(bottom: Gap.sm),
                      decoration: BoxDecoration(
                        color:
                            scheme.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: scheme.outlineVariant.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.circle,
                              size: 8, color: Color(0xFF10B981)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _startPlace.isNotEmpty ? _startPlace : 'Start',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 12, color: Colors.grey),
                          ),
                          const Icon(Icons.circle,
                              size: 8, color: Color(0xFFEF4444)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _endPlace.isNotEmpty ? _endPlace : 'End',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => _autoNameFromPlaces(force: true),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.auto_fix_high_rounded,
                                      size: 12, color: AppColors.brand),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Auto-name',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Name field
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Route Name',
                      hintText: 'e.g. Place A – Place B',
                      prefixIcon: const Icon(Icons.route_rounded),
                      suffixIcon: IconButton(
                        icon: _isAutoNaming
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_fix_high_rounded,
                                color: AppColors.brand, size: 18),
                        tooltip: 'Auto-detect Route Name (Start – End)',
                        onPressed: () => _autoNameFromPlaces(force: true),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: Corners.rMd),
                    ),
                  ),
                  const SizedBox(height: Gap.md),

                  // Tolerance slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        'Deviation Tolerance',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${_tolerance.round()} m',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _tolerance,
                    min: 50,
                    max: 2000,
                    divisions: 39,
                    label: '${_tolerance.round()} m',
                    activeColor: AppColors.brand,
                    onChanged: (double v) =>
                        setState(() => _tolerance = v),
                  ),
                  Text(
                    'Alert will fire when vehicle moves more than '
                    '${_tolerance.round()} m from the route.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),

                  const SizedBox(height: Gap.lg),
                  const Divider(),
                  const SizedBox(height: Gap.xs),

                  // Vehicle assignment header with count & quick actions
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          children: <Widget>[
                            Text(
                              'Assign to Vehicles',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _selectedVehicleIds.isNotEmpty
                                    ? AppColors.brand.withOpacity(0.15)
                                    : scheme.surfaceContainerHighest,
                                borderRadius: Corners.rPill,
                                border: Border.all(
                                  color: _selectedVehicleIds.isNotEmpty
                                      ? AppColors.brand
                                      : scheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                '${_selectedVehicleIds.length} of ${vehicles.length} selected',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _selectedVehicleIds.isNotEmpty
                                      ? AppColors.brand
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Quick action buttons
                      TextButton(
                        onPressed: vehicles.isEmpty
                            ? null
                            : () => setState(() {
                                  _selectedVehicleIds.addAll(
                                      vehicles.map((Vehicle v) => v.id));
                                }),
                        child: const Text('Select All', style: TextStyle(fontSize: 12)),
                      ),
                      if (_selectedVehicleIds.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _selectedVehicleIds.clear()),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Clear', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),

                  const SizedBox(height: Gap.xs),

                  // Search filter
                  if (vehicles.length > 5) ...<Widget>[
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (String text) => setState(() => _searchQuery = text.trim()),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search vehicle by number or name...',
                        hintStyle: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: scheme.outlineVariant),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                  ],

                  if (vehicles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No vehicles found in your fleet.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else if (filteredVehicles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No vehicles match "$_searchQuery".',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: filteredVehicles.map((Vehicle v) {
                        final bool isSelected =
                            _selectedVehicleIds.contains(v.id);
                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedVehicleIds.remove(v.id);
                              } else {
                                _selectedVehicleIds.add(v.id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.brand
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.brand
                                    : scheme.outlineVariant.withOpacity(0.5),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.brand.withOpacity(0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.directions_car_rounded,
                                  size: 15,
                                  color: isSelected
                                      ? Colors.white
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  v.displayName,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : scheme.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: Gap.xl),

                  // Bottom Save button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        shape: RoundedRectangleBorder(borderRadius: Corners.rMd),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _saving
                            ? 'Saving...'
                            : widget.existing == null
                                ? 'Create & Assign Route (${_selectedVehicleIds.length} Vehicles)'
                                : 'Update Route & Assignments (${_selectedVehicleIds.length} Vehicles)',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSearchCard(bool isDark, ThemeData theme) {
    final List<GeocodeSearchResult> sSuggs = _startSuggestions;
    final List<GeocodeSearchResult> eSuggs = _endSuggestions;
    final TextEditingController sCtrl = _startLocationCtrl;
    final TextEditingController eCtrl = _endLocationCtrl;
    final bool isExp = _isSearchCardExpanded;
    final bool isRoute = _isRouting;
    final bool isSearchS = _isSearchingStart;
    final bool isSearchE = _isSearchingEnd;

    final bool hasSuggestions = sSuggs.isNotEmpty || eSuggs.isNotEmpty;
    final Color cardBg = isDark ? const Color(0xFF1E293B).withOpacity(0.96) : Colors.white.withOpacity(0.96);
    final Color borderColor = isDark ? Colors.white12 : Colors.black12;

    return Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header bar
            InkWell(
              onTap: () => setState(() => _isSearchCardExpanded = !isExp),
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(16),
                bottom: isExp ? Radius.zero : const Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.alt_route_rounded, color: Color(0xFF00C6FF), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Route Locations',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isRoute) ...<Widget>[
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C6FF)),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Snapping route...',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ] else if (_waypoints.length >= 2) ...<Widget>[
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  '${_approxLengthKm.toStringAsFixed(1)} km${_routeDurationText != null && _routeDurationText!.isNotEmpty ? " • $_routeDurationText" : ""}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ),
                            ),
                            if (_routingSource != null) ...<Widget>[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00C6FF).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _routingSource!,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF00C6FF),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ] else ...<Widget>[
                      const Spacer(),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      isExp ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ],
                ),
              ),
            ),

            if (isExp) ...<Widget>[
              Divider(height: 1, color: borderColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // Left route line indicator (Green dot -> line -> Red pin)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 1.5,
                          height: 28,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 14),
                      ],
                    ),
                    const SizedBox(width: 10),

                    // Inputs Column
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // Start Location Input
                          SizedBox(
                            height: 36,
                            child: TextField(
                              controller: sCtrl,
                              onChanged: _onStartChanged,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search start location or tap map...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                filled: true,
                                fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: sCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 15),
                                        onPressed: _clearStart,
                                        splashRadius: 14,
                                        padding: EdgeInsets.zero,
                                      )
                                    : (isSearchS
                                        ? const Padding(
                                            padding: EdgeInsets.all(10),
                                            child: SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : null),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Destination Location Input
                          SizedBox(
                            height: 36,
                            child: TextField(
                              controller: eCtrl,
                              onChanged: _onEndChanged,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search destination location or tap map...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                filled: true,
                                fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: eCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 15),
                                        onPressed: _clearEnd,
                                        splashRadius: 14,
                                        padding: EdgeInsets.zero,
                                      )
                                    : (isSearchE
                                        ? const Padding(
                                            padding: EdgeInsets.all(10),
                                            child: SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          )
                                        : null),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Swap Button
                    IconButton(
                      icon: const Icon(Icons.swap_vert_rounded),
                      tooltip: 'Swap start and destination',
                      color: isDark ? Colors.white70 : Colors.black54,
                      onPressed: _swapStartAndEnd,
                    ),
                  ],
                ),
              ),

              // Autocomplete suggestions list
              if (hasSuggestions) ...<Widget>[
                Divider(height: 1, color: borderColor),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: sSuggs.isNotEmpty
                        ? sSuggs.length
                        : eSuggs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                    itemBuilder: (BuildContext context, int index) {
                      final bool isStart = sSuggs.isNotEmpty;
                      final GeocodeSearchResult item =
                          isStart ? sSuggs[index] : eSuggs[index];
                      return InkWell(
                        onTap: () => isStart ? _selectStartPlace(item) : _selectEndPlace(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                isStart ? Icons.trip_origin_rounded : Icons.location_on_outlined,
                                size: 17,
                                color: isStart ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (item.address.isNotEmpty) ...<Widget>[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.address,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    final Path path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RouteStopMatch {
  _RouteStopMatch({
    required this.name,
    required this.address,
    required this.pointIndex,
    required this.distanceKmFromStart,
    required this.distanceMetersFromTrail,
  });

  final String name;
  final String address;
  final int pointIndex;
  final double distanceKmFromStart;
  final double distanceMetersFromTrail;
}

class _RouteQuickStop {
  _RouteQuickStop({
    required this.name,
    required this.pointIndex,
  });

  final String name;
  final int pointIndex;
}

