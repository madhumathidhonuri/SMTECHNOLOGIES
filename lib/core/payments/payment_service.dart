import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────────────
///  MODULAR PAYMENT ABSTRACTION
/// ─────────────────────────────────────────────────────────────────────
///
/// The gateway is undecided, so nothing above this file knows which provider
/// is in use. Renewal flow always talks to [PaymentService]; swapping in
/// Razorpay/Stripe/PayU later means writing one new implementation and
/// changing a single provider override — zero UI changes.
///
/// Contract: a gateway returns a [PaymentResult]; on success the caller
/// posts it to `/api/billing/renewal/verify` for server-side confirmation.
/// The client NEVER treats a local success as an entitlement.

class PaymentRequest {
  const PaymentRequest({
    required this.amount,
    required this.currency,
    required this.vehicleId,
    required this.planId,
    required this.description,
    this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.orderId,
    this.metadata = const <String, dynamic>{},
  });

  final double amount;
  final String currency;
  final String vehicleId;
  final String planId;
  final String description;
  final String? customerName;
  final String? customerEmail;
  final String? customerPhone;

  /// Server-created order id, when the backend pre-creates one.
  final String? orderId;
  final Map<String, dynamic> metadata;
}

enum PaymentStatus { success, failed, cancelled, pending }

class PaymentResult {
  const PaymentResult({
    required this.status,
    required this.gateway,
    this.transactionId,
    this.orderId,
    this.signature,
    this.message,
    this.rawResponse = const <String, dynamic>{},
  });

  final PaymentStatus status;
  final String gateway;
  final String? transactionId;
  final String? orderId;
  final String? signature;
  final String? message;
  final Map<String, dynamic> rawResponse;

  bool get isSuccess => status == PaymentStatus.success;

  /// Exactly the body `/api/billing/renewal/verify` expects.
  Map<String, dynamic> toVerificationPayload({
    required String vehicleId,
    required String planId,
    required double amount,
  }) =>
      <String, dynamic>{
        'vehicleId': vehicleId,
        'planId': planId,
        'amount': amount,
        'gateway': gateway,
        'status': status.name,
        'transactionId': transactionId,
        'orderId': orderId,
        if (signature != null) 'signature': signature,
        'gatewayResponse': rawResponse,
      };

  factory PaymentResult.cancelled(String gateway) => PaymentResult(
        status: PaymentStatus.cancelled,
        gateway: gateway,
        message: 'Payment cancelled.',
      );

  factory PaymentResult.failure(String gateway, String message) =>
      PaymentResult(
        status: PaymentStatus.failed,
        gateway: gateway,
        message: message,
      );
}

/// The single seam every gateway must implement.
abstract class PaymentService {
  String get gatewayName;

  /// True once SDK keys are configured. The UI shows a "coming soon" state
  /// rather than a broken checkout when this is false.
  bool get isConfigured;

  Future<void> initialize();

  /// Presents whatever UI the gateway needs and resolves with the outcome.
  Future<PaymentResult> pay(PaymentRequest request);

  void dispose();
}

/// Ships today. Simulates a realistic authorisation round-trip so the whole
/// renewal → verify → refresh pipeline is exercised end-to-end in QA.
class DummyPaymentService implements PaymentService {
  DummyPaymentService({this.simulateFailure = false, this.latency = const Duration(milliseconds: 2200)});

  /// Flip in debug builds to exercise the failure UI.
  final bool simulateFailure;
  final Duration latency;

  final Random _random = Random();

  @override
  String get gatewayName => 'dummy';

  @override
  bool get isConfigured => true;

  @override
  Future<void> initialize() async {
    debugPrint('[payments] DummyPaymentService ready (no real charges)');
  }

  @override
  Future<PaymentResult> pay(PaymentRequest request) async {
    debugPrint(
      '[payments] simulating ${request.currency} ${request.amount} '
      'for vehicle ${request.vehicleId}',
    );

    await Future<void>.delayed(latency);

    if (simulateFailure) {
      return PaymentResult.failure(
        gatewayName,
        'Your card was declined by the issuing bank. Please try another card.',
      );
    }

    final String txn = 'DUMMY_${DateTime.now().millisecondsSinceEpoch}_'
        '${_random.nextInt(9999).toString().padLeft(4, '0')}';

    return PaymentResult(
      status: PaymentStatus.success,
      gateway: gatewayName,
      transactionId: txn,
      orderId: request.orderId ?? 'ORDER_${_random.nextInt(999999)}',
      signature: 'sim_${txn.hashCode.abs()}',
      message: 'Simulated payment authorised.',
      rawResponse: <String, dynamic>{
        'simulated': true,
        'amount': request.amount,
        'currency': request.currency,
        'capturedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  @override
  void dispose() {}
}

// ── Template for the real integration ────────────────────────────────
//
// Drop-in skeleton kept in-tree so the eventual switch is mechanical:
//
//   class RazorpayPaymentService implements PaymentService {
//     @override String get gatewayName => 'razorpay';
//     @override bool get isConfigured => _keyId.isNotEmpty;
//
//     @override Future<PaymentResult> pay(PaymentRequest r) async {
//       // 1. POST /api/billing/renewal/order  -> { orderId }
//       // 2. _razorpay.open({ key, amount, order_id, prefill })
//       // 3. Complete a Completer<PaymentResult> from the SDK callbacks
//       // 4. Return; caller posts the result to /renewal/verify
//     }
//   }
//
// Then override the provider:
//   paymentServiceProvider.overrideWithValue(RazorpayPaymentService())
