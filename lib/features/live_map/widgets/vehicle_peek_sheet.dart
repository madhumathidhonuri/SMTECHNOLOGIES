import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/json_utils.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/models/trip.dart';
import '../../../data/models/report_models.dart';
import '../../../providers/fleet_provider.dart';
import '../../../providers/safety_parking_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/geocoder.dart';
import '../providers/live_map_providers.dart';
import '../../geofences/geofence_editor_sheet.dart';
import '../../../shared/widgets/live_address.dart';

abstract class TripSegment {
  final DateTime startTime;
  final DateTime endTime;
  TripSegment(this.startTime, this.endTime);
}

class DrivingSegment extends TripSegment {
  final double distanceKm;
  final double avgSpeedKmph;
  DrivingSegment(DateTime startTime, DateTime endTime, this.distanceKm, this.avgSpeedKmph) : super(startTime, endTime);
}

class StopSegment extends TripSegment {
  final double lat;
  final double lng;
  final int index;
  final String title;
  StopSegment(DateTime startTime, DateTime endTime, this.lat, this.lng, this.index, {this.title = ''}) : super(startTime, endTime);
}

List<TripSegment> _buildSegments(List<TrackPoint> route, List<ReportRow> stoppages, Vehicle vehicle) {
  final DateTime now = DateTime.now();
  final DateTime todayStart = DateTime(now.year, now.month, now.day);

  if (route.isEmpty) {
    // If no route points recorded today, construct a real segment from live vehicle state
    if (vehicle.speed <= 3) {
      return [
        StopSegment(
          vehicle.lastPacketAt ?? todayStart,
          now,
          vehicle.latitude ?? 0,
          vehicle.longitude ?? 0,
          1,
          title: 'Stopped',
        ),
      ];
    } else {
      return [
        DrivingSegment(
          vehicle.lastPacketAt ?? todayStart,
          now,
          vehicle.todayDistanceKm ?? 0.0,
          vehicle.speed,
        ),
      ];
    }
  }

  final List<TripSegment> segments = [];
  const Distance dist = Distance();

  DateTime currentStart = route.first.timestamp;
  int routeIndex = 0;

  for (int i = 0; i < stoppages.length; i++) {
    final ReportRow stop = stoppages[i];
    final DateTime stopStart = stop.raw['start_time'] as DateTime;
    final DateTime stopEnd = stop.raw['end_time'] as DateTime;

    // Driving segment before this stop
    if (stopStart.isAfter(currentStart)) {
      double distance = 0.0;
      double speedSum = 0.0;
      int count = 0;
      TrackPoint? prev;
      for (int j = routeIndex; j < route.length; j++) {
        final TrackPoint pt = route[j];
        if (pt.timestamp.isAfter(stopStart)) {
          routeIndex = j;
          break;
        }
        if (pt.timestamp.isAfter(currentStart) || pt.timestamp.isAtSameMomentAs(currentStart)) {
          if (prev != null) {
            distance += dist.distance(prev.latLng, pt.latLng) / 1000.0;
          }
          speedSum += pt.speed;
          count++;
          prev = pt;
        }
      }
      final double avgSpeed = count > 0 ? speedSum / count : 0.0;
      segments.add(DrivingSegment(currentStart, stopStart, distance, avgSpeed));
    }

    segments.add(StopSegment(
      stopStart,
      stopEnd,
      toDouble(stop.raw['start_lat']) ?? 0.0,
      toDouble(stop.raw['start_lng']) ?? 0.0,
      i + 1,
      title: 'Stop ${i + 1}',
    ));

    currentStart = stopEnd;
  }

  // Final driving segment
  final DateTime lastTime = route.last.timestamp;
  if (currentStart.isBefore(lastTime)) {
    double distance = 0.0;
    double speedSum = 0.0;
    int count = 0;
    TrackPoint? prev;
    for (int j = routeIndex; j < route.length; j++) {
      final TrackPoint pt = route[j];
      if (pt.timestamp.isAfter(currentStart) || pt.timestamp.isAtSameMomentAs(currentStart)) {
        if (prev != null) {
          distance += dist.distance(prev.latLng, pt.latLng) / 1000.0;
        }
        speedSum += pt.speed;
        count++;
        prev = pt;
      }
    }
    final double avgSpeed = count > 0 ? speedSum / count : 0.0;
    segments.add(DrivingSegment(currentStart, lastTime, distance, avgSpeed));
  }

  return segments;
}

class CoordinateAddress extends StatefulWidget {
  final double lat;
  final double lng;
  CoordinateAddress({required this.lat, required this.lng, super.key});

  @override
  State<CoordinateAddress> createState() => _CoordinateAddressState();
}

class _CoordinateAddressState extends State<CoordinateAddress> {
  String? _address;

  @override
  void initState() {
    super.initState();
    _address = Geocoder.getCachedAddress(widget.lat, widget.lng);
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CoordinateAddress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      _address = Geocoder.getCachedAddress(widget.lat, widget.lng);
      _resolve();
    }
  }

  void _resolve() {
    Geocoder.getAddress(widget.lat, widget.lng).then((addr) {
      if (mounted && addr != 'Location unavailable') {
        setState(() => _address = addr);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String display = _address != null
        ? Fmt.address(_address)
        : (Geocoder.getCachedAddress(widget.lat, widget.lng) ?? '');
    return Text(
      display.isNotEmpty ? display : '...',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.3,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class VehiclePeekSheet extends ConsumerStatefulWidget {
  const VehiclePeekSheet({
    required this.vehicleId,
    required this.isFollowing,
    required this.onToggleFollow,
    required this.onOpenDetails,
    this.scrollController,
    super.key,
  });

  final String vehicleId;
  final bool isFollowing;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpenDetails;
  final ScrollController? scrollController;

  static String _formatDurationShort(Duration d) => Fmt.durationHms(d);

  static String _formatTimeRange(DateTime start, DateTime end) {
    return 'Today ${_formatTime(start)} - ${_formatTime(end)}';
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$hour:$min:$sec $period';
  }

  @override
  ConsumerState<VehiclePeekSheet> createState() => _VehiclePeekSheetState();
}

class _VehiclePeekSheetState extends ConsumerState<VehiclePeekSheet> {
  final Set<int> _alertsSet = <int>{};
  Timer? _historyRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Gentle 45-second refresh keeps trip timeline updated while viewing this vehicle
    _historyRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      ref.invalidate(vehicleDailyHistoryProvider(widget.vehicleId));
    });
  }

  @override
  void dispose() {
    _historyRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleByIdProvider(widget.vehicleId));
    if (vehicle == null) return const SizedBox.shrink();

    final asyncData = ref.watch(vehicleDailyHistoryProvider(widget.vehicleId));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle pill
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Live Vehicle Status (Always visible, instantaneous)
            _VehicleStatusCard(vehicle: vehicle),
            const SizedBox(height: 16),

            // Timeline Segments
            asyncData.when(
                    data: (data) {
                      final segments = _buildSegments(data.route, data.stoppages, vehicle);

                      Duration totalDrivingDuration = Duration.zero;
                      Duration totalStopDuration = Duration.zero;
                      int stopCount = 0;

                      for (final seg in segments) {
                        if (seg is DrivingSegment) {
                          totalDrivingDuration += seg.endTime.difference(seg.startTime);
                        } else if (seg is StopSegment) {
                          stopCount++;
                          totalStopDuration += seg.endTime.difference(seg.startTime);
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TripSummaryCard(
                            travelledDistance: vehicle.todayDistanceKm ?? 0.0,
                            travelledDuration: totalDrivingDuration,
                            stopCount: stopCount,
                            stopDuration: totalStopDuration,
                            lowNetworkCount: 0,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F172A) : Theme.of(context).colorScheme.surface,
                              border: Border.all(
                                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E293B) : Theme.of(context).colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trip Details',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: segments.length,
                                  itemBuilder: (context, index) {
                                    final seg = segments[index];
                                    final bool isLast = index == segments.length - 1;
                                    final bool isDark = Theme.of(context).brightness == Brightness.dark;

                                    if (seg is DrivingSegment) {
                                      final Duration dur = seg.endTime.difference(seg.startTime);
                                      final Color drivingColor = isDark ? const Color(0xFF10B981) : const Color(0xFF2563EB); // Green in dark mode
                                      
                                      return IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            // Timeline Line & Icon Node
                                            SizedBox(
                                              width: 36,
                                              child: Column(
                                                children: [
                                                  Container(
                                                    width: 30,
                                                    height: 30,
                                                    decoration: BoxDecoration(
                                                      color: drivingColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.navigation_rounded, size: 16, color: Colors.white),
                                                  ),
                                                  if (!isLast)
                                                    Expanded(
                                                      child: Container(
                                                        width: 3.5,
                                                        color: drivingColor,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),

                                            // Segment Content
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(bottom: 24),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          'Driving',
                                                          style: TextStyle(
                                                            fontSize: 15,
                                                            fontWeight: FontWeight.bold,
                                                            color: drivingColor,
                                                          ),
                                                        ),
                                                        Text(
                                                          ' — ${VehiclePeekSheet._formatDurationShort(dur)}',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w500,
                                                            color: isDark ? Colors.white70 : const Color(0xFF64748B),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      VehiclePeekSheet._formatTimeRange(seg.startTime, seg.endTime),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isDark ? Colors.white70 : const Color(0xFF64748B),
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),

                                                    // 2 Card Boxes (Distance & Average Speed)
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Container(
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                              color: isDark ? const Color(0xFF0B1020) : Theme.of(context).colorScheme.surface,
                                                              borderRadius: BorderRadius.circular(12),
                                                              border: Border.all(
                                                                color: isDark ? drivingColor.withValues(alpha: 0.5) : Theme.of(context).colorScheme.outlineVariant,
                                                              ),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Row(
                                                                  children: [
                                                                    Icon(Icons.route_rounded, size: 18, color: drivingColor),
                                                                    const SizedBox(width: 6),
                                                                    Text(
                                                                      'Distance',
                                                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 6),
                                                                Text(
                                                                  '${seg.distanceKm.toStringAsFixed(1)} km',
                                                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Theme.of(context).colorScheme.onSurface),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Container(
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                              color: isDark ? const Color(0xFF0B1020) : Theme.of(context).colorScheme.surface,
                                                              borderRadius: BorderRadius.circular(12),
                                                              border: Border.all(
                                                                color: isDark ? drivingColor.withValues(alpha: 0.5) : Theme.of(context).colorScheme.outlineVariant,
                                                              ),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Row(
                                                                  children: [
                                                                    Icon(Icons.speed_rounded, size: 18, color: drivingColor),
                                                                    const SizedBox(width: 6),
                                                                    Text(
                                                                      'Average Speed',
                                                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(height: 6),
                                                                Text(
                                                                  '${seg.avgSpeedKmph.round()} kmph',
                                                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Theme.of(context).colorScheme.onSurface),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    } else if (seg is StopSegment) {
                                      final Duration dur = seg.endTime.difference(seg.startTime);
                                      final Color stopColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
                                      
                                      return IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            // Timeline Line & Icon Node
                                            SizedBox(
                                              width: 36,
                                              child: Column(
                                                children: [
                                                  Container(
                                                    width: 30,
                                                    height: 30,
                                                    decoration: BoxDecoration(
                                                      color: stopColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.local_gas_station_rounded, size: 16, color: Colors.white),
                                                  ),
                                                  if (!isLast)
                                                    Expanded(
                                                      child: Container(
                                                        width: 3.5,
                                                        color: stopColor,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),

                                            // Segment Content
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(bottom: 24),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            '${seg.title} — ${VehiclePeekSheet._formatDurationShort(dur)}',
                                                            style: TextStyle(
                                                              fontSize: 14,
                                                              fontWeight: FontWeight.bold,
                                                              color: stopColor,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        if (_alertsSet.contains(seg.index))
                                                          Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: const [
                                                              Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                                                              SizedBox(width: 4),
                                                              Text(
                                                                'Geofence set',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: Color(0xFF10B981),
                                                                ),
                                                              ),
                                                            ],
                                                          )
                                                        else
                                                          InkWell(
                                                            onTap: () async {
                                                              final bool? created = await showModalBottomSheet<bool>(
                                                                context: context,
                                                                isScrollControlled: true,
                                                                useSafeArea: true,
                                                                builder: (BuildContext ctx) => GeofenceEditorSheet(
                                                                  initialLocation: LatLng(seg.lat, seg.lng),
                                                                  initialVehicleId: widget.vehicleId,
                                                                ),
                                                              );
                                                              if (created == true) {
                                                                setState(() {
                                                                  _alertsSet.add(seg.index);
                                                                });
                                                              }
                                                            },
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Text(
                                                                  'Set geofence',
                                                                  style: TextStyle(
                                                                    fontSize: 12,
                                                                    fontWeight: FontWeight.bold,
                                                                    color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                                                                  ),
                                                                ),
                                                                Icon(Icons.chevron_right_rounded, size: 16, color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                                                              ],
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      VehiclePeekSheet._formatTimeRange(seg.startTime, seg.endTime),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isDark ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    CoordinateAddress(lat: seg.lat, lng: seg.lng),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ),
                          ),
                    ],
                  );
                },
                loading: () => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TripSummaryCard(
                      travelledDistance: vehicle.todayDistanceKm ?? 0.0,
                      travelledDuration: Duration.zero,
                      stopCount: 0,
                      stopDuration: Duration.zero,
                      lowNetworkCount: 0,
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ],
                ),
                error: (err, stack) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TripSummaryCard(
                      travelledDistance: vehicle.todayDistanceKm ?? 0.0,
                      travelledDuration: Duration.zero,
                      stopCount: 0,
                      stopDuration: Duration.zero,
                      lowNetworkCount: 0,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 24,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                            const SizedBox(height: 6),
                            Text(
                              'Trip details temporarily unavailable',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () => ref.invalidate(vehicleDailyHistoryProvider(widget.vehicleId)),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                  ),

                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Trip Started - ${asyncData.valueOrNull?.route.firstOrNull != null ? Fmt.date(asyncData.valueOrNull!.route.first.timestamp) : 'Today'}, 12:00 AM',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
    );
  }
}

class _VehicleStatusCard extends ConsumerStatefulWidget {
  const _VehicleStatusCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  ConsumerState<_VehicleStatusCard> createState() => _VehicleStatusCardState();
}

class _VehicleStatusCardState extends ConsumerState<_VehicleStatusCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _animController.forward(from: 0.0);

    try {
      ref.invalidate(fleetProvider);
      ref.invalidate(vehicleDailyHistoryProvider(widget.vehicle.id));
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _isRefreshing = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Vehicle vehicle = widget.vehicle;
    final DateTime? sinceTime = vehicle.statusChangedAt ?? vehicle.lastPacketAt;
    final String durationStr = Fmt.statusDuration(sinceTime);
    final String timeStr = Fmt.time12Sec(sinceTime);

    IconData icon;
    Color iconBg;
    Color textCol;
    String statusTitle;

    switch (vehicle.status) {
      case VehicleStatus.moving:
        icon = Icons.navigation_rounded;
        iconBg = const Color(0xFF22C55E);
        textCol = const Color(0xFF22C55E);
        statusTitle = sinceTime != null
            ? 'Moving Since $timeStr ($durationStr)'
            : 'Moving';
      case VehicleStatus.idle:
        icon = Icons.key_rounded;
        iconBg = const Color(0xFFF59E0B);
        textCol = const Color(0xFFF59E0B);
        statusTitle = sinceTime != null
            ? 'Idling Since $timeStr ($durationStr)'
            : 'Idling';
      case VehicleStatus.stopped:
        icon = Icons.local_parking_rounded;
        iconBg = const Color(0xFF64748B);
        textCol = const Color(0xFF64748B);
        statusTitle = sinceTime != null
            ? 'Parking Since $timeStr ($durationStr)'
            : 'Parking';
      case VehicleStatus.offline:
        icon = Icons.cloud_off_rounded;
        iconBg = const Color(0xFFEF4444);
        textCol = const Color(0xFFEF4444);
        statusTitle = sinceTime != null
            ? 'No Data Since $timeStr ($durationStr)'
            : 'No Data';
      case VehicleStatus.noData:
        icon = Icons.sensors_off_rounded;
        iconBg = const Color(0xFF94A3B8);
        textCol = const Color(0xFF94A3B8);
        statusTitle = 'No Data Available';
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Vehicle Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Safety Parking Arm/Disarm Quick Button
                    Material(
                      color: vehicle.isSafetyParkActive
                          ? const Color(0xFFDC2626)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                vehicle.isSafetyParkActive
                                    ? Icons.security_rounded
                                    : Icons.shield_outlined,
                                size: 14,
                                color: vehicle.isSafetyParkActive ? Colors.white : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                vehicle.isSafetyParkActive ? 'ARMED' : 'SAFE PARK',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: vehicle.isSafetyParkActive ? Colors.white : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: Tooltip(
                        message: 'Refresh vehicle data',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _handleRefresh,
                          child: Padding(
                            padding: const EdgeInsets.all(7.0),
                            child: RotationTransition(
                              turns: _animController,
                              child: Icon(
                                Icons.refresh_rounded,
                                size: 19,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isDark
                  ? LinearGradient(
                      colors: [
                        iconBg.withValues(alpha: 0.15),
                        iconBg.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: isDark ? null : Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: isDark
                    ? iconBg.withValues(alpha: 0.4)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon with double ring
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: iconBg.withValues(alpha: 0.5), width: 2),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: isDark ? const Color(0xFF0F172A) : Colors.white, size: 26),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textCol,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 14, color: textCol),
                          const SizedBox(width: 4),
                          Expanded(
                            child: LiveAddress(
                              vehicle: vehicle,
                              
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: textCol,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (vehicle.status == VehicleStatus.moving) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? iconBg.withValues(alpha: 0.1) : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? iconBg.withValues(alpha: 0.5) : Colors.green.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${vehicle.speed.toInt()}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? iconBg : Colors.green.shade700,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.speed_rounded, size: 12, color: isDark ? Colors.white : Colors.black),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'km/h',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({
    required this.travelledDistance,
    required this.travelledDuration,
    required this.stopCount,
    required this.stopDuration,
    required this.lowNetworkCount,
  });

  final double travelledDistance;
  final Duration travelledDuration;
  final int stopCount;
  final Duration stopDuration;
  final int lowNetworkCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trip Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetric(context, isDark,
                  icon: Icons.trip_origin_rounded,
                  iconBgColor: const Color(0xFF3B82F6),
                  title: 'Travelled',
                  value: '${travelledDistance.toStringAsFixed(2)} KM',
                  subtitle: VehiclePeekSheet._formatDurationShort(travelledDuration),
                ),
                VerticalDivider(color: isDark ? const Color(0xFF1E293B) : Theme.of(context).colorScheme.outlineVariant),
                _buildMetric(context, isDark,
                  icon: Icons.square_rounded,
                  iconSize: 12,
                  iconBgColor: const Color(0xFFF59E0B),
                  title: 'Stop',
                  value: '$stopCount Stop',
                  subtitle: VehiclePeekSheet._formatDurationShort(stopDuration),
                ),
                VerticalDivider(color: isDark ? const Color(0xFF1E293B) : Theme.of(context).colorScheme.outlineVariant),
                _buildMetric(context, isDark,
                  icon: Icons.signal_cellular_alt_rounded,
                  iconSize: 14,
                  iconBgColor: const Color(0xFF475569),
                  title: 'Low Network',
                  value: '$lowNetworkCount Time',
                  subtitle: '-',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    BuildContext context, 
    bool isDark, {
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String value,
    required String subtitle,
    double iconSize = 16,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: iconSize, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: iconBgColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
