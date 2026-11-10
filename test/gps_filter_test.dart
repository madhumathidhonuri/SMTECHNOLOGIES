import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/core/utils/gps_filter.dart';
import 'package:fueltracks/data/models/trip.dart';

void main() {
  group('GpsFilter.filterStationaryDrift', () {
    test('removes stationary GPS jitter around a parking location', () {
      final baseTime = DateTime(2026, 11, 5, 21, 9, 36);

      // Simulated scenario:
      // 1. Vehicle driving towards parking spot
      // 2. Arrives at parking spot (12.83400, 79.70300)
      // 3. 50 drift fixes fluctuating around parking spot (+- 10 meters, speed 0, ignition off)
      // 4. Vehicle resumes driving later
      final List<TrackPoint> rawPoints = [
        TrackPoint(
          latitude: 12.83000,
          longitude: 79.70000,
          timestamp: baseTime.subtract(const Duration(minutes: 5)),
          speed: 45.0,
          ignition: true,
        ),
        TrackPoint(
          latitude: 12.83200,
          longitude: 79.70150,
          timestamp: baseTime.subtract(const Duration(minutes: 2)),
          speed: 30.0,
          ignition: true,
        ),
        // Arrival / Parking point
        TrackPoint(
          latitude: 12.83400,
          longitude: 79.70300,
          timestamp: baseTime,
          speed: 0.0,
          ignition: false,
        ),
      ];

      // Add 40 jitter points within 15 meters while parked
      for (int i = 1; i <= 40; i++) {
        final double latOffset = (i % 2 == 0 ? 0.00005 : -0.00006);
        final double lngOffset = (i % 3 == 0 ? 0.00007 : -0.00005);
        rawPoints.add(
          TrackPoint(
            latitude: 12.83400 + latOffset,
            longitude: 79.70300 + lngOffset,
            timestamp: baseTime.add(Duration(minutes: i * 2)),
            speed: 0.0,
            ignition: false,
          ),
        );
      }

      // Driving away later
      rawPoints.add(
        TrackPoint(
          latitude: 12.83800,
          longitude: 79.70600,
          timestamp: baseTime.add(const Duration(hours: 2)),
          speed: 35.0,
          ignition: true,
        ),
      );

      final clean = GpsFilter.filterStationaryDrift(rawPoints);

      // We had 44 points total. The 40 jitter points while parked should all be filtered out!
      expect(clean.length, lessThanOrEqualTo(4));
      expect(clean.first.latitude, 12.83000);
      expect(clean.last.latitude, 12.83800);
    });

    test('suppresses ongoing parking jitter at the end of the route', () {
      final baseTime = DateTime(2026, 11, 5, 21, 9, 36);

      // Vehicle drives and parks at the end of the day (customer's exact case)
      final List<TrackPoint> rawPoints = [
        TrackPoint(
          latitude: 12.83000,
          longitude: 79.70000,
          timestamp: baseTime.subtract(const Duration(minutes: 5)),
          speed: 40.0,
          ignition: true,
        ),
        // Arrival point
        TrackPoint(
          latitude: 12.83400,
          longitude: 79.70300,
          timestamp: baseTime,
          speed: 0.0,
          ignition: false,
        ),
      ];

      // 100 jitter fixes over 3 hours of parking
      for (int i = 1; i <= 100; i++) {
        rawPoints.add(
          TrackPoint(
            latitude: 12.83400 + ((i % 5) * 0.00002),
            longitude: 79.70300 - ((i % 4) * 0.00003),
            timestamp: baseTime.add(Duration(minutes: i)),
            speed: 0.0,
            ignition: false,
          ),
        );
      }

      final clean = GpsFilter.filterStationaryDrift(rawPoints);

      // Only the driving point and the arrival parking point should remain
      expect(clean.length, 2);
      expect(clean[0].latitude, 12.83000);
      expect(clean[1].latitude, 12.83400);
    });
  });
}

