import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/data/models/report_models.dart';

void main() {
  group('ReportResult.parse — tolerates every backend shape', () {
    test('parses a bare list', () {
      final ReportResult r = ReportResult.parse(<dynamic>[
        <String, dynamic>{'vehicleName': 'TS09AB1234', 'distance': 42.5},
        <String, dynamic>{'vehicleName': 'TS09AB5678', 'distance': 17.25},
      ]);

      expect(r.rows.length, 2);
      expect(r.summary.totalDistanceKm, closeTo(59.75, 0.01));
    });

    test('parses an enveloped { data: [...] } response', () {
      final ReportResult r = ReportResult.parse(<String, dynamic>{
        'success': true,
        'data': <dynamic>[
          <String, dynamic>{'vehicleName': 'A', 'distance': 10},
        ],
      });
      expect(r.rows.length, 1);
    });

    test('prefers a server-provided summary over derived totals', () {
      final ReportResult r = ReportResult.parse(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'distance': 10},
          <String, dynamic>{'distance': 10},
        ],
        'summary': <String, dynamic>{
          'totalDistance': 999,
          'totalTrips': 42,
        },
      });

      expect(r.summary.totalDistanceKm, 999);
      expect(r.summary.totalTrips, 42);
    });

    test('humanises column keys for display', () {
      final ReportResult r = ReportResult.parse(<dynamic>[
        <String, dynamic>{'startAddress': 'Depot', 'maxSpeed': 88},
      ]);

      expect(r.columns, contains('Start Address'));
      expect(r.columns, contains('Max Speed'));
      expect(r.rows.first.cells['Max Speed'], '88 km/h');
    });

    test('drops internal identifiers from the visible table', () {
      final ReportResult r = ReportResult.parse(<dynamic>[
        <String, dynamic>{
          '_id': 'xyz',
          '__v': 0,
          'orgId': 'org1',
          'distance': 5,
        },
      ]);

      expect(r.columns, isNot(contains('Id')));
      expect(r.columns, isNot(contains('Org Id')));
      expect(r.columns, contains('Distance'));
    });

    test('never throws on null or malformed payloads', () {
      expect(() => ReportResult.parse(null), returnsNormally);
      expect(() => ReportResult.parse('unexpected'), returnsNormally);
      expect(ReportResult.parse(null).isEmpty, isTrue);
    });
  });

  group('ReportType routing', () {
    test('every type maps to an /api/reports path', () {
      for (final ReportType t in ReportType.values) {
        if (t == ReportType.manualTrip) continue;
        expect(t.path, startsWith('/reports/'));
        expect(t.label, isNotEmpty);
        expect(t.blurb, isNotEmpty);
      }
    });

    test('parses ignition report payload with intervals, events and summary', () {
      final ReportResult r = ReportResult.parse(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'vehicleInfo': <String, dynamic>{
            'name': 'AP21TB3569',
            'plate': 'AP21TB3569',
          },
          'events': <dynamic>[
            <String, dynamic>{
              'time': '2026-10-29T00:00:00.000Z',
              'status': 'ON',
              'durationMs': 17947000,
              'lat': 16.785373,
              'lng': 75.740478,
            },
          ],
          'intervals': <dynamic>[
            <String, dynamic>{
              'status': 'ON',
              'startTime': '2026-10-29T00:00:00.000Z',
              'endTime': '2026-10-29T04:59:07.000Z',
              'durationMs': 17947000,
              'startLat': 16.785373,
              'startLng': 75.740478,
            },
          ],
          'summary': <String, dynamic>{
            'totalRunningMs': 17947000,
            'totalDistance': '190.00',
            'topSpeed': 66,
            'totalEvents': 1,
          },
        },
      });

      expect(r.rows.length, 1);
      expect(r.rows.first.isEngineOn, isTrue);
      expect(r.rows.first.durationSecVal, 17947);
      expect(r.summary.totalDurationSeconds, 17947);
      expect(r.summary.totalDistanceKm, 190.0);
    });

    test('route history and individual reports require a vehicle', () {
      expect(ReportType.routeHistory.requiresVehicle, isTrue);
      expect(ReportType.individual.requiresVehicle, isTrue);
      expect(ReportType.consolidated.requiresVehicle, isFalse);
    });
  });
}
