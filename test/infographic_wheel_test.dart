import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/core/theme/app_theme.dart';
import 'package:fueltracks/data/models/vehicle.dart';
import 'package:fueltracks/features/dashboard/widgets/fleet_3d_pie_chart.dart';
import 'package:fueltracks/features/dashboard/widgets/stat_tiles.dart';
import 'package:fueltracks/providers/fleet_provider.dart';

void main() {
  group('FleetOverviewCard Widget Tests', () {
    testWidgets('renders inside FleetOverviewCard with 3D pie', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: FleetOverviewCard(),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 1200));

      expect(find.text('FLEET OVERVIEW'), findsOneWidget);
      // Renders 3D Isometric Pie Chart directly as the hero visualization
      expect(find.byType(Fleet3DPieChart), findsOneWidget);
    });
  });
}

