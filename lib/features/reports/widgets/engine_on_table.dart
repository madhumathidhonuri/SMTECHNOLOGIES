import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/geocoder.dart';
import '../../../data/models/report_models.dart';

/// Represents a paired Engine ON & OFF cycle.
class EngineCycle {
  const EngineCycle({
    required this.startTime,
    this.endTime,
    this.startLat,
    this.startLng,
    this.startAddress,
    this.endLat,
    this.endLng,
    this.endAddress,
    required this.durationSeconds,
    this.vehicleName,
    this.plate,
    this.isOnOngoing = false,
  });

  final DateTime startTime;
  final DateTime? endTime;
  final double? startLat;
  final double? startLng;
  final String? startAddress;
  final double? endLat;
  final double? endLng;
  final String? endAddress;
  final int durationSeconds;
  final String? vehicleName;
  final String? plate;
  final bool isOnOngoing;
}

/// Parses raw [ReportRow] items into paired [EngineCycle] cycles.
List<EngineCycle> parseEngineCycles(List<ReportRow> rows) {
  if (rows.isEmpty) return const <EngineCycle>[];

  // 1. Check if rows are already pre-paired session rows or pre-calculated intervals
  final bool isPrePaired = rows.any((ReportRow r) =>
      (r.startTime != null && r.endTime != null && r.endTime!.isAfter(r.startTime!)) ||
      (r.startTime != null && r.durationSecVal != null && r.durationSecVal! > 0));

  if (isPrePaired) {
    final List<EngineCycle> cycles = <EngineCycle>[];
    for (final ReportRow r in rows) {
      final DateTime? st = r.startTime ?? r.timestamp;
      if (st == null) continue;
      final DateTime? et = r.endTime;
      final int dur = r.durationSecVal ??
          (et != null ? et.difference(st).inSeconds.abs() : 0);

      // Exclude zero / non-positive duration cycles (e.g. 00:00:00)
      if (dur <= 0) continue;

      cycles.add(EngineCycle(
        startTime: st,
        endTime: et,
        startLat: r.startLat ?? r.latitude,
        startLng: r.startLng ?? r.longitude,
        startAddress: r.raw['start_address']?.toString() ?? r.address,
        endLat: r.endLat ?? r.latitude,
        endLng: r.endLng ?? r.longitude,
        endAddress: r.raw['end_address']?.toString() ?? r.address,
        durationSeconds: dur,
        vehicleName: r.vehicleName,
        plate: r.plate,
        isOnOngoing: r.raw['is_ongoing'] == true || et == null,
      ));
    }
    cycles.sort((EngineCycle a, EngineCycle b) => b.startTime.compareTo(a.startTime));
    return cycles;
  }

  // 2. Discrete events (ON and OFF logs)
  final List<ReportRow> sorted = List<ReportRow>.from(rows)
    ..sort((ReportRow a, ReportRow b) {
      final DateTime da = a.deviceTime ?? a.timestamp ?? DateTime(2000);
      final DateTime db = b.deviceTime ?? b.timestamp ?? DateTime(2000);
      return da.compareTo(db);
    });

  final List<EngineCycle> cycles = <EngineCycle>[];
  ReportRow? lastOn;

  for (final ReportRow r in sorted) {
    final bool isOn = r.isEngineOn;
    final DateTime t = r.deviceTime ?? r.timestamp ?? DateTime.now();

    if (isOn) {
      if (lastOn != null) {
        // Prior ON without an explicit OFF: close prior ON
        final DateTime lastT = lastOn.deviceTime ?? lastOn.timestamp ?? t;
        final int dur = t.difference(lastT).inSeconds;
        if (dur > 0) {
          cycles.add(EngineCycle(
            startTime: lastT,
            endTime: t,
            startLat: lastOn.latitude,
            startLng: lastOn.longitude,
            startAddress: lastOn.address,
            endLat: r.latitude,
            endLng: r.longitude,
            endAddress: r.address,
            durationSeconds: dur,
            vehicleName: lastOn.vehicleName,
            plate: lastOn.plate,
          ));
        }
      }
      lastOn = r;
    } else {
      // OFF event
      if (lastOn != null) {
        final DateTime startT = lastOn.deviceTime ?? lastOn.timestamp ?? t;
        final int dur = t.difference(startT).inSeconds;
        if (dur > 0) {
          cycles.add(EngineCycle(
            startTime: startT,
            endTime: t,
            startLat: lastOn.latitude,
            startLng: lastOn.longitude,
            startAddress: lastOn.address,
            endLat: r.latitude,
            endLng: r.longitude,
            endAddress: r.address,
            durationSeconds: dur,
            vehicleName: lastOn.vehicleName ?? r.vehicleName,
            plate: lastOn.plate ?? r.plate,
          ));
        }
        lastOn = null;
      }
      // Note: Orphaned OFF events without a prior ON have 0 duration and are ignored.
    }
  }

  // Active ongoing engine ON
  if (lastOn != null) {
    final DateTime startT = lastOn.deviceTime ?? lastOn.timestamp ?? DateTime.now();
    final int dur = (lastOn.durationSecVal != null && lastOn.durationSecVal! > 0)
        ? lastOn.durationSecVal!
        : DateTime.now().difference(startT).inSeconds;
    if (dur > 0) {
      cycles.add(EngineCycle(
        startTime: startT,
        endTime: null,
        startLat: lastOn.latitude,
        startLng: lastOn.longitude,
        startAddress: lastOn.address,
        durationSeconds: dur,
        vehicleName: lastOn.vehicleName,
        plate: lastOn.plate,
        isOnOngoing: true,
      ));
    }
  }

  // Explicitly remove any cycle with durationSeconds <= 0 (e.g. 00:00:00)
  cycles.removeWhere((EngineCycle c) => c.durationSeconds <= 0);

  // Newest cycles first
  cycles.sort((EngineCycle a, EngineCycle b) => b.startTime.compareTo(a.startTime));
  return cycles;
}

/// The horizontal scrollable table view reproducing the exact UI in the user screenshots.
class EngineOnTableView extends StatelessWidget {
  const EngineOnTableView({
    required this.cycles,
    this.headerBackgroundColor = const Color(0xFF6D28D9),
    this.onRowTap,
    super.key,
  });

  final List<EngineCycle> cycles;
  final Color headerBackgroundColor;
  final ValueChanged<EngineCycle>? onRowTap;

  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    return _dateTimeFormat.format(dt);
  }

  static Future<void> _launchMap(BuildContext context, double? lat, double? lng) async {
    if (lat == null || lng == null || (lat == 0 && lng == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Coordinates unavailable for this location.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final Uri uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Maps.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<EngineCycle> validCycles =
        cycles.where((EngineCycle c) => c.durationSeconds > 0).toList();

    if (validCycles.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.power_settings_new_rounded, size: 48, color: Colors.purple.shade200),
            const SizedBox(height: 12),
            const Text(
              'No Engine On/Off events found',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4C1D95),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try changing the selected date or vehicle.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    const double colDateWidth = 165;
    const double colStatusWidth = 70;
    const double colDurationWidth = 125;
    const double colLocationWidth = 280;
    const double colGMapWidth = 80;
    const double totalTableWidth = colDateWidth +
        colStatusWidth +
        colDurationWidth +
        colLocationWidth +
        colGMapWidth +
        4; // for divider widths

    const Color borderColor = Color(0xFFEDE9FE);
    const Color zebraShadeColor = Color(0xFFF5F3FF);
    const Color headerDividerColor = Color(0xFF8B5CF6);
    const Color cycleDividerColor = Color(0xFFDDD6FE);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: SizedBox(
        width: totalTableWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ── TABLE HEADER ROW (VIOLET THEME) ──────────────────────
            Container(
              color: headerBackgroundColor,
              height: 44,
              child: const Row(
                children: <Widget>[
                  SizedBox(
                    width: colDateWidth,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'Date & Time',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: headerDividerColor),
                  SizedBox(
                    width: colStatusWidth,
                    child: Center(
                      child: Text(
                        'Status',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: headerDividerColor),
                  SizedBox(
                    width: colDurationWidth,
                    child: Center(
                      child: Text(
                        'Duration (h:m:s)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: headerDividerColor),
                  SizedBox(
                    width: colLocationWidth,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'Nearest Location',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: headerDividerColor),
                  SizedBox(
                    width: colGMapWidth,
                    child: Center(
                      child: Text(
                        'G-Map',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── TABLE ROWS (VIOLET & WHITE ZEBRA CYCLES) ─────────────
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: validCycles.length,
              itemBuilder: (BuildContext context, int index) {
                final EngineCycle cycle = validCycles[index];
                final bool isEven = index % 2 == 0;
                final Color rowBg = isEven ? Colors.white : zebraShadeColor;

                return Container(
                  decoration: BoxDecoration(
                    color: rowBg,
                    border: const Border(
                      bottom: BorderSide(color: cycleDividerColor, width: 1.2),
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // 1. DATE & TIME (ON on top, OFF below)
                        SizedBox(
                          width: colDateWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                  child: Text(
                                    _fmtDate(cycle.startTime),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: borderColor,
                              ),
                              Expanded(
                                child: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 12),
                                  child: Text(
                                    cycle.isOnOngoing
                                        ? 'Still Running...'
                                        : _fmtDate(cycle.endTime),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cycle.isOnOngoing
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(
                            width: 1, thickness: 1, color: borderColor),

                        // 2. STATUS (ON on top, OFF below)
                        SizedBox(
                          width: colStatusWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: const Text(
                                    'ON',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: borderColor,
                              ),
                              Expanded(
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                    cycle.isOnOngoing ? 'ON' : 'OFF',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: cycle.isOnOngoing
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(
                            width: 1, thickness: 1, color: borderColor),

                        // 3. DURATION (h:m:s) — MERGED CELL SPANNING BOTH ROWS
                        SizedBox(
                          width: colDurationWidth,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                Fmt.secsToHms(cycle.durationSeconds),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const VerticalDivider(
                            width: 1, thickness: 1, color: borderColor),

                        // 4. NEAREST LOCATION (ON location on top, OFF location below)
                        SizedBox(
                          width: colLocationWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  child: _EngineAddressCell(
                                    lat: cycle.startLat,
                                    lng: cycle.startLng,
                                    fallback: cycle.startAddress,
                                  ),
                                ),
                              ),
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: borderColor,
                              ),
                              Expanded(
                                child: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  child: _EngineAddressCell(
                                    lat: cycle.endLat ?? cycle.startLat,
                                    lng: cycle.endLng ?? cycle.startLng,
                                    fallback: cycle.endAddress,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(
                            width: 1, thickness: 1, color: borderColor),

                        // 5. G-MAP (Clickable link on top, clickable link below)
                        SizedBox(
                          width: colGMapWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(
                                child: Center(
                                  child: InkWell(
                                    onTap: () => _launchMap(
                                        context, cycle.startLat, cycle.startLng),
                                    borderRadius: BorderRadius.circular(4),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 8),
                                      child: Text(
                                        'G-Map',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6D28D9),
                                          decoration: TextDecoration.underline,
                                          decorationColor: Color(0xFF6D28D9),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(
                                height: 1,
                                thickness: 1,
                                color: borderColor,
                              ),
                              Expanded(
                                child: Center(
                                  child: InkWell(
                                    onTap: () => _launchMap(
                                      context,
                                      cycle.endLat ?? cycle.startLat,
                                      cycle.endLng ?? cycle.startLng,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 8),
                                      child: Text(
                                        'G-Map',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6D28D9),
                                          decoration: TextDecoration.underline,
                                          decorationColor: Color(0xFF6D28D9),
                                        ),
                                      ),
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
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Address cell component for Engine On table with instant cache and background reverse-geocoding.
class _EngineAddressCell extends StatefulWidget {
  const _EngineAddressCell({
    this.lat,
    this.lng,
    this.fallback,
  });

  final double? lat;
  final double? lng;
  final String? fallback;

  @override
  State<_EngineAddressCell> createState() => _EngineAddressCellState();
}

class _EngineAddressCellState extends State<_EngineAddressCell> {
  String? _address;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _EngineAddressCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat ||
        oldWidget.lng != widget.lng ||
        oldWidget.fallback != widget.fallback) {
      _resolve();
    }
  }

  void _resolve() {
    if (widget.fallback != null &&
        widget.fallback!.trim().isNotEmpty &&
        widget.fallback != 'Location unavailable') {
      _address = widget.fallback;
      return;
    }

    if (widget.lat != null &&
        widget.lng != null &&
        widget.lat != 0 &&
        widget.lng != 0) {
      final String? cached = Geocoder.getCachedAddress(widget.lat!, widget.lng!);
      if (cached != null) {
        _address = cached;
        return;
      }

      _loading = true;
      Geocoder.getAddress(widget.lat!, widget.lng!).then((String addr) {
        if (mounted) {
          setState(() {
            _address = addr;
            _loading = false;
          });
        }
      }).catchError((_) {
        if (mounted) {
          setState(() {
            _address = '${widget.lat!.toStringAsFixed(5)}, ${widget.lng!.toStringAsFixed(5)}';
            _loading = false;
          });
        }
      });
    } else {
      _address = 'Location unavailable';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _address == null) {
      return const Text(
        'Fetching location...',
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: Color(0xFF64748B),
        ),
      );
    }

    return Text(
      _address ??
          (widget.lat != null && widget.lng != null
              ? '${widget.lat!.toStringAsFixed(5)}, ${widget.lng!.toStringAsFixed(5)}'
              : 'Location unavailable'),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: Color(0xFF0F172A),
        height: 1.3,
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}
