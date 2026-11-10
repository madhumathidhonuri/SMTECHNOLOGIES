import 'package:equatable/equatable.dart';

import 'json_utils.dart';

class RenewalPlan extends Equatable {
  const RenewalPlan({
    required this.id,
    required this.name,
    required this.durationMonths,
    required this.price,
    this.currency = 'INR',
    this.description,
    this.features = const <String>[],
    this.isPopular = false,
    this.discountPercent,
  });

  final String id;
  final String name;
  final int durationMonths;
  final double price;
  final String currency;
  final String? description;
  final List<String> features;
  final bool isPopular;
  final double? discountPercent;

  double get pricePerMonth => durationMonths > 0 ? price / durationMonths : price;

  String get durationLabel {
    if (durationMonths % 12 == 0 && durationMonths >= 12) {
      final int y = durationMonths ~/ 12;
      return y == 1 ? '1 Year' : '$y Years';
    }
    return durationMonths == 1 ? '1 Month' : '$durationMonths Months';
  }

  factory RenewalPlan.fromJson(Map<String, dynamic> json) => RenewalPlan(
        id: asString(json, <String>['_id', 'id', 'planId']),
        name: asString(json, <String>['name', 'title', 'planName'],
            fallback: 'Renewal Plan'),
        durationMonths: asInt(
            json, <String>['durationMonths', 'months', 'duration', 'validity'],
            fallback: 12),
        price: asDouble(json, <String>['price', 'amount', 'cost', 'rate']),
        currency: asString(json, <String>['currency', 'currencyCode'], fallback: 'INR'),
        description: asStringOrNull(json, <String>['description', 'subtitle']),
        features: (json['features'] is List)
            ? (json['features'] as List<dynamic>)
                .map((dynamic e) => e.toString())
                .toList()
            : const <String>[],
        isPopular: asBool(json, <String>['isPopular', 'popular', 'recommended']),
        discountPercent: asDoubleOrNull(json, <String>['discount', 'discountPercent']),
      );

  @override
  List<Object?> get props => <Object?>[id, name, durationMonths, price];
}

class VehiclePrice extends Equatable {
  const VehiclePrice({
    required this.vehicleId,
    required this.amount,
    this.currency = 'INR',
    this.taxAmount = 0,
    this.taxPercent = 0,
    this.expiryDate,
    this.planId,
  });

  final String vehicleId;
  final double amount;
  final String currency;
  final double taxAmount;
  final double taxPercent;
  final DateTime? expiryDate;
  final String? planId;

  double get total => amount + taxAmount;

  factory VehiclePrice.fromJson(Map<String, dynamic> json) => VehiclePrice(
        vehicleId: asString(json, <String>['vehicleId', 'vehicle', '_id']),
        amount: asDouble(json, <String>['price', 'amount', 'basePrice', 'subtotal']),
        currency: asString(json, <String>['currency'], fallback: 'INR'),
        taxAmount: asDouble(json, <String>['tax', 'taxAmount', 'gst']),
        taxPercent: asDouble(json, <String>['taxPercent', 'gstPercent'], fallback: 18),
        expiryDate: asDate(json, <String>['expiryDate', 'expiresAt', 'validTill']),
        planId: asStringOrNull(json, <String>['planId', 'plan']),
      );

  @override
  List<Object?> get props => <Object?>[vehicleId, amount, taxAmount];
}

class RenewalRecord extends Equatable {
  const RenewalRecord({
    required this.id,
    required this.vehicleName,
    required this.amount,
    this.status = 'success',
    this.paidAt,
    this.newExpiryDate,
    this.invoiceUrl,
    this.transactionId,
  });

  final String id;
  final String vehicleName;
  final double amount;
  final String status;
  final DateTime? paidAt;
  final DateTime? newExpiryDate;
  final String? invoiceUrl;
  final String? transactionId;

  factory RenewalRecord.fromJson(Map<String, dynamic> json) => RenewalRecord(
        id: asString(json, <String>['_id', 'id', 'renewalId']),
        vehicleName: asString(
            json, <String>['vehicleName', 'vehicleNumber', 'registrationNumber'],
            fallback: 'Vehicle'),
        amount: asDouble(json, <String>['amount', 'total', 'price']),
        status: asString(json, <String>['status', 'state'], fallback: 'success'),
        paidAt: asDate(json, <String>['paidAt', 'createdAt', 'date']),
        newExpiryDate: asDate(json, <String>['newExpiryDate', 'expiryDate', 'validTill']),
        invoiceUrl: asStringOrNull(json, <String>['invoiceUrl', 'invoice', 'receiptUrl']),
        transactionId:
            asStringOrNull(json, <String>['transactionId', 'txnId', 'paymentId']),
      );

  @override
  List<Object?> get props => <Object?>[id, vehicleName, amount, status, paidAt];
}
