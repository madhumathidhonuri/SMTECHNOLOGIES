import 'package:equatable/equatable.dart';

import 'json_utils.dart';

/// Every customer-facing report type, wired to its `/api/reports/*` path.
enum ReportType {
  trip,
  distance,
  activity,
  routeHistory,
  ignition,
  overspeeding,
  stoppages,
  idle,
  consolidated,
  fuelConsolidated,
  individual,
  manualTrip,
  geofenceTransit,
  geofenceSinglePlace,
  dailyTrip,
}

extension ReportTypeX on ReportType {
  String get path => switch (this) {
        ReportType.trip => '/reports/trip',
        ReportType.distance => '/reports/distance',
        ReportType.activity => '/reports/activity',
        ReportType.routeHistory => '/reports/route-history',
        ReportType.ignition => '/reports/ignition',
        ReportType.overspeeding => '/reports/overspeeding',
        ReportType.stoppages => '/reports/stoppages',
        ReportType.idle => '/reports/stoppages',
        ReportType.consolidated => '/reports/consolidated',
        ReportType.fuelConsolidated => '/reports/consolidated',
        ReportType.individual => '/reports/individual',
        ReportType.manualTrip => '/trips',
        ReportType.geofenceTransit => '/reports/geofence-transit',
        ReportType.geofenceSinglePlace => '/reports/geofence-single-place',
        ReportType.dailyTrip => '/reports/daily-trip',
      };

  String get label => switch (this) {
        ReportType.trip => 'Automated Trips',
        ReportType.distance => 'Day Wise Distance Report',
        ReportType.activity => 'Activity Report',
        ReportType.routeHistory => 'Route History',
        ReportType.ignition => 'Engine On Report',
        ReportType.overspeeding => 'Overspeeding',
        ReportType.stoppages => 'Stoppage Report',
        ReportType.idle => 'Idle Report',
        ReportType.consolidated => 'Consolidated',
        ReportType.fuelConsolidated => 'Fuel Consolidated',
        ReportType.individual => 'Individual Summary',
        ReportType.manualTrip => 'Manual Trips',
        ReportType.geofenceTransit => 'Geofence Transit',
        ReportType.geofenceSinglePlace => 'Single Place Activity',
        ReportType.dailyTrip => 'Full Day Trips',
      };

  String get blurb => switch (this) {
        ReportType.trip => 'Every journey with start, end, distance and duration',
        ReportType.distance => 'Distance travelled per day and per vehicle',
        ReportType.activity => 'Movement, idling and parking timeline',
        ReportType.routeHistory => 'Full GPS breadcrumb trail on a map',
        ReportType.ignition => 'Engine on and off events with timestamps and locations',
        ReportType.overspeeding => 'Every breach of the configured speed limit',
        ReportType.stoppages => 'Where and how long vehicles stayed parked',
        ReportType.idle => 'Engine running while stationary — wasted fuel',
        ReportType.consolidated => 'Whole-fleet operational totals in a single sheet',
        ReportType.fuelConsolidated => 'Whole-fleet fuel consumption, refuels, thefts and mileage',
        ReportType.individual => 'Deep-dive summary for one vehicle',
        ReportType.manualTrip => 'Pre-planned and manually tracked trips',
        ReportType.geofenceTransit => 'Corridor transit trips between geofences (One-Way, Two-Way & Round Trip)',
        ReportType.geofenceSinglePlace => 'Vehicle entry, exit, duration & idle time at a specific place',
        ReportType.dailyTrip => 'Consolidates the complete day\'s journey from initial departure to final arrival',
      };

  /// A single vehicle must be chosen before running these.
  bool get requiresVehicle => switch (this) {
        ReportType.routeHistory || ReportType.individual => true,
        _ => false,
      };
}

/// Generic tabular report row. Reports across the platform differ wildly in
/// shape, so we normalise to ordered key/value cells plus a few well-known
/// hoisted fields the UI can style specially.
class ReportRow extends Equatable {
  const ReportRow({
    required this.cells,
    this.vehicleName,
    this.timestamp,
    this.distanceKm,
    this.durationSeconds,
    this.speed,
    this.address,
    this.latitude,
    this.longitude,
    this.raw = const <String, dynamic>{},
  });

  final Map<String, String> cells;
  final String? vehicleName;
  final DateTime? timestamp;
  final double? distanceKm;
  final int? durationSeconds;
  final double? speed;
  final String? address;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic> raw;

  bool get hasLocation => latitude != null && longitude != null;

  // Safe typed accessors for specific tabular reports
  String? get vehicleId => asStringOrNull(raw, <String>['vehicle_id', 'vehicleId', 'id']);
  String? get plate => asStringOrNull(raw, <String>['plate', 'vehicleNumber', 'registrationNumber']);
  String? get orgName => asStringOrNull(raw, <String>['org_name', 'orgName', 'organization']);
  String? get driverName => asStringOrNull(raw, <String>['driver_name', 'driverName', 'driver']);
  String? get driverPhone => asStringOrNull(raw, <String>['driver_phone', 'driverPhone', 'driverMobileNumber', 'mobile']);
  String? get status => asStringOrNull(raw, <String>['status', 'state']);
  
  DateTime? get startTime => asDate(raw, <String>['start_time', 'startTime', 'device_time', 'timestamp', 'time']) ?? timestamp;
  DateTime? get endTime => asDate(raw, <String>['end_time', 'endTime']);
  DateTime? get date => asDate(raw, <String>['date', 'start_time', 'startTime', 'time']) ?? timestamp;

  double? get startLat => asDoubleOrNull(raw, <String>['start_lat', 'startLat', 'lat', 'latitude']) ?? latitude;
  double? get startLng => asDoubleOrNull(raw, <String>['start_lng', 'startLng', 'lng', 'lon', 'longitude']) ?? longitude;
  double? get endLat => asDoubleOrNull(raw, <String>['end_lat', 'endLat']);
  double? get endLng => asDoubleOrNull(raw, <String>['end_lng', 'endLng']);

  double? get startOdometer => asDoubleOrNull(raw, <String>[
        'start_odometer',
        'startOdometer',
        'start_odo',
        'startOdo',
        'odometer_start',
        'odometerStart',
        'first_odometer',
        'first_odo',
        'start_odometer_reading',
        'startOdometerReading',
      ]);
  double? get endOdometer => asDoubleOrNull(raw, <String>[
        'end_odometer',
        'endOdometer',
        'end_odo',
        'endOdo',
        'odometer_end',
        'odometerEnd',
        'last_odometer',
        'last_odo',
        'end_odometer_reading',
        'endOdometerReading',
      ]);
  double? get distanceTravelled => asDoubleOrNull(raw, <String>['distance_travelled', 'distanceTravelled', 'distance', 'distanceKm']) ?? distanceKm;
  int get pointCount => asInt(raw, <String>['point_count', 'pointCount', 'pointsLogged']);

  double? get maxSpeedVal => asDoubleOrNull(raw, <String>['max_speed', 'maxSpeed', 'speed', 'topSpeed']) ?? speed;
  double? get avgSpeedVal => asDoubleOrNull(raw, <String>['avg_speed', 'avgSpeed']);
  int? get durationSecVal {
    final double? dur = asDoubleOrNull(raw, <String>['duration_seconds', 'durationSeconds', 'duration']);
    if (dur != null) return dur.round();
    final double? ms = asDoubleOrNull(raw, <String>['durationMs', 'duration_ms']);
    if (ms != null && ms > 0) return (ms / 1000).round();
    return durationSeconds;
  }

  int? get runningSeconds {
    final double? sec = asDoubleOrNull(raw, <String>[
      'running_seconds',
      'runningSeconds',
      'runningTime',
      'driving_seconds',
      'drivingSeconds',
      'drivingTime',
    ]);
    if (sec != null && sec > 0) return sec.round();
    final double? ms = asDoubleOrNull(raw, <String>[
      'totalRunningMs',
      'runningMs',
      'running_ms',
    ]);
    if (ms != null && ms > 0) return (ms / 1000).round();
    return null;
  }
  int? get movingSeconds {
    final int? runSec = runningSeconds;
    if (runSec != null && runSec > 0) return runSec;
    final double dist = distanceTravelled ?? 0.0;
    final double avgSpeed = avgSpeedVal ?? 0.0;
    if (dist > 0 && avgSpeed > 0) {
      return ((dist / avgSpeed) * 3600).round();
    }
    return null;
  }
  int? get idleSeconds => asDoubleOrNull(raw, <String>[
        'idle_seconds',
        'idleSeconds',
        'idleTime',
        'idle_time',
      ])?.round();

  int? get stoppedSeconds {
    // 1. Direct explicit keys from backend
    final int? s = asDoubleOrNull(raw, <String>[
      'stopped_seconds',
      'stoppedSeconds',
      'stoppage_seconds',
      'stoppageSeconds',
      'stopping_seconds',
      'stoppingSeconds',
      'stop_seconds',
      'stopSeconds',
      'stoppage_time_seconds',
      'stoppageTimeSeconds',
      'stopped_duration',
      'stoppedDuration',
      'stoppage_duration',
      'stoppageDuration',
      'stoppages_duration',
      'stopping_duration',
      'stoppingDuration',
      'stop_duration',
      'stopDuration',
      'stopped_time',
      'stoppedTime',
      'stoppage_time',
      'stoppageTime',
      'stopping_time',
      'stoppingTime',
      'stop_time',
      'stopTime',
      'parking_time',
      'parkingTime',
      'parking_seconds',
      'parkingSeconds',
      'parking_duration',
      'parkingDuration',
    ])?.round();
    if (s != null && s > 0) return s;

    // 2. Compute from intermediate legs if present (sum of stoppage gaps between trips)
    if (legs.isNotEmpty) {
      int legGaps = 0;
      for (int i = 0; i < legs.length - 1; i++) {
        final DateTime? cEnd = asDate(legs[i], <String>['end_time', 'endTime']);
        final DateTime? nStart = asDate(legs[i + 1], <String>['start_time', 'startTime']);
        if (cEnd != null && nStart != null) {
          final int gap = nStart.difference(cEnd).inSeconds;
          if (gap > 0) legGaps += gap;
        }
      }
      final DateTime? firstLegStart = asDate(legs.first, <String>['start_time', 'startTime']);
      final DateTime? lastLegEnd = asDate(legs.last, <String>['end_time', 'endTime']);
      if (startTime != null && firstLegStart != null) {
        final int initialGap = firstLegStart.difference(startTime!).inSeconds;
        if (initialGap > 0) legGaps += initialGap;
      }
      if (endTime != null && lastLegEnd != null) {
        final int finalGap = endTime!.difference(lastLegEnd).inSeconds;
        if (finalGap > 0) legGaps += finalGap;
      }
      if (legGaps > 0) return legGaps;
    }

    // 3. Fallback: calculate from total span / total duration minus driving/running time
    final int? totalSpan = totalSpanSeconds ??
        asDoubleOrNull(raw, <String>[
          'total_span_seconds',
          'totalSpanSeconds',
          'total_duration',
          'totalDuration',
          'total_time',
          'totalTime',
          'duration_seconds',
          'durationSeconds',
          'duration',
        ])?.round() ??
        (startTime != null && endTime != null
            ? endTime!.difference(startTime!).inSeconds.abs()
            : null);

    final int effectiveDriving = drivingSeconds ?? runningSeconds ?? movingSeconds ?? 0;
    final int effectiveIdle = idleSeconds ?? 0;

    if (totalSpan != null && totalSpan > 0 && effectiveDriving > 0) {
      final int rem = totalSpan - effectiveDriving - effectiveIdle;
      if (rem > 0) return rem;
    }

    if (totalSpan != null && totalSpan > 0 && effectiveDriving == 0 && (stopsCount > 0 || pointCount > 0)) {
      return totalSpan;
    }

    return s != null && s > 0 ? s : null;
  }

  int? get totalSeconds {
    final int? dur = asDoubleOrNull(raw, <String>[
      'total_time',
      'totalTime',
      'total_seconds',
      'totalSeconds',
      'total_duration',
      'totalDuration',
      'total_span_seconds',
      'totalSpanSeconds',
      'duration_seconds',
      'durationSeconds',
      'duration',
    ])?.round();
    if (dur != null && dur > 0) return dur;
    final double? ms = asDoubleOrNull(raw, <String>[
      'totalRunningMs',
      'durationMs',
      'duration_ms',
    ]);
    if (ms != null && ms > 0) return (ms / 1000).round();
    if (startTime != null && endTime != null) {
      final int diff = endTime!.difference(startTime!).inSeconds.abs();
      if (diff > 0) return diff;
    }
    final int run = runningSeconds ?? drivingSeconds ?? 0;
    final int idle = idleSeconds ?? 0;
    final int stop = stoppedSeconds ?? 0;
    final int sum = run + idle + stop;
    return sum > 0 ? sum : null;
  }

  int get runningMins => runningSeconds != null ? (runningSeconds! / 60).floor() : 0;
  int get idleMins => idleSeconds != null ? (idleSeconds! / 60).floor() : 0;
  int get stoppedMins => stoppedSeconds != null ? (stoppedSeconds! / 60).floor() : 0;

  double get engineOnHours {
    final int runSec = runningSeconds ?? 0;
    final int idleSec = idleSeconds ?? 0;
    return (runSec + idleSec) / 3600.0;
  }

  double? get startFuel => asDoubleOrNull(raw, <String>['start_fuel', 'startFuel', 'startingFuel', 'start_fuel_level', 'startFuelLevel']);
  double? get endFuel => asDoubleOrNull(raw, <String>['end_fuel', 'endFuel', 'endingFuel', 'end_fuel_level', 'endFuelLevel']);
  double? get consumption => asDoubleOrNull(raw, <String>['consumption', 'fuelConsumption', 'fuel_used', 'fuelUsed', 'totalConsumption', 'total_consumption']);
  double? get filling => asDoubleOrNull(raw, <String>['filling', 'fuelFilling', 'fuelFilled', 'refuels', 'refuel', 'totalFilling', 'total_filling']);
  double? get theft => asDoubleOrNull(raw, <String>['theft', 'fuelTheft', 'thefts', 'drain', 'totalTheft', 'total_theft']);
  double? get kmpl => asDoubleOrNull(raw, <String>['kmpl', 'mileage', 'average']);
  double? get lph => asDoubleOrNull(raw, <String>['lph', 'litresPerHour', 'avg_fuel_consumption_hourly']);
  String? get fromLocation => asStringOrNull(raw, <String>['startAddress', 'start_address', 'fromLocation', 'from_location', 'origin']);
  String? get toLocation => asStringOrNull(raw, <String>['endAddress', 'end_address', 'toLocation', 'to_location', 'destination']);

  // Geofence Transit & Single Place fields
  String? get tripLabel => asStringOrNull(raw, <String>['trip_label', 'tripLabel', 'trip_type', 'tripType', 'mode']);
  String? get fromGeofenceName => asStringOrNull(raw, <String>['from_geofence_name', 'fromGeofenceName', 'from_location', 'fromLocation', 'from_geofence', 'start_place', 'from']);
  String? get toGeofenceName => asStringOrNull(raw, <String>['to_geofence_name', 'toGeofenceName', 'to_location', 'toLocation', 'to_geofence', 'end_place', 'to']);
  String? get fromGeofenceId => asStringOrNull(raw, <String>['from_geofence_id', 'fromGeofenceId', 'fromGeofence']);
  String? get toGeofenceId => asStringOrNull(raw, <String>['to_geofence_id', 'toGeofenceId', 'toGeofence']);
  String? get geofenceName => asStringOrNull(raw, <String>['geofence_name', 'geofenceName', 'place_name', 'placeName', 'geofence', 'zone']);
  String? get geofenceIdVal => asStringOrNull(raw, <String>['geofence_id', 'geofenceId']);
  DateTime? get departureTime => asDate(raw, <String>['departure_time', 'departureTime', 'start_time', 'startTime']);
  DateTime? get arrivalTime => asDate(raw, <String>['arrival_time', 'arrivalTime', 'end_time', 'endTime']);
  DateTime? get entryTime => asDate(raw, <String>['entry_time', 'entryTime', 'in_time', 'inTime']);
  DateTime? get exitTime => asDate(raw, <String>['exit_time', 'exitTime', 'out_time', 'outTime']);
  String? get durationFormatted => asStringOrNull(raw, <String>['duration_formatted', 'durationFormatted', 'formatted_duration']);
  int? get idleSecondsInside => asDoubleOrNull(raw, <String>['idle_seconds_inside', 'idleSecondsInside', 'idle_inside', 'idle_seconds'])?.round();

  // Full Day Trips getters
  double? get totalDistanceVal => asDoubleOrNull(raw, <String>['total_distance', 'totalDistance', 'distance', 'distanceKm', 'distance_travelled']) ?? distanceKm;
  int? get drivingSeconds => asDoubleOrNull(raw, <String>['driving_seconds', 'drivingSeconds', 'running_seconds', 'runningSeconds'])?.round() ?? runningSeconds;
  int? get totalSpanSeconds {
    final int? span = asDoubleOrNull(raw, <String>[
      'total_span_seconds',
      'totalSpanSeconds',
      'total_span',
      'totalSpan',
      'total_duration',
      'totalDuration',
      'duration_seconds',
      'durationSeconds',
      'duration',
    ])?.round();
    if (span != null && span > 0) return span;
    if (startTime != null && endTime != null) {
      final int diff = endTime!.difference(startTime!).inSeconds.abs();
      if (diff > 0) return diff;
    }
    return totalSeconds;
  }
  int get stopsCount => asInt(raw, <String>['stops_count', 'stopsCount', 'stops', 'stoppage_count', 'total_stops']);
  int get legsCount => asInt(raw, <String>['legs_count', 'legsCount', 'legs', 'trips_count']);
  List<Map<String, dynamic>> get legs {
    final dynamic l = raw['legs'];
    if (l is List) return asMapList(l);
    return const <Map<String, dynamic>>[];
  }

  // Ignition / Engine On getters
  String? get eventType => asStringOrNull(raw, <String>['event_type', 'eventType', 'type', 'state', 'status', 'ignition']);
  DateTime? get deviceTime => asDate(raw, <String>['device_time', 'deviceTime', 'timestamp', 'date', 'time']) ?? timestamp;
  bool get isEngineOn {
    final String? t = eventType?.toUpperCase();
    if (t == 'ON' || t == 'TRUE' || t == '1') return true;
    final dynamic rawIg = raw['ignition'];
    if (rawIg == true || rawIg == 'true' || rawIg == 1) return true;
    return false;
  }

  int _extractCount(List<String> keys) {
    for (final String k in keys) {
      final Object? v = raw[k];
      if (v is List) return v.length;
      if (v is num) return v.toInt();
      if (v is String) {
        final int? parsed = int.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
    }
    for (final String sub in <String>['summary', 'activity', 'stats', 'events', 'data']) {
      final Object? subMap = raw[sub];
      if (subMap is Map) {
        for (final String k in keys) {
          final Object? v = subMap[k];
          if (v is List) return v.length;
          if (v is num) return v.toInt();
          if (v is String) {
            final int? parsed = int.tryParse(v.trim());
            if (parsed != null) return parsed;
          }
        }
      }
    }
    return asInt(raw, keys);
  }

  int get tripCount => _extractCount(<String>[
        'trip_count',
        'tripCount',
        'trips',
        'totalTrips',
        'total_trips',
        'tripsCount',
        'trip_events',
        'tripEvents',
      ]);

  int get stoppageCount => _extractCount(<String>[
        'stoppage_count',
        'stoppageCount',
        'stoppages',
        'totalStops',
        'total_stops',
        'stops',
        'stop_count',
        'stopCount',
        'total_stoppages',
        'stoppage',
      ]);

  int get overspeedingCount => _extractCount(<String>[
        'overspeeding_count',
        'overspeedingCount',
        'overspeeding',
        'overspeedCount',
        'overspeed_count',
        'overspeeds',
        'total_overspeed',
        'total_overspeeds',
        'total_overspeeding',
        'violations',
      ]);

  factory ReportRow.fromJson(Map<String, dynamic> json) {
    final Map<String, String> cells = <String, String>{};

    json.forEach((String key, dynamic value) {
      if (value == null) return;
      if (value is Map || value is List) return;
      if (<String>['_id', 'id', '__v', 'orgId', 'organizationId', 'userId']
          .contains(key)) {
        return;
      }
      cells[_humanise(key)] = _format(key, value);
    });

    return ReportRow(
      cells: cells,
      raw: Map<String, dynamic>.unmodifiable(json),
      vehicleName: asStringOrNull(json, <String>[
        'vehicle_name', 'vehicleName', 'vehicleNumber', 'registrationNumber', 'vehicle', 'name',
      ]),
      timestamp: asDate(json, <String>[
        'timestamp', 'date', 'time', 'start_time', 'startTime', 'createdAt', 'eventTime', 'departure_time', 'entry_time',
      ]),
      distanceKm:
          asDoubleOrNull(json, <String>['distance', 'distance_travelled', 'distanceKm', 'totalDistance', 'distance_km']),
      durationSeconds:
          asDoubleOrNull(json, <String>['duration_seconds', 'duration', 'durationSeconds', 'totalDuration'])
              ?.round(),
      speed: asDoubleOrNull(json, <String>['speed', 'max_speed', 'maxSpeed', 'avgSpeed', 'max_speed_kmh', 'avg_speed_kmh']),
      address: asStringOrNull(json, <String>['address', 'location', 'place', 'startAddress']),
      latitude: asDoubleOrNull(json, <String>['latitude', 'lat', 'start_lat', 'startLat']),
      longitude: asDoubleOrNull(json, <String>['longitude', 'lng', 'lon', 'start_lng', 'startLng']),
    );
  }

  static String _humanise(String key) {
    final String spaced = key
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'),
            (Match m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  static String _format(String key, dynamic value) {
    final String k = key.toLowerCase();
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is num) {
      if (k.contains('distance')) return '${value.toStringAsFixed(2)} km';
      if (k.contains('speed')) return '${value.toStringAsFixed(0)} km/h';
      if (k.contains('duration') || k.contains('time') && value > 1000) {
        final int s = value.round();
        final int h = s ~/ 3600;
        final int m = (s % 3600) ~/ 60;
        return h > 0 ? '${h}h ${m}m' : '${m}m';
      }
      if (value is double) return value.toStringAsFixed(2);
      return value.toString();
    }
    final String s = value.toString();
    final DateTime? d = DateTime.tryParse(s);
    if (d != null && s.contains('-') && s.length > 9) {
      final DateTime l = d.toLocal();
      return '${l.day.toString().padLeft(2, '0')}/'
          '${l.month.toString().padLeft(2, '0')}/${l.year} '
          '${l.hour.toString().padLeft(2, '0')}:'
          '${l.minute.toString().padLeft(2, '0')}';
    }
    return s;
  }

  @override
  List<Object?> get props => <Object?>[cells, vehicleName, timestamp, raw];
}

/// Headline figures rendered as stat tiles above a report table.
class ReportSummary extends Equatable {
  const ReportSummary({
    this.totalDistanceKm = 0,
    this.totalTrips = 0,
    this.totalDurationSeconds = 0,
    this.idleSeconds = 0,
    this.stoppageCount = 0,
    this.overspeedCount = 0,
    this.maxSpeed = 0,
    this.avgSpeed = 0,
  });

  final double totalDistanceKm;
  final int totalTrips;
  final int totalDurationSeconds;
  final int idleSeconds;
  final int stoppageCount;
  final int overspeedCount;
  final double maxSpeed;
  final double avgSpeed;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    int totalDur = asInt(json, <String>[
      'totalDuration',
      'duration',
      'runningTime',
      'total_duration',
      'total_time',
      'duration_seconds',
    ]);
    if (totalDur <= 0) {
      final double? ms = asDoubleOrNull(json, <String>[
        'totalRunningMs',
        'durationMs',
        'duration_ms',
        'runningMs',
      ]);
      if (ms != null && ms > 0) totalDur = (ms / 1000).round();
    }

    return ReportSummary(
      totalDistanceKm: asDouble(
          json, <String>['totalDistance', 'distance', 'totalDistanceKm']),
      totalTrips: asInt(json, <String>['totalTrips', 'trips', 'tripCount']),
      totalDurationSeconds: totalDur,
      idleSeconds: asInt(json, <String>['idleDuration', 'idleTime', 'totalIdle']),
      stoppageCount: asInt(json, <String>['stoppages', 'stopCount', 'totalStops']),
      overspeedCount:
          asInt(json, <String>['overspeedCount', 'overspeeding', 'violations']),
      maxSpeed: asDouble(json, <String>['maxSpeed', 'topSpeed']),
      avgSpeed: asDouble(json, <String>['avgSpeed', 'averageSpeed']),
    );
  }

  /// Fallback: derive totals client-side when the API returns only rows.
  factory ReportSummary.fromRows(List<ReportRow> rows) {
    double distance = 0;
    int duration = 0;
    double maxSpeed = 0;
    for (final ReportRow r in rows) {
      distance += r.distanceKm ?? 0;
      duration += r.durationSeconds ?? 0;
      if ((r.speed ?? 0) > maxSpeed) maxSpeed = r.speed ?? 0;
    }
    return ReportSummary(
      totalDistanceKm: distance,
      totalTrips: rows.length,
      totalDurationSeconds: duration,
      maxSpeed: maxSpeed,
      avgSpeed: duration > 0 ? distance / (duration / 3600) : 0,
    );
  }

  bool get isEmpty =>
      totalDistanceKm == 0 && totalTrips == 0 && totalDurationSeconds == 0;

  @override
  List<Object?> get props =>
      <Object?>[totalDistanceKm, totalTrips, totalDurationSeconds, maxSpeed];
}

class ReportResult extends Equatable {
  const ReportResult({
    required this.rows,
    required this.summary,
    this.columns = const <String>[],
  });

  final List<ReportRow> rows;
  final ReportSummary summary;
  final List<String> columns;

  bool get isEmpty => rows.isEmpty;

  factory ReportResult.parse(dynamic payload) {
    List<Map<String, dynamic>> raw = <Map<String, dynamic>>[];
    ReportSummary summary = const ReportSummary();

    if (payload is Map<String, dynamic>) {
      final bool isIndividual = payload.containsKey('vehicle') ||
          payload.containsKey('activity') ||
          payload.containsKey('summary');

      final dynamic dataObj = isIndividual
          ? payload
          : (payload['data'] ??
              payload['rows'] ??
              payload['results'] ??
              payload['records'] ??
              payload['trips'] ??
              payload['items'] ??
              payload);

      if (dataObj is List) {
        raw = asMapList(dataObj);
      } else if (dataObj is Map<dynamic, dynamic> || dataObj is Map<String, dynamic>) {
        final Map<String, dynamic> dataMap = Map<String, dynamic>.from(dataObj as Map);
        // Check for Ignition report payload with intervals, events, summary
        if (dataMap.containsKey('intervals') || dataMap.containsKey('events')) {
          final Map<String, dynamic> vInfo = asMap(dataMap, <String>['vehicleInfo', 'vehicle']);
          final String vName = vInfo['name']?.toString() ?? vInfo['plate']?.toString() ?? '-';
          final String vPlate = vInfo['plate']?.toString() ?? vInfo['registrationNumber']?.toString() ?? vName;
          final String vId = vInfo['id']?.toString() ?? '';

          final dynamic summaryObj = dataMap['summary'];
          int totalDurSec = 0;
          double totalDist = 0.0;
          double maxSpd = 0.0;
          int eventCount = 0;

          if (summaryObj is Map) {
            final Map<String, dynamic> sMap = Map<String, dynamic>.from(summaryObj);
            final int totalRunningMs = asInt(sMap, <String>['totalRunningMs', 'runningMs', 'durationMs']);
            totalDurSec = totalRunningMs > 0 ? (totalRunningMs / 1000).round() : 0;
            totalDist = asDouble(sMap, <String>['totalDistance', 'distance']);
            maxSpd = asDouble(sMap, <String>['topSpeed', 'maxSpeed']);
            eventCount = asInt(sMap, <String>['totalEvents', 'eventsCount']);
          }

          final dynamic intervalsObj = dataMap['intervals'];
          final dynamic eventsObj = dataMap['events'];
          final List<Map<String, dynamic>> rawIntervals =
              intervalsObj is List ? asMapList(intervalsObj) : <Map<String, dynamic>>[];
          final List<Map<String, dynamic>> rawEvents =
              eventsObj is List ? asMapList(eventsObj) : <Map<String, dynamic>>[];

          final bool isLastOngoing = rawEvents.isNotEmpty &&
              rawEvents.last['status']?.toString().toUpperCase() == 'ON';

          if (rawIntervals.isNotEmpty) {
            for (int i = 0; i < rawIntervals.length; i++) {
              final Map<String, dynamic> interval = rawIntervals[i];
              final bool isOngoing = (i == rawIntervals.length - 1) && isLastOngoing;
              final int durMs = asInt(interval, <String>['durationMs', 'duration_ms']);
              final int durSec = durMs > 0 ? (durMs / 1000).round() : totalDurSec;

              raw.add(<String, dynamic>{
                'vehicle_id': vId,
                'vehicle_name': vName,
                'plate': vPlate,
                'start_time': interval['startTime'] ?? interval['start_time'],
                'end_time': isOngoing ? null : (interval['endTime'] ?? interval['end_time']),
                'time': interval['startTime'] ?? interval['start_time'],
                'device_time': interval['startTime'] ?? interval['start_time'],
                'duration_seconds': durSec,
                'duration': durSec,
                'duration_ms': durMs,
                'durationMs': durMs,
                'start_lat': interval['startLat'] ?? interval['start_lat'],
                'start_lng': interval['startLng'] ?? interval['start_lng'],
                'end_lat': interval['endLat'] ?? interval['end_lat'],
                'end_lng': interval['endLng'] ?? interval['end_lng'],
                'latitude': interval['startLat'] ?? interval['start_lat'],
                'longitude': interval['startLng'] ?? interval['start_lng'],
                'status': interval['status'] ?? 'ON',
                'event_type': interval['status'] ?? 'ON',
                'is_ongoing': isOngoing,
                'ignition': true,
              });
            }
          } else if (rawEvents.isNotEmpty) {
            final List<Map<String, dynamic>> evList = List<Map<String, dynamic>>.from(rawEvents);
            if (evList.isNotEmpty && evList.first['status']?.toString().toUpperCase() == 'OFF') {
              evList.removeAt(0);
            }
            int idx = 0;
            while (idx < evList.length) {
              final Map<String, dynamic> ev = evList[idx];
              final bool isEvOn = ev['status']?.toString().toUpperCase() == 'ON';
              if (isEvOn && idx + 1 < evList.length && evList[idx + 1]['status']?.toString().toUpperCase() == 'OFF') {
                final Map<String, dynamic> nextEv = evList[idx + 1];
                final int durMs = asInt(nextEv, <String>['durationMs', 'duration_ms']);
                final int durSec = durMs > 0 ? (durMs / 1000).round() : 0;
                raw.add(<String, dynamic>{
                  'vehicle_id': vId,
                  'vehicle_name': vName,
                  'plate': vPlate,
                  'start_time': ev['time'] ?? ev['device_time'],
                  'end_time': nextEv['time'] ?? nextEv['device_time'],
                  'time': ev['time'] ?? ev['device_time'],
                  'device_time': ev['time'] ?? ev['device_time'],
                  'duration_seconds': durSec,
                  'duration': durSec,
                  'duration_ms': durMs,
                  'durationMs': durMs,
                  'start_lat': ev['lat'] ?? ev['latitude'],
                  'start_lng': ev['lng'] ?? ev['longitude'],
                  'end_lat': nextEv['lat'] ?? nextEv['latitude'],
                  'end_lng': nextEv['lng'] ?? nextEv['longitude'],
                  'latitude': ev['lat'] ?? ev['latitude'],
                  'longitude': ev['lng'] ?? ev['longitude'],
                  'status': 'ON',
                  'event_type': 'ON',
                  'is_ongoing': false,
                  'ignition': true,
                });
                idx += 2;
              } else {
                final int durMs = asInt(ev, <String>['durationMs', 'duration_ms']);
                final int durSec = durMs > 0 ? (durMs / 1000).round() : totalDurSec;
                raw.add(<String, dynamic>{
                  'vehicle_id': vId,
                  'vehicle_name': vName,
                  'plate': vPlate,
                  'start_time': ev['time'] ?? ev['device_time'],
                  'end_time': null,
                  'time': ev['time'] ?? ev['device_time'],
                  'device_time': ev['time'] ?? ev['device_time'],
                  'duration_seconds': durSec,
                  'duration': durSec,
                  'duration_ms': durMs,
                  'durationMs': durMs,
                  'start_lat': ev['lat'] ?? ev['latitude'],
                  'start_lng': ev['lng'] ?? ev['longitude'],
                  'latitude': ev['lat'] ?? ev['latitude'],
                  'longitude': ev['lng'] ?? ev['longitude'],
                  'status': ev['status'] ?? 'ON',
                  'event_type': ev['status'] ?? 'ON',
                  'is_ongoing': true,
                  'ignition': true,
                });
                idx += 1;
              }
            }
          }

          if (totalDurSec == 0 && raw.isNotEmpty) {
            totalDurSec = raw.fold<int>(0, (int sum, Map<String, dynamic> r) => sum + (asInt(r, <String>['duration_seconds']) ));
          }

          summary = ReportSummary(
            totalDurationSeconds: totalDurSec,
            totalDistanceKm: totalDist,
            maxSpeed: maxSpd,
            totalTrips: eventCount > 0 ? eventCount : raw.length,
          );
        } else if (dataMap.containsKey('vehicle') ||
            dataMap.containsKey('activity') ||
            dataMap.containsKey('summary')) {
          final Map<String, dynamic> v = asMap(dataMap, <String>['vehicle']);
          final Map<String, dynamic> a = asMap(dataMap, <String>['activity']);
          final Map<String, dynamic> s = asMap(dataMap, <String>['summary']);
          final dynamic trips = dataMap['trips'];
          final dynamic stoppages = dataMap['stoppages'];
          final dynamic overspeeding = dataMap['overspeeding'];

          final Map<String, dynamic> singleRow = <String, dynamic>{
            'vehicle_name': v['name'] ?? v['registrationNumber'] ?? '-',
            'plate': v['plate'] ?? v['registrationNumber'] ?? '-',
            'distance_travelled': a['distance_travelled'] ?? a['distance'] ?? 0,
            'running_seconds': a['running_seconds'] ?? 0,
            'idle_seconds': a['idle_seconds'] ?? 0,
            'stopped_seconds': a['stopped_seconds'] ?? 0,
            'trip_count': s['trip_count'] ?? (trips is List ? trips.length : 0),
            'stoppage_count': s['stoppage_count'] ?? (stoppages is List ? stoppages.length : 0),
            'overspeeding_count': s['overspeeding_count'] ?? (overspeeding is List ? overspeeding.length : 0),
          };
          raw = <Map<String, dynamic>>[singleRow];
        } else {
          raw = asMapList(dataMap);
        }
      } else {
        raw = asMapList(payload);
      }

      if (summary.isEmpty) {
        final Map<String, dynamic> s =
            asMap(payload, <String>['summary', 'totals', 'aggregate', 'stats']);
        summary = s.isNotEmpty ? ReportSummary.fromJson(s) : ReportSummary.fromJson(payload);
      }
    } else if (payload is List) {
      raw = asMapList(payload);
    }

    final List<ReportRow> rows =
        raw.map(ReportRow.fromJson).toList(growable: false);

    if (summary.isEmpty && rows.isNotEmpty) {
      summary = ReportSummary.fromRows(rows);
    }

    final List<String> columns =
        rows.isEmpty ? <String>[] : rows.first.cells.keys.toList();

    return ReportResult(rows: rows, summary: summary, columns: columns);
  }

  @override
  List<Object?> get props => <Object?>[rows, summary];
}
