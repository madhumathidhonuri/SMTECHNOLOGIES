import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/report_models.dart';
import '../../../data/models/vehicle.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/fleet_provider.dart';
import '../widgets/engine_on_table.dart';

/// Primary Engine On screen with violet & white theme,
/// non-dropdown vehicle subheader, and calendar icon toggleable
/// bottom date card matching user specifications.
class PrimaryEngineOnScreen extends ConsumerStatefulWidget {
  const PrimaryEngineOnScreen({
    this.vehicleId,
    this.initialDate,
    super.key,
  });

  final String? vehicleId;
  final DateTime? initialDate;

  @override
  ConsumerState<PrimaryEngineOnScreen> createState() =>
      _PrimaryEngineOnScreenState();
}

class _PrimaryEngineOnScreenState extends ConsumerState<PrimaryEngineOnScreen> {
  String? _selectedVehicleId;
  late DateTime _startDate;
  late DateTime _endDate;

  late DateTime _tempStartDate;
  late DateTime _tempEndDate;
  bool _showDateCard = false;

  bool _loading = false;
  String? _error;
  List<EngineCycle> _cycles = const <EngineCycle>[];

  static const Color _primaryViolet = Color(0xFF6D28D9); // Violet brand theme
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _timeFormat = DateFormat('hh:mm a');

  @override
  void initState() {
    super.initState();
    _selectedVehicleId = widget.vehicleId;

    final DateTime base = widget.initialDate ?? DateTime.now();
    _startDate = DateTime(base.year, base.month, base.day, 0, 0, 0);
    _endDate = DateTime(base.year, base.month, base.day, 23, 59, 59);

    _tempStartDate = _startDate;
    _tempEndDate = _endDate;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedVehicleId == null || _selectedVehicleId!.isEmpty) {
        final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
        if (vehicles.isNotEmpty) {
          _selectedVehicleId = vehicles.first.id;
        }
      }
      unawaited(_fetchData());
    });
  }

  int? _serverTotalDurationSeconds;

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ReportResult res = await ref.read(reportRepositoryProvider).run(
            type: ReportType.ignition,
            start: _startDate,
            end: _endDate,
            vehicleId: _selectedVehicleId,
          );

      if (!mounted) return;
      final List<EngineCycle> parsed = parseEngineCycles(res.rows);
      final int? serverTotal = res.summary.totalDurationSeconds > 0
          ? res.summary.totalDurationSeconds
          : null;

      setState(() {
        _cycles = parsed;
        _serverTotalDurationSeconds = serverTotal;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load Engine On records: $e';
        _loading = false;
      });
    }
  }

  int get _totalDurationSeconds {
    if (_serverTotalDurationSeconds != null && _serverTotalDurationSeconds! > 0) {
      return _serverTotalDurationSeconds!;
    }
    return _cycles.fold<int>(0, (int sum, EngineCycle c) => sum + c.durationSeconds);
  }

  Vehicle? _resolveVehicle(List<Vehicle> vehicles) {
    if (_selectedVehicleId == null) return vehicles.firstOrNull;
    return vehicles.where((Vehicle v) => v.id == _selectedVehicleId).firstOrNull ??
        vehicles.firstOrNull;
  }

  Future<DateTime?> _pickDate(DateTime initial) async {
    return showDialog<DateTime>(
      context: context,
      builder: (BuildContext ctx) {
        DateTime chosen = initial;
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Cute clean header (no giant bold words)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Select Date',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _primaryViolet,
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16, color: Color(0xFFEDE9FE)),
                  Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: _primaryViolet,
                        onPrimary: Colors.white,
                        surface: Colors.white,
                        onSurface: Color(0xFF0F172A),
                      ),
                      datePickerTheme: const DatePickerThemeData(
                        headerHeadlineStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        weekdayStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                        dayStyle: TextStyle(fontSize: 12),
                        yearStyle: TextStyle(fontSize: 12),
                      ),
                    ),
                    child: CalendarDatePicker(
                      initialDate: initial,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      onDateChanged: (DateTime d) {
                        chosen = d;
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(chosen),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryViolet,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text(
                          'OK',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    );
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) async {
    return showTimePicker(
      context: context,
      initialTime: initial,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryViolet,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: _primaryViolet,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  void _onStartDateClick() async {
    final DateTime? picked = await _pickDate(_tempStartDate);
    if (picked != null) {
      setState(() {
        _tempStartDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _tempStartDate.hour,
          _tempStartDate.minute,
        );
      });
    }
  }

  void _onEndDateClick() async {
    final DateTime? picked = await _pickDate(_tempEndDate);
    if (picked != null) {
      setState(() {
        _tempEndDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _tempEndDate.hour,
          _tempEndDate.minute,
        );
      });
    }
  }

  void _onStartTimeClick() async {
    final TimeOfDay? picked =
        await _pickTime(TimeOfDay.fromDateTime(_tempStartDate));
    if (picked != null) {
      setState(() {
        _tempStartDate = DateTime(
          _tempStartDate.year,
          _tempStartDate.month,
          _tempStartDate.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _onEndTimeClick() async {
    final TimeOfDay? picked =
        await _pickTime(TimeOfDay.fromDateTime(_tempEndDate));
    if (picked != null) {
      setState(() {
        _tempEndDate = DateTime(
          _tempEndDate.year,
          _tempEndDate.month,
          _tempEndDate.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _onDone() {
    setState(() {
      _startDate = _tempStartDate;
      _endDate = _tempEndDate;
      _showDateCard = false;
    });
    unawaited(_fetchData());
  }

  Widget _buildDateCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDDD6FE), width: 1),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1F4C1D95),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Cute small header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: _primaryViolet,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    'Select Date & Time',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.2,
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showDateCard = false),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Start and End Column selection
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      // Left: Start column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Start',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: _onStartDateClick,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _dateFormat.format(_tempStartDate),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            InkWell(
                              onTap: _onStartTimeClick,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _timeFormat.format(_tempStartDate),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: _primaryViolet,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Container(
                        height: 36,
                        width: 1,
                        color: const Color(0xFFEDE9FE),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),

                      // Right: End column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'End',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: _onEndDateClick,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _dateFormat.format(_tempEndDate),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            InkWell(
                              onTap: _onEndTimeClick,
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _timeFormat.format(_tempEndDate),
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: _primaryViolet,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Small cute DONE pill button
                  SizedBox(
                    width: 88,
                    height: 30,
                    child: ElevatedButton(
                      onPressed: _onDone,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryViolet,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'DONE',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final List<Vehicle> vehicles = ref.watch(fleetProvider).vehicles;
    final Vehicle? currentVehicle = _resolveVehicle(vehicles);

    final String vehicleTitle = currentVehicle != null
        ? (currentVehicle.registrationNumber.isNotEmpty &&
                currentVehicle.displayName != currentVehicle.registrationNumber
            ? '${currentVehicle.displayName.toUpperCase()} ${currentVehicle.registrationNumber.toUpperCase()}'
            : currentVehicle.displayName.toUpperCase())
        : 'PRINCY AP39WP 6407';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 8,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (_selectedVehicleId != null) {
              context.go('/vehicle/$_selectedVehicleId');
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: const Text(
          'Primary Engine On',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFEDE9FE), width: 1),
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(
              Icons.calendar_month_rounded,
              color: _showDateCard ? _primaryViolet : const Color(0xFF0F172A),
            ),
            tooltip: 'Filter by Date & Time',
            onPressed: () {
              setState(() {
                _showDateCard = !_showDateCard;
                if (_showDateCard) {
                  _tempStartDate = _startDate;
                  _tempEndDate = _endDate;
                }
              });
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                // ── SUBHEADER: VEHICLE NAME & TOTAL DURATION (NO DROPDOWN) ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFEDE9FE), width: 1.2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      // Left: Vehicle plate / name cleanly without dropdown
                      Expanded(
                        child: Text(
                          vehicleTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: Color(0xFF0F172A),
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Right: Total Duration label + value in Violet
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text(
                            'Total Duration',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6D28D9),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Fmt.secsToHms(_totalDurationSeconds),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── BODY: REFRESHABLE TABLE OR LOAD/ERROR STATE ───────────
                Expanded(
                  child: RefreshIndicator(
                    color: _primaryViolet,
                    onRefresh: _fetchData,
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: _primaryViolet),
                          )
                        : _error != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        size: 44,
                                        color: Color(0xFFEF4444),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: () => unawaited(_fetchData()),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _primaryViolet,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.refresh_rounded, size: 16),
                                        label: const Text('Try Again'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: _showDateCard ? 200 : 24,
                                  ),
                                  child: EngineOnTableView(
                                    cycles: _cycles,
                                    headerBackgroundColor: _primaryViolet,
                                  ),
                                ),
                              ),
                  ),
                ),
              ],
            ),

            // ── BOTTOM SMALL DATE CARD (matching Screenshot 2 & 3) ─────
            if (_showDateCard)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildDateCard(),
              ),
          ],
        ),
      ),
    );
  }
}
