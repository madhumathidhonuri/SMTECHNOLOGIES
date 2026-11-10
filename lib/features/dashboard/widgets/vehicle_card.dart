import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/vehicle_icons.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/repositories/vehicle_repository.dart';
import '../../../providers/core_providers.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/live_address.dart';

class VehicleCard extends ConsumerWidget {
  const VehicleCard({
    required this.vehicle,
    required this.onTap,
    this.onTrack,
    this.dense = false,
    this.glass = false,
    this.minimal = false,
    super.key,
  });

  final Vehicle vehicle;
  final VoidCallback onTap;
  final VoidCallback? onTrack;
  final bool dense;
  final bool glass;
  final bool minimal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color statusColor = AppColors.forStatus(vehicle.status.key);

    void showDebugDialog() async {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext ctx) =>
            const Center(child: CircularProgressIndicator()),
      );

      try {
        final VehicleRepository vehicleRepo =
            ref.read(vehicleRepositoryProvider);
        final Vehicle detailedVehicle =
            await vehicleRepo.getVehicle(vehicle.id);
        if (!context.mounted) return;
        Navigator.pop(context);

        showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text('${vehicle.name} Detailed Raw JSON'),
            content: SizedBox(
              width: double.maxFinite,
              height: 450,
              child: SingleChildScrollView(
                child: SelectableText(
                  JsonEncoder.withIndent("  ").convert(detailedVehicle.raw),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        Navigator.pop(context);
        showDialog<void>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to load detailed vehicle data: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }

    final Widget content = Padding(
      padding: const EdgeInsets.all(14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── HEADER ROW: Vehicle Icon/Avatar + Name/Plate + Status Pill + Arrow ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Vehicle Avatar Squircle
              Container(
                width: 50,
                height: 50,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F6FD),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC7D7EC).withOpacity(0.5),
                      offset: const Offset(0, 2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/vehicles/${vehicle.displayType}.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    VehicleIcons.forType(vehicle.displayType),
                    size: 30,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and Update Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            vehicle.displayName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0D1B36),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDateTimeShort(vehicle.lastPacketAt),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7A8FA8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Status Pill
              _buildStatusPill(vehicle.status, statusColor),

              const SizedBox(width: 6),

              // Chevron button
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F6FD),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFC7D7EC).withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Color(0xFF1E60FF),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── TELEMETRY CHIPS ROW (Speed | Today km | Battery/Odo) ──
          Row(
            children: [
              // Speed
              Expanded(
                child: _buildMetricChip(
                  icon: Icons.speed_rounded,
                  iconColor: const Color(0xFF1E60FF),
                  value: '${vehicle.speed.round()} km/h',
                  label: 'Speed',
                ),
              ),
              const SizedBox(width: 8),

              // Today km
              Expanded(
                child: _buildMetricChip(
                  icon: Icons.alt_route_rounded,
                  iconColor: const Color(0xFF0284C7),
                  value: '${vehicle.todayDistanceKm?.toStringAsFixed(0) ?? '0'} km',
                  label: 'Today',
                ),
              ),
              const SizedBox(width: 8),

              // Battery or Odometer
              Expanded(
                child: _buildMetricChip(
                  icon: (vehicle.batteryLevel != null && vehicle.batteryLevel! > 0)
                      ? Icons.battery_charging_full_rounded
                      : Icons.straighten_rounded,
                  iconColor: (vehicle.batteryLevel != null && vehicle.batteryLevel! > 0)
                      ? const Color(0xFFEAB308)
                      : const Color(0xFF10B981),
                  value: (vehicle.batteryLevel != null && vehicle.batteryLevel! > 0)
                      ? '${vehicle.batteryLevel!.toStringAsFixed(1)} V'
                      : (vehicle.odometer != null
                          ? '${vehicle.odometer!.toStringAsFixed(0)} km'
                          : 'N/A'),
                  label: (vehicle.batteryLevel != null && vehicle.batteryLevel! > 0)
                      ? 'Battery'
                      : 'Odometer',
                ),
              ),
            ],
          ),

          if (!minimal) ...[
            const SizedBox(height: 10),

            // ── LIVE STATUS DURATION STRIP ──
            _LiveStatusStrip(vehicle: vehicle),

            const SizedBox(height: 10),

            // ── LOCATION / ADDRESS ROW ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 16,
                  color: Color(0xFF1E60FF),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: LiveAddress(
                    vehicle: vehicle,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF566A85),
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Signal and satellites
                if (vehicle.satellites != null || vehicle.odometer != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.signal_cellular_alt_rounded,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                      if (vehicle.satellites != null) ...[
                        const SizedBox(width: 2),
                        Text(
                          '${vehicle.satellites}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7A8FA8),
                          ),
                        ),
                      ],
                    ],
                  ),

                if (onTrack != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onTrack,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E60FF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.near_me_rounded, size: 12, color: Color(0xFF1E60FF)),
                          SizedBox(width: 3),
                          Text(
                            'Track',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E60FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (glass) {
      return Padding(
        padding: EdgeInsets.only(bottom: dense ? Gap.md : Gap.lg),
        child: GestureDetector(
          onLongPress: showDebugDialog,
          child: GlassCard(
            padding: EdgeInsets.zero,
            onTap: onTap,
            child: content,
          ),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: dense ? Gap.xs : Gap.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.55),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          onLongPress: showDebugDialog,
          borderRadius: BorderRadius.circular(18),
          splashColor: const Color(0xFF1E60FF).withOpacity(0.06),
          child: content,
        ),
      ),
    );
  }

  Widget _buildStatusPill(VehicleStatus status, Color statusColor) {
    Color bg;
    Color fg;

    switch (status) {
      case VehicleStatus.moving:
        bg = const Color(0xFFE8F9F1);
        fg = const Color(0xFF10B981);
      case VehicleStatus.idle:
        bg = const Color(0xFFFEF9C3);
        fg = const Color(0xFFD97706);
      case VehicleStatus.stopped:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
      case VehicleStatus.offline:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFEF4444);
      case VehicleStatus.noData:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EEF8), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7A8FA8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0D1B36),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTimeShort(DateTime? dt) {
    if (dt == null) return 'N/A';
    final String date = Fmt.dateShort(dt);
    final String time = Fmt.time12Sec(dt);
    return '$date • $time';
  }
}

class _LiveStatusStrip extends StatefulWidget {
  const _LiveStatusStrip({required this.vehicle});

  final Vehicle vehicle;

  @override
  State<_LiveStatusStrip> createState() => _LiveStatusStripState();
}

class _LiveStatusStripState extends State<_LiveStatusStrip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _LiveStatusStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicle.status != widget.vehicle.status ||
        oldWidget.vehicle.statusChangedAt != widget.vehicle.statusChangedAt ||
        oldWidget.vehicle.lastPacketAt != widget.vehicle.lastPacketAt) {
      _timer?.cancel();
      _startTimer();
    }
  }

  void _startTimer() {
    final DateTime? ts =
        widget.vehicle.statusChangedAt ?? widget.vehicle.lastPacketAt;
    if (ts == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Vehicle v = widget.vehicle;
    final DateTime? since = v.statusChangedAt ?? v.lastPacketAt;

    Color color;
    Color bg;
    IconData icon;
    String statusTitle;

    switch (v.status) {
      case VehicleStatus.moving:
        color = const Color(0xFF10B981);
        bg = const Color(0xFFE8F9F1);
        icon = Icons.navigation_rounded;
        statusTitle = 'Moving';
      case VehicleStatus.idle:
        color = const Color(0xFFD97706);
        bg = const Color(0xFFFEF9C3);
        icon = Icons.key_rounded;
        statusTitle = 'Idle';
      case VehicleStatus.stopped:
        color = const Color(0xFF64748B);
        bg = const Color(0xFFF1F5F9);
        icon = Icons.local_parking_rounded;
        statusTitle = 'Stopped';
      case VehicleStatus.offline:
        color = const Color(0xFFEF4444);
        bg = const Color(0xFFFEE2E2);
        icon = Icons.cloud_off_rounded;
        statusTitle = 'Offline';
      case VehicleStatus.noData:
        color = const Color(0xFF64748B);
        bg = const Color(0xFFF1F5F9);
        icon = Icons.sensors_off_rounded;
        statusTitle = 'Unreachable';
    }

    if (v.status == VehicleStatus.noData || since == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Text(
              statusTitle,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    final String durStr = Fmt.statusDuration(since);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                Text(
                  '$statusTitle for ',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  durStr,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  'since ${Fmt.time12Sec(since)}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: color.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
