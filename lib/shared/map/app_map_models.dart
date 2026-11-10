import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

class AppMarker {
  final String id;
  final ll.LatLng position;
  final Widget widget;
  final Alignment alignment;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final double? hue;

  const AppMarker({
    required this.id,
    required this.position,
    required this.widget,
    this.alignment = Alignment.center,
    this.width = 40,
    this.height = 40,
    this.onTap,
    this.hue,
  });
}

class AppPolyline {
  final String id;
  final List<ll.LatLng> points;
  final Color color;
  final double strokeWidth;

  const AppPolyline({
    required this.id,
    required this.points,
    this.color = Colors.blue,
    this.strokeWidth = 3.0,
  });
}

class AppCircle {
  final String id;
  final ll.LatLng center;
  final double radiusMeters;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  const AppCircle({
    required this.id,
    required this.center,
    required this.radiusMeters,
    this.fillColor = const Color(0x330000FF),
    this.strokeColor = Colors.blue,
    this.strokeWidth = 2.0,
  });
}

class AppPolygon {
  final String id;
  final List<ll.LatLng> points;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  const AppPolygon({
    required this.id,
    required this.points,
    this.fillColor = const Color(0x330000FF),
    this.strokeColor = Colors.blue,
    this.strokeWidth = 2.0,
  });
}
