import 'package:equatable/equatable.dart';
import '../../core/utils/formatters.dart';
import 'json_utils.dart';

/// A user-defined trip created and managed through the Trips screen.
/// Distinct from the auto-detected [Trip] class used in history playback.
class UserTrip extends Equatable {
  const UserTrip({
    required this.id,
    required this.vehicleId,
    required this.name,
    required this.status,
    this.routeId,
    this.routeName,
    this.vehicleName,
    this.plate,
    this.origin,
    this.destination,
    this.notes,
    this.startTime,
    this.endTime,
    this.distanceKm = 0.0,
    this.maxSpeed = 0,
    this.avgSpeed = 0.0,
    this.durationSecs,
    this.stoppageCount = 0,
    this.createdAt,
  });

  final String id;
  final String vehicleId;
  final String name;
  final String status; // planned | in_progress | completed | cancelled
  final String? routeId;
  final String? routeName;
  final String? vehicleName;
  final String? plate;
  final String? origin;
  final String? destination;
  final String? notes;
  final DateTime? startTime;
  final DateTime? endTime;
  final double distanceKm;
  final int maxSpeed;
  final double avgSpeed;
  final int? durationSecs;
  final int stoppageCount;
  final DateTime? createdAt;

  bool get isActive    => status == 'in_progress';
  bool get isPlanned   => status == 'planned';
  bool get isCompleted => status == 'completed';

  String get durationLabel {
    final s = durationSecs ?? 0;
    return Fmt.secsToHms(s);
  }

  String get distanceLabel => '${distanceKm.toStringAsFixed(1)} km';

  String get formattedStartTime {
    if (startTime == null) return '—';
    final DateTime t = startTime!;
    final String day = '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
    final String hour = (t.hour % 12 == 0 ? 12 : t.hour % 12).toString().padLeft(2, '0');
    final String min = t.minute.toString().padLeft(2, '0');
    final String sec = t.second.toString().padLeft(2, '0');
    final String ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$day $hour:$min:$sec $ampm';
  }

  String get formattedEndTime {
    if (endTime == null) return '—';
    final DateTime t = endTime!;
    final String day = '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
    final String hour = (t.hour % 12 == 0 ? 12 : t.hour % 12).toString().padLeft(2, '0');
    final String min = t.minute.toString().padLeft(2, '0');
    final String sec = t.second.toString().padLeft(2, '0');
    final String ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$day $hour:$min:$sec $ampm';
  }

  String get formattedTimeRange {
    if (startTime == null && endTime == null) return 'Time not specified';
    return '$formattedStartTime → $formattedEndTime';
  }

  UserTrip copyWith({
    String? id,
    String? vehicleId,
    String? name,
    String? status,
    String? routeId,
    String? routeName,
    String? vehicleName,
    String? plate,
    String? origin,
    String? destination,
    String? notes,
    DateTime? startTime,
    DateTime? endTime,
    double? distanceKm,
    int? maxSpeed,
    double? avgSpeed,
    int? durationSecs,
    int? stoppageCount,
    DateTime? createdAt,
  }) =>
      UserTrip(
        id: id ?? this.id,
        vehicleId: vehicleId ?? this.vehicleId,
        name: name ?? this.name,
        status: status ?? this.status,
        routeId: routeId ?? this.routeId,
        routeName: routeName ?? this.routeName,
        vehicleName: vehicleName ?? this.vehicleName,
        plate: plate ?? this.plate,
        origin: origin ?? this.origin,
        destination: destination ?? this.destination,
        notes: notes ?? this.notes,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        distanceKm: distanceKm ?? this.distanceKm,
        maxSpeed: maxSpeed ?? this.maxSpeed,
        avgSpeed: avgSpeed ?? this.avgSpeed,
        durationSecs: durationSecs ?? this.durationSecs,
        stoppageCount: stoppageCount ?? this.stoppageCount,
        createdAt: createdAt ?? this.createdAt,
      );

  factory UserTrip.fromJson(Map<String, dynamic> json) => UserTrip(
        id:           asString(json, ['id', '_id']),
        vehicleId:    asString(json, ['vehicle_id', 'vehicleId']),
        name:         asString(json, ['name', 'title'], fallback: 'Unnamed Trip'),
        status:       asString(json, ['status'], fallback: 'planned'),
        routeId:      asStringOrNull(json, ['route_id', 'routeId']),
        routeName:    asStringOrNull(json, ['route_name', 'routeName']),
        vehicleName:  asStringOrNull(json, ['vehicle_name', 'vehicleName']),
        plate:        asStringOrNull(json, ['plate', 'registrationNumber']),
        origin:       asStringOrNull(json, ['origin', 'fromAddress']),
        destination:  asStringOrNull(json, ['destination', 'toAddress']),
        notes:        asStringOrNull(json, ['notes', 'description']),
        startTime:    asDate(json, ['start_time', 'startTime', 'startedAt']),
        endTime:      asDate(json, ['end_time', 'endTime', 'endedAt']),
        distanceKm:   asDouble(json, ['distance_km', 'distanceKm', 'distance'], fallback: 0.0),
        maxSpeed:     asInt(json, ['max_speed', 'maxSpeed'], fallback: 0),
        avgSpeed:     asDouble(json, ['avg_speed', 'avgSpeed'], fallback: 0.0),
        durationSecs: toInt(json['duration_secs'] ?? json['durationSecs']),
        stoppageCount: asInt(json, ['stoppage_count', 'stoppageCount', 'stoppages', 'stops'], fallback: 0),
        createdAt:    asDate(json, ['created_at', 'createdAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'vehicle_id': vehicleId,
        'name': name,
        'status': status,
        if (routeId != null) 'route_id': routeId,
        if (routeName != null) 'route_name': routeName,
        if (vehicleName != null) 'vehicle_name': vehicleName,
        if (plate != null) 'plate': plate,
        if (origin != null) 'origin': origin,
        if (destination != null) 'destination': destination,
        if (notes != null) 'notes': notes,
        if (startTime != null) 'start_time': startTime!.toIso8601String(),
        if (endTime != null) 'end_time': endTime!.toIso8601String(),
        'distance_km': distanceKm,
        'max_speed': maxSpeed,
        'avg_speed': avgSpeed,
        if (durationSecs != null) 'duration_secs': durationSecs,
        'stoppage_count': stoppageCount,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };

  Map<String, dynamic> toCreateJson() => <String, dynamic>{
        'vehicleId':      vehicleId,
        'name':           name,
        'status':         status,
        if (routeId != null)       'routeId':       routeId,
        if (routeName != null)     'routeName':     routeName,
        if (origin != null)        'origin':        origin,
        if (destination != null)   'destination':   destination,
        if (notes != null)         'notes':         notes,
        if (startTime != null)     'startTime':     startTime!.toIso8601String(),
        if (endTime != null)       'endTime':       endTime!.toIso8601String(),
        if (distanceKm > 0)        'distanceKm':    distanceKm,
        if (durationSecs != null)  'durationSecs':  durationSecs,
        if (stoppageCount > 0)     'stoppageCount': stoppageCount,
      };

  @override
  List<Object?> get props => [id, status, distanceKm, stoppageCount];
}
