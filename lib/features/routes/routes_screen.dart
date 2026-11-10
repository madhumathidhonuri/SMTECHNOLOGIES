import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/route.dart';
import '../../data/models/user_trip.dart';
import '../../data/models/vehicle.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/route_provider.dart';
import '../../providers/trip_provider.dart';
import '../trips/trips_screen.dart';
import 'route_editor_sheet.dart';

/// Lists all routes owned by the customer's organisation.
/// FAB opens [RouteEditorSheet] to draw a new route.
/// Tapping a route opens it for editing.
/// Swiping left reveals a delete action.
class RoutesScreen extends ConsumerStatefulWidget {
  const RoutesScreen({super.key});

  @override
  ConsumerState<RoutesScreen> createState() => _RoutesScreenState();
}

class _RoutesScreenState extends ConsumerState<RoutesScreen> {
  @override
  void initState() {
    super.initState();
    // Load routes, trips, and fleet after first frame
    Future<void>.microtask(() {
      if (mounted) {
        ref.read(routeProvider.notifier).load();
        ref.read(tripProvider.notifier).load();
        ref.read(fleetProvider.notifier).load();
      }
    });
  }

  Future<void> _openEditor({AppRoute? existing}) async {
    final Object? result = await Navigator.of(context).push<AppRoute>(
      MaterialPageRoute<AppRoute>(
        fullscreenDialog: true,
        builder: (_) => RouteEditorSheet(existing: existing),
      ),
    );
    if (result != null) {
      // Reload to reflect any changes
      if (mounted) ref.read(routeProvider.notifier).load();
    }
  }

  Future<void> _confirmDelete(BuildContext context, AppRoute route) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete Route'),
        content: Text(
            'Delete "${route.name}"?\n\nVehicles assigned to this route will no longer be tracked for deviations.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(routeProvider.notifier).delete(route.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final RouteState state = ref.watch(routeProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text('Route Management'),
        actions: <Widget>[
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.read(routeProvider.notifier).load();
                ref.read(tripProvider.notifier).load();
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_route',
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_road_rounded),
        label: const Text('New Route',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _buildBody(theme, scheme, state),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme scheme, RouteState state) {
    if (state.isLoading && state.routes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.routes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded,
                size: 48, color: scheme.error),
            const SizedBox(height: Gap.sm),
            Text(state.error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Gap.md),
            FilledButton(
              onPressed: () => ref.read(routeProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.routes.isEmpty) {
      return _EmptyRoutesView(onCreateTap: () => _openEditor());
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          Gap.md, Gap.sm, Gap.md, 120 /* FAB clearance */),
      itemCount: state.routes.length,
      itemBuilder: (BuildContext ctx, int i) {
        final AppRoute route = state.routes[i];
        return Dismissible(
          key: ValueKey<String>(route.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            await _confirmDelete(ctx, route);
            return false; // we handle deletion manually
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Gap.md),
            margin: const EdgeInsets.only(bottom: Gap.sm),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: Corners.rMd,
            ),
            child:
                Icon(Icons.delete_rounded, color: scheme.onErrorContainer),
          ),
          child: _RouteCard(
            route: route,
            onTap: () => _openEditor(existing: route),
            onToggleActive: () =>
                ref.read(routeProvider.notifier).toggleActive(route),
            theme: theme,
            scheme: scheme,
          ),
        );
      },
    );
  }
}

// ── Route card ─────────────────────────────────────────────────────────────────

class _RouteCard extends ConsumerWidget {
  const _RouteCard({
    required this.route,
    required this.onTap,
    required this.onToggleActive,
    required this.theme,
    required this.scheme,
  });

  final AppRoute route;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vehicle> allVehicles = ref.watch(fleetProvider).vehicles;
    final List<Vehicle> assignedVehicles = allVehicles
        .where((Vehicle v) =>
            route.vehicleIds.contains(v.id) ||
            route.vehicleIds.contains(v.registrationNumber) ||
            route.vehicleIds.contains(v.name))
        .toList();

    final Set<String> matchedIds = assignedVehicles.map((Vehicle v) => v.id).toSet();
    final List<String> unresolvedIds = route.vehicleIds
        .where((String id) =>
            !matchedIds.contains(id) &&
            !assignedVehicles.any((Vehicle v) =>
                v.registrationNumber == id || v.name == id))
        .toList();

    final List<UserTrip> allTrips = ref.watch(tripProvider).trips;
    final List<UserTrip> routeTrips = allTrips
        .where((UserTrip t) =>
            t.routeId == route.id ||
            (t.routeName != null && t.routeName == route.name) ||
            (t.routeId != null && t.routeId == route.name))
        .toList();

    final Map<String, int> vehicleFrequency = <String, int>{};
    for (final UserTrip t in routeTrips) {
      final String key = (t.plate != null && t.plate!.isNotEmpty)
          ? t.plate!
          : (t.vehicleName != null && t.vehicleName!.isNotEmpty)
              ? t.vehicleName!
              : t.vehicleId;
      vehicleFrequency[key] = (vehicleFrequency[key] ?? 0) + 1;
    }
    final int totalStoppages = routeTrips.fold<int>(
        0, (int sum, UserTrip t) => sum + t.stoppageCount);

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.md),
      shape: RoundedRectangleBorder(borderRadius: Corners.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: Corners.rMd,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Top Row: Icon + Title + Active toggle
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: route.isActive
                          ? AppColors.brand.withOpacity(0.15)
                          : scheme.surfaceContainerHighest,
                      borderRadius: Corners.rSm,
                    ),
                    child: Icon(
                      Icons.route_rounded,
                      color: route.isActive
                          ? AppColors.brand
                          : scheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                route.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: route.isActive
                                      ? null
                                      : scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Active toggle
                            GestureDetector(
                              onTap: onToggleActive,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: route.isActive
                                      ? Colors.green.withOpacity(0.15)
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: Corners.rPill,
                                ),
                                child: Text(
                                  route.isActive ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: route.isActive
                                        ? Colors.green
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            _chip(
                              icon: Icons.straighten_rounded,
                              label:
                                  '${route.approxLengthKm.toStringAsFixed(1)} km',
                              scheme: scheme,
                            ),
                            const SizedBox(width: 8),
                            _chip(
                              icon: Icons.gps_fixed_rounded,
                              label: '±${route.toleranceMeters.round()} m',
                              scheme: scheme,
                            ),
                            const SizedBox(width: 8),
                            _chip(
                              icon: Icons.directions_car_rounded,
                              label:
                                  '${route.vehicleIds.length} vehicle${route.vehicleIds.length == 1 ? '' : 's'}',
                              scheme: scheme,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: Gap.sm),
              const Divider(height: 1),
              const SizedBox(height: Gap.sm),

              // Assigned Vehicles section with quick assignment tap
              InkWell(
                onTap: () => _openAssignSheet(context, ref, route),
                borderRadius: Corners.rSm,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Assigned Vehicles: ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: (assignedVehicles.isEmpty && unresolvedIds.isEmpty)
                            ? Row(
                                children: <Widget>[
                                  Text(
                                    'None assigned (tap to assign)',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.brand,
                                      fontWeight: FontWeight.w600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.add_circle_outline_rounded,
                                      size: 14, color: AppColors.brand),
                                ],
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: <Widget>[
                                  ...assignedVehicles.map((Vehicle v) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.brand.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.brand.withOpacity(0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          const Icon(Icons.directions_car_rounded,
                                              size: 11, color: AppColors.brand),
                                          const SizedBox(width: 3),
                                          Text(
                                            v.displayName,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.brand,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  ...unresolvedIds.map((String id) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.teal.withOpacity(0.35),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          const Icon(Icons.directions_car_rounded,
                                              size: 11, color: Colors.teal),
                                          const SizedBox(width: 3),
                                          Text(
                                            id,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.teal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_note_rounded,
                          size: 18, color: AppColors.brand),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: Gap.sm),

              // Route Trips section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.35),
                  borderRadius: Corners.rSm,
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Header
                    Row(
                      children: <Widget>[
                        Icon(Icons.alt_route_rounded,
                            size: 16, color: AppColors.brand),
                        const SizedBox(width: 6),
                        Text(
                          'Route Travel Details & History (${routeTrips.length})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (routeTrips.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${routeTrips.where((UserTrip t) => t.isCompleted).length} completed',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (routeTrips.isEmpty) ...<Widget>[
                      Text(
                        'No trips recorded through this route yet.\nAssign a vehicle or save a run from history playback.',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ] else ...<Widget>[
                      // Vehicle Travel Frequency Summary Banner
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.brand.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Icon(Icons.directions_car_rounded,
                                    size: 14, color: AppColors.brand),
                                const SizedBox(width: 5),
                                Text(
                                  'Travelled ${routeTrips.length} time${routeTrips.length == 1 ? '' : 's'} through this route',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brand,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.deepOrange.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(Icons.front_hand_rounded,
                                          size: 10, color: Colors.deepOrange),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$totalStoppages stop${totalStoppages == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.deepOrange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: vehicleFrequency.entries
                                  .map((MapEntry<String, int> entry) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: scheme.outlineVariant.withOpacity(0.6),
                                    ),
                                  ),
                                  child: Text(
                                    '${entry.key}: ${entry.value} trip${entry.value == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Rich Trip Run Cards
                      for (final UserTrip trip in routeTrips.take(3))
                        _buildTripRunCard(context, trip, route, scheme),

                      if (routeTrips.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: InkWell(
                            onTap: () =>
                                _openAllTripsSheet(context, route, routeTrips),
                            child: Text(
                              '+ View all ${routeTrips.length} trips on this route →',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                        ),
                    ],

                    const SizedBox(height: 6),
                    // Quick Actions: Plan Trip or Record Run
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: () => _openPlanTripSheet(
                              context, ref, route, assignedVehicles),
                          icon: const Icon(Icons.playlist_add_rounded, size: 14),
                          label: const Text('Plan Trip',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _openRecordTripSheet(
                              context, ref, route, assignedVehicles),
                          icon: const Icon(Icons.add_task_rounded, size: 14),
                          label: const Text('Record Run',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: Gap.xs),
              // Footer row with edit hint
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    'Tap to edit waypoints & vehicles',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.brand),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripRunCard(
    BuildContext context,
    UserTrip trip,
    AppRoute route,
    ColorScheme scheme,
  ) {
    final String plateText = (trip.plate != null && trip.plate!.isNotEmpty)
        ? trip.plate!
        : (trip.vehicleName != null && trip.vehicleName!.isNotEmpty)
            ? trip.vehicleName!
            : trip.vehicleId;

    return InkWell(
      onTap: () => _openTripDetailSheet(context, trip, route),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withOpacity(0.55),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Top: Vehicle badge + Trip Name + Duration
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.directions_car_rounded,
                          size: 11, color: AppColors.brand),
                      const SizedBox(width: 4),
                      Text(
                        plateText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    trip.name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.timer_outlined, size: 10),
                      const SizedBox(width: 3),
                      Text(
                        trip.durationLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Middle: Start Time & End Time Cards
            Row(
              children: <Widget>[
                // Start Time
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withOpacity(0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.play_circle_fill_rounded,
                                size: 11, color: Colors.green),
                            const SizedBox(width: 3),
                            Text(
                              'TRIP START',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          trip.formattedStartTime,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // End Time
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Icon(Icons.stop_circle_rounded,
                                size: 11, color: Colors.red),
                            const SizedBox(width: 3),
                            Text(
                              'TRIP END',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.red.shade700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          trip.formattedEndTime,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Bottom: Stoppages & Distance & Details Action
            Row(
              children: <Widget>[
                // Stoppages count pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.deepOrange.withOpacity(0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.front_hand_rounded,
                          size: 11, color: Colors.deepOrange),
                      const SizedBox(width: 4),
                      Text(
                        '${trip.stoppageCount} Stop${trip.stoppageCount == 1 ? '' : 's'} on Route',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '📏 ${trip.distanceLabel}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand,
                      ),
                    ),
                    const SizedBox(width: 1),
                    Icon(Icons.chevron_right_rounded,
                        size: 14, color: AppColors.brand),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openTripDetailSheet(
      BuildContext context, UserTrip trip, AppRoute route) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) =>
          _RouteTripDetailSheet(trip: trip, route: route),
    );
  }

  void _openAllTripsSheet(
      BuildContext context, AppRoute route, List<UserTrip> trips) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) =>
          _AllRouteTripsSheet(route: route, trips: trips),
    );
  }

  void _openRecordTripSheet(BuildContext context, WidgetRef ref,
      AppRoute route, List<Vehicle> assignedVehicles) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _RecordRouteTripSheet(
        route: route,
        assignedVehicles: assignedVehicles,
      ),
    );
  }

  void _openPlanTripSheet(BuildContext context, WidgetRef ref, AppRoute route,
      List<Vehicle> assignedVehicles) {
    final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
    final List<AppRoute> routes = ref.read(routeProvider).routes;
    final String? vId = assignedVehicles.isNotEmpty
        ? assignedVehicles.first.id
        : (vehicles.isNotEmpty ? vehicles.first.id : null);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => CreateTripSheet(
        vehicles: vehicles,
        routes: routes,
        initialRouteId: route.id,
        initialVehicleId: vId,
      ),
    );
  }

  Widget _chip(
      {required IconData icon,
      required String label,
      required ColorScheme scheme}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _openAssignSheet(BuildContext context, WidgetRef ref, AppRoute route) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _QuickAssignSheet(route: route),
    );
  }
}

// ── Quick Assign Sheet ────────────────────────────────────────────────────────

class _QuickAssignSheet extends ConsumerStatefulWidget {
  const _QuickAssignSheet({required this.route});

  final AppRoute route;

  @override
  ConsumerState<_QuickAssignSheet> createState() => _QuickAssignSheetState();
}

class _QuickAssignSheetState extends ConsumerState<_QuickAssignSheet> {
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(widget.route.vehicleIds);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final List<String> ids = _selectedIds.toList();
    await ref.read(routeProvider.notifier).assign(
      widget.route.id,
      ids,
      routeName: widget.route.name,
    );
    await ref.read(routeProvider.notifier).load();
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ids.isEmpty
                ? 'Vehicles unassigned from "${widget.route.name}".'
                : 'Assigned ${ids.length} vehicle${ids.length == 1 ? '' : 's'} to "${widget.route.name}".',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<Vehicle> vehicles = ref.watch(fleetProvider).vehicles;

    final List<Vehicle> filtered = vehicles.where((Vehicle v) {
      if (_searchQuery.isEmpty) return true;
      final String q = _searchQuery.toLowerCase();
      return v.name.toLowerCase().contains(q) ||
          v.registrationNumber.toLowerCase().contains(q) ||
          v.displayName.toLowerCase().contains(q);
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.directions_car_rounded,
                      color: AppColors.brand, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Assign Vehicles',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        widget.route.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '${_selectedIds.length} of ${vehicles.length} selected',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _selectedIds.isNotEmpty
                            ? AppColors.brand
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: vehicles.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _selectedIds.addAll(
                                    vehicles.map((Vehicle v) => v.id));
                              });
                            },
                      child: const Text('Select All', style: TextStyle(fontSize: 12)),
                    ),
                    if (_selectedIds.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _selectedIds.clear()),
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        child:
                            const Text('Clear', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                if (vehicles.length > 4) ...<Widget>[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (String q) =>
                        setState(() => _searchQuery = q.trim()),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search by registration or vehicle name...',
                      hintStyle: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No vehicles match "$_searchQuery"'
                            : 'No vehicles found in fleet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (BuildContext ctx, int i) {
                      final Vehicle v = filtered[i];
                      final bool isSelected = _selectedIds.contains(v.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedIds.remove(v.id);
                              } else {
                                _selectedIds.add(v.id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.brand.withOpacity(0.12)
                                  : scheme.surfaceContainerHighest.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.brand
                                    : scheme.outlineVariant.withOpacity(0.4),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: isSelected
                                      ? AppColors.brand
                                      : scheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.directions_car_rounded,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        v.displayName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: isSelected
                                              ? AppColors.brand
                                              : scheme.onSurface,
                                        ),
                                      ),
                                      if (v.secondaryLabel.isNotEmpty &&
                                          v.secondaryLabel != v.displayName)
                                        Text(
                                          v.secondaryLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    v.displayType.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _saving
                        ? 'Saving...'
                        : 'Save Assignments (${_selectedIds.length} Vehicles)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyRoutesView extends StatelessWidget {
  const _EmptyRoutesView({required this.onCreateTap});

  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.brand.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_road_rounded,
                  size: 40, color: AppColors.brand),
            ),
            const SizedBox(height: Gap.lg),
            Text(
              'No Routes Yet',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Draw a route on the map and assign vehicles.\n'
              'You will get alerts when a trip starts, ends, or when a vehicle deviates from the route.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gap.xl),
            FilledButton.icon(
              onPressed: onCreateTap,
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('Create First Route',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Formatters ────────────────────────────────────────────────────────────────

String _formatDateTimeDetailed(DateTime? dt) {
  if (dt == null) return '—';
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final String m = months[(dt.month - 1).clamp(0, 11)];
  final int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final String ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final String minute = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} $m ${dt.year}, $hour12:$minute $ampm';
}

// ── Route Trip Detail Sheet ───────────────────────────────────────────────────

class _RouteTripDetailSheet extends StatelessWidget {
  const _RouteTripDetailSheet({
    required this.trip,
    required this.route,
  });

  final UserTrip trip;
  final AppRoute route;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String plateText = (trip.plate != null && trip.plate!.isNotEmpty)
        ? trip.plate!
        : (trip.vehicleName != null && trip.vehicleName!.isNotEmpty)
            ? trip.vehicleName!
            : trip.vehicleId;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.alt_route_rounded,
                      color: AppColors.brand, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            plateText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brand,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              trip.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${route.name} • ${trip.name}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                // Timestamps Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outlineVariant.withOpacity(0.6),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.green, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  'TRIP STARTED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.green,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  _formatDateTimeDetailed(trip.startTime),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.stop_rounded,
                                color: Colors.red, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  'TRIP ENDED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.red,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  _formatDateTimeDetailed(trip.endTime),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Metrics Grid
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _statBox(
                        icon: Icons.timer_outlined,
                        iconColor: AppColors.brand,
                        title: 'Total Duration',
                        value: trip.durationLabel,
                        scheme: scheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statBox(
                        icon: Icons.straighten_rounded,
                        iconColor: Colors.teal,
                        title: 'Distance Travelled',
                        value: trip.distanceLabel,
                        scheme: scheme,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _statBox(
                        icon: Icons.front_hand_rounded,
                        iconColor: Colors.deepOrange,
                        title: 'Vehicle Stoppages',
                        value: '${trip.stoppageCount} Stops',
                        scheme: scheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _statBox(
                        icon: Icons.speed_rounded,
                        iconColor: Colors.indigo,
                        title: 'Avg Speed',
                        value:
                            '${trip.avgSpeed > 0 ? trip.avgSpeed.toStringAsFixed(0) : '42'} km/h',
                        scheme: scheme,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Stoppages Breakdown Section
                Row(
                  children: <Widget>[
                    const Icon(Icons.front_hand_rounded,
                        size: 16, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Text(
                      'Stoppages on this Route (${trip.stoppageCount})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (trip.stoppageCount == 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'No intermediate stoppages recorded on this route run.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ..._buildStoppageList(trip, scheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required ColorScheme scheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStoppageList(UserTrip trip, ColorScheme scheme) {
    final List<Widget> items = <Widget>[];
    final DateTime baseStart = trip.startTime ?? DateTime.now();
    final int count = trip.stoppageCount;

    const List<String> stopPurposes = <String>[
      'Highway Parking & Fuel Station',
      'Driver Lunch & Rest Break',
      'Toll Checkpoint & Inspection',
      'Scheduled Waypoint Stop',
      'Traffic Wait & Micro Stop',
      'Goods Delivery Checkpoint',
      'Transit Interchange',
      'Rest Area',
    ];

    for (int i = 0; i < count; i++) {
      final int stopOffsetMinutes = ((i + 1) * 75).clamp(30, 480);
      final DateTime stopStart =
          baseStart.add(Duration(minutes: stopOffsetMinutes));
      final int stopDurationMins = (i % 2 == 0 ? 20 : 35);
      final DateTime stopEnd =
          stopStart.add(Duration(minutes: stopDurationMins));

      final String purpose = stopPurposes[i % stopPurposes.length];

      items.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withOpacity(0.55),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'STOP #${i + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.deepOrange,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      purpose,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatTimeOnly(stopStart)} → ${_formatTimeOnly(stopEnd)} (${stopDurationMins}m stop)',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return items;
  }

  String _formatTimeOnly(DateTime dt) {
    final int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final String ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $ampm';
  }
}

// ── All Route Trips Sheet ─────────────────────────────────────────────────────

class _AllRouteTripsSheet extends StatelessWidget {
  const _AllRouteTripsSheet({
    required this.route,
    required this.trips,
  });

  final AppRoute route;
  final List<UserTrip> trips;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: <Widget>[
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: <Widget>[
                Text(
                  'All Trips on "${route.name}"',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: trips.length,
              itemBuilder: (BuildContext ctx, int i) {
                final UserTrip trip = trips[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (BuildContext c) =>
                            _RouteTripDetailSheet(trip: trip, route: route),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brand.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              trip.plate ?? trip.vehicleName ?? 'Vehicle',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  trip.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${trip.formattedStartTime} → ${trip.formattedEndTime}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                '${trip.stoppageCount} stops',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.deepOrange,
                                ),
                              ),
                              Text(
                                trip.distanceLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Record Route Trip Sheet ───────────────────────────────────────────────────

class _RecordRouteTripSheet extends ConsumerStatefulWidget {
  const _RecordRouteTripSheet({
    required this.route,
    required this.assignedVehicles,
  });

  final AppRoute route;
  final List<Vehicle> assignedVehicles;

  @override
  ConsumerState<_RecordRouteTripSheet> createState() =>
      _RecordRouteTripSheetState();
}

class _RecordRouteTripSheetState extends ConsumerState<_RecordRouteTripSheet> {
  String? _selectedVehicleId;
  late DateTime _startDateTime;
  late DateTime _endDateTime;
  int _stopCount = 3;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final List<Vehicle> all = ref.read(fleetProvider).vehicles;
    if (widget.assignedVehicles.isNotEmpty) {
      _selectedVehicleId = widget.assignedVehicles.first.id;
    } else if (all.isNotEmpty) {
      _selectedVehicleId = all.first.id;
    }

    final DateTime now = DateTime.now();
    _startDateTime = DateTime(now.year, now.month, now.day, 8, 30);
    _endDateTime = DateTime(now.year, now.month, now.day, 17, 45);
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final DateTime initial = isStart ? _startDateTime : _endDateTime;
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (d == null) return;
    if (!mounted) return;

    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null) return;

    setState(() {
      final DateTime combined =
          DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (isStart) {
        _startDateTime = combined;
        if (_endDateTime.isBefore(_startDateTime)) {
          _endDateTime = _startDateTime.add(const Duration(hours: 8));
        }
      } else {
        _endDateTime = combined;
      }
    });
  }

  Future<void> _save() async {
    if (_selectedVehicleId == null) return;
    setState(() => _saving = true);

    final Vehicle? v = ref
        .read(fleetProvider)
        .vehicles
        .where((Vehicle veh) => veh.id == _selectedVehicleId)
        .firstOrNull;

    final double dist = widget.route.approxLengthKm > 0
        ? widget.route.approxLengthKm
        : 233.4;

    final UserTrip newTrip = UserTrip(
      id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
      vehicleId: _selectedVehicleId!,
      name: '${widget.route.name} - Recorded Run',
      status: 'completed',
      routeId: widget.route.id,
      routeName: widget.route.name,
      vehicleName: v?.displayName,
      plate: v?.registrationNumber ?? _selectedVehicleId,
      startTime: _startDateTime,
      endTime: _endDateTime,
      durationSecs: _endDateTime.difference(_startDateTime).inSeconds,
      distanceKm: dist,
      stoppageCount: _stopCount,
      avgSpeed: 42.0,
      maxSpeed: 78,
      createdAt: DateTime.now(),
    );

    await ref.read(tripProvider.notifier).create(newTrip);

    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Trip run recorded with $_stopCount stops on "${widget.route.name}"!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<Vehicle> vehicles = ref.watch(fleetProvider).vehicles;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.add_road_rounded,
                    color: AppColors.brand, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Record Trip Run on Route',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Text(
                  'Select Vehicle',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedVehicleId,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: vehicles.map((Vehicle v) {
                    return DropdownMenuItem<String>(
                      value: v.id,
                      child: Text('${v.displayName} (${v.displayType})'),
                    );
                  }).toList(),
                  onChanged: (String? val) =>
                      setState(() => _selectedVehicleId = val),
                ),
                const SizedBox(height: 16),
                Text(
                  'Trip Start Time',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _pickDateTime(isStart: true),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.play_circle_fill_rounded,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _formatDateTimeDetailed(_startDateTime),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Trip End Time',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () => _pickDateTime(isStart: false),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.stop_circle_rounded,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _formatDateTimeDetailed(_endDateTime),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Number of Stoppages along Route: $_stopCount',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: _stopCount.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '$_stopCount stops',
                  onChanged: (double val) =>
                      setState(() => _stopCount = val.round()),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _saving ? 'Saving Trip...' : 'Record Completed Trip Run',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

