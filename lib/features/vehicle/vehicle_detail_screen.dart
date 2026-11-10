import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/share_helper.dart';
import '../../data/models/vehicle.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/safety_parking_provider.dart';
import '../../shared/widgets/app_states.dart';
import '../alerts/alerts_screen.dart';
import 'tabs/vehicle_info_tab.dart';
import 'tabs/vehicle_live_tab.dart';
import 'tabs/vehicle_playback_tab.dart';

/// Comprehensive Tabbed Vehicle Detail Screen (Live, History, Alerts, Info)
class VehicleDetailScreen extends ConsumerStatefulWidget {
  const VehicleDetailScreen({
    required this.vehicleId,
    this.initialTab = 0,
    super.key,
  });

  final String vehicleId;
  final int initialTab;

  @override
  ConsumerState<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends ConsumerState<VehicleDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socketServiceProvider).joinVehicle(widget.vehicleId);
      ref.read(secureStoreProvider).setLastVehicleId(widget.vehicleId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Vehicle? vehicle = ref.watch(vehicleByIdProvider(widget.vehicleId));

    if (vehicle == null) {
      final bool isLoading = ref.watch(fleetProvider).isLoading;
      if (isLoading) {
        return Scaffold(
          appBar: _tabController.index == 1 ? null : AppBar(),
          body: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }
      return Scaffold(
        appBar: _tabController.index == 1 ? null : AppBar(),
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
      appBar: _tabController.index == 1 ? null : AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/vehicle/${widget.vehicleId}');
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
                    tooltip: 'Share Location via WhatsApp',
                    onPressed: () => _shareLocation(vehicle),
                  ),
                  IconButton(
                    icon: Icon(
                      vehicle.isSafetyParkActive
                          ? Icons.security_rounded
                          : Icons.shield_outlined,
                      size: 20,
                      color: vehicle.isSafetyParkActive ? const Color(0xFFDC2626) : null,
                    ),
                    tooltip: vehicle.isSafetyParkActive
                        ? 'Safety Parking ARMED (Tap to Disarm)'
                        : 'Arm Safety Parking (Theft Siren)',
                    onPressed: () async {
                      final bool target = !vehicle.isSafetyParkActive;
                      if (target) {
                        await ref.read(safetyParkingProvider.notifier).arm(vehicle.id);
                      } else {
                        await ref.read(safetyParkingProvider.notifier).disarm(vehicle.id);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              target
                                  ? '🛡️ Safety Parking ARMED for ${vehicle.displayName}!'
                                  : 'Safety Parking Disarmed.',
                            ),
                            backgroundColor: target ? const Color(0xFFDC2626) : const Color(0xFF475569),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    tooltip: 'Vehicle Settings',
                    onPressed: () => context.push('/vehicle/${widget.vehicleId}/settings'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.my_location_rounded, size: 20),
                    tooltip: 'Focus on Map',
                    onPressed: () => context.push('/vehicle-map?focus=${widget.vehicleId}'),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          indicatorColor: theme.colorScheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          tabs: const [
            Tab(text: 'Live'),
            Tab(text: 'History'),
            Tab(text: 'Alerts'),
            Tab(text: 'Info'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          VehicleLiveTab(vehicleId: widget.vehicleId),
          VehiclePlaybackTab(vehicleId: widget.vehicleId),
          AlertsScreen(vehicleId: widget.vehicleId),
          VehicleInfoTab(vehicleId: widget.vehicleId),
        ],
      ),
    );
  }

  Future<void> _shareLocation(Vehicle vehicle) async {
    await ShareHelper.shareVehicleLocation(vehicle);
  }
}
