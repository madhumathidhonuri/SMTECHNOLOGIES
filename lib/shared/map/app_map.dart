import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart' as ll;

import 'app_map_models.dart';
import 'app_map_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/brand_config.dart';

class _FmAppMapController implements AppMapController {
  final fm.MapController _controller;
  _FmAppMapController(this._controller);

  @override
  void move(ll.LatLng center, double zoom) {
    _controller.move(center, zoom);
  }

  @override
  void fitBounds(List<ll.LatLng> points, {double padding = 50.0}) {
    if (points.isEmpty) return;
    final bounds = fm.LatLngBounds.fromPoints(points);
    _controller.fitCamera(
      fm.CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.all(padding),
      ),
    );
  }

  @override
  double getZoom() => _controller.camera.zoom;

  @override
  ll.LatLng getCenter() => _controller.camera.center;
}

class _GmAppMapController implements AppMapController {
  final gm.GoogleMapController _controller;
  double _currentZoom = 13.0;
  ll.LatLng _currentCenter = const ll.LatLng(0, 0);

  _GmAppMapController(this._controller);

  @override
  void move(ll.LatLng center, double zoom) {
    _currentZoom = zoom;
    _currentCenter = center;
    _controller.animateCamera(
      gm.CameraUpdate.newCameraPosition(
        gm.CameraPosition(
          target: gm.LatLng(center.latitude, center.longitude),
          zoom: zoom,
        ),
      ),
    );
  }

  @override
  void fitBounds(List<ll.LatLng> points, {double padding = 50.0}) {
    if (points.isEmpty) return;
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
    _controller.animateCamera(
      gm.CameraUpdate.newLatLngBounds(
        gm.LatLngBounds(
          southwest: gm.LatLng(minLat, minLng),
          northeast: gm.LatLng(maxLat, maxLng),
        ),
        padding,
      ),
    );
  }

  @override
  double getZoom() => _currentZoom;

  @override
  ll.LatLng getCenter() => _currentCenter;
}

class AppMap extends StatefulWidget {
  final String mapType; // 'osm', 'google', 'satellite'
  final String? apiKey;
  final ll.LatLng initialCenter;
  final double initialZoom;
  final List<AppMarker> markers;
  final List<AppPolyline> polylines;
  final List<AppCircle> circles;
  final List<AppPolygon> polygons;
  final void Function(AppMapController controller)? onMapCreated;
  final void Function(ll.LatLng)? onTap;

  const AppMap({
    Key? key,
    this.mapType = 'google',
    this.apiKey,
    required this.initialCenter,
    this.initialZoom = 13.0,
    this.markers = const [],
    this.polylines = const [],
    this.circles = const [],
    this.polygons = const [],
    this.onMapCreated,
    this.onTap,
  }) : super(key: key);

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  final fm.MapController _fmController = fm.MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isOsm) {
        widget.onMapCreated?.call(_FmAppMapController(_fmController));
      }
    });
  }

  String get _effectiveApiKey =>
      (widget.apiKey != null && widget.apiKey!.isNotEmpty)
          ? widget.apiKey!
          : AppConfig.googleMapsApiKey;

  bool get _isOsm => widget.mapType == 'osm' && _effectiveApiKey.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isOsm) {
      return _buildFlutterMap(context);
    } else {
      return _buildGoogleMap(context);
    }
  }

  Widget _buildFlutterMap(BuildContext context) {
    final String key = _effectiveApiKey;
    final String keyParam = key.isNotEmpty ? '&key=$key' : '';

    final Widget tileLayer = fm.TileLayer(
      key: const ValueKey<String>('app_map_tile_layer'),
      urlTemplate: widget.mapType == 'satellite'
          ? 'https://mt{s}.google.com/vt/lyrs=y&scale=2&x={x}&y={y}&z={z}$keyParam'
          : 'https://mt{s}.google.com/vt/lyrs=m&scale=2&x={x}&y={y}&z={z}$keyParam',
      subdomains: const <String>['0', '1', '2', '3'],
      maxNativeZoom: 20,
      maxZoom: 22.0,
      userAgentPackageName: BrandConfig.applicationId,
      panBuffer: 4,
      keepBuffer: 6,
      tileDisplay: const fm.TileDisplay.instantaneous(),
    );

    return fm.FlutterMap(
      mapController: _fmController,
      options: fm.MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        onTap: (tapPosition, point) => widget.onTap?.call(point),
      ),
      children: [
        tileLayer,
        if (widget.polygons.isNotEmpty)
          fm.PolygonLayer(
            polygons: widget.polygons.map((p) => fm.Polygon(
              points: p.points,
              color: p.fillColor,
              borderColor: p.strokeColor,
              borderStrokeWidth: p.strokeWidth,
            )).toList(),
          ),
        if (widget.polylines.isNotEmpty)
          fm.PolylineLayer(
            polylines: widget.polylines.map((p) => fm.Polyline(
              points: p.points,
              color: p.color,
              strokeWidth: p.strokeWidth,
            )).toList(),
          ),
        if (widget.circles.isNotEmpty)
          fm.CircleLayer(
            circles: widget.circles.map((c) => fm.CircleMarker(
              point: c.center,
              radius: c.radiusMeters,
              useRadiusInMeter: true,
              color: c.fillColor,
              borderColor: c.strokeColor,
              borderStrokeWidth: c.strokeWidth,
            )).toList(),
          ),
        if (widget.markers.isNotEmpty)
          fm.MarkerLayer(
            markers: widget.markers.map((m) => fm.Marker(
              point: m.position,
              width: m.width,
              height: m.height,
              alignment: m.alignment,
              child: GestureDetector(
                onTap: m.onTap,
                child: m.widget,
              ),
            )).toList(),
          ),
      ],
    );
  }

  Widget _buildGoogleMap(BuildContext context) {
    return gm.GoogleMap(
      style: null,
      initialCameraPosition: gm.CameraPosition(
        target: gm.LatLng(widget.initialCenter.latitude, widget.initialCenter.longitude),
        zoom: widget.initialZoom,
      ),
      mapType: widget.mapType == 'satellite' ? gm.MapType.satellite : gm.MapType.normal,
      onMapCreated: (controller) {
        widget.onMapCreated?.call(_GmAppMapController(controller));
      },
      onTap: (pos) => widget.onTap?.call(ll.LatLng(pos.latitude, pos.longitude)),
      markers: widget.markers.map((m) {
        return gm.Marker(
          markerId: gm.MarkerId(m.id),
          position: gm.LatLng(m.position.latitude, m.position.longitude),
          onTap: m.onTap,
          icon: m.hue != null
              ? gm.BitmapDescriptor.defaultMarkerWithHue(m.hue!)
              : gm.BitmapDescriptor.defaultMarker,
        );
      }).toSet(),
      polylines: widget.polylines.map((p) {
        return gm.Polyline(
          polylineId: gm.PolylineId(p.id),
          points: p.points.map((pt) => gm.LatLng(pt.latitude, pt.longitude)).toList(),
          color: p.color,
          width: p.strokeWidth.toInt(),
        );
      }).toSet(),
      circles: widget.circles.map((c) {
        return gm.Circle(
          circleId: gm.CircleId(c.id),
          center: gm.LatLng(c.center.latitude, c.center.longitude),
          radius: c.radiusMeters,
          fillColor: c.fillColor,
          strokeColor: c.strokeColor,
          strokeWidth: c.strokeWidth.toInt(),
        );
      }).toSet(),
      polygons: widget.polygons.map((p) {
        return gm.Polygon(
          polygonId: gm.PolygonId(p.id),
          points: p.points.map((pt) => gm.LatLng(pt.latitude, pt.longitude)).toList(),
          fillColor: p.fillColor,
          strokeColor: p.strokeColor,
          strokeWidth: p.strokeWidth.toInt(),
        );
      }).toSet(),
    );
  }
}
