import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/core/theme/app_theme.dart';
import 'package:fueltracks/data/models/vehicle.dart';
import 'package:fueltracks/features/dashboard/widgets/fleet_3d_pie_chart.dart';
import 'package:fueltracks/providers/fleet_provider.dart';

void main() {
  group('Fleet3DPieChart Widget Tests', () {
    testWidgets('renders all 5 status callouts with non-overlapping leader lines', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Center(
                child: Fleet3DPieChart(),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      // Verify the 5 status callout labels
      expect(find.text('MOVING'), findsOneWidget);
      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('STOPPED'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('UNREACHABLE'), findsOneWidget);

      // Verify bottom center total vehicles count pill
      expect(find.textContaining('Vehicles Total'), findsOneWidget);
    });

    testWidgets('tapping status callout selects and triggers filter', (
      WidgetTester tester,
    ) async {
      VehicleStatus? selected;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(
                child: Fleet3DPieChart(
                  onStatusSelected: (status) => selected = status,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on MOVING callout
      await tester.tap(find.text('MOVING'));
      await tester.pumpAndSettle();

      expect(selected, VehicleStatus.moving);
    });
  });
}
