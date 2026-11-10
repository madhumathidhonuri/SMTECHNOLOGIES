import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/utils/formatters.dart';
import '../../../data/models/report_models.dart';
import '../../../data/models/trip.dart';
import '../../../data/models/vehicle.dart';
import 'map_tiles.dart';

/// Controller for interacting with [GoogleLiveMap].
class GoogleLiveMapController {
  gm.GoogleMapController? _raw;

  void attach(gm.GoogleMapController controller) {
    _raw = controller;
  }

  void move(ll.LatLng target, {double? zoom}) {
    if (_raw == null) return;
    if (zoom != null) {
      _raw!.animateCamera(
        gm.CameraUpdate.newLatLngZoom(
          gm.LatLng(target.latitude, target.longitude),
          zoom,
        ),
      );
    } else {
      _raw!.animateCamera(
        gm.CameraUpdate.newLatLng(
          gm.LatLng(target.latitude, target.longitude),
        ),
      );
    }
  }

  void fitBounds(List<ll.LatLng> points, {double padding = 50.0}) {
    if (_raw == null || points.isEmpty) return;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    _raw!.animateCamera(
      gm.CameraUpdate.newLatLngBounds(
        gm.LatLngBounds(
          southwest: gm.LatLng(minLat, minLng),
          northeast: gm.LatLng(maxLat, maxLng),
        ),
        padding,
      ),
    );
  }

  void zoomIn() => _raw?.animateCamera(gm.CameraUpdate.zoomIn());
  void zoomOut() => _raw?.animateCamera(gm.CameraUpdate.zoomOut());
}

/// Official native Google Map implementation with WebGL vector rendering,
/// zero tile grid lines, and smooth hardware acceleration.
class GoogleLiveMap extends StatefulWidget {
  const GoogleLiveMap({
    super.key,
    required this.controller,
    required this.vehicles,
    required this.style,
    required this.fallbackCenter,
    required this.selectedId,
    required this.followingId,
    required this.onMapReady,
    required this.onUserInteracting,
    required this.onTapMap,
    required this.onSelectVehicle,
    this.pendingFocusId,
    this.route = const <TrackPoint>[],
    this.stoppages = const <ReportRow>[],
    this.showTrail = false,
    this.onTapStoppage,
  });

  final GoogleLiveMapController controller;
  final List<Vehicle> vehicles;
  final MapStyle style;
  final ll.LatLng fallbackCenter;
  final String? selectedId;
  final String? followingId;
  final String? pendingFocusId;
  final VoidCallback onMapReady;
  final ValueChanged<bool> onUserInteracting;
  final VoidCallback onTapMap;
  final ValueChanged<Vehicle> onSelectVehicle;
  final List<TrackPoint> route;
  final List<ReportRow> stoppages;
  final bool showTrail;
  final void Function(ReportRow, int)? onTapStoppage;

  @override
  State<GoogleLiveMap> createState() => _GoogleLiveMapState();
}

class _GoogleLiveMapState extends State<GoogleLiveMap> {
  bool _isUserInteracting = false;
  String? _lastFollowingId;

  gm.MapType get _mapType => switch (widget.style) {
        MapStyle.satellite => gm.MapType.hybrid,
        MapStyle.terrain => gm.MapType.terrain,
        MapStyle.standard || MapStyle.google => gm.MapType.normal,
      };

  @override
  void didUpdateWidget(GoogleLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String? followingId = widget.followingId;
    if (followingId != null && !_isUserInteracting) {
      final Vehicle? fv = widget.vehicles.cast<Vehicle?>().firstWhere(
            (v) => v?.id == followingId,
            orElse: () => null,
          );
      if (fv != null && fv.hasLocation && fv.id != _lastFollowingId) {
        _lastFollowingId = fv.id;
        widget.controller.move(ll.LatLng(fv.latitude!, fv.longitude!));
      }
    }
  }

  double _hueForStatus(VehicleStatus status) {
    return switch (status) {
      VehicleStatus.moving => gm.BitmapDescriptor.hueGreen,
      VehicleStatus.idle => gm.BitmapDescriptor.hueOrange,
      VehicleStatus.stopped => gm.BitmapDescriptor.hueAzure,
      VehicleStatus.offline => gm.BitmapDescriptor.hueViolet,
      VehicleStatus.noData => gm.BitmapDescriptor.hueRose,
    };
  }

  Set<gm.Marker> _buildMarkers() {
    final Set<gm.Marker> markers = <gm.Marker>{};

    for (final v in widget.vehicles) {
      if (!v.hasLocation) continue;
      final bool isSelected = v.id == widget.selectedId;

      markers.add(
        gm.Marker(
          markerId: gm.MarkerId(v.id),
          position: gm.LatLng(v.latitude!, v.longitude!),
          rotation: v.heading.toDouble(),
          icon: gm.BitmapDescriptor.defaultMarkerWithHue(_hueForStatus(v.status)),
          zIndexInt: isSelected ? 10 : 1,
          infoWindow: gm.InfoWindow(
            title: v.displayName.toUpperCase(),
            snippet: '${v.speed.toStringAsFixed(0)} km/h • ${v.status.label}',
            onTap: () => widget.onSelectVehicle(v),
          ),
          onTap: () {
            widget.onSelectVehicle(v);
          },
        ),
      );
    }

    // Stoppages
    for (int i = 0; i < widget.stoppages.length; i++) {
      final stop = widget.stoppages[i];
      final lat = stop.startLat ?? stop.endLat;
      final lng = stop.startLng ?? stop.endLng;
      if (lat == null || lng == null) continue;

      final String durationSnippet = Fmt.secsToHms(stop.durationSecVal);

      markers.add(
        gm.Marker(
          markerId: gm.MarkerId('stop_${stop.vehicleId ?? i}_$i'),
          position: gm.LatLng(lat, lng),
          icon: gm.BitmapDescriptor.defaultMarkerWithHue(gm.BitmapDescriptor.hueRose),
          infoWindow: gm.InfoWindow(
            title: 'Stop #${i + 1}',
            snippet: durationSnippet,
            onTap: () => widget.onTapStoppage?.call(stop, i + 1),
          ),
          onTap: () => widget.onTapStoppage?.call(stop, i + 1),
        ),
      );
    }

    return markers;
  }

  Set<gm.Polyline> _buildPolylines() {
    final Set<gm.Polyline> polylines = <gm.Polyline>{};

    if (widget.showTrail && widget.route.isNotEmpty) {
      final List<gm.LatLng> pts = widget.route
          .where((p) => p.isValid)
          .map((p) => gm.LatLng(p.latitude, p.longitude))
          .toList();

      if (pts.isNotEmpty) {
        polylines.add(
          gm.Polyline(
            polylineId: const gm.PolylineId('live_trail'),
            points: pts,
            color: const Color(0xFF4F6BFF),
            width: 5,
            geodesic: true,
            jointType: gm.JointType.round,
            startCap: gm.Cap.roundCap,
            endCap: gm.Cap.roundCap,
          ),
        );
      }
    }

    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    return gm.GoogleMap(
      initialCameraPosition: gm.CameraPosition(
        target: gm.LatLng(
          widget.fallbackCenter.latitude,
          widget.fallbackCenter.longitude,
        ),
        zoom: 15.0,
      ),
      mapType: _mapType,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
      markers: _buildMarkers(),
      polylines: _buildPolylines(),
      onMapCreated: (gm.GoogleMapController controller) {
        widget.controller.attach(controller);
        widget.onMapReady();
      },
      onCameraMoveStarted: () {
        _isUserInteracting = true;
        widget.onUserInteracting(true);
      },
      onCameraIdle: () {
        _isUserInteracting = false;
        widget.onUserInteracting(false);
      },
      onTap: (_) => widget.onTapMap(),
    );
  }
}
