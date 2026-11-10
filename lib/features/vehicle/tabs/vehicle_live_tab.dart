import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/fleet_provider.dart';
import '../../../providers/auth_provider.dart';

import '../../../shared/widgets/live_address.dart';
import '../../live_map/widgets/map_tiles.dart';
import '../../live_map/widgets/vehicle_marker.dart';
import '../widgets/telemetry_grid.dart';

/// Live tab: a pinned mini-map plus a full telemetry grid, both updating
/// from the same throttled fleet stream.
class VehicleLiveTab extends ConsumerStatefulWidget {
  const VehicleLiveTab({required this.vehicleId, super.key});

  final String vehicleId;

  @override
  ConsumerState<VehicleLiveTab> createState() => _VehicleLiveTabState();
}

class _VehicleLiveTabState extends ConsumerState<VehicleLiveTab>
    with AutomaticKeepAliveClientMixin {
  final MapController _map = MapController();
  bool _ready = false;

  LatLng? _lastCamera;

  @override
  bool get wantKeepAlive => true;

  void _follow(Vehicle v) {
    if (!v.hasLocation || !_ready) return;

    final LatLng target = LatLng(v.latitude!, v.longitude!);

    // Skip sub-metre jitter — avoids constant camera churn while parked.
    if (_lastCamera != null &&
        (_lastCamera!.latitude - target.latitude).abs() < 0.00002 &&
        (_lastCamera!.longitude - target.longitude).abs() < 0.00002) {
      return;
    }
    _lastCamera = target;
    _map.move(target, _map.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final ThemeData theme = Theme.of(context);
    final Vehicle? vehicle = ref.watch(vehicleByIdProvider(widget.vehicleId));

    if (vehicle == null) return const SizedBox.shrink();

    ref.listen<Vehicle?>(vehicleByIdProvider(widget.vehicleId),
        (Vehicle? _, Vehicle? next) {
      if (next != null) _follow(next);
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.x4l),
      children: <Widget>[
        // ── Mini map ─────────────────────────────────────────────
        ClipRRect(
          borderRadius: Corners.rLg,
          child: SizedBox(
            height: 230,
            child: vehicle.hasLocation
                ? Stack(
                    children: <Widget>[
                      FlutterMap(
                        mapController: _map,
                        options: MapOptions(
                          initialCenter:
                              LatLng(vehicle.latitude!, vehicle.longitude!),
                          initialZoom: 15.5,
                          minZoom: 3,
                          maxZoom: 19,
                          backgroundColor: theme.colorScheme.surfaceContainer,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.pinchZoom |
                                InteractiveFlag.drag |
                                InteractiveFlag.doubleTapZoom,
                          ),
                          onMapReady: () {
                            if (mounted) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() => _ready = true);
                              });
                            }
                          },
                        ),
                        children: <Widget>[
                          buildTileLayer(
                            MapStyleX.fromKey(
                              ref.read(secureStoreProvider).mapType,
                            ),
                            apiKey: ref.read(authProvider).user?.apiKey,
                          ),
                          MarkerLayer(
                            markers: <Marker>[
                              Marker(
                                point: LatLng(
                                    vehicle.latitude!, vehicle.longitude!),
                                // Match the actual VehicleMarkerPin dimensions (44×48).
                                // Alignment(0.0, -0.89) places the sharp teardrop needle tip
                                // directly onto the GPS road coordinate.
                                width: 44,
                                height: 48,
                                alignment: const Alignment(0.0, -0.89),
                                child: GestureDetector(
                                  onTap: () => context.push('/vehicle-map?focus=${vehicle.id}'),
                                  child: VehicleMarkerPin(
                                    vehicle: vehicle,
                                    selected: true,
                                    useSprite: true,
                                    headingOverride: vehicle.heading,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: OsmAttribution(
                              style: MapStyle.standard,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      // Tap-to-expand overlay — opens full zoomed live map
                      Positioned(
                        top: Gap.sm,
                        right: Gap.sm,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => context.push(
                              '/vehicle-map?focus=${vehicle.id}',
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.gps_fixed_rounded,
                                      size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'Live Track',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: theme.colorScheme.surfaceContainer,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.location_off_rounded,
                              size: 30,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: Gap.sm),
                          Text('No GPS fix available',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
          ),
        ),

        const SizedBox(height: Gap.md),
        Builder(
          builder: (context) {
            final Color statusAccent = AppColors.forStatus(vehicle.status.key);
            final String titleText = switch (vehicle.status) {
              VehicleStatus.moving => 'Vehicle Moving',
              VehicleStatus.idle => 'Vehicle Idling',
              VehicleStatus.stopped => 'Vehicle Stopped',
              VehicleStatus.offline => 'Vehicle Offline',
              VehicleStatus.noData => 'No Data Available',
            };
            final String sinceText = switch (vehicle.status) {
              VehicleStatus.moving => 'Moving since',
              VehicleStatus.idle => 'Idling since',
              VehicleStatus.stopped => 'Stopped since',
              VehicleStatus.offline => 'Offline since',
              VehicleStatus.noData => 'Status',
            };
            final IconData statusIcon = switch (vehicle.status) {
              VehicleStatus.moving => Icons.play_circle_filled_rounded,
              VehicleStatus.idle => Icons.pause_circle_filled_rounded,
              VehicleStatus.stopped => Icons.pause_circle_filled_rounded,
              VehicleStatus.offline => Icons.cloud_off_rounded,
              VehicleStatus.noData => Icons.sensors_off_rounded,
            };

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
              decoration: BoxDecoration(
                color: statusAccent.withOpacity(0.08),
                borderRadius: Corners.rMd,
                border: Border.all(color: statusAccent.withOpacity(0.25), width: 1),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      statusIcon,
                      size: 18,
                      color: statusAccent,
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
                              titleText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: statusAccent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                vehicle.ignition ? 'Ignition ON' : 'Ignition OFF',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: statusAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$sinceText ${Fmt.time(vehicle.statusChangedAt ?? vehicle.lastPacketAt)} (${Fmt.statusDuration(vehicle.statusChangedAt ?? vehicle.lastPacketAt)})',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: Gap.lg),

        // ── Address + actions ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: Gap.md),
                child: Text(
                  'CURRENT LOCATION',
                  style: AppTypography.eyebrow(theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.place_rounded,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        LiveAddress(
                          vehicle: vehicle,
                          
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        // The lat/long text can be removed as requested.
                      ],
                    ),
                  ),
                ],
              ),
              if (vehicle.hasLocation) ...<Widget>[
                const SizedBox(height: Gap.lg),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openDirections(vehicle),
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: const Text('Directions'),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    if (vehicle.driverPhone != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _call(vehicle.driverPhone!),
                          icon: const Icon(Icons.phone_rounded, size: 18),
                          label: const Text('Call driver'),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: Gap.lg),
        Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.3), height: 1),
        const SizedBox(height: Gap.lg),

        TelemetryGrid(vehicle: vehicle),
      ],
    );
  }

  Future<void> _openDirections(Vehicle v) async {
    final Uri uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${v.latitude},${v.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _call(String phone) async {
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
