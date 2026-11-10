import 'package:latlong2/latlong.dart' as ll;

abstract class AppMapController {
  void move(ll.LatLng center, double zoom);
  void fitBounds(List<ll.LatLng> points, {double padding = 50.0});
  double getZoom();
  ll.LatLng getCenter();
}

class AppMapControllerWrapper implements AppMapController {
  AppMapController? _inner;

  void setInner(AppMapController inner) {
    _inner = inner;
  }

  @override
  void move(ll.LatLng center, double zoom) {
    _inner?.move(center, zoom);
  }

  @override
  void fitBounds(List<ll.LatLng> points, {double padding = 50.0}) {
    _inner?.fitBounds(points, padding: padding);
  }

  @override
  double getZoom() {
    return _inner?.getZoom() ?? 13.0;
  }

  @override
  ll.LatLng getCenter() {
    return _inner?.getCenter() ?? const ll.LatLng(0, 0);
  }
}
