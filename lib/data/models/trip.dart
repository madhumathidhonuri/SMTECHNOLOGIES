import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'json_utils.dart';

/// A single GPS fix used for playback and polyline rendering.
class TrackPoint extends Equatable {
  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speed = 0,
    this.heading = 0,
    this.ignition = false,
    this.address,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double speed;
  final double heading;
  final bool ignition;
  final String? address;

  LatLng get latLng => LatLng(latitude, longitude);

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    double? lat = asDoubleOrNull(json, <String>['latitude', 'lat', 'y']);
    double? lng = asDoubleOrNull(json, <String>['longitude', 'lng', 'lon', 'x']);

    if ((lat == null || lng == null) && json['coordinates'] is List) {
      final List<dynamic> c = json['coordinates'] as List<dynamic>;
      if (c.length >= 2) {
        lng = toDouble(c[0]);
        lat = toDouble(c[1]);
      }
    }

    return TrackPoint(
      latitude: lat ?? 0,
      longitude: lng ?? 0,
      timestamp: asDate(json, <String>[
            'device_time', 'deviceTime', 'server_time', 'serverTime', 'timestamp', 'time', 'gpsTime', 'fixTime', 'createdAt',
          ]) ??
          DateTime(1970),
      speed: asDouble(json, <String>['speed', 'spd']),
      heading: asDouble(json, <String>['direction', 'heading', 'course', 'bearing', 'angle']),
      ignition: asBool(json, <String>['ignition', 'ign', 'acc']),
      address: asStringOrNull(json, <String>['address', 'location']),
    );
  }

  bool get isValid =>
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      !(latitude == 0 && longitude == 0) &&
      timestamp.year > 2000;

  @override
  List<Object?> get props =>
      <Object?>[latitude, longitude, timestamp, speed, heading];
}

class Trip extends Equatable {
  const Trip({
    required this.id,
    this.vehicleId,
    this.vehicleName,
    this.startTime,
    this.endTime,
    this.startAddress,
    this.endAddress,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.distanceKm = 0,
    this.maxSpeed = 0,
    this.avgSpeed = 0,
    this.durationSeconds = 0,
    this.idleSeconds = 0,
    this.fuelConsumed,
  });

  final String id;
  final String? vehicleId;
  final String? vehicleName;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? startAddress;
  final String? endAddress;
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;
  final double distanceKm;
  final double maxSpeed;
  final double avgSpeed;
  final int durationSeconds;
  final int idleSeconds;
  final double? fuelConsumed;

  Duration get duration => Duration(seconds: durationSeconds);
  Duration get idleDuration => Duration(seconds: idleSeconds);

  factory Trip.fromJson(Map<String, dynamic> json) {
    final DateTime? start = asDate(json, <String>[
      'startTime', 'start', 'startedAt', 'from', 'tripStart', 'startDate',
    ]);
    final DateTime? end = asDate(json, <String>[
      'endTime', 'end', 'endedAt', 'to', 'tripEnd', 'endDate',
    ]);

    int seconds = asInt(json, <String>['duration', 'durationSeconds', 'tripDuration']);
    if (seconds == 0 && start != null && end != null) {
      seconds = end.difference(start).inSeconds;
    }

    return Trip(
      id: asString(json, <String>['_id', 'id', 'tripId'],
          fallback: '${start?.millisecondsSinceEpoch ?? 0}'),
      vehicleId: asStringOrNull(json, <String>['vehicleId', 'vehicle']),
      vehicleName: asStringOrNull(
          json, <String>['vehicleName', 'vehicleNumber', 'registrationNumber']),
      startTime: start,
      endTime: end,
      startAddress: asStringOrNull(
          json, <String>['startAddress', 'startLocation', 'fromAddress', 'origin']),
      endAddress: asStringOrNull(
          json, <String>['endAddress', 'endLocation', 'toAddress', 'destination']),
      startLat: asDoubleOrNull(json, <String>['startLat', 'startLatitude', 'fromLat']),
      startLng: asDoubleOrNull(json, <String>['startLng', 'startLongitude', 'fromLng']),
      endLat: asDoubleOrNull(json, <String>['endLat', 'endLatitude', 'toLat']),
      endLng: asDoubleOrNull(json, <String>['endLng', 'endLongitude', 'toLng']),
      distanceKm: asDouble(json, <String>['distance', 'distanceKm', 'totalDistance', 'km']),
      maxSpeed: asDouble(json, <String>['maxSpeed', 'topSpeed', 'peakSpeed']),
      avgSpeed: asDouble(json, <String>['avgSpeed', 'averageSpeed', 'meanSpeed']),
      durationSeconds: seconds,
      idleSeconds: asInt(json, <String>['idleDuration', 'idleTime', 'idleSeconds']),
      fuelConsumed: asDoubleOrNull(json, <String>['fuel', 'fuelConsumed', 'fuelUsed']),
    );
  }

  @override
  List<Object?> get props => <Object?>[id, startTime, endTime, distanceKm];
}
