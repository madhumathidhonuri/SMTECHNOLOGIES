import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/vehicle.dart';

/// Status pill with a live pulse on moving vehicles.
///
/// The pulse is deliberately subtle and only animates for `moving` — an
/// always-on animation across a 300-row list would burn frames and battery
/// for no informational gain.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.status,
    this.compact = false,
    this.showDot = true,
    super.key,
  });

  final VehicleStatus status;
  final bool compact;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.forStatus(status.key);
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Gap.sm : Gap.md,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: Corners.rPill,
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showDot) ...<Widget>[
            _StatusDot(
              color: color,
              animate: status == VehicleStatus.moving,
              size: compact ? 6 : 7,
            ),
            SizedBox(width: compact ? 5 : 7),
          ],
          Text(
            status.label,
            style: (compact
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({
    required this.color,
    required this.animate,
    this.size = 7,
  });

  final Color color;
  final bool animate;
  final double size;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with TickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _start();
  }

  void _start() {
    _controller?.dispose();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && _controller == null) {
      _start();
    } else if (!widget.animate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );

    if (_controller == null) return dot;

    return SizedBox(
      width: widget.size * 2.4,
      height: widget.size * 2.4,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _controller!,
            builder: (BuildContext context, Widget? _) {
              final double t = _controller!.value;
              return Container(
                width: widget.size + (widget.size * 1.4 * t),
                height: widget.size + (widget.size * 1.4 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity((1 - t) * 0.45),
                ),
              );
            },
          ),
          dot,
        ],
      ),
    );
  }
}

/// Generic labelled pill used for signal, ignition, fuel etc.
class InfoPill extends StatelessWidget {
  const InfoPill({
    required this.icon,
    required this.label,
    this.color,
    this.background,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color c = color ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.surfaceContainerHigh,
        borderRadius: Corners.rXs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: c,
              letterSpacing: 0.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
