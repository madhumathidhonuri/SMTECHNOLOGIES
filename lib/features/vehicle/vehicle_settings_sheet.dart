import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/vehicle.dart';
import '../../providers/fleet_provider.dart';

class VehicleSettingsSheet extends ConsumerStatefulWidget {
  const VehicleSettingsSheet({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  ConsumerState<VehicleSettingsSheet> createState() =>
      _VehicleSettingsSheetState();
}

class _VehicleSettingsSheetState extends ConsumerState<VehicleSettingsSheet> {
  late double _speedLimit;
  late double _overspeedDuration;
  late double _idleDuration;
  late bool _safetyPark;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final Vehicle? vehicle = ref.read(vehicleByIdProvider(widget.vehicleId));
    _speedLimit = vehicle?.speedLimit ?? 80.0;
    _overspeedDuration = vehicle?.overspeedDurationAlert ?? 3.0;
    _idleDuration = vehicle?.idleDurationAlert ?? 60.0;
    _safetyPark = vehicle?.isSafetyParkActive ?? false;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(fleetProvider.notifier).updateSettings(
            widget.vehicleId,
            overSpeedLimit: _speedLimit,
            overspeedDurationAlert: _overspeedDuration,
            idleDurationAlert: _idleDuration,
            safetyPark: _safetyPark,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle settings updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Vehicle? vehicle = ref.watch(vehicleByIdProvider(widget.vehicleId));

    if (vehicle == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Gap.lg),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: Corners.rPill,
                  ),
                ),
              ),
              Text(
                'Vehicle Settings',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                vehicle.displayName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.md),

              // ── Safety Parking (Theft Alarm) ──────────────────────────
              Container(
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: _safetyPark
                      ? const Color(0xFFFEF2F2)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: Corners.rLg,
                  border: Border.all(
                    color: _safetyPark ? const Color(0xFFDC2626) : scheme.outlineVariant,
                    width: _safetyPark ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _safetyPark ? Icons.security_rounded : Icons.shield_outlined,
                      color: _safetyPark ? const Color(0xFFDC2626) : scheme.onSurfaceVariant,
                      size: 24,
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Safety Parking (Theft Alarm)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _safetyPark ? const Color(0xFFDC2626) : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _safetyPark
                                ? 'ARMED: Siren sounds if moved or turned ON'
                                : 'Tap to arm anti-theft parking guard',
                            style: TextStyle(
                              fontSize: 11,
                              color: _safetyPark ? const Color(0xFF991B1B) : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _safetyPark,
                      activeColor: const Color(0xFFDC2626),
                      onChanged: (bool val) => setState(() => _safetyPark = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: Gap.lg),

              // ── Overspeed Limit ──────────────────────────────────────────
              _SectionHeader(
                icon: Icons.speed_rounded,
                title: 'Overspeed Threshold',
                value: '${_speedLimit.round()} km/h',
              ),
              Slider(
                value: _speedLimit,
                min: 30,
                max: 120,
                divisions: 90,
                label: '${_speedLimit.round()} km/h',
                activeColor: AppColors.brand,
                onChanged: (double v) => setState(() => _speedLimit = v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Alert triggers when vehicle exceeds this speed.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: Gap.lg),

              // ── Overspeed Duration ───────────────────────────────────────
              _SectionHeader(
                icon: Icons.timer_rounded,
                title: 'Overspeed Duration',
                value: '${_overspeedDuration.round()} mins',
              ),
              Slider(
                value: _overspeedDuration,
                min: 1,
                max: 10,
                divisions: 9,
                label: '${_overspeedDuration.round()} mins',
                activeColor: AppColors.brand,
                onChanged: (double v) =>
                    setState(() => _overspeedDuration = v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Requires speeding continuously for this long before sending the alert.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: Gap.lg),

              // ── Idle Duration ────────────────────────────────────────────
              _SectionHeader(
                icon: Icons.hourglass_empty_rounded,
                title: 'Idle Duration Alert',
                value: '${_idleDuration.round()} mins',
              ),
              Slider(
                value: _idleDuration.clamp(5, 180),
                min: 5,
                max: 180,
                divisions: 35,
                label: '${_idleDuration.round()} mins',
                activeColor: AppColors.brand,
                onChanged: (double v) => setState(() => _idleDuration = v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Alert triggers when engine is ON but vehicle is stationary for this long.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: Gap.xl),

              // Save Button
              FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: Corners.rMd),
                  backgroundColor: AppColors.brand,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Settings',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
              const SizedBox(height: Gap.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: scheme.onSurface),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}
