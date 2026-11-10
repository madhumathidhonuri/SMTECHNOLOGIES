import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/payments/payment_service.dart';
import '../models/billing.dart';
import '../models/json_utils.dart';

class BillingRepository {
  BillingRepository(this._api);

  final ApiClient _api;

  Future<List<RenewalPlan>> getPlans() async {
    final dynamic res = await _api.get<dynamic>('/billing/renewal-plans');
    return asMapList(res)
        .map(RenewalPlan.fromJson)
        .toList(growable: false);
  }

  Future<VehiclePrice> getVehiclePrice(String vehicleId) async {
    final dynamic res =
        await _api.get<dynamic>('/billing/vehicle-price/$vehicleId');
    final Map<String, dynamic> map =
        res is Map<String, dynamic> ? res : <String, dynamic>{};
    return VehiclePrice.fromJson(<String, dynamic>{
      'vehicleId': vehicleId,
      ...map,
    });
  }

  /// `POST /api/billing/renewal/verify`
  ///
  /// The **server** decides whether the renewal is real. A local
  /// [PaymentResult] is only evidence; entitlement comes from this response.
  Future<RenewalRecord> verifyRenewal({
    required PaymentResult payment,
    required String vehicleId,
    required String planId,
    required double amount,
  }) async {
    if (!payment.isSuccess) {
      throw ApiException(
        message: payment.message ?? 'Payment was not completed.',
      );
    }

    final dynamic res = await _api.post<dynamic>(
      '/billing/renewal/verify',
      body: payment.toVerificationPayload(
        vehicleId: vehicleId,
        planId: planId,
        amount: amount,
      ),
    );

    return RenewalRecord.fromJson(
      res is Map<String, dynamic> ? res : <String, dynamic>{},
    );
  }

  Future<List<RenewalRecord>> getHistory() async {
    try {
      final dynamic res = await _api.get<dynamic>('/billing/renewals');
      return asMapList(res).map(RenewalRecord.fromJson).toList(growable: false);
    } on ApiException catch (e) {
      if (e.isNotFound) return const <RenewalRecord>[];
      rethrow;
    }
  }
}
