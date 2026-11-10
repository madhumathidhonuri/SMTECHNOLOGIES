import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/share_helper.dart';
import '../../core/utils/vehicle_icons.dart';
import '../../data/models/vehicle.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/safety_parking_provider.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/live_address.dart';

/// Vehicle Menu Screen (Springboard for vehicle actions & navigation)
class VehicleMenuScreen extends ConsumerStatefulWidget {
  const VehicleMenuScreen({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  ConsumerState<VehicleMenuScreen> createState() => _VehicleMenuScreenState();
}

class _VehicleMenuScreenState extends ConsumerState<VehicleMenuScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socketServiceProvider).joinVehicle(widget.vehicleId);
      ref.read(secureStoreProvider).setLastVehicleId(widget.vehicleId);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Vehicle? vehicle = ref.watch(vehicleByIdProvider(widget.vehicleId));

    if (vehicle == null) {
      final bool isLoading = ref.watch(fleetProvider).isLoading;
      if (isLoading) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.help_outline_rounded,
          title: 'Vehicle unavailable',
          message: 'This vehicle is no longer part of your fleet, or the list '
              'has not finished loading.',
          actionLabel: 'Back to fleet',
          onAction: () => context.go('/dashboard'),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color statusColor = AppColors.forStatus(vehicle.status.key);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(Icons.circle, size: 10, color: statusColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                vehicle.displayName.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_outlined, size: 20),
                    tooltip: 'Share Location',
                    onPressed: () => ShareHelper.shareVehicleLocation(vehicle),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: 'Vehicle Settings',
                    onPressed: () =>
                        context.push('/vehicle/${widget.vehicleId}/settings'),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.x4l),
        children: [
          // ── Hero Card ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2238) : Colors.white,
              borderRadius: Corners.rLg,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: statusColor.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/vehicles/${vehicle.displayType}.png',
                      height: 60,
                      width: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        VehicleIcons.forType(vehicle.displayType),
                        size: 40,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  vehicle.displayName.toUpperCase(),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  vehicle.status.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _HeroMetric(
                      label: 'Speed',
                      value: '${vehicle.speed.round()} km/h',
                      color: AppColors.success,
                    ),
                    _HeroMetric(
                      label: 'Odometer',
                      value: vehicle.odometer != null
                          ? '${vehicle.odometer!.toStringAsFixed(0)} km'
                          : 'N/A',
                      color: Colors.cyan,
                    ),
                    _HeroMetric(
                      label: 'Battery',
                      value: vehicle.batteryLevel != null
                          ? '${vehicle.batteryLevel!.toStringAsFixed(1)} V'
                          : 'N/A',
                      color: Colors.orange,
                    ),
                    _HeroMetric(
                      label: 'Ignition',
                      value: vehicle.ignition ? 'ON' : 'OFF',
                      color: vehicle.ignition
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place_rounded,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: LiveAddress(
                        vehicle: vehicle,
                        
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.grey.shade300
                              : const Color(0xFF4A5568),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: Gap.md),

          // ── Safety Parking Quick Control Banner ───────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: vehicle.isSafetyParkActive
                  ? (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2))
                  : (isDark ? const Color(0xFF1E2238) : Colors.white),
              borderRadius: Corners.rLg,
              border: Border.all(
                color: vehicle.isSafetyParkActive
                    ? const Color(0xFFDC2626)
                    : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                width: vehicle.isSafetyParkActive ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: (vehicle.isSafetyParkActive ? const Color(0xFFDC2626) : Colors.black)
                      .withValues(alpha: vehicle.isSafetyParkActive ? 0.15 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: vehicle.isSafetyParkActive
                        ? const Color(0xFFDC2626)
                        : (isDark ? Colors.white12 : const Color(0xFFF1F5F9)),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    vehicle.isSafetyParkActive ? Icons.security_rounded : Icons.shield_outlined,
                    color: vehicle.isSafetyParkActive ? Colors.white : const Color(0xFF64748B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Safety Parking',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: vehicle.isSafetyParkActive
                                  ? const Color(0xFFDC2626)
                                  : (isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              vehicle.isSafetyParkActive ? 'ARMED' : 'DISARMED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: vehicle.isSafetyParkActive ? Colors.white : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vehicle.isSafetyParkActive
                            ? 'Siren triggers if moved or ignition turns ON'
                            : 'Tap to arm anti-theft parking guard',
                        style: TextStyle(
                          fontSize: 11,
                          color: vehicle.isSafetyParkActive
                              ? const Color(0xFFDC2626)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: vehicle.isSafetyParkActive,
                  activeColor: const Color(0xFFDC2626),
                  onChanged: (bool val) async {
                    if (val) {
                      await ref.read(safetyParkingProvider.notifier).arm(vehicle.id);
                    } else {
                      await ref.read(safetyParkingProvider.notifier).disarm(vehicle.id);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: Gap.lg),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: Gap.md),
            child: Text(
              'VEHICLE MENU',
              style: AppTypography.eyebrow(theme.colorScheme.onSurfaceVariant),
            ),
          ),

          // ── Menu List Items ───────────────────────────────────────────
          _MenuItemCard(
            title: 'Vehicle Detail',
            subtitle: 'Live map, status banner, telemetry & tabbed view',
            icon: Icons.space_dashboard_rounded,
            accentColor: const Color(0xFF3B82F6), // Blue
            onTap: () => context.push('/vehicle/${widget.vehicleId}/detail'),
          ),

          _MenuItemCard(
            title: 'Live Map Tracking',
            subtitle: 'Full-screen interactive map with real-time location',
            icon: Icons.map_rounded,
            accentColor: const Color(0xFF10B981), // Emerald
            onTap: () => context.push('/vehicle-map?focus=${widget.vehicleId}'),
          ),

          _MenuItemCard(
            title: 'Playback & History',
            subtitle: 'Replay past trips, route trails & stoppage analysis',
            icon: Icons.history_rounded,
            accentColor: const Color(0xFFF59E0B), // Amber
            onTap: () =>
                context.push('/vehicle/${widget.vehicleId}/detail?tab=1'),
          ),

          _MenuItemCard(
            title: 'Alerts & Events',
            subtitle: 'View overspeed, geofence, ignition & battery logs',
            icon: Icons.notifications_active_rounded,
            accentColor: const Color(0xFFEF4444), // Red
            onTap: () =>
                context.push('/vehicle/${widget.vehicleId}/detail?tab=2'),
          ),

          _MenuItemCard(
            title: 'Geofences',
            subtitle: 'Virtual boundaries, entry/exit zones & alerts',
            icon: Icons.fence_rounded,
            accentColor: const Color(0xFF10B981), // Emerald
            onTap: () =>
                context.push('/vehicle/${widget.vehicleId}/geofences'),
          ),

          _MenuItemCard(
            title: 'Vehicle Info & Specs',
            subtitle: 'Hardware details, IMEI, driver assignment & docs',
            icon: Icons.info_outline_rounded,
            accentColor: const Color(0xFF06B6D4), // Cyan
            onTap: () =>
                context.push('/vehicle/${widget.vehicleId}/detail?tab=3'),
          ),

          _MenuItemCard(
            title: 'Fitment Certificate',
            subtitle: 'View, verify & download official AIS-140 certificate (PDF)',
            icon: Icons.verified_user_rounded,
            accentColor: const Color(0xFF10B981), // Emerald
            onTap: () =>
                context.push('/vehicle/${widget.vehicleId}/fitment-certificate'),
          ),

          _MenuItemCard(
            title: 'Vehicle Reports',
            subtitle: 'Distance, trip summary, idle time & fuel reports',
            icon: Icons.assessment_rounded,
            accentColor: const Color(0xFF8B5CF6), // Purple
            onTap: () => context.go('/reports?vehicle=${widget.vehicleId}'),
          ),

          _MenuItemCard(
            title: 'Primary Engine On',
            subtitle: 'Engine ON/OFF events, total duration & nearest locations',
            icon: Icons.power_settings_new_rounded,
            accentColor: const Color(0xFFF59E0B), // Amber
            onTap: () =>
                context.push('/vehicle/${widget.vehicleId}/engine-on'),
          ),

          _MenuItemCard(
            title: 'Alert & Notification Configuration',
            subtitle: 'Speed limits, alert thresholds & notification toggles',
            icon: Icons.notifications_active_outlined,
            accentColor: const Color(0xFF64748B), // Slate
            onTap: () => context.push('/vehicle/${widget.vehicleId}/settings'),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  const _MenuItemCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2238) : Colors.white,
        borderRadius: Corners.rLg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: Corners.rLg,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF2E3355),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
