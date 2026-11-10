import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/geofence.dart';
import '../../data/models/report_models.dart';
import '../../data/models/vehicle.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import 'services/report_export_service.dart';
import 'widgets/report_filter_bar.dart';
import 'widgets/report_table_views.dart';
import 'widgets/report_top_tabs.dart';

class ReportDetailScreen extends ConsumerStatefulWidget {
  const ReportDetailScreen({
    this.type = ReportType.trip,
    this.initialVehicleId,
    this.initialFromGeofenceId,
    this.initialToGeofenceId,
    this.initialMode,
    super.key,
  });

  final ReportType type;
  final String? initialVehicleId;
  final String? initialFromGeofenceId;
  final String? initialToGeofenceId;
  final String? initialMode;

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  late ReportType _currentType;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _vehicleId;
  String _transitMode = 'all';
  String? _fromGeofenceId;
  String? _toGeofenceId;
  String? _singleGeofenceId;
  List<Geofence> _geofences = const <Geofence>[];

  ReportResult? _result;
  bool _loading = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentType = widget.type;
    _vehicleId = widget.initialVehicleId;
    _transitMode = widget.initialMode ?? 'all';
    _fromGeofenceId = widget.initialFromGeofenceId;
    _toGeofenceId = widget.initialToGeofenceId;

    final DateTime now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
    _endDate = now;

    _loadGeofences();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentType.requiresVehicle && (_vehicleId == null || _vehicleId!.isEmpty)) {
        final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
        if (vehicles.isNotEmpty) {
          _vehicleId = vehicles.first.id;
        }
      }
      _run();
    });
  }

  Future<void> _loadGeofences() async {
    try {
      final List<Geofence> fences =
          await ref.read(geofenceRepositoryProvider).getGeofences();
      if (mounted) {
        setState(() {
          _geofences = fences;
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant ReportDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool shouldRun = false;
    
    if (oldWidget.type != widget.type) {
      _currentType = widget.type;
      shouldRun = true;
    }
    
    if (oldWidget.initialVehicleId != widget.initialVehicleId) {
      _vehicleId = widget.initialVehicleId;
      shouldRun = true;
    }
    
    if (shouldRun) {
      setState(() {});
      _run();
    }
  }

  void _onTabChanged(ReportType newType) {
    if (_currentType == newType) return;
    setState(() {
      _currentType = newType;
      _searchController.clear();
      _searchQuery = '';
      if (newType.requiresVehicle && (_vehicleId == null || _vehicleId!.isEmpty)) {
        final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
        if (vehicles.isNotEmpty) {
          _vehicleId = vehicles.first.id;
        }
      }
      _result = null;
      _error = null;
    });
    _run();
  }

  Future<void> _run() async {
    if (_currentType.requiresVehicle && (_vehicleId == null || _vehicleId!.isEmpty)) {
      setState(() {
        _error = 'Please select a vehicle to generate this report.';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ReportResult res = await ref.read(reportRepositoryProvider).run(
            type: _currentType,
            start: _startDate,
            end: _endDate,
            vehicleId: _vehicleId,
            mode: _transitMode,
            fromGeofenceId: _fromGeofenceId,
            toGeofenceId: _toGeofenceId,
            geofenceId: _singleGeofenceId,
          );

      if (!mounted) return;
      setState(() {
        _result = res;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load report: $e';
        _loading = false;
      });
    }
  }

  Future<void> _handleExport(String format) async {
    final ReportResult? res = _result;
    if (res == null || res.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No report records to export.')),
      );
      return;
    }

    final List<Vehicle> vehicles = ref.read(fleetProvider).vehicles;
    final String q = _searchQuery.trim().toLowerCase();
    final List<ReportRow> rowsToExport = q.isEmpty
        ? res.rows
        : res.rows.where((ReportRow row) {
            final String? vId = row.vehicleId;
            final Vehicle? v = vId != null
                ? vehicles.where((veh) => veh.id == vId).firstOrNull
                : null;
            final String vName = (row.vehicleName ?? v?.displayName ?? '').toLowerCase();
            final String vPlate = (row.plate ?? v?.registrationNumber ?? '').toLowerCase();
            final String vRawName = (v?.name ?? '').toLowerCase();
            final String org = (row.orgName ?? '').toLowerCase();
            final String driver = (row.driverName ?? '').toLowerCase();
            final String idStr = (vId ?? '').toLowerCase();

            return vName.contains(q) ||
                vPlate.contains(q) ||
                vRawName.contains(q) ||
                org.contains(q) ||
                driver.contains(q) ||
                idStr.contains(q);
          }).toList();

    if (rowsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matching records to export.')),
      );
      return;
    }

    try {
      if (format == 'csv') {
        await ReportExportService.exportCsv(type: _currentType, rows: rowsToExport);
      } else if (format == 'excel') {
        await ReportExportService.exportExcel(type: _currentType, rows: rowsToExport);
      } else {
        await ReportExportService.exportPdf(type: _currentType, rows: rowsToExport);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${format.toUpperCase()} export downloaded successfully.'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Vehicle> vehicles = ref.watch(fleetProvider).vehicles;
    final ReportResult? res = _result;
    final List<ReportRow> allRows = res?.rows ?? const <ReportRow>[];
    final String q = _searchQuery.trim().toLowerCase();
    final List<ReportRow> displayRows = q.isEmpty
        ? allRows
        : allRows.where((ReportRow row) {
            final String? vId = row.vehicleId;
            final Vehicle? v = vId != null
                ? vehicles.where((veh) => veh.id == vId).firstOrNull
                : null;
            final String vName = (row.vehicleName ?? v?.displayName ?? '').toLowerCase();
            final String vPlate = (row.plate ?? v?.registrationNumber ?? '').toLowerCase();
            final String vRawName = (v?.name ?? '').toLowerCase();
            final String org = (row.orgName ?? '').toLowerCase();
            final String driver = (row.driverName ?? '').toLowerCase();
            final String idStr = (vId ?? '').toLowerCase();

            return vName.contains(q) ||
                vPlate.contains(q) ||
                vRawName.contains(q) ||
                org.contains(q) ||
                driver.contains(q) ||
                idStr.contains(q);
          }).toList();

    final int totalCount = allRows.length;
    final int displayCount = displayRows.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Subtle light background like web
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (widget.initialVehicleId != null) {
              context.go('/vehicle/${widget.initialVehicleId}');
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: const Text(
          'Reports',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _run,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 40),
            children: <Widget>[
              // Top Horizontal Tabs
              ReportTopTabs(
                selectedType: _currentType,
                onTabSelected: _onTabChanged,
              ),

              const SizedBox(height: 8),

              // Filter Controls Card
              ReportFilterBar(
                type: _currentType,
                startDate: _startDate,
                endDate: _endDate,
                onDateRangeChanged: (DateTime s, DateTime e) {
                  setState(() {
                    _startDate = s;
                    _endDate = e;
                  });
                  _run();
                },
                vehicleId: _vehicleId,
                onVehicleChanged: (String? vId) {
                  setState(() {
                    _vehicleId = vId;
                  });
                  _run();
                },
                onGenerate: _run,
                isLoading: _loading,
                requiresVehicle: _currentType.requiresVehicle,
                onTypeChanged: (ReportType t) {
                  if (_currentType == t) return;
                  setState(() {
                    _currentType = t;
                    _result = null;
                    _error = null;
                  });
                  _run();
                },
                transitMode: _transitMode,
                onTransitModeChanged: (String m) {
                  setState(() => _transitMode = m);
                  _run();
                },
                fromGeofenceId: _fromGeofenceId,
                onFromGeofenceChanged: (String? id) {
                  setState(() => _fromGeofenceId = id);
                  _run();
                },
                toGeofenceId: _toGeofenceId,
                onToGeofenceChanged: (String? id) {
                  setState(() => _toGeofenceId = id);
                  _run();
                },
                singleGeofenceId: _singleGeofenceId,
                onSingleGeofenceChanged: (String? id) {
                  setState(() => _singleGeofenceId = id);
                  _run();
                },
                geofences: _geofences,
              ),

              const SizedBox(height: 8),

              // Report Results Card Container
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    // Table Header Bar: "Report Results (N records)" + Export Buttons
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Text(
                                'Report Results',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? '($displayCount of $totalCount records)'
                                    : '($totalCount records)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _searchQuery.isNotEmpty && displayCount == 0
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),

                          // Download Action Button (opens floating card popup)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: displayCount > 0 ? () => _showDownloadModal(context, displayCount) : null,
                              borderRadius: BorderRadius.circular(8),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: displayCount > 0
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: displayCount > 0
                                      ? <BoxShadow>[
                                          BoxShadow(
                                            color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                  border: Border.all(
                                    color: displayCount > 0
                                        ? const Color(0xFF2563EB)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.download_rounded,
                                      size: 15,
                                      color: displayCount > 0
                                          ? Colors.white
                                          : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Download',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: displayCount > 0
                                            ? Colors.white
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 16,
                                      color: displayCount > 0
                                          ? Colors.white
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // In-card Search Bar
                    if (totalCount > 0 && !_loading)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by vehicle name or plate number...',
                            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF64748B)),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    splashRadius: 16,
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                            ),
                          ),
                          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                          onChanged: (String val) {
                            setState(() {
                              _searchQuery = val.trim();
                            });
                          },
                        ),
                      ),

                    // Swipe hint banner for wide tables
                    if (displayCount > 0 && !_loading)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: const Row(
                          children: <Widget>[
                            Icon(Icons.swap_horiz_rounded, size: 15, color: Color(0xFF64748B)),
                            SizedBox(width: 6),
                            Text(
                              'Swipe left/right on table to view all columns',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Table Body Content
                    if (_loading)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 60),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Generating report data...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_error != null)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 36),
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _run,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Try Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (res == null || allRows.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.search_off_rounded, color: Color(0xFF94A3B8), size: 32),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No records found matching your criteria.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Try adjusting the date range or selecting a different vehicle.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (displayRows.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.search_off_rounded, color: Color(0xFF94A3B8), size: 32),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No vehicles found matching "$_searchQuery"',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Check the vehicle name or plate, or clear the search to view all results.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              icon: const Icon(Icons.clear_rounded, size: 14),
                              label: const Text('Clear Search'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2563EB),
                                side: const BorderSide(color: Color(0xFF93C5FD)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildTableForType(
                          _currentType,
                          ReportResult(
                            rows: displayRows,
                            summary: ReportSummary.fromRows(displayRows),
                            columns: res.columns,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableForType(ReportType type, ReportResult res) {
    final bool showVehicle = _vehicleId == null || _vehicleId!.isEmpty;
    final Vehicle? selectedVehicle = _vehicleId != null
        ? ref.read(fleetProvider).vehicles.where((v) => v.id == _vehicleId).firstOrNull
        : null;

    switch (type) {
      case ReportType.trip:
        return TripReportTable(rows: res.rows, showVehicle: showVehicle);
      case ReportType.manualTrip:
        return ManualTripReportTable(rows: res.rows, showVehicle: showVehicle);
      case ReportType.distance:
        return DailyDistanceReportTable(rows: res.rows);
      case ReportType.overspeeding:
        return OverspeedingReportTable(
          rows: res.rows,
          startDate: _startDate,
          endDate: _endDate,
        );
      case ReportType.stoppages:
        return StoppageReportTable(
          rows: res.rows,
          startDate: _startDate,
          endDate: _endDate,
        );
      case ReportType.idle:
        return IdleReportTable(
          rows: res.rows,
          startDate: _startDate,
          endDate: _endDate,
        );
      case ReportType.individual:
        return IndividualReportTable(
          rows: res.rows,
          fallbackVehicleName: selectedVehicle?.name,
          fallbackPlate: selectedVehicle?.registrationNumber ?? selectedVehicle?.plate,
        );
      case ReportType.consolidated:
        return ConsolidatedReportTable(
          rows: res.rows,
          startDate: _startDate,
          endDate: _endDate,
          vehicles: ref.watch(fleetProvider).vehicles,
        );
      case ReportType.fuelConsolidated:
        return FuelConsolidatedReportTable(
          rows: res.rows,
          startDate: _startDate,
          endDate: _endDate,
          vehicles: ref.watch(fleetProvider).vehicles,
        );
      case ReportType.geofenceTransit:
        return GeofenceTransitReportTable(
          rows: res.rows,
          showVehicle: showVehicle,
        );
      case ReportType.geofenceSinglePlace:
        return GeofenceSinglePlaceReportTable(
          rows: res.rows,
          showVehicle: showVehicle,
        );
      case ReportType.dailyTrip:
        return DailyTripReportTable(
          rows: res.rows,
          showVehicle: showVehicle,
        );
      case ReportType.ignition:
        return IgnitionReportTable(
          rows: res.rows,
          showVehicle: showVehicle,
        );
      default:
        return GenericReportTable(result: res);
    }
  }

  void _showDownloadModal(BuildContext context, int count) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.file_download_outlined,
                              size: 20,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text(
                                  'Download Report',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_currentType.label} · $count records',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            splashRadius: 18,
                          ),
                        ],
                      ),
                    ),

                    // Options List
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _downloadOptionCard(
                            title: 'Excel Spreadsheet',
                            extension: 'XLSX',
                            subtitle: 'Formatted columns, data rows & summary metrics',
                            icon: Icons.table_view_rounded,
                            accentColor: const Color(0xFF10B981),
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              _handleExport('excel');
                            },
                          ),
                          const SizedBox(height: 10),
                          _downloadOptionCard(
                            title: 'PDF Document',
                            extension: 'PDF',
                            subtitle: 'Print-ready formal report with tables & headers',
                            icon: Icons.picture_as_pdf_rounded,
                            accentColor: const Color(0xFFEF4444),
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              _handleExport('pdf');
                            },
                          ),
                          const SizedBox(height: 10),
                          _downloadOptionCard(
                            title: 'CSV Data File',
                            extension: 'CSV',
                            subtitle: 'Raw tabular comma-separated values',
                            icon: Icons.insert_drive_file_rounded,
                            accentColor: const Color(0xFF0284C7),
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              _handleExport('csv');
                            },
                          ),
                        ],
                      ),
                    ),

                    // Footer hint
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(Icons.shield_outlined, size: 14, color: Color(0xFF94A3B8)),
                          SizedBox(width: 6),
                          Text(
                            'Generated locally from active report view',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _downloadOptionCard({
    required String title,
    required String extension,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            extension,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
