import 'package:flutter_test/flutter_test.dart';
import 'package:fueltracks/core/payments/payment_service.dart';

void main() {
  group('DummyPaymentService', () {
    test('returns a successful, verifiable result', () async {
      final DummyPaymentService gateway =
          DummyPaymentService(latency: Duration.zero);
      await gateway.initialize();

      final PaymentResult result = await gateway.pay(
        const PaymentRequest(
          amount: 1200,
          currency: 'INR',
          vehicleId: 'veh_1',
          planId: 'plan_12m',
          description: '12 month renewal',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.gateway, 'dummy');
      expect(result.transactionId, isNotNull);
      expect(result.transactionId, startsWith('DUMMY_'));
    });

    test('builds the exact /renewal/verify payload', () async {
      final DummyPaymentService gateway =
          DummyPaymentService(latency: Duration.zero);

      final PaymentResult result = await gateway.pay(
        const PaymentRequest(
          amount: 999.5,
          currency: 'INR',
          vehicleId: 'veh_9',
          planId: 'plan_6m',
          description: 'test',
        ),
      );

      final Map<String, dynamic> payload = result.toVerificationPayload(
        vehicleId: 'veh_9',
        planId: 'plan_6m',
        amount: 999.5,
      );

      expect(payload['vehicleId'], 'veh_9');
      expect(payload['planId'], 'plan_6m');
      expect(payload['amount'], 999.5);
      expect(payload['gateway'], 'dummy');
      expect(payload['status'], 'success');
      expect(payload['transactionId'], isNotNull);
      expect(payload.containsKey('gatewayResponse'), isTrue);
    });

    test('simulated failure is surfaced, not silently swallowed', () async {
      final DummyPaymentService gateway = DummyPaymentService(
        simulateFailure: true,
        latency: Duration.zero,
      );

      final PaymentResult result = await gateway.pay(
        const PaymentRequest(
          amount: 100,
          currency: 'INR',
          vehicleId: 'v',
          planId: 'p',
          description: 'd',
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, PaymentStatus.failed);
      expect(result.message, isNotNull);
    });

    test('any gateway satisfies the swappable interface', () {
      final PaymentService service = DummyPaymentService();
      expect(service, isA<PaymentService>());
      expect(service.isConfigured, isTrue);
      expect(service.gatewayName, isNotEmpty);
    });
  });
}
