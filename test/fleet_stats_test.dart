import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/data/models/vehicle.dart';
import 'package:fueltracks/providers/fleet_provider.dart';

Vehicle v({
  required String id,
  bool ignition = false,
  double speed = 0,
  Duration age = const Duration(minutes: 1),
  double? speedLimit,
  DateTime? expiry,
  double? todayKm,
}) =>
    Vehicle(
      id: id,
      name: id,
      ignition: ignition,
      speed: speed,
      speedLimit: speedLimit,
      expiryDate: expiry,
      todayDistanceKm: todayKm,
      latitude: 1,
      longitude: 1,
      lastPacketAt: DateTime.now().subtract(age),
    );

void main() {
  group('FleetStats', () {
    test('counts each status bucket correctly', () {
      final List<Vehicle> fleet = <Vehicle>[
        v(id: 'a', ignition: true, speed: 40), // moving
        v(id: 'b', ignition: true, speed: 45), // moving
        v(id: 'c', ignition: true, speed: 0), // idle
        v(id: 'd'), // stopped
        v(id: 'e', age: const Duration(hours: 3)), // offline
      ];

      final FleetStats s = FleetStats.from(fleet);

      expect(s.total, 5);
      expect(s.moving, 2);
      expect(s.idle, 1);
      expect(s.stopped, 1);
      expect(s.offline, 1);
      expect(s.online, 4);
      expect(s.onlinePercent, 0.8);
    });

    test('excludes offline vehicles from the overspeeding count', () {
      final List<Vehicle> fleet = <Vehicle>[
        v(id: 'a', ignition: true, speed: 90, speedLimit: 60),
        v(
          id: 'b',
          ignition: true,
          speed: 90,
          speedLimit: 60,
          age: const Duration(hours: 4), // offline — stale speed, ignore
        ),
      ];

      expect(FleetStats.from(fleet).overspeeding, 1);
    });

    test('sums distance travelled today', () {
      final List<Vehicle> fleet = <Vehicle>[
        v(id: 'a', todayKm: 120.5),
        v(id: 'b', todayKm: 79.5),
        v(id: 'c'),
      ];
      expect(FleetStats.from(fleet).totalDistanceToday, 200.0);
    });

    test('counts vehicles expiring soon', () {
      final List<Vehicle> fleet = <Vehicle>[
        v(id: 'a', expiry: DateTime.now().add(const Duration(days: 5))),
        v(id: 'b', expiry: DateTime.now().add(const Duration(days: 200))),
        v(id: 'c', expiry: DateTime.now().subtract(const Duration(days: 2))),
      ];
      expect(FleetStats.from(fleet).expiringSoon, 2);
    });

    test('handles an empty fleet without dividing by zero', () {
      final FleetStats s = FleetStats.from(<Vehicle>[]);
      expect(s.total, 0);
      expect(s.onlinePercent, 0);
      expect(s.utilisation, 0);
    });
  });
}
