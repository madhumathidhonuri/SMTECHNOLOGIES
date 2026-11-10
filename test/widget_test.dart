import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/core/theme/app_colors.dart';
import 'package:fueltracks/core/theme/app_theme.dart';
import 'package:fueltracks/data/models/vehicle.dart';
import 'package:fueltracks/features/profile/legal_document_sheet.dart';
import 'package:fueltracks/shared/widgets/app_states.dart';
import 'package:fueltracks/shared/widgets/status_chip.dart';

Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('Theme', () {
    test('both themes build and are Material 3', () {
      expect(AppTheme.dark().useMaterial3, isTrue);
      expect(AppTheme.light().useMaterial3, isTrue);
      expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
      expect(AppTheme.light().colorScheme.brightness, Brightness.light);
    });

    test('status colours are distinct so states are never ambiguous', () {
      final Set<int> colors = <int>{
        AppColors.forStatus('moving').value,
        AppColors.forStatus('idle').value,
        AppColors.forStatus('stopped').value,
        AppColors.forStatus('offline').value,
      };
      expect(colors.length, 4);
    });
  });

  group('StatusChip', () {
    testWidgets('renders the correct label for each status', (
      WidgetTester tester,
    ) async {
      for (final VehicleStatus status in VehicleStatus.values) {
        await tester.pumpWidget(wrap(StatusChip(status: status)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(status.label), findsOneWidget);
      }
    });

    testWidgets('animated moving chip does not leak its ticker', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const StatusChip(status: VehicleStatus.moving)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Replacing it must dispose the repeating controller cleanly.
      await tester.pumpWidget(
        wrap(const StatusChip(status: VehicleStatus.offline)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline'), findsOneWidget);
    });
  });

  group('States', () {
    testWidgets('EmptyState shows its action when provided', (
      WidgetTester tester,
    ) async {
      bool tapped = false;

      await tester.pumpWidget(
        wrap(
          EmptyState(
            icon: Icons.no_transfer_rounded,
            title: 'No vehicles yet',
            message: 'They will appear here automatically.',
            actionLabel: 'Refresh',
            onAction: () => tapped = true,
          ),
        ),
      );

      expect(find.text('No vehicles yet'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      expect(tapped, isTrue);
    });

    testWidgets('ErrorState exposes a retry affordance', (
      WidgetTester tester,
    ) async {
      bool retried = false;

      await tester.pumpWidget(
        wrap(
          ErrorState(
            message: 'No internet connection.',
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text('No internet connection.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });

  group('Legal Documents Sheet', () {
    testWidgets('renders Privacy Policy sheet properly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const LegalDocumentSheet(type: LegalDocumentType.privacyPolicy)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Information We Collect'), findsOneWidget);
    });

    testWidgets('renders Terms of Service sheet properly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const LegalDocumentSheet(type: LegalDocumentType.termsOfService)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('User Accounts & Access'), findsOneWidget);
    });
  });
}
