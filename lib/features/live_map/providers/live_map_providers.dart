import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/gps_filter.dart';
import '../../../data/models/report_models.dart';
import '../../../data/models/trip.dart';
import '../../../providers/core_providers.dart';

final activeFollowingVehicleIdProvider = StateProvider<String?>((ref) => null);

class VehicleDailyData {
  const VehicleDailyData({
    required this.route,
    required this.stoppages,
  });

  final List<TrackPoint> route;
  final List<ReportRow> stoppages;
}

final vehicleDailyHistoryProvider =
    FutureProvider.family<VehicleDailyData, String>((ref, vehicleId) async {
  if (vehicleId.isEmpty) {
    return const VehicleDailyData(route: [], stoppages: []);
  }

  final vehicleRepo = ref.watch(vehicleRepositoryProvider);

  final now = DateTime.now();
  final startLocal = DateTime(now.year, now.month, now.day);
  final endLocal = now;

  // Apply Traccar UTC/IST offset bug workaround (same as vehicle_playback_tab)
  final DateTime startIstUtc = DateTime.utc(
    startLocal.year, startLocal.month, startLocal.day,
    startLocal.hour, startLocal.minute, startLocal.second,
  );
  final DateTime endIstUtc = DateTime.utc(
    endLocal.year, endLocal.month, endLocal.day,
    endLocal.hour, endLocal.minute, endLocal.second,
  );

  final DateTime startQuery = startIstUtc.subtract(const Duration(hours: 5, minutes: 30));
  final DateTime endQuery = endIstUtc.subtract(const Duration(hours: 5, minutes: 30));

  List<TrackPoint> rawPts = const <TrackPoint>[];
  try {
    rawPts = await vehicleRepo.getHistory(
      vehicleId: vehicleId,
      start: startQuery,
      end: endQuery,
    );
  } catch (e) {
    debugPrint('[vehicleDailyHistoryProvider] Error fetching history for $vehicleId: $e');
    return const VehicleDailyData(route: <TrackPoint>[], stoppages: <ReportRow>[]);
  }
  
  final List<TrackPoint> pts = List<TrackPoint>.from(rawPts);

  // Sort chronologically — the API does not guarantee order and often returns descending.
  // Without this, the time difference calculations will be negative and stoppages will never trigger.
  pts.sort((TrackPoint a, TrackPoint b) =>
      a.timestamp.compareTo(b.timestamp));

  // Compute stoppages from the points
  final List<ReportRow> stoppages = [];
  TrackPoint? stopStart;
  TrackPoint? stopEnd;
  List<TrackPoint> currentStopPoints = [];
  int movingCount = 0;

  for (int i = 0; i < pts.length; i++) {
    final TrackPoint p = pts[i];
    if (p.speed <= 3) {
      stopStart ??= p;
      stopEnd = p;
      currentStopPoints.add(p);
      movingCount = 0;
    } else {
      if (stopStart != null && stopEnd != null) {
        movingCount++;
        // Only break the stop if we have 2 consecutive points > 3 km/h
        if (movingCount >= 2) {
          final Duration diff = stopEnd.timestamp.difference(stopStart.timestamp);
          if (diff.inMinutes >= 5) {
            // Pick representative resting point (lowest speed / stationary cluster center)
            TrackPoint bestPt = stopStart;
            if (currentStopPoints.isNotEmpty) {
              final zeroPts = currentStopPoints.where((tp) => tp.speed == 0).toList();
              if (zeroPts.isNotEmpty) {
                bestPt = zeroPts[zeroPts.length ~/ 2];
              } else {
                bestPt = currentStopPoints.reduce((a, b) => a.speed <= b.speed ? a : b);
              }
            }
            // Show ALL stoppages >= 5 mins, even if it's the initial one
            stoppages.add(ReportRow(
              cells: const {},
              raw: {
                'start_lat': bestPt.latitude,
                'start_lng': bestPt.longitude,
                'end_lat': stopEnd.latitude,
                'end_lng': stopEnd.longitude,
                'start_time': stopStart.timestamp,
                'end_time': stopEnd.timestamp,
                'duration_seconds': diff.inSeconds,
              },
            ));
          }
          stopStart = null;
          stopEnd = null;
          currentStopPoints = [];
          movingCount = 0;
        }
      }
    }
  }

  // Handle an ongoing stoppage at the end of the data
  if (stopStart != null && stopEnd != null) {
    final Duration diff = stopEnd.timestamp.difference(stopStart.timestamp);
    if (diff.inMinutes >= 5) {
      TrackPoint bestPt = stopStart;
      if (currentStopPoints.isNotEmpty) {
        final zeroPts = currentStopPoints.where((tp) => tp.speed == 0).toList();
        if (zeroPts.isNotEmpty) {
          bestPt = zeroPts[zeroPts.length ~/ 2];
        } else {
          bestPt = currentStopPoints.reduce((a, b) => a.speed <= b.speed ? a : b);
        }
      }
      stoppages.add(ReportRow(
        cells: const {},
        raw: {
          'start_lat': bestPt.latitude,
          'start_lng': bestPt.longitude,
          'end_lat': stopEnd.latitude,
          'end_lng': stopEnd.longitude,
          'start_time': stopStart.timestamp,
          'end_time': stopEnd.timestamp,
          'duration_seconds': diff.inSeconds,
        },
      ));
    }
  }

  // Merge consecutive overlapping stoppages (e.g. GPS drift) so numbering doesn't skip
  final List<ReportRow> mergedStoppages = [];
  const dist = Distance();
  for (final stop in stoppages) {
    if (mergedStoppages.isEmpty) {
      mergedStoppages.add(stop);
    } else {
      final last = mergedStoppages.last;
      if (last.startLat != null && last.startLng != null && stop.startLat != null && stop.startLng != null) {
        final double meters = dist(LatLng(last.startLat!, last.startLng!), LatLng(stop.startLat!, stop.startLng!));
        // Increase merge radius to 150 meters to cover large parking lots and prevent visual overlap
        if (meters < 150) {
          // Merge them into one
          final updated = ReportRow(
            cells: const {},
            raw: {
              ...last.raw,
              'end_time': stop.raw['end_time'],
              'duration_seconds': (last.durationSecVal ?? 0) + (stop.durationSecVal ?? 0),
            },
          );
          mergedStoppages.removeLast();
          mergedStoppages.add(updated);
        } else {
          mergedStoppages.add(stop);
        }
      } else {
        mergedStoppages.add(stop);
      }
    }
  }

  final List<TrackPoint> cleanRoute = GpsFilter.filterStationaryDrift(pts);

  return VehicleDailyData(
    route: cleanRoute,
    stoppages: mergedStoppages,
  );
});
