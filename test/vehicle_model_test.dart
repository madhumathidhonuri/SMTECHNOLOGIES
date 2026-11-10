import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/data/models/vehicle.dart';

void main() {
  group('Vehicle.fromJson — defensive parsing', () {
    test('parses a flat payload', () {
      final Vehicle v = Vehicle.fromJson(<String, dynamic>{
        '_id': 'abc123',
        'name': 'Truck One',
        'registrationNumber': 'TS09AB1234',
        'imei': '860123456789012',
        'latitude': 17.385,
        'longitude': 78.4867,
        'speed': 42.5,
        'ignition': true,
        'timestamp': DateTime.now().toIso8601String(),
      });

      expect(v.id, 'abc123');
      expect(v.displayName, 'TS09AB1234');
      expect(v.speed, 42.5);
      expect(v.ignition, isTrue);
      expect(v.hasLocation, isTrue);
      expect(v.status, VehicleStatus.moving);
    });

    test('parses nested lastLocation', () {
      final Vehicle v = Vehicle.fromJson(<String, dynamic>{
        'id': 'x',
        'name': 'Car',
        'lastLocation': <String, dynamic>{
          'lat': 12.9,
          'lng': 77.6,
          'speed': '0',
          'ignition': 1,
          'deviceTime': DateTime.now().toIso8601String(),
        },
      });

      expect(v.latitude, 12.9);
      expect(v.longitude, 77.6);
      expect(v.speed, 0);
      expect(v.ignition, isTrue);
      // Ignition on + no speed = idle.
      expect(v.status, VehicleStatus.idle);
    });

    test('parses GeoJSON coordinates [lng, lat]', () {
      final Vehicle v = Vehicle.fromJson(<String, dynamic>{
        '_id': 'g',
        'name': 'Geo',
        'position': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[78.4867, 17.385],
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
      });

      expect(v.longitude, 78.4867);
      expect(v.latitude, 17.385);
    });

    test('handles string numerics and missing fields', () {
      final Vehicle v = Vehicle.fromJson(<String, dynamic>{
        '_id': 'y',
        'vehicleNumber': 'KA01XY9999',
        'speed': '55.2 km/h',
        'battery': '87',
      });

      expect(v.speed, closeTo(55.2, 0.01));
      expect(v.batteryLevel, 87);
      expect(v.displayName, 'KA01XY9999');
    });

    test('never throws on an empty or junk payload', () {
      expect(() => Vehicle.fromJson(<String, dynamic>{}), returnsNormally);
      expect(
        () => Vehicle.fromJson(<String, dynamic>{'latitude': 'not-a-number'}),
        returnsNormally,
      );
    });
  });

  group('Derived status', () {
    Vehicle build({
      required bool ignition,
      required double speed,
      required Duration age,
    }) =>
        Vehicle(
          id: 'v',
          name: 'v',
          ignition: ignition,
          speed: speed,
          latitude: 1,
          longitude: 1,
          lastPacketAt: DateTime.now().subtract(age),
        );

    test('stale packet => offline regardless of telemetry', () {
      final Vehicle v = build(
        ignition: true,
        speed: 80,
        age: const Duration(hours: 2),
      );
      expect(v.status, VehicleStatus.offline);
    });

    test('ignition off => stopped', () {
      final Vehicle v =
          build(ignition: false, speed: 0, age: const Duration(minutes: 1));
      expect(v.status, VehicleStatus.stopped);
    });

    test('ignition on, moving => moving', () {
      final Vehicle v =
          build(ignition: true, speed: 30, age: const Duration(minutes: 1));
      expect(v.status, VehicleStatus.moving);
    });

    test('ignition on, stationary => idle', () {
      final Vehicle v =
          build(ignition: true, speed: 1, age: const Duration(minutes: 1));
      expect(v.status, VehicleStatus.idle);
    });

    test('no packet at all => offline', () {
      const Vehicle v = Vehicle(id: 'v', name: 'v');
      expect(v.status, VehicleStatus.offline);
    });
  });

  group('mergeLive — partial socket frames', () {
    test('keeps existing metadata not present in the frame', () {
      final Vehicle base = Vehicle(
        id: 'v1',
        name: 'Truck',
        registrationNumber: 'TS09AB1234',
        imei: '860123456789012',
        driverName: 'Ravi',
        odometer: 12000,
        latitude: 17.0,
        longitude: 78.0,
        speed: 0,
        ignition: false,
        lastPacketAt: DateTime.now().subtract(const Duration(minutes: 3)),
      );

      final Vehicle merged = base.mergeLive(<String, dynamic>{
        'latitude': 17.1,
        'longitude': 78.1,
        'speed': 46,
        'ignition': true,
      });

      expect(merged.latitude, 17.1);
      expect(merged.speed, 46);
      expect(merged.ignition, isTrue);
      // Preserved:
      expect(merged.registrationNumber, 'TS09AB1234');
      expect(merged.driverName, 'Ravi');
      expect(merged.odometer, 12000);
      expect(merged.imei, '860123456789012');
      expect(merged.status, VehicleStatus.moving);
    });

    test('stamps a fresh timestamp when the frame omits one', () {
      final Vehicle base = Vehicle(
        id: 'v',
        name: 'v',
        lastPacketAt: DateTime.now().subtract(const Duration(hours: 5)),
      );
      expect(base.status, VehicleStatus.offline);

      final Vehicle merged =
          base.mergeLive(<String, dynamic>{'speed': 10, 'ignition': true});
      expect(merged.status, VehicleStatus.moving);
    });
  });

  group('Expiry helpers', () {
    test('flags a vehicle expiring within 30 days', () {
      final Vehicle v = Vehicle(
        id: 'v',
        name: 'v',
        expiryDate: DateTime.now().add(const Duration(days: 10)),
      );
      expect(v.isExpiringSoon, isTrue);
      expect(v.isExpired, isFalse);
      expect(v.daysToExpiry, 10);
    });

    test('flags an expired vehicle', () {
      final Vehicle v = Vehicle(
        id: 'v',
        name: 'v',
        expiryDate: DateTime.now().subtract(const Duration(days: 3)),
      );
      expect(v.isExpired, isTrue);
      expect(v.isExpiringSoon, isTrue);
    });

    test('no expiry date is not treated as expiring', () {
      const Vehicle v = Vehicle(id: 'v', name: 'v');
      expect(v.isExpiringSoon, isFalse);
      expect(v.daysToExpiry, isNull);
    });
  });

  group('Overspeeding', () {
    test('uses the per-vehicle limit when present', () {
      const Vehicle v =
          Vehicle(id: 'v', name: 'v', speed: 55, speedLimit: 50);
      expect(v.isOverspeeding, isTrue);
    });

    test('falls back to the default limit', () {
      const Vehicle v = Vehicle(id: 'v', name: 'v', speed: 55);
      expect(v.isOverspeeding, isFalse); // default is 60
    });
  });
}
