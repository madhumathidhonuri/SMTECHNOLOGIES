import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/core/utils/formatters.dart';
import 'package:fueltracks/data/models/report_models.dart';
import 'package:fueltracks/features/reports/widgets/report_table_views.dart';
import 'package:fueltracks/features/reports/widgets/report_top_tabs.dart';

void main() {
  group('Web Report Formatters', () {
    test('formats dates, times and durations to match web app format', () {
      final DateTime dt = DateTime(2026, 8, 2, 16, 51, 34);
      expect(Fmt.dateWeb(dt), '02-08-2026');
      expect(Fmt.dateTimeWeb(dt), '02-08-2026 16:51:34');
      expect(Fmt.durationWeb(458), '00:07:38');
      expect(Fmt.durationWeb(21861), '06:04:21');
      expect(Fmt.durationWeb(0), '00:00:00');
      expect(Fmt.durationWeb(null), '00:00:00');
    });
  });

  group('ReportRow Typed Accessors', () {
    test('correctly extracts typed properties from raw backend JSON', () {
      final ReportRow row = ReportRow.fromJson(<String, dynamic>{
        'vehicle_name': 'Activa',
        'plate': 'TS07HH 4867',
        'org_name': 'FuelTracks',
        'start_time': '2026-08-02T16:51:34.000Z',
        'end_time': '2026-08-02T16:59:12.000Z',
        'start_lat': 17.4399,
        'start_lng': 78.4983,
        'end_lat': 17.4450,
        'end_lng': 78.5020,
        'duration_seconds': 458,
        'distance': 2.0,
        'max_speed': 31,
        'avg_speed': 10,
        'start_odometer': 4164,
        'end_odometer': 4183,
        'distance_travelled': 19,
        'point_count': 1226,
        'status': 'Parked',
        'driver_name': 'Ramesh',
        'driver_phone': '9876543210',
      });

      expect(row.vehicleName, 'Activa');
      expect(row.plate, 'TS07HH 4867');
      expect(row.orgName, 'FuelTracks');
      expect(row.startLat, 17.4399);
      expect(row.startLng, 78.4983);
      expect(row.endLat, 17.4450);
      expect(row.endLng, 78.5020);
      expect(row.durationSecVal, 458);
      expect(row.distanceTravelled, 19.0);
      expect(row.maxSpeedVal, 31.0);
      expect(row.avgSpeedVal, 10.0);
      expect(row.startOdometer, 4164.0);
      expect(row.endOdometer, 4183.0);
      expect(row.pointCount, 1226);
      expect(row.status, 'Parked');
      expect(row.driverName, 'Ramesh');
      expect(row.driverPhone, '9876543210');
    });
  });

  group('Report Widgets Rendering', () {
    testWidgets('ReportTopTabs renders all report tabs and highlights selected', (WidgetTester tester) async {
      ReportType selected = ReportType.trip;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportTopTabs(
              selectedType: selected,
              onTabSelected: (ReportType t) => selected = t,
            ),
          ),
        ),
      );

      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Day Wise Distance Report'), findsOneWidget);
      expect(find.text('Overspeeding'), findsOneWidget);
      expect(find.text('Stoppage'), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Consolidated'), findsOneWidget);
      expect(find.text('Individual'), findsOneWidget);

      await tester.tap(find.text('Day Wise Distance Report'));
      expect(selected, ReportType.distance);
    });

    testWidgets('TripReportTable renders 8 columns with data', (WidgetTester tester) async {
      final List<ReportRow> rows = <ReportRow>[
        ReportRow.fromJson(<String, dynamic>{
          'start_time': '2026-08-02T16:51:34.000Z',
          'end_time': '2026-08-02T16:59:12.000Z',
          'duration_seconds': 458,
          'distance': 2.0,
          'max_speed': 31,
          'avg_speed': 10,
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripReportTable(rows: rows),
          ),
        ),
      );

      expect(find.text('START TIME'), findsOneWidget);
      expect(find.text('START ADDRESS'), findsOneWidget);
      expect(find.text('END TIME'), findsOneWidget);
      expect(find.text('END ADDRESS'), findsOneWidget);
      expect(find.text('DURATION (HH:MM:SS)'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('MAX SPEED'), findsOneWidget);
      expect(find.text('AVG SPEED'), findsOneWidget);
      expect(find.text('00:07:38'), findsOneWidget);
    });

    testWidgets('DailyDistanceReportTable renders 8 columns with data', (WidgetTester tester) async {
      final List<ReportRow> rows = <ReportRow>[
        ReportRow.fromJson(<String, dynamic>{
          'vehicle_name': 'Activa',
          'plate': 'TS07HH 4867',
          'org_name': 'FuelTracks',
          'date': '2026-08-02T00:00:00.000Z',
          'start_odometer': 4164,
          'end_odometer': 4183,
          'distance_travelled': 19,
          'point_count': 1226,
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyDistanceReportTable(rows: rows),
          ),
        ),
      );

      expect(find.text('VEHICLE NAME'), findsOneWidget);
      expect(find.text('PLATE'), findsOneWidget);
      expect(find.text('ORG'), findsOneWidget);
      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('START ODOMETER'), findsOneWidget);
      expect(find.text('END ODOMETER'), findsOneWidget);
      expect(find.text('DISTANCE TRAVELLED (KM)'), findsOneWidget);
      expect(find.text('POINTS LOGGED'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('TS07HH 4867'), findsOneWidget);
      expect(find.text('19 km'), findsOneWidget);
      expect(find.text('1226'), findsOneWidget);
    });

    testWidgets('OverspeedingReportTable renders vehicle banner and overspeed columns', (WidgetTester tester) async {
      final List<ReportRow> rows = <ReportRow>[
        ReportRow.fromJson(<String, dynamic>{
          'vehicle_name': 'WINDSOR',
          'start_time': '2026-08-01T22:31:47.000Z',
          'max_speed': 72,
          'duration_seconds': 10,
          'driver_name': '-',
          'driver_phone': '-',
          'distance': 0.00,
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverspeedingReportTable(
              rows: rows,
              startDate: DateTime(2026, 7, 29),
              endDate: DateTime(2026, 8, 2),
            ),
          ),
        ),
      );

      expect(find.text('Vehicle Name : WINDSOR'), findsOneWidget);
      expect(find.text('Speed Limit : 60'), findsOneWidget);
      expect(find.text('OverSpeed'), findsOneWidget);
      expect(find.text('00:00:10'), findsOneWidget);
    });

    testWidgets('StoppageReportTable renders duration summary and parked rows', (WidgetTester tester) async {
      final List<ReportRow> rows = <ReportRow>[
        ReportRow.fromJson(<String, dynamic>{
          'vehicle_name': 'Activa',
          'status': 'Parked',
          'start_time': '2026-08-02T21:37:56.000Z',
          'end_time': '2026-08-02T21:40:46.000Z',
          'duration_seconds': 170,
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoppageReportTable(
              rows: rows,
              startDate: DateTime(2026, 7, 28),
              endDate: DateTime(2026, 8, 2),
            ),
          ),
        ),
      );

      expect(find.text('Vehicle Name : Activa'), findsOneWidget);
      expect(find.text('Moving : '), findsOneWidget);
      expect(find.text('Parked : '), findsOneWidget);
      expect(find.text('Idle : '), findsOneWidget);
      expect(find.text('00:02:50'), findsNWidgets(2)); // summary stat and table cell
    });

    testWidgets('IdleReportTable renders duration summary and idle rows', (WidgetTester tester) async {
      final List<ReportRow> rows = <ReportRow>[
        ReportRow.fromJson(<String, dynamic>{
          'vehicle_name': 'Activa',
          'status': 'Idle',
          'start_time': '2026-08-02T21:37:56.000Z',
          'end_time': '2026-08-02T21:39:47.000Z',
          'duration_seconds': 111,
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IdleReportTable(
              rows: rows,
              startDate: DateTime(2026, 7, 28),
              endDate: DateTime(2026, 8, 2),
            ),
          ),
        ),
      );

      expect(find.text('Vehicle Name : Activa'), findsOneWidget);
      expect(find.text('Idle : '), findsOneWidget); // summary badge label
      expect(find.text('Idle'), findsOneWidget); // table cell
      expect(find.text('00:01:51'), findsNWidgets(2)); // summary stat and table cell
    });

    testWidgets('IndividualReportTable renders exact web columns and metrics', (WidgetTester tester) async {
      final ReportResult parsed = ReportResult.parse(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{
          'vehicle': <String, dynamic>{'name': 'WINDSOR', 'plate': '-'},
          'activity': <String, dynamic>{
            'distance_travelled': 632,
            'running_seconds': 61080,
            'idle_seconds': 110520,
          },
          'summary': <String, dynamic>{
            'trip_count': 60,
            'stoppage_count': 352,
            'overspeeding_count': 120,
          },
        },
      });

      expect(parsed.rows.length, 1);
      final ReportRow row = parsed.rows.first;
      expect(row.vehicleName, 'WINDSOR');
      expect(row.runningMins, 1018);
      expect(row.idleMins, 1842);
      expect(row.tripCount, 60);
      expect(row.stoppageCount, 352);
      expect(row.overspeedingCount, 120);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndividualReportTable(rows: parsed.rows),
          ),
        ),
      );

      expect(find.text('WINDSOR'), findsOneWidget);
      expect(find.text('632 km'), findsOneWidget);
      expect(find.text('1018 mins'), findsOneWidget);
      expect(find.text('1842 mins'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('352'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
    });

    testWidgets('ConsolidatedReportTable renders whole-fleet columns', (WidgetTester tester) async {
      final List<ReportRow> rows = <ReportRow>[
        ReportRow.fromJson(<String, dynamic>{
          'vehicle_name': 'WINDSOR',
          'plate': '-',
          'distance_travelled': 632,
          'running_seconds': 61080,
          'idle_seconds': 110520,
          'stopped_seconds': 14700,
        }),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsolidatedReportTable(
              rows: rows,
              startDate: DateTime.now().subtract(const Duration(days: 1)),
              endDate: DateTime.now(),
              vehicles: const [],
            ),
          ),
        ),
      );

      expect(find.text('WINDSOR'), findsOneWidget);
      expect(find.text('632'), findsOneWidget);
      expect(find.text('1018'), findsOneWidget);
      expect(find.text('1842'), findsOneWidget);
      expect(find.text('245'), findsOneWidget);
    });
  });
}

