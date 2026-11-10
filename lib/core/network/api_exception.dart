import 'package:dio/dio.dart';

/// A single, user-presentable error type for the whole app.
///
/// Repositories never leak `DioException` upward — the UI only ever sees
/// an [ApiException] with a message that is safe to display verbatim.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.kind = ApiErrorKind.unknown,
    this.fieldErrors = const <String, String>{},
    this.code,
    this.raw,
  });

  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  /// Server-side validation errors keyed by field name.
  final Map<String, String> fieldErrors;

  /// Machine-readable code from the backend envelope, e.g. `NO_TOKEN`,
  /// `VALIDATION_ERROR`, `INVALID_CREDENTIALS`, `NOT_FOUND`.
  final String? code;
  final Object? raw;

  /// True when the route itself is missing — used to degrade gracefully for
  /// endpoints that are not deployed yet.
  bool get isMissingRoute => statusCode == 404 || code == 'NOT_FOUND';

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isNetwork => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  /// Whether a "Retry" affordance makes sense for this failure.
  bool get isRetryable =>
      isNetwork || kind == ApiErrorKind.server || statusCode == 429;

  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          message: 'The server took too long to respond. Please try again.',
          kind: ApiErrorKind.timeout,
          raw: e,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          message: 'No internet connection. Reconnect and try again.',
          kind: ApiErrorKind.network,
          raw: e,
        );
      case DioExceptionType.cancel:
        return ApiException(
          message: 'Request cancelled.',
          kind: ApiErrorKind.cancelled,
          raw: e,
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          message: 'Secure connection could not be verified.',
          kind: ApiErrorKind.network,
          raw: e,
        );
      case DioExceptionType.badResponse:
        return _fromResponse(e);
      case DioExceptionType.unknown:
      default:
        return ApiException(
          message: 'Something went wrong. Please try again.',
          kind: ApiErrorKind.unknown,
          raw: e,
        );
    }
  }

  static ApiException _fromResponse(DioException e) {
    final int? status = e.response?.statusCode;
    final dynamic body = e.response?.data;

    String message = switch (status ?? 0) {
      400 => 'That request was invalid.',
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You do not have access to this resource.',
      404 => 'We could not find what you were looking for.',
      409 => 'This action conflicts with existing data.',
      422 => 'Please correct the highlighted fields.',
      429 => 'Too many requests. Please slow down and retry shortly.',
      >= 500 => 'Our servers are having trouble. Please try again soon.',
      _ => 'Request failed. Please try again.',
    };

    final Map<String, String> fields = <String, String>{};

    String? code;

    if (body is Map) {
      final Object? rawCode = body['code'];
      if (rawCode is String && rawCode.isNotEmpty) code = rawCode;

      // fueltracks.in replies { success:false, error:"…", code:"…" }.
      final Object? m = body['error'] ?? body['message'] ?? body['msg'];
      if (m is String && m.trim().isNotEmpty) {
        message = m.trim();
      } else if (m is List && m.isNotEmpty) {
        message = m.first.toString();
      }

      final Object? errs = body['errors'];
      if (errs is Map) {
        errs.forEach((Object? k, Object? v) {
          if (v is String) {
            fields[k.toString()] = v;
          } else if (v is List && v.isNotEmpty) {
            fields[k.toString()] = v.first.toString();
          } else if (v is Map && v['message'] != null) {
            fields[k.toString()] = v['message'].toString();
          }
        });
      } else if (errs is List) {
        for (final Object? item in errs) {
          if (item is Map && item['param'] != null) {
            fields[item['param'].toString()] =
                (item['msg'] ?? item['message'] ?? '').toString();
          }
        }
      }
    }

    return ApiException(
      message: message,
      statusCode: status,
      kind: (status ?? 0) >= 500 ? ApiErrorKind.server : ApiErrorKind.client,
      fieldErrors: fields,
      code: code,
      raw: e,
    );
  }

  factory ApiException.offline() => const ApiException(
        message: 'You are offline. Connect to the internet to continue.',
        kind: ApiErrorKind.network,
      );

  @override
  String toString() => 'ApiException($statusCode, $kind): $message';
}

enum ApiErrorKind { network, timeout, client, server, cancelled, unknown }
