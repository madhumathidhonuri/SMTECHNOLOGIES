import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../data/models/vehicle.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/live_address.dart';
import 'dart:math' as math;

class NavigationHUD extends StatelessWidget {
  const NavigationHUD({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24 + MediaQuery.paddingOf(context).bottom, // Clears system safe area
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1020).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left side: Speedometer and Fuel
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SmallSpeedometerWidget(vehicle: vehicle),
                const SizedBox(height: 12),
                _FuelLevelWidget(vehicle: vehicle),
              ],
            ),
            const SizedBox(width: 20),
            // Right side: Status, Direction, Address
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatusWidget(vehicle: vehicle),
                      const Spacer(),
                      _DirectionWidget(vehicle: vehicle),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'LOCATION',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LiveAddress(
                    vehicle: vehicle,
                    
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallSpeedometerWidget extends StatelessWidget {
  const _SmallSpeedometerWidget({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(60, 60),
            painter: _SmallSpeedGaugePainter(speed: vehicle.speed),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${vehicle.speed.toInt()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const Text(
                'km/h',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallSpeedGaugePainter extends CustomPainter {
  _SmallSpeedGaugePainter({required this.speed});
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    const double startDeg = 135;
    const double sweepDeg = 270;
    final double startRad = startDeg * math.pi / 180;
    final double sweepRad = sweepDeg * math.pi / 180;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    final double maxSpeed = 200;
    final double normalised = (speed.clamp(0.0, maxSpeed) / maxSpeed);
    final double activeSweep = sweepRad * normalised;

    if (activeSweep > 0) {
      final double blueEnd = activeSweep.clamp(0, sweepRad * 0.6);
      if (blueEnd > 0) {
        canvas.drawArc(
          rect,
          startRad,
          blueEnd,
          false,
          Paint()
            ..color = const Color(0xFF5C8DFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      }
      if (normalised > 0.6) {
        final double redStart = startRad + sweepRad * 0.6;
        final double redSweep = activeSweep - sweepRad * 0.6;
        canvas.drawArc(
          rect,
          redStart,
          redSweep,
          false,
          Paint()
            ..color = const Color(0xFFFF3B30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SmallSpeedGaugePainter old) => old.speed != speed;
}

class _FuelLevelWidget extends StatelessWidget {
  const _FuelLevelWidget({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final double fuel = vehicle.fuelLevel ?? 0.0;
    final bool hasFuel = vehicle.fuelLevel != null;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.local_gas_station_rounded,
          color: hasFuel ? (fuel > 20 ? Colors.greenAccent : Colors.redAccent) : Colors.white54,
          size: 18,
        ),
        const SizedBox(width: 6),
        Text(
          hasFuel ? '${fuel.toInt()} L' : 'N/A',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _StatusWidget extends StatelessWidget {
  const _StatusWidget({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final statusColor = AppColors.forStatus(vehicle.status.key);
    final String statusLabel = vehicle.status.key[0].toUpperCase() +
        vehicle.status.key.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusLabel,
            style: TextStyle(
              color: statusColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectionWidget extends StatelessWidget {
  const _DirectionWidget({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    String direction = 'N';
    final h = vehicle.heading % 360;
    if (h >= 337.5 || h < 22.5) direction = 'N';
    else if (h >= 22.5 && h < 67.5) direction = 'NE';
    else if (h >= 67.5 && h < 112.5) direction = 'E';
    else if (h >= 112.5 && h < 157.5) direction = 'SE';
    else if (h >= 157.5 && h < 202.5) direction = 'S';
    else if (h >= 202.5 && h < 247.5) direction = 'SW';
    else if (h >= 247.5 && h < 292.5) direction = 'W';
    else if (h >= 292.5 && h < 337.5) direction = 'NW';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.explore_outlined, color: Colors.white54, size: 16),
        const SizedBox(width: 4),
        Text(
          direction,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
