import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/fleet_provider.dart';

/// Sticky filter bar: quick presets, a custom range picker and an optional
/// vehicle selector.
///
/// Presets exist because ~90% of report runs are "today", "yesterday" or
/// "this week" — forcing a two-tap calendar for those is friction.
class DateRangeBar extends ConsumerWidget {
  const DateRangeBar({
    required this.range,
    required this.onRangeChanged,
    required this.vehicleId,
    required this.onVehicleChanged,
    required this.requiresVehicle,
    super.key,
  });

  final DateTimeRange range;
  final ValueChanged<DateTimeRange> onRangeChanged;
  final String? vehicleId;
  final ValueChanged<String?> onVehicleChanged;
  final bool requiresVehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<Vehicle> vehicles = ref.watch(fleetProvider).vehicles;

    final Vehicle? selected = vehicleId == null
        ? null
        : vehicles.cast<Vehicle?>().firstWhere(
              (Vehicle? v) => v?.id == vehicleId,
              orElse: () => null,
            );

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        children: <Widget>[
          // Presets
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _preset(context, 'Today', _today()),
                _preset(context, 'Yesterday', _yesterday()),
                _preset(context, 'Last 7 days', _lastDays(7)),
                _preset(context, 'Last 30 days', _lastDays(30)),
                _preset(context, 'This month', _thisMonth()),
              ],
            ),
          ),

          const SizedBox(height: Gap.sm),

          Row(
            children: <Widget>[
              Expanded(
                child: _FilterButton(
                  icon: Icons.date_range_rounded,
                  label: _rangeLabel(),
                  onTap: () => _pickRange(context),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: _FilterButton(
                  icon: Icons.directions_car_rounded,
                  label: selected?.displayName ??
                      (requiresVehicle ? 'Select vehicle' : 'All vehicles'),
                  highlight: requiresVehicle && selected == null,
                  onTap: () => _pickVehicle(context, vehicles),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preset(BuildContext context, String label, DateTimeRange value) {
    final bool selected = _sameRange(range, value);

    return Padding(
      padding: const EdgeInsets.only(right: Gap.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onRangeChanged(value),
      ),
    );
  }

  bool _sameRange(DateTimeRange a, DateTimeRange b) =>
      a.start.year == b.start.year &&
      a.start.month == b.start.month &&
      a.start.day == b.start.day &&
      a.end.year == b.end.year &&
      a.end.month == b.end.month &&
      a.end.day == b.end.day;

  static DateTimeRange _today() {
    final DateTime n = DateTime.now();
    return DateTimeRange(start: DateTime(n.year, n.month, n.day), end: n);
  }

  static DateTimeRange _yesterday() {
    final DateTime n = DateTime.now().subtract(const Duration(days: 1));
    return DateTimeRange(
      start: DateTime(n.year, n.month, n.day),
      end: DateTime(n.year, n.month, n.day, 23, 59, 59),
    );
  }

  static DateTimeRange _lastDays(int days) {
    final DateTime n = DateTime.now();
    return DateTimeRange(
      start: DateTime(n.year, n.month, n.day)
          .subtract(Duration(days: days - 1)),
      end: n,
    );
  }

  static DateTimeRange _thisMonth() {
    final DateTime n = DateTime.now();
    return DateTimeRange(start: DateTime(n.year, n.month), end: n);
  }

  String _rangeLabel() {
    if (_sameRange(range, _today())) return 'Today';
    if (_sameRange(range, _yesterday())) return 'Yesterday';
    if (range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day) {
      return Fmt.date(range.start);
    }
    return '${Fmt.dateShort(range.start)} – ${Fmt.dateShort(range.end)}';
  }

  Future<void> _pickRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: range,
      helpText: 'Select report period',
      saveText: 'Apply',
    );
    if (picked != null) onRangeChanged(picked);
  }

  Future<void> _pickVehicle(
    BuildContext context,
    List<Vehicle> vehicles,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: highlight
          ? theme.colorScheme.primary.withOpacity(0.14)
          : theme.colorScheme.surfaceContainer,
      borderRadius: Corners.rSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: Corners.rSm,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          decoration: BoxDecoration(
            borderRadius: Corners.rSm,
            border: Border.all(
              color: highlight
                  ? theme.colorScheme.primary.withOpacity(0.5)
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: highlight
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: highlight
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
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
    final ThemeData theme = Theme.of(context);

    final List<Vehicle> filtered = widget.vehicles
        .where((Vehicle v) =>
            _query.isEmpty ||
            v.displayName.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.md),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('Select vehicle', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    Text(
                      '${filtered.length}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search vehicles',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (String v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
              itemCount: filtered.length + (widget.allowAll ? 1 : 0),
              itemBuilder: (BuildContext context, int i) {
                if (widget.allowAll && i == 0) {
                  return ListTile(
                    leading: const Icon(Icons.select_all_rounded),
                    title: const Text('All vehicles'),
                    selected: widget.selectedId == null,
                    onTap: () => widget.onSelect(null),
                  );
                }

                final Vehicle v = filtered[i - (widget.allowAll ? 1 : 0)];

                return ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    child: Text(
                      v.displayName.characters.take(2).toString().toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0),
                    ),
                  ),
                  title: Text(v.displayName),
                  subtitle: Text(v.secondaryLabel),
                  selected: widget.selectedId == v.id,
                  trailing: widget.selectedId == v.id
                      ? Icon(Icons.check_circle_rounded,
                          color: theme.colorScheme.primary, size: 20)
                      : null,
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
