import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/route.dart';
import '../../data/models/user_trip.dart';
import '../../data/models/vehicle.dart';
import '../../providers/fleet_provider.dart';
import '../../providers/route_provider.dart';
import '../../providers/trip_provider.dart';

/// Main Trips screen — lists all user-defined trips and shows active trips at top.
class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (mounted) {
        ref.read(tripProvider.notifier).load();
        ref.read(routeProvider.notifier).load();
      }
    });
  }

  Future<void> _openCreate() async {
    final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
    final List<AppRoute> routes = ref.read(routeProvider).routes;

    if (vehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No vehicles found in your fleet.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateTripSheet(vehicles: vehicles, routes: routes),
    );
  }

  Future<void> _endTrip(UserTrip trip) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('End Trip'),
        content: Text('End "${trip.name}"?\nDistance: ${trip.distanceLabel}'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final bool ok = await ref.read(tripProvider.notifier).end(trip.id);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(tripProvider).error ?? 'Failed to end trip')),
        );
      }
    }
  }

  Future<void> _startTrip(UserTrip trip) async {
    final bool ok = await ref.read(tripProvider.notifier).start(trip.id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(tripProvider).error ?? 'Failed to start trip')),
      );
    }
  }

  Future<void> _cancelTrip(UserTrip trip) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Cancel Trip'),
        content: Text('Cancel "${trip.name}"?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Trip'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ref.read(tripProvider.notifier).cancel(trip.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TripState state = ref.watch(tripProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text('Trips', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: <Widget>[
          if (state.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.read(tripProvider.notifier).load(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_trip',
        onPressed: _openCreate,
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('New Trip', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _buildBody(theme, scheme, state),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme scheme, TripState state) {
    if (state.isLoading && state.trips.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.route_rounded, size: 40, color: AppColors.brand),
              ),
              const SizedBox(height: Gap.lg),
              Text('No Trips Yet', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Gap.sm),
              Text(
                'Create a trip to track a journey from start to finish.\nDistance accumulates across multiple days.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.xl),
              FilledButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Create First Trip', style: TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(tripProvider.notifier).load(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 120),
        children: <Widget>[
          // ── Active trips section ────────────────────────────────────
          if (state.activeTrips.isNotEmpty) ...<Widget>[
            _SectionHeader(label: '🟢 In Progress (${state.activeTrips.length})'),
            const SizedBox(height: Gap.xs),
            ...state.activeTrips.map((UserTrip t) => _TripCard(
              trip: t,
              onEnd: () => _endTrip(t),
              onCancel: null,
              onStart: null,
            )),
            const SizedBox(height: Gap.md),
          ],

          // ── Planned trips ───────────────────────────────────────────
          if (state.plannedTrips.isNotEmpty) ...<Widget>[
            _SectionHeader(label: '📋 Planned (${state.plannedTrips.length})'),
            const SizedBox(height: Gap.xs),
            ...state.plannedTrips.map((UserTrip t) => _TripCard(
              trip: t,
              onStart: () => _startTrip(t),
              onEnd: null,
              onCancel: () => _cancelTrip(t),
            )),
            const SizedBox(height: Gap.md),
          ],

          // ── Completed trips ─────────────────────────────────────────
          if (state.completedTrips.isNotEmpty) ...<Widget>[
            _SectionHeader(label: '✅ Completed (${state.completedTrips.length})'),
            const SizedBox(height: Gap.xs),
            ...state.completedTrips.map((UserTrip t) => _TripCard(
              trip: t,
              onEnd: null,
              onStart: null,
              onCancel: null,
            )),
          ],
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.2,
          ),
        ),
      );
}

// ── Trip card ──────────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.onEnd,
    required this.onStart,
    required this.onCancel,
  });

  final UserTrip trip;
  final VoidCallback? onEnd;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isActive = trip.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      shape: RoundedRectangleBorder(borderRadius: Corners.rMd),
      elevation: isActive ? 2 : 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: Corners.rMd,
          border: isActive
              ? Border.all(color: Colors.green.shade300, width: 1.5)
              : Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Row 1: name + status
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      trip.name,
                      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusChip(status: trip.status),
                ],
              ),

              // Row 2: vehicle
              if (trip.vehicleName != null) ...<Widget>[
                const SizedBox(height: 4),
                Row(children: <Widget>[
                  Icon(Icons.directions_car_rounded, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${trip.vehicleName} · ${trip.plate ?? ""}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ],

              // Row 3: origin → destination or route
              if (trip.origin != null && trip.destination != null) ...<Widget>[
                const SizedBox(height: 4),
                Row(children: <Widget>[
                  Icon(Icons.location_on_rounded, size: 13, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(trip.origin!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.arrow_forward_rounded, size: 12),
                  ),
                  Icon(Icons.flag_rounded, size: 13, color: Colors.red.shade600),
                  const SizedBox(width: 4),
                  Expanded(child: Text(trip.destination!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                ]),
              ] else if (trip.routeName != null) ...<Widget>[
                const SizedBox(height: 4),
                Row(children: <Widget>[
                  Icon(Icons.route_rounded, size: 13, color: AppColors.brand),
                  const SizedBox(width: 4),
                  Text(trip.routeName!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.brand, fontWeight: FontWeight.w600)),
                ]),
              ],

              const SizedBox(height: Gap.sm),
              const Divider(height: 1),
              const SizedBox(height: Gap.sm),

              // Row 4: stats row
              Row(
                children: <Widget>[
                  _Stat(icon: Icons.straighten_rounded, value: trip.distanceLabel),
                  const SizedBox(width: Gap.md),
                  _Stat(icon: Icons.timer_rounded, value: trip.durationLabel),
                  if (trip.maxSpeed > 0) ...<Widget>[
                    const SizedBox(width: Gap.md),
                    _Stat(icon: Icons.speed_rounded, value: '${trip.maxSpeed} km/h'),
                  ],
                  if (trip.startTime != null) ...<Widget>[
                    const SizedBox(width: Gap.md),
                    _Stat(
                      icon: Icons.calendar_today_rounded,
                      value: DateFormat('d MMM, HH:mm:ss').format(trip.startTime!),
                    ),
                  ],
                  const Spacer(),
                  // Action buttons
                  if (onStart != null)
                    _ActionButton(label: 'Start', icon: Icons.play_arrow_rounded, color: Colors.green, onTap: onStart!),
                  if (onEnd != null)
                    _ActionButton(label: 'End', icon: Icons.stop_rounded, color: Colors.red, onTap: onEnd!),
                  if (onCancel != null) ...<Widget>[
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      color: scheme.onSurfaceVariant,
                      onPressed: onCancel,
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerHighest,
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Icon(icon, size: 13, color: scheme.onSurfaceVariant),
      const SizedBox(width: 3),
      Text(value, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
    ]);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg, text;
    String label;
    switch (status) {
      case 'in_progress':
        bg = Colors.green.shade50; text = Colors.green.shade700; label = 'In Progress';
      case 'planned':
        bg = Colors.blue.shade50; text = Colors.blue.shade700; label = 'Planned';
      case 'cancelled':
        bg = Colors.red.shade50; text = Colors.red.shade700; label = 'Cancelled';
      default:
        bg = Colors.grey.shade100; text = Colors.grey.shade600; label = 'Completed';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: Corners.rPill),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: text)),
    );
  }
}

// ── Create Trip Bottom Sheet ───────────────────────────────────────────────────

class CreateTripSheet extends ConsumerStatefulWidget {
  const CreateTripSheet({
    required this.vehicles,
    required this.routes,
    this.initialVehicleId,
    this.initialRouteId,
    super.key,
  });

  final List<Vehicle> vehicles;
  final List<AppRoute> routes;
  final String? initialVehicleId;
  final String? initialRouteId;

  @override
  ConsumerState<CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends ConsumerState<CreateTripSheet> {
  final TextEditingController _nameCtrl   = TextEditingController();
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl   = TextEditingController();
  final TextEditingController _notesCtrl  = TextEditingController();

  late String _vehicleId;
  String? _routeId;
  bool _startNow = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialVehicleId != null &&
        widget.vehicles.any((Vehicle v) => v.id == widget.initialVehicleId)) {
      _vehicleId = widget.initialVehicleId!;
    } else {
      _vehicleId = widget.vehicles.first.id;
    }

    if (widget.initialRouteId != null &&
        widget.routes.any((AppRoute r) => r.id == widget.initialRouteId)) {
      _routeId = widget.initialRouteId;
      final AppRoute? rt =
          widget.routes.where((AppRoute r) => r.id == _routeId).firstOrNull;
      if (rt != null) {
        _nameCtrl.text = '${rt.name} Trip';
      }
    } else {
      final AppRoute? assigned = widget.routes
          .where((AppRoute r) => r.vehicleIds.contains(_vehicleId))
          .firstOrNull;
      if (assigned != null) {
        _routeId = assigned.id;
        _nameCtrl.text = '${assigned.name} Trip';
      }
    }
  }

  void _onVehicleChanged(String vId) {
    setState(() {
      _vehicleId = vId;
      final AppRoute? assigned = widget.routes
          .where((AppRoute r) => r.vehicleIds.contains(vId))
          .firstOrNull;
      if (assigned != null) {
        _routeId = assigned.id;
        if (_nameCtrl.text.isEmpty || _nameCtrl.text.endsWith('Trip')) {
          _nameCtrl.text = '${assigned.name} Trip';
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a trip name.');
      return;
    }
    setState(() { _saving = true; _error = null; });

    final Vehicle? veh =
        widget.vehicles.where((Vehicle v) => v.id == _vehicleId).firstOrNull;
    final AppRoute? rt =
        widget.routes.where((AppRoute r) => r.id == _routeId).firstOrNull;

    final UserTrip draft = UserTrip(
      id: '',
      vehicleId: _vehicleId,
      name: name,
      status: _startNow ? 'in_progress' : 'planned',
      routeId: _routeId,
      routeName: rt?.name,
      vehicleName: veh?.displayName,
      plate: veh?.registrationNumber ?? veh?.displayName,
      origin: _originCtrl.text.trim().isEmpty ? null : _originCtrl.text.trim(),
      destination: _destCtrl.text.trim().isEmpty ? null : _destCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      startTime: _startNow ? DateTime.now() : null,
      distanceKm: rt?.approxLengthKm ?? 0.0,
      createdAt: DateTime.now(),
    );

    final UserTrip? created = await ref.read(tripProvider.notifier).create(draft, startNow: _startNow);

    setState(() => _saving = false);

    if (created != null && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_startNow ? 'Trip started! Tracking distance...' : 'Trip saved.'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      setState(() => _error = ref.read(tripProvider).error ?? 'Failed to save trip.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (BuildContext ctx, ScrollController sc) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: <Widget>[
            // Handle
            const SizedBox(height: Gap.sm),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: Corners.rPill)),
            const SizedBox(height: Gap.sm),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.md, Gap.sm),
              child: Row(children: <Widget>[
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('New Trip', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text('Track a journey across any number of days', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ])),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: ListView(
                controller: sc,
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xl),
                children: <Widget>[
                  if (_error != null) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.all(Gap.sm),
                      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: Corners.rSm),
                      child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
                    ),
                    const SizedBox(height: Gap.sm),
                  ],

                  _label('Vehicle *'),
                  DropdownButtonFormField<String>(
                    value: _vehicleId,
                    decoration: _inputDecoration(),
                    onChanged: (String? v) {
                      if (v != null) _onVehicleChanged(v);
                    },
                    items: widget.vehicles.map((Vehicle v) =>
                      DropdownMenuItem<String>(value: v.id, child: Text(v.displayName))).toList(),
                  ),
                  () {
                    final AppRoute? assigned = widget.routes
                        .where((AppRoute r) => r.vehicleIds.contains(_vehicleId))
                        .firstOrNull;
                    if (assigned != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(
                              'Assigned Route: ${assigned.name}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }(),
                  const SizedBox(height: Gap.md),

                  _label('Trip Name *'),
                  TextField(controller: _nameCtrl, decoration: _inputDecoration(hint: 'e.g. Hyderabad → Vijayawada')),
                  const SizedBox(height: Gap.md),

                  Row(children: <Widget>[
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      _label('From (Origin)'),
                      TextField(controller: _originCtrl, decoration: _inputDecoration(hint: 'Hyderabad')),
                    ])),
                    const SizedBox(width: Gap.md),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      _label('To (Destination)'),
                      TextField(controller: _destCtrl, decoration: _inputDecoration(hint: 'Vijayawada')),
                    ])),
                  ]),
                  const SizedBox(height: Gap.md),

                  _label('Route (Optional)'),
                  DropdownButtonFormField<String?>(
                    value: _routeId,
                    decoration: _inputDecoration(),
                    onChanged: (String? v) => setState(() => _routeId = v),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('No route — track distance only')),
                      ...widget.routes.map((AppRoute r) =>
                        DropdownMenuItem<String?>(value: r.id, child: Text(r.name))),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      'Link to a pre-drawn route to enable deviation alerts.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: Gap.md),

                  _label('Notes'),
                  TextField(controller: _notesCtrl, maxLines: 2, decoration: _inputDecoration(hint: 'Optional notes...')),
                  const SizedBox(height: Gap.lg),

                  // Start Now toggle
                  GestureDetector(
                    onTap: () => setState(() => _startNow = !_startNow),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(Gap.md),
                      decoration: BoxDecoration(
                        color: _startNow ? Colors.green.shade50 : scheme.surfaceContainerHighest,
                        borderRadius: Corners.rMd,
                        border: Border.all(color: _startNow ? Colors.green.shade300 : scheme.outlineVariant),
                      ),
                      child: Row(children: <Widget>[
                        Switch(value: _startNow, onChanged: (bool v) => setState(() => _startNow = v), activeColor: Colors.green),
                        const SizedBox(width: Gap.sm),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text('Start trip immediately', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: _startNow ? Colors.green.shade700 : null)),
                          Text('Distance accumulation begins right now.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ])),
                      ]),
                    ),
                  ),
                  const SizedBox(height: Gap.xl),

                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_startNow ? Icons.play_arrow_rounded : Icons.save_rounded),
                    label: Text(_startNow ? 'Save & Start Trip' : 'Save for Later',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _startNow ? Colors.green : AppColors.brand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size.fromHeight(50),
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
      );

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: Corners.rMd),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      );
}
