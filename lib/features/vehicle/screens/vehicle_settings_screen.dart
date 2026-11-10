import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/json_utils.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/fleet_provider.dart';
import '../../../providers/safety_parking_provider.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/duration_alert_card.dart';

class VehicleSettingsScreen extends ConsumerStatefulWidget {
  const VehicleSettingsScreen({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  ConsumerState<VehicleSettingsScreen> createState() =>
      _VehicleSettingsScreenState();
}

class _VehicleSettingsScreenState
    extends ConsumerState<VehicleSettingsScreen> {
  late double _speedLimit;
  late double _overspeedDuration;
  late double _idleDuration;
  late double _parkingDuration;
  late double _movingDuration;
  late bool _safetyPark;
  late TextEditingController _idleController;
  late TextEditingController _parkingController;
  late TextEditingController _movingController;
  bool _applyAccountWide = true;
  bool _isSaving = false;

  final Map<String, bool> _alertToggles = {
    'engine_on': true,
    'engine_off': true,
    'moving': true,
    'parking': true,
    'stoppage': true,
    'excessive_idle': true,
    'overspeed': true,
    'geofence': true,
    'main_battery_disconnected': true,
    'main_battery_connected': true,
    'sos': true,
    'trip_started': true,
    'trip_ended': true,
    'route_deviation': true,
  };

  @override
  void initState() {
    super.initState();
    final Vehicle? vehicle = ref.read(vehicleByIdProvider(widget.vehicleId));
    final Map<String, dynamic> metadata = (vehicle?.raw['metadata'] as Map<String, dynamic>?) ?? {};
    _speedLimit = toDouble(metadata['overSpeedLimit']) ??
        toDouble(metadata['speedLimit']) ??
        80.0;
    _overspeedDuration = toDouble(metadata['overspeedDurationAlert']) ?? 3.0;
    _idleDuration = toDouble(metadata['idleDurationAlert']) ?? 60.0;
    _parkingDuration = toDouble(metadata['parkingDurationAlert']) ??
        toDouble(metadata['stoppageThreshold']) ??
        60.0;
    _movingDuration = toDouble(metadata['movingDurationAlert']) ?? 60.0;
    _safetyPark = vehicle?.isSafetyParkActive ?? (metadata['safetyPark'] == 'YES');

    _idleController = TextEditingController(text: '${_idleDuration.round()}');
    _parkingController = TextEditingController(text: '${_parkingDuration.round()}');
    _movingController = TextEditingController(text: '${_movingDuration.round()}');
    
    final alertConfig = metadata['alertConfig'] as Map<String, dynamic>? ?? {};
    for (final key in _alertToggles.keys) {
      if (alertConfig.containsKey(key)) {
        _alertToggles[key] = alertConfig[key] == true;
      }
    }

    // Load account-wide user preferences if available
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final Map<String, dynamic>? remote =
            await ref.read(alertRepositoryProvider).getPreferences();
        if (remote != null && mounted) {
          setState(() {
            if (remote['speed_limit'] != null) {
              _speedLimit = toDouble(remote['speed_limit']) ?? _speedLimit;
            }
            if (remote['idle_duration_mins'] != null) {
              _idleDuration = toDouble(remote['idle_duration_mins']) ?? _idleDuration;
              _idleController.text = '${_idleDuration.round()}';
            }
            if (remote['parking_duration_mins'] != null) {
              _parkingDuration = toDouble(remote['parking_duration_mins']) ?? _parkingDuration;
              _parkingController.text = '${_parkingDuration.round()}';
            }
            if (remote['moving_duration_mins'] != null) {
              _movingDuration = toDouble(remote['moving_duration_mins']) ?? _movingDuration;
              _movingController.text = '${_movingDuration.round()}';
            }
            for (final key in _alertToggles.keys) {
              if (remote.containsKey(key) && remote[key] is bool) {
                _alertToggles[key] = remote[key] as bool;
              }
            }
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _idleController.dispose();
    _parkingController.dispose();
    _movingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (_applyAccountWide) {
        // Save user-wide preferences (applies across account and backend auto-syncs all org vehicles)
        final Map<String, dynamic> userPrefs = <String, dynamic>{
          ..._alertToggles,
          'speed_limit': _speedLimit,
          'idle_duration_mins': _idleDuration,
          'parking_duration_mins': _parkingDuration,
          'moving_duration_mins': _movingDuration,
        };
        await ref.read(alertRepositoryProvider).updatePreferences(userPrefs);
      }

      await ref.read(fleetProvider.notifier).updateSettings(
            widget.vehicleId,
            overSpeedLimit: _speedLimit,
            overspeedDurationAlert: _overspeedDuration,
            idleDurationAlert: _idleDuration,
            stoppageThreshold: _parkingDuration,
            parkingDurationAlert: _parkingDuration,
            movingDurationAlert: _movingDuration,
            alertConfig: _alertToggles,
            safetyPark: _safetyPark,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: <Widget>[
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(_applyAccountWide
                      ? 'Alert configuration saved for your account & applied to all vehicles!'
                      : 'Vehicle settings saved successfully!'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update settings: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Vehicle? vehicle = ref.watch(vehicleByIdProvider(widget.vehicleId));

    if (vehicle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Vehicle Settings')),
        body: const EmptyState(
          icon: Icons.error_outline,
          title: 'Vehicle not found',
          message: 'Unable to load vehicle details.',
        ),
      );
    }

    final Color cardBg = isDark
        ? const Color(0xFF0F2138)
        : Colors.white;

    final Color borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Alert & Notification Configuration'),
          centerTitle: true,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'General'),
              Tab(text: 'Alerts Config'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.all(Gap.lg),
                      children: <Widget>[
                        // ── Hero Vehicle Header ────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(Gap.md),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: Corners.rLg,
                      border: Border.all(color: borderColor),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(Gap.md),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withOpacity(0.12),
                            borderRadius: Corners.rMd,
                          ),
                          child: Icon(
                            Icons.directions_car_rounded,
                            color: AppColors.brand,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                vehicle.displayName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vehicle.registrationNumber.isNotEmpty
                                    ? vehicle.registrationNumber
                                    : 'IMEI: ${vehicle.imei}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusBadge(status: vehicle.status),
                      ],
                    ),
                  ),

                  const SizedBox(height: Gap.md),

                  // ── User-Wise (All Vehicles) Switch Banner ───────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
                    decoration: BoxDecoration(
                      color: _applyAccountWide
                          ? (isDark
                              ? const Color(0xFF1E3A8A).withOpacity(0.3)
                              : const Color(0xFFEFF6FF))
                          : cardBg,
                      borderRadius: Corners.rLg,
                      border: Border.all(
                        color: _applyAccountWide
                            ? const Color(0xFF3B82F6)
                            : borderColor,
                        width: _applyAccountWide ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _applyAccountWide
                                ? const Color(0xFF2563EB)
                                : scheme.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.admin_panel_settings_rounded,
                            color: _applyAccountWide ? Colors.white : scheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Account-Wide Configuration',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (_applyAccountWide) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ALL VEHICLES',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _applyAccountWide
                                    ? 'Settings apply to your user profile and sync across all vehicles'
                                    : 'Settings apply only to ${vehicle.displayName}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _applyAccountWide,
                          activeColor: const Color(0xFF2563EB),
                          onChanged: (bool val) => setState(() => _applyAccountWide = val),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Gap.lg),

                  // ── Section 0: Safety Parking (Theft Police Siren) ────
                  Container(
                    decoration: BoxDecoration(
                      color: _safetyPark
                          ? (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2))
                          : cardBg,
                      borderRadius: Corners.rLg,
                      border: Border.all(
                        color: _safetyPark ? const Color(0xFFDC2626) : borderColor,
                        width: _safetyPark ? 1.5 : 1.0,
                      ),
                      boxShadow: <BoxShadow>[
                        if (_safetyPark)
                          BoxShadow(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    padding: const EdgeInsets.all(Gap.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _safetyPark
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF64748B).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _safetyPark ? Icons.security_rounded : Icons.shield_outlined,
                                color: _safetyPark ? Colors.white : const Color(0xFF64748B),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: Gap.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Text(
                                        'Safety Parking (Theft Alarm)',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: _safetyPark ? const Color(0xFFDC2626) : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _safetyPark
                                        ? 'ARMED: Continuous police siren & red border lightning'
                                        : 'DISARMED: Vehicle is unmonitored for parking breaches',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: _safetyPark ? FontWeight.bold : FontWeight.normal,
                                      color: _safetyPark
                                          ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
                                          : scheme.onSurfaceVariant,
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
                        const SizedBox(height: Gap.sm),
                        Text(
                          'When armed, if this vehicle moves (speed > 1 km/h) or the engine turns ON, an immediate continuous police siren will sound across the mobile app with glowing red border lightning until turned off.',
                          style: TextStyle(
                            fontSize: 11,
                            color: _safetyPark
                                ? (isDark ? Colors.white70 : const Color(0xFF7F1D1D))
                                : scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: Gap.sm),
                        Row(
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: () {
                                ref.read(safetyParkingProvider.notifier).triggerTestAlarm(
                                      vehicleName: vehicle.displayName,
                                      plate: vehicle.registrationNumber,
                                    );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(color: Color(0xFFDC2626)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.volume_up_rounded, size: 14),
                              label: const Text(
                                'Test Siren & Lightning',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Gap.lg),

                  // ── Section 1: Overspeed Limit ─────────────────────
                  _SettingsCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isDark: isDark,
                    title: 'Overspeed Threshold',
                    subtitle: 'Alert triggers when vehicle speed exceeds limit',
                    icon: Icons.speed_rounded,
                    iconColor: const Color(0xFFFF9800),
                    badgeText: '${_speedLimit.round()} km/h',
                    badgeColor: const Color(0xFFFF9800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Slider(
                          value: _speedLimit,
                          min: 30,
                          max: 140,
                          divisions: 110,
                          label: '${_speedLimit.round()} km/h',
                          activeColor: const Color(0xFFFF9800),
                          onChanged: (double v) =>
                              setState(() => _speedLimit = v),
                        ),
                        const SizedBox(height: Gap.xs),
                        Wrap(
                          spacing: Gap.xs,
                          runSpacing: Gap.xs,
                          children: <double>[40, 60, 80, 100, 120]
                              .map(
                                (double preset) => ChoiceChip(
                                  label: Text('${preset.round()} km/h'),
                                  selected: _speedLimit == preset,
                                  selectedColor: const Color(0xFFFF9800)
                                      .withOpacity(0.2),
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _speedLimit == preset
                                        ? const Color(0xFFFF9800)
                                        : scheme.onSurfaceVariant,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _speedLimit = preset),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Gap.lg),

                  // ── Section 2: Overspeed Duration ──────────────────
                  _SettingsCard(
                    cardBg: cardBg,
                    borderColor: borderColor,
                    isDark: isDark,
                    title: 'Overspeed Duration',
                    subtitle:
                        'Speeding duration required before firing alert',
                    icon: Icons.timer_rounded,
                    iconColor: const Color(0xFF2196F3),
                    badgeText: '${_overspeedDuration.round()} mins',
                    badgeColor: const Color(0xFF2196F3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Slider(
                          value: _overspeedDuration,
                          min: 1,
                          max: 15,
                          divisions: 14,
                          label: '${_overspeedDuration.round()} mins',
                          activeColor: const Color(0xFF2196F3),
                          onChanged: (double v) =>
                              setState(() => _overspeedDuration = v),
                        ),
                        const SizedBox(height: Gap.xs),
                        Wrap(
                          spacing: Gap.xs,
                          children: <double>[1, 3, 5, 10]
                              .map(
                                (double preset) => ChoiceChip(
                                  label: Text('${preset.round()} mins'),
                                  selected: _overspeedDuration == preset,
                                  selectedColor: const Color(0xFF2196F3)
                                      .withOpacity(0.2),
                                  labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _overspeedDuration == preset
                                        ? const Color(0xFF2196F3)
                                        : scheme.onSurfaceVariant,
                                  ),
                                  onSelected: (_) => setState(
                                      () => _overspeedDuration = preset),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: Gap.lg),

                  // ── Section 3: Idle Duration ───────────────────────
                  DurationAlertCard(
                    title: 'Idle Duration',
                    subtitle: 'Alert triggers when engine is ON but stationary',
                    icon: Icons.hourglass_empty_rounded,
                    iconColor: const Color(0xFF9C27B0),
                    badgeColor: const Color(0xFF9C27B0),
                    controller: _idleController,
                    duration: _idleDuration,
                    enabled: _alertToggles['excessive_idle'] ?? true,
                    onToggle: (bool val) => setState(() {
                      _alertToggles['excessive_idle'] = val;
                      _alertToggles['idle'] = val;
                    }),
                    onDurationChanged: (double v) => setState(() => _idleDuration = v),
                  ),

                  const SizedBox(height: Gap.lg),

                ],
              ),
              
              ListView(
                padding: const EdgeInsets.all(Gap.lg),
                children: [
                  // ── Parking Alert Card ──
                  DurationAlertCard(
                    title: 'Parking',
                    subtitle: 'Alert triggers when vehicle is parked beyond duration',
                    icon: Icons.local_parking_rounded,
                    iconColor: const Color(0xFF2563EB),
                    badgeColor: const Color(0xFF2563EB),
                    controller: _parkingController,
                    duration: _parkingDuration,
                    enabled: _alertToggles['parking'] ?? true,
                    onToggle: (bool val) => setState(() => _alertToggles['parking'] = val),
                    onDurationChanged: (double v) => setState(() => _parkingDuration = v),
                  ),

                  const SizedBox(height: Gap.md),

                  // ── Moving (After Stoppage) Alert Card ──
                  DurationAlertCard(
                    title: 'Moving (After Stoppage)',
                    subtitle: 'Alert triggers when vehicle starts moving after stoppage',
                    icon: Icons.directions_car_rounded,
                    iconColor: const Color(0xFF0D9488),
                    badgeColor: const Color(0xFF0D9488),
                    controller: _movingController,
                    duration: _movingDuration,
                    enabled: _alertToggles['moving'] ?? true,
                    onToggle: (bool val) => setState(() => _alertToggles['moving'] = val),
                    onDurationChanged: (double v) => setState(() => _movingDuration = v),
                  ),

                  const SizedBox(height: Gap.md),

                  // ── Idle Alert Card ──
                  DurationAlertCard(
                    title: 'Idle Duration',
                    subtitle: 'Alert triggers when engine is ON but stationary beyond duration',
                    icon: Icons.hourglass_empty_rounded,
                    iconColor: const Color(0xFF9C27B0),
                    badgeColor: const Color(0xFF9C27B0),
                    controller: _idleController,
                    duration: _idleDuration,
                    enabled: _alertToggles['excessive_idle'] ?? true,
                    onToggle: (bool val) => setState(() {
                      _alertToggles['excessive_idle'] = val;
                      _alertToggles['idle'] = val;
                    }),
                    onDurationChanged: (double v) => setState(() => _idleDuration = v),
                  ),

                  const SizedBox(height: Gap.lg),

                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: Corners.rLg,
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      children: [
                        for (final entry in _alertToggles.entries.where((e) =>
                            !const <String>{'parking', 'moving', 'stoppage', 'excessive_idle', 'idle'}
                                .contains(e.key))) ...[
                          SwitchListTile(
                            value: entry.value,
                            activeColor: const Color(0xFF2E7D32),
                            title: Text('${entry.key.replaceAll('_', ' ').toUpperCase()} ALERT'),
                            subtitle: Text('Receive notifications for ${entry.key.replaceAll('_', ' ')}'),
                            onChanged: (bool val) => setState(() => _alertToggles[entry.key] = val),
                          ),
                          Divider(height: 1, color: borderColor),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.xxl),
                ],
              ),

            ],
          ),
        ),

        // ── Save Action Bar ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(top: BorderSide(color: borderColor)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    shape: RoundedRectangleBorder(
                      borderRadius: Corners.rLg,
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    _isSaving ? 'Saving Changes...' : 'Save Settings',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final VehicleStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = switch (status) {
      VehicleStatus.moving => (const Color(0xFF2E7D32), 'Moving'),
      VehicleStatus.idle => (const Color(0xFFED6C02), 'Idle'),
      VehicleStatus.stopped => (const Color(0xFF757575), 'Parking'),
      VehicleStatus.offline => (const Color(0xFFD32F2F), 'No Data'),
      VehicleStatus.noData => (const Color(0xFF94A3B8), 'Unreachable'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: Corners.rPill,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.cardBg,
    required this.borderColor,
    required this.isDark,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.badgeText,
    required this.badgeColor,
    required this.child,
  });

  final Color cardBg;
  final Color borderColor;
  final bool isDark;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String badgeText;
  final Color badgeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: Corners.rLg,
        border: Border.all(color: borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(Gap.xs + 2),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: Corners.rSm,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: Corners.rPill,
                  border: Border.all(color: badgeColor.withOpacity(0.3)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          child,
        ],
      ),
    );
  }
}
