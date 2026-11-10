import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/vehicle_icons.dart';
import '../../../data/models/vehicle.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  VEHICLE MARKER — Teardrop map pin with white vehicle icon (as requested):
//  Compact status-colored pin with white vehicle icon in the circle head.
// ─────────────────────────────────────────────────────────────────────────────
class VehicleMarkerPin extends StatefulWidget {
  const VehicleMarkerPin({
    required this.vehicle,
    this.selected = false,
    this.showLabel = false,
    this.showSpeed = true,
    this.useSprite = false,
    this.headingOverride,
    super.key,
  });

  final Vehicle vehicle;
  final bool selected;
  final bool showLabel;
  final bool showSpeed;
  final bool useSprite;
  final double? headingOverride;

  @override
  State<VehicleMarkerPin> createState() => _VehicleMarkerPinState();
}

class _VehicleMarkerPinState extends State<VehicleMarkerPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    if (widget.selected) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(VehicleMarkerPin old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.selected && old.selected) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  static Color statusColor(VehicleStatus status) {
    switch (status) {
      case VehicleStatus.moving:
        return const Color(0xFF00A651); // Green (Moving)
      case VehicleStatus.idle:
        return const Color(0xFFF59E0B); // Yellow (Idle)
      case VehicleStatus.stopped:
        return const Color(0xFF64748B); // Gray (Parking)
      case VehicleStatus.offline:
        return const Color(0xFFEF4444); // Red (Offline)
      case VehicleStatus.noData:
        return const Color(0xFF94A3B8); // Slate Gray (No Data)
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color pinColor = statusColor(widget.vehicle.status);

    const double pinWidth = 30.0;
    const double pinHeight = 40.0;

    final Widget pinWidget = SizedBox(
      width: pinWidth + 14, // extra width for ground shadow spread
      height: pinHeight + 8, // extra height for ground shadow
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // ── 1. 3D Ground Perspective Shadow (Cast on the road at the pin tip) ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: widget.selected ? 26.0 : 22.0,
                height: widget.selected ? 8.5 : 7.0,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(widget.selected ? 26.0 : 22.0, widget.selected ? 8.5 : 7.0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: widget.selected ? 0.40 : 0.48),
                      blurRadius: widget.selected ? 6.0 : 4.0,
                      spreadRadius: widget.selected ? 1.0 : 0.0,
                      offset: const Offset(1.5, 2.0),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 2. Pulse effect when selected (Expanding 3D Ground Ring) ──
          if (widget.selected)
            Positioned(
              bottom: -2,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final double scale = 1.0 + (_pulseController.value * 0.45);
                    final double opacity = (1.0 - _pulseController.value).clamp(0.0, 1.0) * 0.6;
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 32,
                        height: 12,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(Radius.elliptical(32, 12)),
                          border: Border.all(
                            color: pinColor.withValues(alpha: opacity),
                            width: 2.0,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // ── 3. Standing 3D Pin Body (Needle tip grounded at bottom: 2.0) ──
          Positioned(
            bottom: 2.0,
            child: SizedBox(
              width: pinWidth,
              height: pinHeight,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  // 3D Teardrop Custom Paint with spherical gradient and rim highlight
                  CustomPaint(
                    size: const Size(pinWidth, pinHeight),
                    painter: _TeardropPinPainter(
                      color: pinColor,
                      isSelected: widget.selected,
                    ),
                  ),

                  // White Vehicle Icon centered in top spherical head with inner shadow
                  Positioned(
                    top: 2.5,
                    left: 0,
                    right: 0,
                    height: pinWidth - 4,
                    child: Center(
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 2.0,
                              offset: Offset(0, 1.0),
                            ),
                          ],
                        ),
                        child: Icon(
                          VehicleIcons.forType(widget.vehicle.type),
                          color: Colors.white,
                          size: 15.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 4. Floating Speed Badge directly above pin head without disturbing marker ──
          if (widget.showSpeed)
            Positioned(
              bottom: pinHeight + 3.0,
              left: -32.0,
              right: -32.0,
              child: Center(
                child: _SpeedBadge(
                  speed: widget.vehicle.speed,
                  status: widget.vehicle.status,
                  color: pinColor,
                  isSelected: widget.selected,
                ),
              ),
            ),
        ],
      ),
    );

    if (!widget.showLabel) return pinWidget;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Label(
          text: widget.vehicle.displayName,
          color: pinColor,
        ),
        const SizedBox(height: 2),
        pinWidget,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  3D Teardrop Map Pin Painter (Spherical Highlight, 3D Bevel & Metallic Rim)
// ─────────────────────────────────────────────────────────────────────────────
class _TeardropPinPainter extends CustomPainter {
  final Color color;
  final bool isSelected;

  const _TeardropPinPainter({
    required this.color,
    this.isSelected = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    const double strokeWidth = 1.4;
    final double tipY = h - (strokeWidth / 2.0); // sharp bottom tip
    final double tipX = w / 2.0;
    final double r = w / 2.0;

    // Build the 3D teardrop path
    final Path path = Path();
    path.moveTo(tipX, tipY);
    path.cubicTo(w * 0.08, tipY * 0.70, 0.0, r * 1.38, 0.0, r);
    path.arcToPoint(Offset(w, r), radius: Radius.circular(r), clockwise: true);
    path.cubicTo(w, r * 1.38, w * 0.92, tipY * 0.70, tipX, tipY);
    path.close();

    // 1. 3D Body Fill using multi-stop spherical radial gradient
    // Simulates an overhead 45-degree sun shining on a physical glossy bulb
    final Paint fillPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(tipX - (r * 0.28), r - (r * 0.28)), // Top-left light source reflection
        r * 1.35,
        <Color>[
          Color.lerp(color, Colors.white, 0.55)!, // Crisp specular top-left highlight
          Color.lerp(color, Colors.white, 0.18)!, // Mid-upper glossy tone
          color,                                  // True status color
          Color.lerp(color, Colors.black, 0.28)!, // Deep bottom-right shaded bevel
          Color.lerp(color, Colors.black, 0.45)!, // Ambient occlusion rim
        ],
        <double>[0.0, 0.25, 0.60, 0.88, 1.0],
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 2. High-gloss specular arc on top-left of the spherical head
    final Path highlightArc = Path();
    highlightArc.addArc(
      Rect.fromCircle(center: Offset(tipX, r), radius: r - 1.8),
      -math.pi * 0.85,
      math.pi * 0.65,
    );
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(highlightArc, highlightPaint);

    // 3. Crisp Outer 3D Rim Stroke (White light rim on top, shaded rim on bottom)
    final Paint borderPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(tipX, 0),
        Offset(tipX, h),
        <Color>[
          Colors.white.withValues(alpha: 0.95), // Bright crest rim
          Colors.white.withValues(alpha: 0.75),
          Color.lerp(color, Colors.white, 0.40)!.withValues(alpha: 0.80),
          Color.lerp(color, Colors.black, 0.35)!.withValues(alpha: 0.85), // Shaded tip
        ],
        <double>[0.0, 0.35, 0.70, 1.0],
      )
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_TeardropPinPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Label chip displayed above the marker
// ─────────────────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  const _Label({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.90),
        borderRadius: Corners.rXs,
        border: Border.all(color: color.withValues(alpha: 0.65), width: 1.0),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 4)],
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 9.5,
          letterSpacing: 0.3,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Real-time Speed Badge floating directly on the marker
// ─────────────────────────────────────────────────────────────────────────────
class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({
    required this.speed,
    required this.status,
    required this.color,
    this.isSelected = false,
  });

  final double speed;
  final VehicleStatus status;
  final Color color;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final int speedInt = math.max(0, speed.toInt());
    final String speedText = '$speedInt km/h';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92), // Sleek dark slate
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: color,
          width: isSelected ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Live status pulse indicator
          Container(
            width: 4.5,
            height: 4.5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 3.0),
          Text(
            speedText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
