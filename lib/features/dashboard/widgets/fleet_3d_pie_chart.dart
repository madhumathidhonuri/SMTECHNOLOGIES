import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/fleet_provider.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  FLEET 3D ISOMETRIC PIE CHART
/// ─────────────────────────────────────────────────────────────────────────
/// A photorealistic 3D isometric pie chart supporting all 5 fleet statuses:
/// - MOVING (Deep Navy Blue / Emerald)
/// - IDLE (Sky Cyan / Amber)
/// - STOPPED (Coral Pink / Rose)
/// - OFFLINE (Warm Golden Orange - Exploded)
/// - UNREACHABLE (Vivid Purple / Crimson)
///
/// Features:
/// - Isometric perspective projection with 3D cylinder extrusion.
/// - Dynamic directional face shading (top face, outer rim, radial cut walls).
/// - Interactive exploded / elevated slice with contact shadow.
/// - Guaranteed non-overlapping callout leader lines and shelves.
/// - Interactive tap-to-select with Riverpod fleetFilterProvider integration.
class Fleet3DPieChart extends ConsumerStatefulWidget {
  const Fleet3DPieChart({
    super.key,
    this.explodedStatus = VehicleStatus.offline,
    this.onStatusSelected,
  });

  /// Status to explode by default when no filter is active.
  final VehicleStatus explodedStatus;

  /// Optional callback when a status is tapped.
  final ValueChanged<VehicleStatus?>? onStatusSelected;

  @override
  ConsumerState<Fleet3DPieChart> createState() => _Fleet3DPieChartState();
}

class _Fleet3DPieChartState extends ConsumerState<Fleet3DPieChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _entranceAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSliceTapped(VehicleStatus status) {
    final StateController<VehicleStatus?> ctrl =
        ref.read(fleetFilterProvider.notifier);
    final VehicleStatus? next = ctrl.state == status ? null : status;
    ctrl.state = next;
    widget.onStatusSelected?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final FleetStats stats = ref.watch(fleetStatsProvider);
    final VehicleStatus? activeFilter = ref.watch(fleetFilterProvider);

    // All 5 statuses with custom color specification:
    // - idle: Yellow
    // - moving: Dark Green
    // - stopped: Grey
    // - offline: Red (Exploded)
    // - unreachable: Black
    final List<PieSliceData> rawSlices = <PieSliceData>[
      PieSliceData(
        status: VehicleStatus.offline,
        label: 'OFFLINE',
        subLabel: 'no data',
        count: stats.offline,
        icon: Icons.cloud_off_rounded,
        topColor: const Color(0xFFEF4444), // Red (Exploded)
        sideColor: const Color(0xFFB91C1C),
        innerWallColor: const Color(0xFFDC2626),
      ),
      PieSliceData(
        status: VehicleStatus.noData,
        label: 'UNREACHABLE',
        subLabel: 'unreachable',
        count: stats.noData,
        icon: Icons.sensors_off_rounded,
        topColor: isDark ? const Color(0xFF27272A) : const Color(0xFF18181B), // Black
        sideColor: const Color(0xFF09090B),
        innerWallColor: const Color(0xFF18181B),
      ),
      PieSliceData(
        status: VehicleStatus.stopped,
        label: 'STOPPED',
        subLabel: 'parked',
        count: stats.stopped,
        icon: Icons.local_parking_rounded,
        topColor: const Color(0xFF64748B), // Grey
        sideColor: const Color(0xFF334155),
        innerWallColor: const Color(0xFF475569),
      ),
      PieSliceData(
        status: VehicleStatus.idle,
        label: 'IDLE',
        subLabel: 'idling',
        count: stats.idle,
        icon: Icons.hourglass_top_rounded,
        topColor: const Color(0xFFEAB308), // Yellow
        sideColor: const Color(0xFFA16207),
        innerWallColor: const Color(0xFFCA8A04),
      ),
      PieSliceData(
        status: VehicleStatus.moving,
        label: 'MOVING',
        subLabel: 'driving',
        count: stats.moving,
        icon: Icons.navigation_rounded,
        topColor: const Color(0xFF15803D), // Dark Green
        sideColor: const Color(0xFF14532D),
        innerWallColor: const Color(0xFF166534),
      ),
    ];

    final int total = stats.total;
    final double safeTotal = total > 0 ? total.toDouble() : 5.0;

    // Minimum visible angle per slice so even 0-count statuses have clear 3D representation
    const double minAngle = 0.28; // ~16 degrees
    final double remainingSweep = (2 * math.pi) - (rawSlices.length * minAngle);

    final List<PieSliceData> computedSlices = <PieSliceData>[];
    // Start angle calibrated so OFFLINE occupies Top-Left (~1.08π to 1.35π)
    double currentAngle = 1.08 * math.pi;

    for (final PieSliceData s in rawSlices) {
      final double fraction = total > 0 ? (s.count / safeTotal) : 0.20;
      final double sweep = minAngle + (fraction * remainingSweep);
      final double percent = total > 0 ? (s.count / total * 100) : 20.0;

      final bool isExploded = activeFilter != null
          ? activeFilter == s.status
          : s.status == widget.explodedStatus;

      computedSlices.add(
        s.copyWith(
          startAngle: currentAngle,
          sweepAngle: sweep,
          percentage: percent,
          isExploded: isExploded,
          isSelected: activeFilter == s.status,
          isDimmed: false,
        ),
      );

      currentAngle += sweep;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        // Optimal height giving balanced breathing room for 3D pie and callouts
        final double height = (width * 0.80).clamp(275.0, 320.0);
        final Size chartSize = Size(width, height);

        // Precompute non-overlapping leader line shelves close to the pie
        final Map<VehicleStatus, _CalloutShelf> shelves =
            _computeCalloutShelves(computedSlices, chartSize);

        return AnimatedBuilder(
          animation: _entranceAnimation,
          builder: (BuildContext context, Widget? child) {
            return SizedBox(
              width: width,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── 1. The 3D Isometric Canvas Painter ───────────────────
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (TapUpDetails details) {
                        _handleCanvasTap(
                          details.localPosition,
                          chartSize,
                          computedSlices,
                        );
                      },
                      child: CustomPaint(
                        painter: _IsometricPieChartPainter(
                          slices: computedSlices,
                          shelves: shelves,
                          progress: _entranceAnimation.value,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),

                  // ── 2. Interactive Callout Labels on Leader Lines ────────
                  for (final PieSliceData slice in computedSlices)
                    if (slice.status != null &&
                        shelves.containsKey(slice.status))
                      _buildCalloutLabel(
                        slice: slice,
                        shelf: shelves[slice.status!]!,
                        isDark: isDark,
                      ),

                  // ── 3. Subtle Bottom Center Fleet Badge ──────────────────
                  Align(
                    alignment: const Alignment(0.0, 0.99),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3.5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B).withValues(alpha: 0.90)
                            : Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$total Vehicles Total',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF475569),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Calculates mathematically collision-free shelves for each slice
  Map<VehicleStatus, _CalloutShelf> _computeCalloutShelves(
    List<PieSliceData> slices,
    Size size,
  ) {
    // Center shifted slightly right to give ample breathing room for 3 left-side labels and exploded slice
    final Offset center = Offset(size.width * 0.53, size.height * 0.48);
    final double rx = size.width * 0.20;
    final double ry = rx * 0.52;
    const double extrusionHeight = 24.0;

    final List<PieSliceData> leftSlices = [];
    final List<PieSliceData> rightSlices = [];

    for (final PieSliceData s in slices) {
      final double midAngle = s.startAngle + (s.sweepAngle / 2);
      if (math.cos(midAngle) < 0) {
        leftSlices.add(s);
      } else {
        rightSlices.add(s);
      }
    }

    // Sort top to bottom by sin of midAngle
    leftSlices.sort((a, b) {
      final double midA = a.startAngle + (a.sweepAngle / 2);
      final double midB = b.startAngle + (b.sweepAngle / 2);
      return math.sin(midA).compareTo(math.sin(midB));
    });

    rightSlices.sort((a, b) {
      final double midA = a.startAngle + (a.sweepAngle / 2);
      final double midB = b.startAngle + (b.sweepAngle / 2);
      return math.sin(midA).compareTo(math.sin(midB));
    });

    final Map<VehicleStatus, _CalloutShelf> result = {};

    // Snug bounds kept close to the pie
    final double topBoundY = center.dy - ry - 22.0;
    final double bottomBoundY = center.dy + ry + extrusionHeight + 20.0;

    const double elbowMargin = 12.0;

    // Generate distinct Y coordinates for left side
    final List<double> leftYs = _distributeYs(
      count: leftSlices.length,
      topY: topBoundY,
      bottomY: bottomBoundY,
      centerY: center.dy,
    );

    for (int i = 0; i < leftSlices.length; i++) {
      final PieSliceData s = leftSlices[i];
      if (s.status == null) continue;
      double y = leftYs[i];
      // Give MOVING extra downward clearance so it never collides with the exploded top-left slice
      if (s.status == VehicleStatus.moving) {
        y += 8.0;
      }
      final double elbowX = center.dx - rx - elbowMargin;
      result[s.status!] = _CalloutShelf(
        isLeft: true,
        elbowX: elbowX,
        elbowY: y,
        endX: 10.0,
      );
    }

    // Generate distinct Y coordinates for right side
    final List<double> rightYs = _distributeYs(
      count: rightSlices.length,
      topY: topBoundY + 4.0,
      bottomY: bottomBoundY - 4.0,
      centerY: center.dy,
    );

    for (int i = 0; i < rightSlices.length; i++) {
      final PieSliceData s = rightSlices[i];
      if (s.status == null) continue;
      final double y = rightYs[i];
      final double elbowX = center.dx + rx + elbowMargin;
      result[s.status!] = _CalloutShelf(
        isLeft: false,
        elbowX: elbowX,
        elbowY: y,
        endX: size.width - 10.0,
      );
    }

    return result;
  }

  List<double> _distributeYs({
    required int count,
    required double topY,
    required double bottomY,
    required double centerY,
  }) {
    if (count == 0) return [];
    if (count == 1) return [centerY];
    if (count == 2) {
      return [topY + 10.0, bottomY - 10.0];
    }
    final List<double> ys = [];
    final double step = (bottomY - topY) / (count - 1);
    for (int i = 0; i < count; i++) {
      ys.add(topY + (i * step));
    }
    return ys;
  }

  void _handleCanvasTap(
    Offset tapPos,
    Size size,
    List<PieSliceData> slices,
  ) {
    final Offset center = Offset(size.width * 0.53, size.height * 0.48);
    final double rx = size.width * 0.20;
    final double ry = rx * 0.52;

    final double dx = (tapPos.dx - center.dx) / rx;
    final double dy = (tapPos.dy - center.dy) / ry;
    final double dist = math.sqrt(dx * dx + dy * dy);

    if (dist <= 1.45) {
      double angle = math.atan2(dy, dx);
      if (angle < 0) angle += 2 * math.pi;

      for (final PieSliceData s in slices) {
        double start = s.startAngle % (2 * math.pi);
        double end = (s.startAngle + s.sweepAngle) % (2 * math.pi);

        bool hit = false;
        if (start < end) {
          hit = angle >= start && angle <= end;
        } else {
          hit = angle >= start || angle <= end;
        }

        if (hit && s.status != null) {
          _onSliceTapped(s.status!);
          return;
        }
      }
    }
  }

  Widget _buildCalloutLabel({
    required PieSliceData slice,
    required _CalloutShelf shelf,
    required bool isDark,
  }) {
    final bool isLeft = shelf.isLeft;
    final Color accentColor = slice.status == VehicleStatus.noData
        ? (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B))
        : slice.topColor;
    final Color labelColor = slice.isSelected
        ? accentColor
        : (isDark ? Colors.white : const Color(0xFF0F172A));

    return Positioned(
      left: isLeft ? 10.0 : null,
      right: isLeft ? null : 10.0,
      top: shelf.elbowY - 40.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (slice.status != null) _onSliceTapped(slice.status!);
        },
        child: Column(
          crossAxisAlignment:
              isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isLeft && slice.isSelected) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  slice.icon,
                  size: 14,
                  color: accentColor,
                ),
                const SizedBox(width: 4),
                Text(
                  slice.label,
                  style: TextStyle(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: labelColor,
                  ),
                ),
                if (isLeft && slice.isSelected) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 1.5),
            Text(
              '${slice.count} (${slice.percentage.toStringAsFixed(0)}%)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalloutShelf {
  const _CalloutShelf({
    required this.isLeft,
    required this.elbowX,
    required this.elbowY,
    required this.endX,
  });

  final bool isLeft;
  final double elbowX;
  final double elbowY;
  final double endX;
}

/// ─────────────────────────────────────────────────────────────────────────
///  PIE SLICE DATA MODEL
/// ─────────────────────────────────────────────────────────────────────────
class PieSliceData {
  const PieSliceData({
    required this.label,
    required this.subLabel,
    required this.count,
    required this.icon,
    required this.topColor,
    required this.sideColor,
    required this.innerWallColor,
    this.status,
    this.startAngle = 0.0,
    this.sweepAngle = 0.0,
    this.percentage = 0.0,
    this.isExploded = false,
    this.isSelected = false,
    this.isDimmed = false,
  });

  final String label;
  final String subLabel;
  final int count;
  final IconData icon;
  final Color topColor;
  final Color sideColor;
  final Color innerWallColor;
  final VehicleStatus? status;
  final double startAngle;
  final double sweepAngle;
  final double percentage;
  final bool isExploded;
  final bool isSelected;
  final bool isDimmed;

  PieSliceData copyWith({
    String? label,
    String? subLabel,
    int? count,
    IconData? icon,
    Color? topColor,
    Color? sideColor,
    Color? innerWallColor,
    VehicleStatus? status,
    double? startAngle,
    double? sweepAngle,
    double? percentage,
    bool? isExploded,
    bool? isSelected,
    bool? isDimmed,
  }) {
    return PieSliceData(
      label: label ?? this.label,
      subLabel: subLabel ?? this.subLabel,
      count: count ?? this.count,
      icon: icon ?? this.icon,
      topColor: topColor ?? this.topColor,
      sideColor: sideColor ?? this.sideColor,
      innerWallColor: innerWallColor ?? this.innerWallColor,
      status: status ?? this.status,
      startAngle: startAngle ?? this.startAngle,
      sweepAngle: sweepAngle ?? this.sweepAngle,
      percentage: percentage ?? this.percentage,
      isExploded: isExploded ?? this.isExploded,
      isSelected: isSelected ?? this.isSelected,
      isDimmed: isDimmed ?? this.isDimmed,
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  3D ISOMETRIC PIE CHART PAINTER
/// ─────────────────────────────────────────────────────────────────────────
class _IsometricPieChartPainter extends CustomPainter {
  _IsometricPieChartPainter({
    required this.slices,
    required this.shelves,
    required this.progress,
    required this.isDark,
  });

  final List<PieSliceData> slices;
  final Map<VehicleStatus, _CalloutShelf> shelves;
  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty || progress <= 0) return;

    final Offset center = Offset(size.width * 0.53, size.height * 0.48);
    final double rx = size.width * 0.20 * progress;
    final double ry = rx * 0.52; // Isometric tilt ratio
    const double extrusionHeight = 24.0; // Cylinder thickness
    const double explodeDist = 12.0; // Distance exploded slice detaches
    const double explodeLift = 10.0; // Upward height exploded slice rises

    // Sort slices by depth (back to front) for clean 3D occlusion
    final List<PieSliceData> sorted = List<PieSliceData>.from(slices)
      ..sort((a, b) {
        final double midA = a.startAngle + (a.sweepAngle / 2);
        final double midB = b.startAngle + (b.sweepAngle / 2);
        return math.sin(midA).compareTo(math.sin(midB));
      });

    // ── STEP 1: Ambient Base Drop Shadow ──────────────────────────────────
    final Rect baseOval = Rect.fromCenter(
      center: center.translate(0, extrusionHeight + 6),
      width: rx * 2.12,
      height: ry * 2.12,
    );
    canvas.drawOval(
      baseOval,
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // ── STEP 2: Render Each 3D Slice ──────────────────────────────────────
    for (final PieSliceData slice in sorted) {
      _drawSlice3D(
        canvas: canvas,
        center: center,
        rx: rx,
        ry: ry,
        h: extrusionHeight,
        explodeDist: explodeDist,
        explodeLift: explodeLift,
        slice: slice,
      );
    }

    // ── STEP 3: Render Leader Lines (Pointer Dots & Callouts) ─────────────
    _drawLeaderLines(
      canvas: canvas,
      center: center,
      rx: rx,
      ry: ry,
      explodeDist: explodeDist,
      explodeLift: explodeLift,
    );
  }

  void _drawSlice3D({
    required Canvas canvas,
    required Offset center,
    required double rx,
    required double ry,
    required double h,
    required double explodeDist,
    required double explodeLift,
    required PieSliceData slice,
  }) {
    final double midAngle = slice.startAngle + (slice.sweepAngle / 2);

    // Explode displacement offset
    Offset sliceOffset = Offset.zero;
    if (slice.isExploded) {
      final double dx = explodeDist * math.cos(midAngle);
      final double dy = (explodeDist * math.sin(midAngle) * 0.52) - explodeLift;
      sliceOffset = Offset(dx, dy);
    }

    final Offset cTop = center + sliceOffset;
    final Offset cBot = cTop.translate(0, h);

    final double sAngle = slice.startAngle;
    final double eAngle = slice.startAngle + slice.sweepAngle;

    // Keep all slices at 100% solid, full original vibrancy (never dim or lighten)
    final Color topColor = slice.topColor;
    final Color sideColor = slice.sideColor;
    final Color innerWallColor = slice.innerWallColor;

    // ── A. Exploded Slice Contact Shadow ──────────────────────────────────
    if (slice.isExploded) {
      final Path shadowPath = Path();
      const int steps = 16;
      shadowPath.moveTo(
        center.dx + (explodeDist * math.cos(midAngle)),
        center.dy + (explodeDist * math.sin(midAngle) * 0.52) + h + 2,
      );
      for (int i = 0; i <= steps; i++) {
        final double t = sAngle + (slice.sweepAngle * (i / steps));
        final double x = center.dx +
            (explodeDist * math.cos(midAngle)) +
            (rx * math.cos(t));
        final double y = center.dy +
            (explodeDist * math.sin(midAngle) * 0.52) +
            (ry * math.sin(t)) +
            h +
            2;
        shadowPath.lineTo(x, y);
      }
      shadowPath.close();

      canvas.drawPath(
        shadowPath,
        Paint()
          ..color = Colors.black.withValues(alpha: isDark ? 0.28 : 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // ── B. Radial Cut Walls ────────────────────────────────────────────────
    final Offset pStartTop = Offset(
      cTop.dx + (rx * math.cos(sAngle)),
      cTop.dy + (ry * math.sin(sAngle)),
    );
    final Offset pStartBot = pStartTop.translate(0, h);

    final Offset pEndTop = Offset(
      cTop.dx + (rx * math.cos(eAngle)),
      cTop.dy + (ry * math.sin(eAngle)),
    );
    final Offset pEndBot = pEndTop.translate(0, h);

    // Wall 1: Start Wall Quad
    final double startWallNormalX = math.sin(sAngle);
    if (slice.isExploded || startWallNormalX > -0.1) {
      final Path wallStart = Path()
        ..moveTo(cTop.dx, cTop.dy)
        ..lineTo(pStartTop.dx, pStartTop.dy)
        ..lineTo(pStartBot.dx, pStartBot.dy)
        ..lineTo(cBot.dx, cBot.dy)
        ..close();

      final Color shadedStart = Color.lerp(
        innerWallColor,
        Colors.black,
        startWallNormalX > 0 ? 0.15 : 0.30,
      )!;

      canvas.drawPath(
        wallStart,
        Paint()
          ..color = shadedStart
          ..style = PaintingStyle.fill,
      );
    }

    // Wall 2: End Wall Quad
    final double endWallNormalX = -math.sin(eAngle);
    if (slice.isExploded || endWallNormalX > -0.1) {
      final Path wallEnd = Path()
        ..moveTo(pEndTop.dx, pEndTop.dy)
        ..lineTo(cTop.dx, cTop.dy)
        ..lineTo(cBot.dx, cBot.dy)
        ..lineTo(pEndBot.dx, pEndBot.dy)
        ..close();

      final Color shadedEnd = Color.lerp(
        innerWallColor,
        Colors.black,
        endWallNormalX > 0 ? 0.12 : 0.28,
      )!;

      canvas.drawPath(
        wallEnd,
        Paint()
          ..color = shadedEnd
          ..style = PaintingStyle.fill,
      );
    }

    // ── C. Outer Cylindrical Rim ──────────────────────────────────────────
    const int rimSteps = 24;
    final Path rimPath = Path();
    bool rimVisible = false;

    for (int i = 0; i <= rimSteps; i++) {
      final double t = sAngle + (slice.sweepAngle * (i / rimSteps));
      if (math.sin(t) >= -0.05 || slice.isExploded) {
        rimVisible = true;
        break;
      }
    }

    if (rimVisible) {
      rimPath.moveTo(pStartTop.dx, pStartTop.dy);
      for (int i = 1; i <= rimSteps; i++) {
        final double t = sAngle + (slice.sweepAngle * (i / rimSteps));
        rimPath.lineTo(
          cTop.dx + (rx * math.cos(t)),
          cTop.dy + (ry * math.sin(t)),
        );
      }
      rimPath.lineTo(pEndBot.dx, pEndBot.dy);
      for (int i = rimSteps - 1; i >= 0; i--) {
        final double t = sAngle + (slice.sweepAngle * (i / rimSteps));
        rimPath.lineTo(
          cBot.dx + (rx * math.cos(t)),
          cBot.dy + (ry * math.sin(t)),
        );
      }
      rimPath.close();

      canvas.drawPath(
        rimPath,
        Paint()
          ..color = sideColor
          ..style = PaintingStyle.fill,
      );
    }

    // ── D. Top Elliptical Face ───────────────────────────────────────────
    final Path topPath = Path()..moveTo(cTop.dx, cTop.dy);
    const int topSteps = 28;
    for (int i = 0; i <= topSteps; i++) {
      final double t = sAngle + (slice.sweepAngle * (i / topSteps));
      topPath.lineTo(
        cTop.dx + (rx * math.cos(t)),
        cTop.dy + (ry * math.sin(t)),
      );
    }
    topPath.close();

    final Paint topPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(topColor, Colors.white, 0.12)!,
          topColor,
        ],
      ).createShader(
        Rect.fromCenter(center: cTop, width: rx * 2, height: ry * 2),
      );

    canvas.drawPath(topPath, topPaint);

    final Paint edgeStroke = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.20 : 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(topPath, edgeStroke);
  }

  void _drawLeaderLines({
    required Canvas canvas,
    required Offset center,
    required double rx,
    required double ry,
    required double explodeDist,
    required double explodeLift,
  }) {
    final Paint defaultLinePaint = Paint()
      ..color = isDark
          ? const Color(0xFF64748B).withValues(alpha: 0.85)
          : const Color(0xFF94A3B8).withValues(alpha: 0.90)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint dotPaint = Paint()..style = PaintingStyle.fill;

    for (final PieSliceData slice in slices) {
      if (slice.status == null || !shelves.containsKey(slice.status)) continue;
      final _CalloutShelf shelf = shelves[slice.status!]!;

      final double midAngle = slice.startAngle + (slice.sweepAngle / 2);

      Offset sliceOffset = Offset.zero;
      if (slice.isExploded) {
        final double dx = explodeDist * math.cos(midAngle);
        final double dy =
            (explodeDist * math.sin(midAngle) * 0.52) - explodeLift;
        sliceOffset = Offset(dx, dy);
      }

      final Offset cTop = center + sliceOffset;

      // 1. Anchor dot resting on slice top surface
      final Offset anchorDot = Offset(
        cTop.dx + (rx * 0.65 * math.cos(midAngle)),
        cTop.dy + (ry * 0.65 * math.sin(midAngle)),
      );

      // Draw anchor dot
      dotPaint.color = isDark
          ? const Color(0xFFCBD5E1)
          : const Color(0xFF475569);
      canvas.drawCircle(anchorDot, 3.2, dotPaint);

      // Draw angled connector & horizontal shelf
      final Path leaderPath = Path()
        ..moveTo(anchorDot.dx, anchorDot.dy)
        ..lineTo(shelf.elbowX, shelf.elbowY)
        ..lineTo(shelf.endX, shelf.elbowY);

      if (slice.isSelected) {
        final Paint activeLinePaint = Paint()
          ..color = slice.topColor
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(leaderPath, activeLinePaint);
      } else {
        canvas.drawPath(leaderPath, defaultLinePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IsometricPieChartPainter oldDelegate) {
    return oldDelegate.slices != slices ||
        oldDelegate.shelves != shelves ||
        oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark;
  }
}
