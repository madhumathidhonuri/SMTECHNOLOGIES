import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class LeftMapControls extends StatelessWidget {
  const LeftMapControls({
    required this.onLayers,
    required this.onRecenter,
    super.key,
  });

  final VoidCallback onLayers;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFC7D7EC).withOpacity(0.55),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: Color(0xFF10B981), size: 8),
              SizedBox(width: 6),
              Text(
                'Live',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Color(0xFF0D1B36),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        
        // Vertical control stack
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFC7D7EC).withOpacity(0.55),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SquareButton(
                icon: Icons.layers_outlined,
                onTap: onLayers,
              ),
              _Divider(),
              _SquareButton(
                icon: Icons.my_location_rounded,
                onTap: onRecenter,
              ),
              _Divider(),
              _SquareButton(
                icon: Icons.traffic_outlined,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RightMapControls extends StatelessWidget {
  const RightMapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    super.key,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Compass
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFC7D7EC).withOpacity(0.55),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.explore_outlined, color: Color(0xFF1E60FF), size: 24),
          ),
        ),
        const SizedBox(height: 120),
        
        // Zoom Controls
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFC7D7EC).withOpacity(0.55),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SquareButton(
                icon: Icons.add,
                onTap: onZoomIn,
              ),
              _Divider(),
              _SquareButton(
                icon: Icons.remove,
                onTap: onZoomOut,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFC7D7EC).withOpacity(0.55),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _SquareButton(
            icon: Icons.layers_clear_outlined,
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    this.icon,
    this.text,
    this.isActive = false,
    required this.onTap,
  });

  final IconData? icon;
  final String? text;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: icon != null
              ? Icon(
                  icon,
                  color: isActive ? const Color(0xFF1E60FF) : const Color(0xFF566A85),
                  size: 22,
                )
              : Text(
                  text!,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: isActive ? const Color(0xFF1E60FF) : const Color(0xFF566A85),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 1,
      color: const Color(0xFFE2ECF8),
    );
  }
}
