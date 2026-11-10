import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/safety_parking_provider.dart';

class SafetyParkingTheftOverlay extends ConsumerStatefulWidget {
  const SafetyParkingTheftOverlay({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SafetyParkingTheftOverlay> createState() =>
      _SafetyParkingTheftOverlayState();
}

class _SafetyParkingTheftOverlayState extends ConsumerState<SafetyParkingTheftOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);

    _pulseAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SafetyParkingState safetyState = ref.watch(safetyParkingProvider);
    final ActiveTheftAlarm? alarm = safetyState.activeAlarm;

    if (alarm == null) {
      return widget.child;
    }

    return Stack(
      children: <Widget>[
        // The underlying app screens
        widget.child,

        // ── FULL MOBILE LIGHTNING IN THE MOBILE BORDERS WITH RED COLOR ──
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (BuildContext context, _) {
                final double v = _pulseAnim.value;
                final Color redPrimary = Color.lerp(
                  const Color(0xFFDC2626),
                  const Color(0xFFFF0000),
                  v,
                )!;
                final double borderWidth = 5.0 + 3.0 * v;
                final double glowRadius = 14.0 + 20.0 * v;

                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: redPrimary,
                      width: borderWidth,
                    ),
                    boxShadow: <BoxShadow>[
                      // Outer glowing red aura
                      BoxShadow(
                        color: const Color(0xFFFF0000).withValues(alpha: 0.5 + 0.45 * v),
                        blurRadius: glowRadius,
                        spreadRadius: 3.0 + 3.0 * v,
                      ),
                      // Inner glowing red lightning effect
                      BoxShadow(
                        color: const Color(0xFFFF2222).withValues(alpha: 0.35 + 0.3 * v),
                        blurRadius: glowRadius * 0.7,
                        spreadRadius: 1.0,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Corner Lightning Visual Embellishments
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (BuildContext context, _) {
                final double opacity = 0.6 + 0.4 * _pulseAnim.value;
                return Stack(
                  children: <Widget>[
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Icon(Icons.flash_on_rounded, color: Colors.redAccent.withValues(alpha: opacity), size: 28),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(Icons.flash_on_rounded, color: Colors.redAccent.withValues(alpha: opacity), size: 28),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Icon(Icons.flash_on_rounded, color: Colors.redAccent.withValues(alpha: opacity), size: 28),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Icon(Icons.flash_on_rounded, color: Colors.redAccent.withValues(alpha: opacity), size: 28),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // ── TOP EMERGENCY SIREN BANNER ──
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (BuildContext context, Widget? child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF7F1D1D), Color(0xFFDC2626), Color(0xFF991B1B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5 + 0.5 * _pulseAnim.value),
                        width: 2,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: const Color(0xFFFF0000).withValues(alpha: 0.5 * _pulseAnim.value),
                          blurRadius: 25,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: child,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Flashing Siren Badge
                          AnimatedBuilder(
                            animation: _pulseAnim,
                            builder: (BuildContext context, _) {
                              final double scale = 1.0 + 0.15 * math.sin(_pulseAnim.value * math.pi);
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Color(0xFFDC2626),
                                    size: 26,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          // Alert text
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    const Text(
                                      '🚨 THEFT ALARM ACTIVE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (safetyState.isSirenSounding)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            Icon(Icons.volume_up_rounded, color: Colors.white, size: 12),
                                            SizedBox(width: 4),
                                            Text(
                                              'SIREN ON',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${alarm.vehicleName} (${alarm.plate})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  alarm.alertText,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Action buttons
                      Row(
                        children: <Widget>[
                          // Primary Disarm & Stop Siren
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                ref.read(safetyParkingProvider.notifier).disarmAndStopSiren();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFFDC2626),
                                elevation: 3,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.shield_outlined, size: 16),
                              label: const Text(
                                'Turn OFF Safety Parking',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Secondary Silence Siren
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                if (safetyState.isSirenSounding) {
                                  ref.read(safetyParkingProvider.notifier).silenceSiren();
                                } else {
                                  ref.read(safetyParkingProvider.notifier).dismissAlarm();
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: Icon(
                                safetyState.isSirenSounding
                                    ? Icons.volume_off_rounded
                                    : Icons.close_rounded,
                                size: 15,
                              ),
                              label: Text(
                                safetyState.isSirenSounding ? 'Mute / Stop Siren' : 'Dismiss Alert',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
