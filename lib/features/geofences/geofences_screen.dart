import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/geofence.dart';
import '../../data/models/vehicle.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import '../../shared/map/app_map.dart';
import '../../shared/map/app_map_controller.dart';
import '../../shared/map/app_map_models.dart';
import '../../shared/widgets/app_states.dart';
import '../live_map/widgets/map_tiles.dart';
import 'geofence_editor_sheet.dart';

class GeofencesScreen extends ConsumerStatefulWidget {
  const GeofencesScreen({this.vehicleId, super.key});

  final String? vehicleId;

  @override
  ConsumerState<GeofencesScreen> createState() => _GeofencesScreenState();
}

class _GeofencesScreenState extends ConsumerState<GeofencesScreen> {
  List<Geofence> _fences = <Geofence>[];
  bool _loading = true;
  String? _error;
  AppMapController? _mapController;
  String? _focusedFenceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<Geofence> data = await ref
          .read(geofenceRepositoryProvider)
          .getGeofences(vehicleId: widget.vehicleId);
      if (!mounted) return;
      setState(() {
        _fences = data;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitFences());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _fitFences() {
    if (_mapController == null) return;
    final List<LatLng> points = <LatLng>[];
    for (final Geofence g in _fences) {
      if (g.center != null) points.add(g.center!);
      if (g.shape == GeofenceShape.polygon) {
        points.addAll(g.points);
      }
    }
    if (points.isNotEmpty) {
      if (points.length == 1) {
        _mapController!.move(points.first, 14.5);
      } else {
        _mapController!.fitBounds(points, padding: 60.0);
      }
    }
  }

  LatLng _getInitialCenter(Vehicle? vehicle) {
    final valid = _fences.where((Geofence g) => g.center != null).toList();
    if (valid.isNotEmpty) {
      double latSum = 0;
      double lngSum = 0;
      for (final Geofence g in valid) {
        latSum += g.center!.latitude;
        lngSum += g.center!.longitude;
      }
      return LatLng(latSum / valid.length, lngSum / valid.length);
    }
    if (vehicle != null && vehicle.hasLocation) {
      return LatLng(vehicle.latitude!, vehicle.longitude!);
    }
    return const LatLng(17.385, 78.4867);
  }

  double _getInitialZoom() {
    if (_fences.isEmpty) return 14.0;
    if (_fences.length == 1) {
      return _zoomFor(_fences.first);
    }
    final valid = _fences
        .where((Geofence g) => g.center != null)
        .map((Geofence g) => g.center!)
        .toList();
    if (valid.length < 2) return 14.0;
    double minLat = valid.first.latitude;
    double maxLat = valid.first.latitude;
    double minLng = valid.first.longitude;
    double maxLng = valid.first.longitude;
    for (final LatLng p in valid) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final double latDiff = maxLat - minLat;
    final double lngDiff = maxLng - minLng;
    final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    if (maxDiff > 1.0) return 8.0;
    if (maxDiff > 0.5) return 9.5;
    if (maxDiff > 0.2) return 11.0;
    if (maxDiff > 0.08) return 12.0;
    if (maxDiff > 0.03) return 13.0;
    if (maxDiff > 0.01) return 14.0;
    return 15.0;
  }

  Future<void> _create() async {
    final Vehicle? vehicle = widget.vehicleId != null
        ? ref.read(vehicleByIdProvider(widget.vehicleId!))
        : null;
    final LatLng? initialLoc = vehicle != null && vehicle.hasLocation
        ? LatLng(vehicle.latitude!, vehicle.longitude!)
        : null;

    final bool? created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext ctx) => GeofenceEditorSheet(
        initialLocation: initialLoc,
        initialVehicleId: widget.vehicleId,
        initialName: vehicle != null ? '${vehicle.name} Geofence' : null,
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _delete(Geofence fence) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete geofence?'),
        content: Text(
          '"${fence.name}" will be removed and you will stop receiving '
          'entry and exit alerts for it.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref.read(geofenceRepositoryProvider).delete(
        fence.id,
        vehicleId: widget.vehicleId,
      );
      if (!mounted) return;
      setState(() => _fences.removeWhere((Geofence g) => g.id == fence.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${fence.name}" deleted')),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitFences());
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggle(Geofence fence, bool active) async {
    setState(() {
      final int i = _fences.indexWhere((Geofence g) => g.id == fence.id);
      if (i != -1) _fences[i] = fence.copyWith(isActive: active);
    });

    try {
      await ref.read(geofenceRepositoryProvider).update(
        fence.id,
        <String, dynamic>{'isActive': active},
        vehicleId: widget.vehicleId,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // Roll back the optimistic update.
      setState(() {
        final int i = _fences.indexWhere((Geofence g) => g.id == fence.id);
        if (i != -1) _fences[i] = fence;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Vehicle? vehicle = widget.vehicleId != null
        ? ref.watch(vehicleByIdProvider(widget.vehicleId!))
        : null;

    final LatLng initialCenter = _getInitialCenter(vehicle);
    final double initialZoom = _getInitialZoom();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Geofences'),
            if (vehicle != null)
              Text(
                vehicle.displayName.toUpperCase(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: Gap.xs),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('New geofence'),
      ),
      body: _loading
          ? const ListSkeleton(count: 4)
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _fences.isEmpty
                  ? EmptyState(
                      icon: Icons.fence_rounded,
                      title: 'No geofences yet',
                      message: 'Draw a zone around a depot, customer site or '
                          'restricted area and get alerted whenever a vehicle '
                          'enters or leaves it.',
                      actionLabel: 'Create your first geofence',
                      onAction: _create,
                    )
                  : Column(
                      children: [
                        // ── ONE Unified Map at the Top ──
                        SizedBox(
                          height: 290,
                          width: double.infinity,
                          child: Stack(
                            children: [
                              AppMap(
                                mapType: MapStyleX.fromKey(
                                  ref.read(secureStoreProvider).mapType,
                                ).name,
                                apiKey: ref.read(authProvider).user?.apiKey,
                                initialCenter: initialCenter,
                                initialZoom: initialZoom,
                                onMapCreated: (AppMapController ctrl) {
                                  _mapController = ctrl;
                                  _fitFences();
                                },
                                circles: [
                                  for (final Geofence g in _fences)
                                    if (g.shape == GeofenceShape.circle &&
                                        g.center != null)
                                      AppCircle(
                                        id: 'circle_${g.id}',
                                        center: g.center!,
                                        radiusMeters: g.radiusMeters,
                                        fillColor: _parseColor(g.colorHex)
                                            .withValues(
                                                alpha: g.isActive
                                                    ? (g.id == _focusedFenceId
                                                        ? 0.32
                                                        : 0.18)
                                                    : 0.06),
                                        strokeColor: g.isActive
                                            ? _parseColor(g.colorHex)
                                            : _parseColor(g.colorHex)
                                                .withValues(alpha: 0.35),
                                        strokeWidth:
                                            g.id == _focusedFenceId ? 3 : 2,
                                      ),
                                ],
                                polygons: [
                                  for (final Geofence g in _fences)
                                    if (g.shape == GeofenceShape.polygon &&
                                        g.points.isNotEmpty)
                                      AppPolygon(
                                        id: 'poly_${g.id}',
                                        points: g.points,
                                        fillColor: _parseColor(g.colorHex)
                                            .withValues(
                                                alpha: g.isActive
                                                    ? (g.id == _focusedFenceId
                                                        ? 0.32
                                                        : 0.18)
                                                    : 0.06),
                                        strokeColor: g.isActive
                                            ? _parseColor(g.colorHex)
                                            : _parseColor(g.colorHex)
                                                .withValues(alpha: 0.35),
                                        strokeWidth:
                                            g.id == _focusedFenceId ? 3 : 2,
                                      ),
                                ],
                                markers: [
                                  // ONLY the geofences that the user added (no extra vehicle pins)
                                  for (final Geofence g in _fences)
                                    if (g.center != null)
                                      AppMarker(
                                        id: 'pin_${g.id}',
                                        position: g.center!,
                                        hue: HSVColor.fromColor(_parseColor(g.colorHex)).hue,
                                        width: 130,
                                        height: 44,
                                        widget: GestureDetector(
                                          onTap: () {
                                            setState(() =>
                                                _focusedFenceId = g.id);
                                            _mapController?.move(
                                              g.center!,
                                              _zoomFor(g),
                                            );
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      _parseColor(g.colorHex),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border:
                                                      g.id == _focusedFenceId
                                                          ? Border.all(
                                                              color:
                                                                  Colors.white,
                                                              width: 2,
                                                            )
                                                          : null,
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Colors.black26,
                                                      blurRadius: 4,
                                                      offset: Offset(0, 1),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  g.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.arrow_drop_down,
                                                color: _parseColor(g.colorHex),
                                                size: 14,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                ],
                              ),

                              // Quick fit bounds button
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Material(
                                  color:
                                      Theme.of(context).colorScheme.surface,
                                  shape: const CircleBorder(),
                                  elevation: 3,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _fitFences,
                                    child: const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Icon(
                                        Icons.crop_free_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Section header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Gap.lg, Gap.md, Gap.lg, Gap.xs),
                          child: Row(
                            children: [
                              Text(
                                'ASSIGNED GEOFENCES (${_fences.length})',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      letterSpacing: 0.8,
                                    ),
                              ),
                            ],
                          ),
                        ),

                        // ── List of added geofences below without mini-maps ──
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  Gap.lg, Gap.xs, Gap.lg, 96),
                              itemCount: _fences.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: Gap.md),
                              itemBuilder: (BuildContext context, int i) =>
                                  _GeofenceListItem(
                                fence: _fences[i],
                                isSelected: _fences[i].id == _focusedFenceId,
                                onTap: () {
                                  setState(
                                      () => _focusedFenceId = _fences[i].id);
                                  if (_fences[i].center != null) {
                                    _mapController?.move(
                                      _fences[i].center!,
                                      _zoomFor(_fences[i]),
                                    );
                                  }
                                },
                                onDelete: () => _delete(_fences[i]),
                                onToggle: (bool active) =>
                                    _toggle(_fences[i], active),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  static double _zoomFor(Geofence f) {
    if (f.shape == GeofenceShape.polygon) {
      if (f.points.isEmpty) return 14;
      double minLat = f.points.first.latitude;
      double maxLat = f.points.first.latitude;
      double minLng = f.points.first.longitude;
      double maxLng = f.points.first.longitude;
      for (final LatLng p in f.points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final double latDiff = maxLat - minLat;
      final double lngDiff = maxLng - minLng;
      final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
      if (maxDiff > 0.1) return 11.5;
      if (maxDiff > 0.04) return 13.0;
      if (maxDiff > 0.015) return 14.0;
      if (maxDiff > 0.005) return 15.0;
      return 16.0;
    }
    final double r = f.radiusMeters;
    if (r <= 200) return 15.5;
    if (r <= 500) return 14.5;
    if (r <= 1500) return 13;
    return 11.5;
  }

  static Color _parseColor(String hex) {
    try {
      final String clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return AppColors.brand;
    }
  }
}

class _GeofenceListItem extends ConsumerWidget {
  const _GeofenceListItem({
    required this.fence,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onToggle,
  });

  final Geofence fence;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Color color = _GeofencesScreenState._parseColor(fence.colorHex);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corners.lg),
      child: Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(Corners.lg),
          border: Border.all(
            color: isSelected
                ? color
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    fence.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: fence.isActive,
                  onChanged: onToggle,
                ),
              ],
            ),
            if (fence.description != null &&
                fence.description!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(fence.description!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: <Widget>[
                _tag(
                  theme,
                  fence.shape == GeofenceShape.circle
                      ? Icons.circle_outlined
                      : Icons.hexagon_outlined,
                  fence.shape == GeofenceShape.circle
                      ? '${fence.radiusMeters.round()} m radius'
                      : '${fence.points.length} points',
                ),
                _tag(
                  theme,
                  Icons.crop_free_rounded,
                  '${fence.areaKm2.toStringAsFixed(2)} km²',
                ),
                if (fence.alertOnEnter)
                  _tag(theme, Icons.login_rounded, 'Entry alert'),
                if (fence.alertOnExit)
                  _tag(theme, Icons.logout_rounded, 'Exit alert'),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: <Widget>[
                Text(
                  'Created ${Fmt.relative(fence.createdAt)}',
                  style:
                      theme.textTheme.labelSmall?.copyWith(letterSpacing: 0),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger),
                  icon:
                      const Icon(Icons.delete_outline_rounded, size: 17),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(ThemeData theme, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: Corners.rXs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      );
}
