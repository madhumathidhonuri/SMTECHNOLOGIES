import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/geofence.dart';
import '../../../data/models/report_models.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/fleet_provider.dart';

enum DatePreset { today, yesterday, last7days, last30days, custom }

class ReportFilterBar extends ConsumerWidget {
  const ReportFilterBar({
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.onDateRangeChanged,
    required this.vehicleId,
    required this.onVehicleChanged,
    required this.onGenerate,
    required this.isLoading,
    this.requiresVehicle = false,
    this.onTypeChanged,
    this.transitMode,
    this.onTransitModeChanged,
    this.fromGeofenceId,
    this.onFromGeofenceChanged,
    this.toGeofenceId,
    this.onToGeofenceChanged,
    this.singleGeofenceId,
    this.onSingleGeofenceChanged,
    this.geofences = const <Geofence>[],
    super.key,
  });

  final ReportType type;
  final DateTime startDate;
  final DateTime endDate;
  final void Function(DateTime start, DateTime end) onDateRangeChanged;
  final String? vehicleId;
  final ValueChanged<String?> onVehicleChanged;
  final VoidCallback onGenerate;
  final bool isLoading;
  final bool requiresVehicle;
  final ValueChanged<ReportType>? onTypeChanged;
  final String? transitMode;
  final ValueChanged<String>? onTransitModeChanged;
  final String? fromGeofenceId;
  final ValueChanged<String?>? onFromGeofenceChanged;
  final String? toGeofenceId;
  final ValueChanged<String?>? onToGeofenceChanged;
  final String? singleGeofenceId;
  final ValueChanged<String?>? onSingleGeofenceChanged;
  final List<Geofence> geofences;

  LinearGradient _getGradient(ReportType type) {
    switch (type) {
      case ReportType.trip:
        return const LinearGradient(
          colors: <Color>[Color(0xFFA855F7), Color(0xFF9333EA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.distance:
        return const LinearGradient(
          colors: <Color>[Color(0xFF0EA5E9), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.overspeeding:
        return const LinearGradient(
          colors: <Color>[Color(0xFFF43F5E), Color(0xFFE11D48)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.stoppages:
        return const LinearGradient(
          colors: <Color>[Color(0xFFF97316), Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.idle:
        return const LinearGradient(
          colors: <Color>[Color(0xFFF59E0B), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.consolidated:
        return const LinearGradient(
          colors: <Color>[Color(0xFF22C55E), Color(0xFF16A34A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.fuelConsolidated:
        return const LinearGradient(
          colors: <Color>[Color(0xFFFB923C), Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.geofenceTransit:
        return const LinearGradient(
          colors: <Color>[Color(0xFF14B8A6), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.geofenceSinglePlace:
        return const LinearGradient(
          colors: <Color>[Color(0xFF818CF8), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.dailyTrip:
        return const LinearGradient(
          colors: <Color>[Color(0xFF34D399), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.ignition:
        return const LinearGradient(
          colors: <Color>[Color(0xFFFBBF24), Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ReportType.individual:
      default:
        return const LinearGradient(
          colors: <Color>[Color(0xFF3B82F6), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  Color _getAccentColor(ReportType type) {
    switch (type) {
      case ReportType.trip:
        return const Color(0xFF9333EA);
      case ReportType.distance:
        return const Color(0xFF0284C7);
      case ReportType.overspeeding:
        return const Color(0xFFE11D48);
      case ReportType.stoppages:
        return const Color(0xFFEA580C);
      case ReportType.idle:
        return const Color(0xFFD97706);
      case ReportType.consolidated:
        return const Color(0xFF16A34A);
      case ReportType.fuelConsolidated:
        return const Color(0xFFEA580C);
      case ReportType.geofenceTransit:
        return const Color(0xFF0D9488);
      case ReportType.geofenceSinglePlace:
        return const Color(0xFF6366F1);
      case ReportType.dailyTrip:
        return const Color(0xFF10B981);
      case ReportType.ignition:
        return const Color(0xFFD97706);
      case ReportType.individual:
      default:
        return const Color(0xFF2563EB);
    }
  }

  DatePreset _detectPreset(DateTime s, DateTime e) {
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);

    if (s.year == todayStart.year && s.month == todayStart.month && s.day == todayStart.day) {
      return DatePreset.today;
    }

    final DateTime yStart = todayStart.subtract(const Duration(days: 1));
    if (s.year == yStart.year && s.month == yStart.month && s.day == yStart.day) {
      return DatePreset.yesterday;
    }

    final DateTime s7 = todayStart.subtract(const Duration(days: 7));
    if (s.year == s7.year && s.month == s7.month && s.day == s7.day) {
      return DatePreset.last7days;
    }

    final DateTime s30 = todayStart.subtract(const Duration(days: 30));
    if (s.year == s30.year && s.month == s30.month && s.day == s30.day) {
      return DatePreset.last30days;
    }

    return DatePreset.custom;
  }

  void _applyPreset(DatePreset preset, BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final DateTime todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (preset) {
      case DatePreset.today:
        onDateRangeChanged(todayStart, todayEnd);
        break;
      case DatePreset.yesterday:
        final DateTime yStart = todayStart.subtract(const Duration(days: 1));
        final DateTime yEnd = DateTime(yStart.year, yStart.month, yStart.day, 23, 59, 59);
        onDateRangeChanged(yStart, yEnd);
        break;
      case DatePreset.last7days:
        final DateTime s7 = todayStart.subtract(const Duration(days: 7));
        onDateRangeChanged(s7, todayEnd);
        break;
      case DatePreset.last30days:
        final DateTime s30 = todayStart.subtract(const Duration(days: 30));
        onDateRangeChanged(s30, todayEnd);
        break;
      case DatePreset.custom:
        _pickDateOrTime(context);
        break;
    }
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final Color activeColor = _getAccentColor(type);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeColor : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFFE2E8F0),
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: activeColor.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 12, color: selected ? Colors.white : const Color(0xFF64748B)),
              const SizedBox(width: 4),
            ] else if (selected) ...<Widget>[
              const Icon(Icons.check_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vehicle> vehicles = ref.watch(fleetProvider).vehicles;
    final bool isTrip = type == ReportType.trip || type == ReportType.manualTrip;
    final String dateText = isTrip
        ? '${Fmt.dateTimeFilter(startDate)}   →   ${Fmt.dateTimeFilter(endDate)}'
        : '${Fmt.dateWeb(startDate)}   →   ${Fmt.dateWeb(endDate)}';

    final DatePreset preset = _detectPreset(startDate, endDate);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC7D7EC).withOpacity(0.55),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Geofence Transit Mode Selector (All | One-Way | Two-Way | Round Trip)
          if (type == ReportType.geofenceTransit) ...<Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.sync_alt_rounded, size: 14, color: Color(0xFF0D9488)),
                    SizedBox(width: 6),
                    Text(
                      'CORRIDOR TRANSIT MODE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: <Widget>[
                      _buildChip(
                        context: context,
                        label: 'All Trips',
                        selected: (transitMode ?? 'all') == 'all',
                        onTap: () => onTransitModeChanged?.call('all'),
                      ),
                      const SizedBox(width: 8),
                      _buildChip(
                        context: context,
                        label: 'One-Way (A ➔ B)',
                        selected: transitMode == 'single_way',
                        onTap: () => onTransitModeChanged?.call('single_way'),
                      ),
                      const SizedBox(width: 8),
                      _buildChip(
                        context: context,
                        label: 'Two-Way (A ⇄ B)',
                        selected: transitMode == 'two_way',
                        onTap: () => onTransitModeChanged?.call('two_way'),
                      ),
                      const SizedBox(width: 8),
                      _buildChip(
                        context: context,
                        label: 'Round Trip (A ➔ A)',
                        selected: transitMode == 'same_location',
                        onTap: () => onTransitModeChanged?.call('same_location'),
                      ),
                    ],
                  ),
                ),
                if (geofences.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      // From Geofence
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'ORIGIN (FROM)',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  value: fromGeofenceId,
                                  hint: const Text('All Places', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                  items: <DropdownMenuItem<String?>>[
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All Places', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                    ...geofences.map((g) => DropdownMenuItem<String?>(
                                      value: g.id,
                                      child: Text(g.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                    )),
                                  ],
                                  onChanged: onFromGeofenceChanged,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // To Geofence
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'DESTINATION (TO)',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  value: toGeofenceId,
                                  hint: const Text('All Places', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                  items: <DropdownMenuItem<String?>>[
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All Places', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                    ...geofences.map((g) => DropdownMenuItem<String?>(
                                      value: g.id,
                                      child: Text(g.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                    )),
                                  ],
                                  onChanged: onToGeofenceChanged,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
              ],
            ),
          ],

          // Single Place Activity Selector
          if (type == ReportType.geofenceSinglePlace && geofences.isNotEmpty) ...<Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.fmd_good_rounded, size: 14, color: Color(0xFF6366F1)),
                    SizedBox(width: 6),
                    Text(
                      'SELECT GEOFENCE / PLACE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: singleGeofenceId,
                      hint: const Text('All Geofences & Places', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Geofences & Places', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        ...geofences.map((g) => DropdownMenuItem<String?>(
                          value: g.id,
                          child: Text(g.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: onSingleGeofenceChanged,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ],
          if (isTrip && onTypeChanged != null) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: GestureDetector(
                    onTap: () => onTypeChanged!(ReportType.trip),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: type == ReportType.trip
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFF8FAFC),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                        border: Border.all(
                          color: type == ReportType.trip
                              ? const Color(0xFF6366F1)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.electric_bolt_rounded,
                            size: 14,
                            color: type == ReportType.trip
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Automated',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: type == ReportType.trip
                                    ? Colors.white
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onTypeChanged!(ReportType.manualTrip),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: type == ReportType.manualTrip
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFF8FAFC),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                        border: Border.all(
                          color: type == ReportType.manualTrip
                              ? const Color(0xFF6366F1)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.edit_road_rounded,
                            size: 14,
                            color: type == ReportType.manualTrip
                                ? Colors.white
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Manual',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: type == ReportType.manualTrip
                                    ? Colors.white
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Inline Vehicle Picker
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    'VEHICLE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  InkWell(
                    onTap: () => _showVehiclePickerModal(context, vehicles),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.search_rounded, size: 14, color: Color(0xFF2563EB)),
                          SizedBox(width: 4),
                          Text(
                            'Search & Select',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (!requiresVehicle)
                    _buildChip(
                      context: context,
                      label: 'All Vehicles',
                      selected: vehicleId == null,
                      onTap: () => onVehicleChanged(null),
                    ),
                  ...() {
                    if (vehicles.length <= 6) {
                      return vehicles.map((Vehicle v) => _buildChip(
                            context: context,
                            label: v.displayName,
                            selected: vehicleId == v.id,
                            onTap: () => onVehicleChanged(v.id),
                          ));
                    }
                    final List<Vehicle> initial = vehicles.take(5).toList();
                    final Vehicle? selectedV = vehicleId != null
                        ? vehicles.where((v) => v.id == vehicleId).firstOrNull
                        : null;
                    final bool selectedInInitial = selectedV != null && initial.any((v) => v.id == selectedV.id);

                    return <Widget>[
                      ...initial.map((Vehicle v) => _buildChip(
                            context: context,
                            label: v.displayName,
                            selected: vehicleId == v.id,
                            onTap: () => onVehicleChanged(v.id),
                          )),
                      if (selectedV != null && !selectedInInitial)
                        _buildChip(
                          context: context,
                          label: selectedV.displayName,
                          selected: true,
                          onTap: () => onVehicleChanged(selectedV.id),
                        ),
                      _buildChip(
                        context: context,
                        label: '+ Search / More (${vehicles.length})',
                        selected: false,
                        icon: Icons.search_rounded,
                        onTap: () => _showVehiclePickerModal(context, vehicles),
                      ),
                    ];
                  }(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Inline Date Preset Picker
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'DATE FILTER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _buildChip(
                    context: context,
                    label: 'Today',
                    selected: preset == DatePreset.today,
                    onTap: () => _applyPreset(DatePreset.today, context),
                  ),
                  _buildChip(
                    context: context,
                    label: 'Yesterday',
                    selected: preset == DatePreset.yesterday,
                    onTap: () => _applyPreset(DatePreset.yesterday, context),
                  ),
                  _buildChip(
                    context: context,
                    label: 'Last 7 Days',
                    selected: preset == DatePreset.last7days,
                    onTap: () => _applyPreset(DatePreset.last7days, context),
                  ),
                  _buildChip(
                    context: context,
                    label: 'Last 30 Days',
                    selected: preset == DatePreset.last30days,
                    onTap: () => _applyPreset(DatePreset.last30days, context),
                  ),
                  _buildChip(
                    context: context,
                    label: preset == DatePreset.custom ? 'Custom' : 'Custom Range...',
                    selected: preset == DatePreset.custom,
                    onTap: () => _applyPreset(DatePreset.custom, context),
                    icon: Icons.edit_calendar_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Active: $dateText',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Generate Button with Web Gradient
          SizedBox(
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: _getGradient(type),
                borderRadius: BorderRadius.circular(8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _getAccentColor(type).withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isLoading ? null : onGenerate,
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text(
                                'Generate Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _showVehiclePickerModal(
    BuildContext context,
    List<Vehicle> vehicles,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (BuildContext ctx) => _VehiclePickerSheet(
        vehicles: vehicles,
        selectedId: vehicleId,
        allowAll: !requiresVehicle,
        onSelect: (String? id) {
          Navigator.pop(ctx);
          onVehicleChanged(id);
        },
      ),
    );
  }

  Future<void> _pickDateOrTime(BuildContext context) async {
    if (type == ReportType.trip) {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (BuildContext ctx) => _DateTimeRangePickerSheet(
          initialStart: startDate,
          initialEnd: endDate,
          onApply: (DateTime start, DateTime end) {
            Navigator.of(ctx, rootNavigator: true).pop();
            onDateRangeChanged(start, end);
          },
        ),
      );
    } else {
      final DateTime now = DateTime.now();
      final DateTime minDate = DateTime(now.year - 3, 1, 1);
      final DateTime maxDate = DateTime(now.year + 1, 12, 31);
      final DateTime initialStart = startDate.isBefore(minDate)
          ? minDate
          : (startDate.isAfter(maxDate) ? maxDate : startDate);
      final DateTime initialEnd = endDate.isBefore(minDate)
          ? minDate
          : (endDate.isAfter(maxDate) ? maxDate : endDate);

      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: minDate,
        lastDate: maxDate,
        initialDateRange: DateTimeRange(
          start: initialStart.isAfter(initialEnd) ? initialEnd : initialStart,
          end: initialEnd,
        ),
        helpText: 'Select Report Date Range',
        saveText: 'Apply',
      );
      if (picked != null) {
        final DateTime s = DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0);
        final DateTime e = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        onDateRangeChanged(s, e);
      }
    }
  }
}

class _VehiclePickerSheet extends StatefulWidget {
  const _VehiclePickerSheet({
    required this.vehicles,
    required this.selectedId,
    required this.allowAll,
    required this.onSelect,
  });

  final List<Vehicle> vehicles;
  final String? selectedId;
  final bool allowAll;
  final ValueChanged<String?> onSelect;

  @override
  State<_VehiclePickerSheet> createState() => _VehiclePickerSheetState();
}

class _VehiclePickerSheetState extends State<_VehiclePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final List<Vehicle> filtered = widget.vehicles
        .where((Vehicle v) =>
            _query.isEmpty ||
            v.displayName.toLowerCase().contains(_query.toLowerCase()) ||
            v.registrationNumber.toLowerCase().contains(_query.toLowerCase()) ||
            v.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Text(
                      'Select Vehicle',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const Spacer(),
                    Text(
                      '${filtered.length} vehicles',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by vehicle name or plate...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: filtered.length + (widget.allowAll ? 1 : 0),
              itemBuilder: (BuildContext context, int i) {
                if (widget.allowAll && i == 0) {
                  final bool isSelected = widget.selectedId == null;
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.apps_rounded,
                        color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        size: 20,
                      ),
                    ),
                    title: const Text('All Vehicles', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    subtitle: const Text('Generate combined report for all fleet', style: TextStyle(fontSize: 12)),
                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB)) : null,
                    onTap: () => widget.onSelect(null),
                  );
                }

                final Vehicle v = filtered[i - (widget.allowAll ? 1 : 0)];
                final bool isSelected = widget.selectedId == v.id;

                return ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Text(
                      v.displayName.characters.take(2).toString().toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2563EB), fontSize: 12),
                    ),
                  ),
                  title: Text(
                    v.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                  subtitle: Text(
                    v.registrationNumber.isNotEmpty ? v.registrationNumber : 'No plate registered',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB)) : null,
                  onTap: () => widget.onSelect(v.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeRangePickerSheet extends StatefulWidget {
  const _DateTimeRangePickerSheet({
    required this.initialStart,
    required this.initialEnd,
    required this.onApply,
  });

  final DateTime initialStart;
  final DateTime initialEnd;
  final void Function(DateTime start, DateTime end) onApply;

  @override
  State<_DateTimeRangePickerSheet> createState() => _DateTimeRangePickerSheetState();
}

class _DateTimeRangePickerSheetState extends State<_DateTimeRangePickerSheet> {
  late DateTime _start;
  late DateTime _end;
  int? _selectedPresetDays;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _selectedPresetDays = _detectPreset(_start, _end);
  }

  int? _detectPreset(DateTime s, DateTime e) {
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final DateTime todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // Check Today:
    if (s.year == todayStart.year &&
        s.month == todayStart.month &&
        s.day == todayStart.day &&
        e.year == todayEnd.year &&
        e.month == todayEnd.month &&
        e.day == todayEnd.day) {
      return 0;
    }

    // Check Yesterday:
    final DateTime yStart = todayStart.subtract(const Duration(days: 1));
    final DateTime yEnd = DateTime(yStart.year, yStart.month, yStart.day, 23, 59, 59);
    if (s.year == yStart.year &&
        s.month == yStart.month &&
        s.day == yStart.day &&
        e.year == yEnd.year &&
        e.month == yEnd.month &&
        e.day == yEnd.day) {
      return 1;
    }

    // Check Last 7 Days:
    final DateTime s7 = todayStart.subtract(const Duration(days: 7));
    if (s.year == s7.year &&
        s.month == s7.month &&
        s.day == s7.day &&
        e.year == todayEnd.year &&
        e.month == todayEnd.month &&
        e.day == todayEnd.day) {
      return 7;
    }

    // Check Last 30 Days:
    final DateTime s30 = todayStart.subtract(const Duration(days: 30));
    if (s.year == s30.year &&
        s.month == s30.month &&
        s.day == s30.day &&
        e.year == todayEnd.year &&
        e.month == todayEnd.month &&
        e.day == todayEnd.day) {
      return 30;
    }

    return null;
  }

  void _setPreset(int daysAgo) {
    final DateTime now = DateTime.now();
    setState(() {
      _selectedPresetDays = daysAgo;
      if (daysAgo == 0) {
        _start = DateTime(now.year, now.month, now.day, 0, 0, 0);
        _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (daysAgo == 1) {
        final DateTime y = now.subtract(const Duration(days: 1));
        _start = DateTime(y.year, y.month, y.day, 0, 0, 0);
        _end = DateTime(y.year, y.month, y.day, 23, 59, 59);
      } else {
        _start = DateTime(now.year, now.month, now.day, 0, 0, 0).subtract(Duration(days: daysAgo));
        _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final DateTime current = isStart ? _start : _end;
    final DateTime now = DateTime.now();
    final DateTime minDate = DateTime(now.year - 3, 1, 1);
    final DateTime maxDate = DateTime(now.year + 1, 12, 31);
    final DateTime safeInitial = current.isBefore(minDate)
        ? minDate
        : (current.isAfter(maxDate) ? maxDate : current);

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: minDate,
      lastDate: maxDate,
    );
    if (pickedDate == null || !mounted) return;

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (pickedTime == null || !mounted) return;

    final DateTime result = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _start = result;
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(hours: 1));
        }
      } else {
        _end = result;
        if (_end.isBefore(_start)) {
          _start = _end.subtract(const Duration(hours: 1));
        }
      }
      _selectedPresetDays = _detectPreset(_start, _end);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.paddingOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                const Text(
                  'Select Date & Time',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () => widget.onApply(_start, _end),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9333EA).withOpacity(0.12),
                    foregroundColor: const Color(0xFF9333EA),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick Presets
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _presetChip('Today', 0, () => _setPreset(0)),
                  const SizedBox(width: 8),
                  _presetChip('Yesterday', 1, () => _setPreset(1)),
                  const SizedBox(width: 8),
                  _presetChip('Last 7 Days', 7, () => _setPreset(7)),
                  const SizedBox(width: 8),
                  _presetChip('Last 30 Days', 30, () => _setPreset(30)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Start Time Card
            InkWell(
              onTap: () => _pickDateTime(isStart: true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.access_time_rounded, color: Color(0xFF9333EA), size: 20),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'START DATE & TIME',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Fmt.dateTimeFilter(_start),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.edit_rounded, color: Color(0xFF94A3B8), size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // End Time Card
            InkWell(
              onTap: () => _pickDateTime(isStart: false),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.access_time_rounded, color: Color(0xFF0284C7), size: 20),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'END DATE & TIME',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Fmt.dateTimeFilter(_end),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.edit_rounded, color: Color(0xFF94A3B8), size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: () => widget.onApply(_start, _end),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9333EA),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Apply Date & Time Range', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, int days, VoidCallback onTap) {
    final bool isSelected = _selectedPresetDays == days;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF9333EA) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF9333EA) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF9333EA).withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }
}
