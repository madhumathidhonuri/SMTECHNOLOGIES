import 'package:flutter/material.dart';
import 'dart:math' as math;

class Vehicle3DMarker extends StatelessWidget {
  const Vehicle3DMarker({
    super.key,
    required this.bearing,
    this.useVespa = false,
    this.size = 60.0,
  });

  final double bearing;
  final bool useVespa;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: bearing * math.pi / 180,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            useVespa ? Icons.moped_rounded : Icons.directions_car_rounded,
            size: size * 0.6,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
