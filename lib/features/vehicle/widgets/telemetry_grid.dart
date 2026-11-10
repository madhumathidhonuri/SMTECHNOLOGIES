import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/vehicle.dart';


/// Instrument-cluster grid of every live signal the tracker reports.
class TelemetryGrid extends StatelessWidget {
  const TelemetryGrid({required this.vehicle, super.key});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final List<_Cell> cells = <_Cell>[
      _Cell(
        icon: Icons.speed_rounded,
        label: 'Speed',
        value: '${vehicle.speed.round()}',
        unit: 'km/h',
        color: vehicle.isOverspeeding ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
        subtitle: vehicle.speedLimit != null
            ? 'Limit ${vehicle.speedLimit!.round()}'
            : null,
      ),
      _Cell(
        icon: vehicle.ignition
            ? Icons.power_settings_new_rounded
            : Icons.power_off_rounded,
        label: 'Ignition',
        value: vehicle.ignition ? 'ON' : 'OFF',
        color: vehicle.ignition ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
      ),
      if (vehicle.odometer != null)
        _Cell(
          icon: Icons.timeline_rounded,
          label: 'Odometer',
          value: vehicle.odometer!.toStringAsFixed(0),
          unit: 'km',
          color: const Color(0xFF6366F1),
        ),
      if (vehicle.todayDistanceKm != null)
        _Cell(
          icon: Icons.route_rounded,
          label: 'Today',
          value: vehicle.todayDistanceKm!.toStringAsFixed(1),
          unit: 'km',
          color: const Color(0xFF8B5CF6),
        ),
      _Cell(
        icon: Icons.explore_rounded,
        label: 'Heading',
        value: Fmt.heading(vehicle.heading),
        unit: '${vehicle.heading.round()}°',
        color: const Color(0xFF0D9488),
      ),
      if (vehicle.fuelLevel != null)
        _Cell(
          icon: Icons.local_gas_station_rounded,
          label: 'Fuel',
          value: vehicle.fuelLevel!.round().toString(),
          unit: vehicle.fuelLevel! > 100 ? 'L' : '%',
          color: vehicle.fuelLevel! < 15 ? const Color(0xFFEF4444) : const Color(0xFFF97316),
        ),
      if (vehicle.batteryLevel != null && vehicle.batteryLevel! > 0)
        _Cell(
          icon: Icons.battery_charging_full_rounded,
          label: 'Battery',
          value: vehicle.batteryLevel!.toStringAsFixed(1),
          unit: 'V',
          color: vehicle.batteryLevel! < 11.5 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
        ),
      if (vehicle.gsmSignal != null)
        _Cell(
          icon: Icons.signal_cellular_alt_rounded,
          label: 'GSM',
          value: '${vehicle.gsmSignal}',
          unit: vehicle.gsmSignal! > 5 ? '%' : '/5',
          color: const Color(0xFFEC4899),
        ),
      if (vehicle.satellites != null)
        _Cell(
          icon: Icons.satellite_alt_rounded,
          label: 'Satellites',
          value: '${vehicle.satellites}',
          color: const Color(0xFF2563EB),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: Gap.sm),
          child: Text(
            'LIVE TELEMETRY',
            style: AppTypography.eyebrow(theme.colorScheme.onSurfaceVariant),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 88,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.98,
          ),
          itemBuilder: (BuildContext context, int i) =>
              _TelemetryCell(cell: cells[i]),
        ),
      ],
    );
  }
}

class _Cell {
  const _Cell({
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final String? subtitle;
}

class _TelemetryCell extends StatelessWidget {
  const _TelemetryCell({required this.cell});

  final _Cell cell;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color accent = cell.color ?? const Color(0xFF0284C7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
          width: 1.2,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.25 : 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  cell.icon,
                  size: 13,
                  color: accent,
                ),
              ),
              if (cell.unit != null)
                Text(
                  cell.unit!,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  cell.value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1E2432),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                cell.subtitle ?? cell.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
