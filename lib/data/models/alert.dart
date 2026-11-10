import 'dart:convert';
import 'package:equatable/equatable.dart';

import 'json_utils.dart';

enum AlertSeverity { critical, warning, info }

class FleetAlert extends Equatable {
  const FleetAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.vehicleId,
    this.vehicleName,
    this.latitude,
    this.longitude,
    this.address,
    this.speed,
    this.createdAt,
    this.endTime,
    this.durationMinutes,
    this.isRead = false,
  });

  final String id;

  /// overspeed | geofence_enter | geofence_exit | ignition_on | ignition_off |
  /// sos | power_cut | low_battery | harsh_braking | idle | tow …
  final String type;
  final String title;
  final String message;
  final String? vehicleId;
  final String? vehicleName;
  final double? latitude;
  final double? longitude;
  final String? address;
  final double? speed;
  final DateTime? createdAt;
  /// End time of a stoppage/idle event (if provided by the API).
  final DateTime? endTime;
  /// Duration in minutes for stoppage/idle events.
  final int? durationMinutes;
  final bool isRead;

  bool get hasLocation => latitude != null && longitude != null;

  /// Effective duration in minutes derived from durationMinutes, endTime-createdAt, or message text.
  int? get effectiveDurationMinutes {
    if (durationMinutes != null && durationMinutes! > 0) return durationMinutes;
    if (endTime != null && createdAt != null) return endTime!.difference(createdAt!).inMinutes;
    return extractDurationFromText(message);
  }

  /// For stoppage alerts, the backend generates the alert when the stoppage ENDS (with a known duration).
  /// For parking or ongoing alerts where duration is null or 0, the vehicle has just parked and parking is ongoing.
  DateTime? get calculatedStartTime {
    final String t = type.toLowerCase().trim();
    if (t == 'excessive_idle' || t == 'excessive_idling') {
      return createdAt;
    }
    if (t == 'stoppage' || t == 'parking' || t == 'idle') {
      final int? mins = effectiveDurationMinutes;
      if (mins != null && mins > 0 && createdAt != null) {
        if (endTime != null) {
          return endTime!.subtract(Duration(minutes: mins));
        }
        return createdAt!.subtract(Duration(minutes: mins));
      }
    }
    return createdAt;
  }

  /// Calculated end time. For stoppages with known duration, this is createdAt.
  /// If duration is unknown or zero, or if endTime equals startTime, it is ONGOING (returns null).
  DateTime? get calculatedEndTime {
    if (endTime != null) {
      if (calculatedStartTime != null &&
          endTime!.difference(calculatedStartTime!).inSeconds.abs() < 60) {
        return null; // Ongoing — start and end times cannot be the same minute
      }
      return endTime;
    }
    
    final String t = type.toLowerCase().trim();
    if (t == 'excessive_idle' || t == 'excessive_idling') {
      final int? mins = effectiveDurationMinutes;
      if (mins != null && mins > 0 && createdAt != null) {
        return createdAt!.add(Duration(minutes: mins));
      }
      return null; // Ongoing idling
    }

    final bool isStoppage = t == 'stoppage' || t == 'parking' || t == 'idle';
    if (isStoppage) {
      final int? mins = effectiveDurationMinutes;
      if (mins != null && mins > 0 && createdAt != null) {
        return createdAt; // Ended after known stoppage duration
      }
      // If duration is null or 0, the vehicle is currently parked / stopped — it is ONGOING!
      return null;
    }
    
    final int? mins = effectiveDurationMinutes;
    if (mins != null && mins > 0 && createdAt != null) {
      return createdAt!.add(Duration(minutes: mins));
    }
    return null;
  }

  /// True if this alert represents an overspeeding event.
  bool get isOverspeed {
    final String t = type.toLowerCase().trim();
    final String tl = title.toLowerCase();
    final String msg = message.toLowerCase();
    return t.contains('overspeed') ||
        tl.contains('overspeed') ||
        msg.contains('overspeed') ||
        msg.contains('speed limit') ||
        msg.contains('speeding');
  }

  /// True if this alert represents sustained continuous overspeeding.
  bool get isContinuousOverspeed {
    final String tl = title.toLowerCase();
    final String msg = message.toLowerCase();
    return isOverspeed &&
        (tl.contains('continuous') ||
            msg.contains('continuous') ||
            msg.contains('continuously'));
  }

  /// True if this alert represents excessive idling.
  bool get isExcessiveIdle {
    final String t = type.toLowerCase().trim();
    final String tl = title.toLowerCase();
    final String msg = message.toLowerCase();
    return t == 'excessive_idle' ||
        t == 'excessive_idling' ||
        t == 'idle' ||
        tl.contains('idling') ||
        msg.contains('idling alert') ||
        msg.contains('been idling');
  }

  /// True if this alert represents main battery cut or restoration.
  bool get isMainBatteryAlert {
    final String t = type.toLowerCase().trim();
    final String tl = title.toLowerCase();
    final String msg = message.toLowerCase();
    return t.contains('main_battery') ||
        tl.contains('main battery') ||
        msg.contains('main battery');
  }

  /// Formatted duration string for stoppage/parking/idle alerts
  String? get formattedStoppageDuration {
    final int? mins = effectiveDurationMinutes;
    if (mins == null || mins <= 0) return null;

    final int hrs = mins ~/ 60;
    final int remMins = mins % 60;
    if (hrs >= 1) {
      return remMins > 0 ? '$hrs hr ${remMins}m' : '$hrs hr${hrs > 1 ? 's' : ''}';
    }
    return '$mins mins';
  }

  static int? extractDurationFromText(String text) {
    if (text.isEmpty) return null;
    
    // Check for combined "X hr(s) Y min(s)" pattern first
    final RegExp hrMinReg = RegExp(
      r'(\d+)\s*(?:hours?|hrs?)\s*(?:and\s*)?(\d+)?\s*(?:minutes?|mins?)?',
      caseSensitive: false,
    );
    final Match? hrMinMatch = hrMinReg.firstMatch(text);
    if (hrMinMatch != null) {
      final int hrs = int.tryParse(hrMinMatch.group(1) ?? '') ?? 0;
      final int mins = int.tryParse(hrMinMatch.group(2) ?? '') ?? 0;
      if (hrs > 0 || mins > 0) {
        return (hrs * 60) + mins;
      }
    }

    // Check single unit "X min(s)" or "X hr(s)"
    final RegExp singleReg = RegExp(r'(\d+)\s*(minutes?|mins?|hours?|hrs?)', caseSensitive: false);
    final Match? match = singleReg.firstMatch(text);
    if (match != null) {
      final int? numVal = int.tryParse(match.group(1) ?? '');
      final String unit = (match.group(2) ?? '').toLowerCase();
      if (numVal != null) {
        if (unit.startsWith('h')) {
          return numVal * 60;
        }
        return numVal;
      }
    }
    return null;
  }

  AlertSeverity get severity {
    final String t = type.toLowerCase().trim();
    if (t == 'main_battery_disconnected' ||
        t == 'sos' ||
        t == 'panic' ||
        t == 'crash' ||
        t == 'accident' ||
        t == 'tow' ||
        t == 'power_cut' ||
        t == 'power_disconnected' ||
        t == 'theft' ||
        t == 'theft_alarm' ||
        t == 'safety_park' ||
        t == 'fuel_theft' ||
        isContinuousOverspeed) {
      return AlertSeverity.critical;
    }

    if (t == 'overspeed' ||
        t == 'overspeeding' ||
        t == 'excessive_idle' ||
        t == 'excessive_idling' ||
        t == 'idle' ||
        t == 'harsh_braking' ||
        t == 'harsh_acceleration' ||
        t == 'geofence' ||
        t == 'geofence_enter' ||
        t == 'geofenceenter' ||
        t == 'geofence_exit' ||
        t == 'geofenceexit' ||
        t == 'low_battery') {
      return AlertSeverity.warning;
    }

    return AlertSeverity.info;
  }

  factory FleetAlert.fromJson(Map<String, dynamic> json) {
    final String rawType =
        asString(json, <String>['type', 'alertType', 'alert_type', 'event', 'eventType', 'event_type'],
            fallback: 'info');
    final Map<String, dynamic> veh =
        asMap(json, <String>['vehicle', 'vehicleData']);
    final Map<String, dynamic> meta = () {
      final dynamic m = json['metadata'] ?? json['meta'];
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m);
      if (m is String && m.trim().startsWith('{')) {
        try {
          final dynamic dec = jsonDecode(m);
          if (dec is Map) return Map<String, dynamic>.from(dec);
        } catch (_) {}
      }
      return <String, dynamic>{};
    }();

    return FleetAlert(
      id: asString(json, <String>['_id', 'id', 'alertId', 'alert_id']),
      type: rawType.toLowerCase(),
      title: asString(json, <String>['title', 'name', 'heading', 'alert_title', 'alertTitle'],
          fallback: titleFor(rawType)),
      message: asString(json, <String>['message', 'description', 'body', 'text', 'alert_message', 'alertMessage', 'alertText', 'alert_text'],
          fallback: titleFor(rawType)),
      vehicleId: asStringOrNull(json, <String>['vehicleId', 'vehicle_id']) ??
          asStringOrNull(veh, <String>['_id', 'id']) ??
          asStringOrNull(meta, <String>['vehicleId', 'vehicle_id']),
      vehicleName:
          asStringOrNull(json, <String>['vehicleName', 'vehicle_name', 'vehicleNumber', 'regNo', 'plate']) ??
              asStringOrNull(veh, <String>['registrationNumber', 'name', 'vehicleName']) ??
              asStringOrNull(meta, <String>['vehicleName', 'vehicle_name', 'plate']),
      latitude: asDoubleOrNull(json, <String>['latitude', 'lat']) ??
          asDoubleOrNull(meta, <String>['latitude', 'lat']),
      longitude: asDoubleOrNull(json, <String>['longitude', 'lng', 'lon']) ??
          asDoubleOrNull(meta, <String>['longitude', 'lng', 'lon']),
      address: () {
        final String? raw = asStringOrNull(json, <String>['address', 'location', 'place']) ??
            asStringOrNull(meta, <String>['address', 'location', 'place']);
        if (raw == null || raw.trim().isEmpty) return null;
        final String lower = raw.trim().toLowerCase();
        if (lower == 'location pending' ||
            lower == 'unknown location' ||
            lower == 'location unavailable') {
          return null;
        }
        return raw.trim();
      }(),
      speed: asDoubleOrNull(json, <String>['speed']) ??
          asDoubleOrNull(meta, <String>['speed']),
      createdAt: asDate(json,
          <String>[
            'createdAt', 'created_at', 'timestamp', 'time',
            'occurredAt', 'occurred_at', 'date', 'locTime',
            'loc_time', 'deviceTime', 'device_time', 'serverTime',
            'server_time', 'recorded_at', 'recordedAt',
          ]) ??
          asDate(meta, <String>['createdAt', 'created_at', 'timestamp', 'recorded_at', 'deviceTime', 'serverTime']),
      endTime: asDate(json,
          <String>['endTime', 'end_time', 'stoppageEnd', 'stoppage_end', 'endAt', 'end_at']),
      durationMinutes: _parseDurationMinutes(json),
      isRead: asBool(json, <String>['isRead', 'is_read', 'read', 'seen']),
    );
  }

  /// Tries to extract a duration in minutes from various API shapes.
  static int? _parseDurationMinutes(Map<String, dynamic> json) {
    // Try direct integer fields first
    for (final String key in <String>['durationMinutes', 'duration_minutes', 'stoppageDuration', 'stoppage_duration']) {
      final dynamic v = json[key];
      if (v is int) return v;
      if (v is double) return v.round();
      if (v is String) {
        final int? parsed = int.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    // Try a 'duration' field that might be seconds or minutes
    for (final String key in <String>['duration', 'elapsed', 'idleDuration', 'idle_duration']) {
      final dynamic v = json[key];
      if (v is int) return v > 1440 ? (v ~/ 60) : v; // assume seconds if > 24h in minutes
      if (v is double) return v > 1440 ? (v ~/ 60).round() : v.round();
    }
    return null;
  }

  static String titleFor(String type) => switch (type.toLowerCase().trim()) {
        'overspeed' || 'overspeeding' => 'Overspeeding',
        'continuous_overspeed' => 'Continuous Overspeed',
        'main_battery_disconnected' || 'power_cut' || 'power_disconnected' => 'Main Battery Disconnected',
        'main_battery_connected' => 'Main Battery Connected',
        'geofence' => 'Geofence Alert',
        'geofence_enter' || 'geofenceenter' => 'Geofence Entry',
        'geofence_exit' || 'geofenceexit' => 'Geofence Exit',
        'ignition_on' => 'Engine On',
        'ignition_off' => 'Ignition Off',
        'trip_started' || 'trip_start' || 'trip_begin' || 'start_trip' => 'Trip Started',
        'trip_ended' || 'trip_end' || 'trip_completed' => 'Trip Ended',
        'sos' || 'panic' => 'SOS Emergency',
        'low_battery' => 'Low Battery',
        'harsh_braking' => 'Harsh Braking',
        'harsh_acceleration' => 'Harsh Acceleration',
        'idle' || 'excessive_idle' || 'excessive_idling' => 'Excessive Idling',
        'tow' => 'Tow Detected',
        'stoppage' => 'Long Stoppage',
        'moving' || 'start_moving' => 'Vehicle Moving',
        'stopped' => 'Vehicle Stopped',
        'parking' => 'Parking Alert',
        'theft' || 'theft_alarm' || 'safety_park' || 'fuel_theft' => 'Vehicle Theft Alarm',
        'fuel_refill' || 'fuel_refill_final' => 'Fuel Refill Confirmed',
        _ => 'Fleet Alert',
      };

  FleetAlert copyWith({
    bool? isRead,
    String? vehicleId,
    String? vehicleName,
  }) => FleetAlert(
        id: id,
        type: type,
        title: title,
        message: message,
        vehicleId: vehicleId ?? this.vehicleId,
        vehicleName: vehicleName ?? this.vehicleName,
        latitude: latitude,
        longitude: longitude,
        address: address,
        speed: speed,
        createdAt: createdAt,
        endTime: endTime,
        durationMinutes: durationMinutes,
        isRead: isRead ?? this.isRead,
      );

  @override
  List<Object?> get props =>
      <Object?>[id, type, title, message, vehicleId, createdAt, endTime, durationMinutes, isRead];
}
