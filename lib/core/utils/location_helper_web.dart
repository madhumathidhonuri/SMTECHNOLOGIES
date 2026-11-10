import 'dart:async';
import 'dart:html' as html;
import 'package:latlong2/latlong.dart';

Future<LatLng?> getBrowserCurrentLocation() async {
  try {
    final completer = Completer<LatLng?>();

    html.window.navigator.geolocation.getCurrentPosition(
      enableHighAccuracy: true,
      timeout: const Duration(seconds: 6),
    ).then((html.Geoposition pos) {
      if (pos.coords?.latitude != null && pos.coords?.longitude != null) {
        completer.complete(
          LatLng(pos.coords!.latitude!.toDouble(), pos.coords!.longitude!.toDouble()),
        );
      } else {
        completer.complete(null);
      }
    }).catchError((_) {
      completer.complete(null);
    });

    return await completer.future.timeout(
      const Duration(seconds: 7),
      onTimeout: () => null,
    );
  } catch (_) {
    return null;
  }
}
