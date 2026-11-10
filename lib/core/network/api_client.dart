import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Thin, typed wrapper over Dio.
///
/// Responsibilities:
///  * one configured [Dio] for the whole app
///  * JWT injection + refresh (see [AuthInterceptor])
///  * envelope unwrapping — the backend replies either as a bare payload or
///    as `{ success, data, message }`; callers always get the payload
///  * `DioException` → [ApiException] translation
class ApiClient {
  ApiClient._(this._dio);

  final Dio _dio;
  Dio get raw => _dio;

  factory ApiClient.create({
    required SecureStore store,
    required Future<void> Function() onSessionExpired,
  }) {
    final BaseOptions options = BaseOptions(
      baseUrl: AppConfig.apiRoot,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      responseType: ResponseType.json,
      headers: <String, dynamic>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Client': 'fueltracks-flutter',
        'X-Client-Platform': defaultTargetPlatform.name,
      },
      // We inspect non-2xx ourselves so validation bodies survive.
      validateStatus: (int? s) => s != null && s >= 200 && s < 300,
    );

    final Dio dio = Dio(options);
    final Dio tokenDio = Dio(options); // interceptor-free, for refresh/replay

    dio.interceptors.add(
      AuthInterceptor(
        store: store,
        tokenDio: tokenDio,
        onSessionExpired: onSessionExpired,
      ),
    );

    if (AppConfig.isDebugLoggingEnabled) {
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: false,
          requestBody: true,
          responseBody: false,
          responseHeader: false,
          compact: true,
          maxWidth: 100,
        ),
      );
    }

    return ApiClient._(dio);
  }

  // ── Verbs ────────────────────────────────────────────────────────
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _guard<T>(() => _dio.get<dynamic>(
            path,
            queryParameters: _clean(query),
            cancelToken: cancelToken,
          ));

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) =>
      _guard<T>(() => _dio.post<dynamic>(
            path,
            data: body,
            queryParameters: _clean(query),
            cancelToken: cancelToken,
          ));

  Future<T> put<T>(
    String path, {
    Object? body,
    CancelToken? cancelToken,
  }) =>
      _guard<T>(() => _dio.put<dynamic>(
            path,
            data: body,
            cancelToken: cancelToken,
          ));

  Future<T> patch<T>(String path, {Object? body}) =>
      _guard<T>(() => _dio.patch<dynamic>(path, data: body));

  Future<T> delete<T>(String path, {Object? body}) =>
      _guard<T>(() => _dio.delete<dynamic>(path, data: body));

  // ── Internals ────────────────────────────────────────────────────
  Future<T> _guard<T>(Future<Response<dynamic>> Function() run) async {
    try {
      final Response<dynamic> res = await run();
      return _unwrap<T>(res.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(message: 'Unexpected error: $e', raw: e);
    }
  }

  /// Unwraps `{ success: true, data: {...} }` envelopes while passing bare
  /// payloads straight through.
  T _unwrap<T>(dynamic data) {
    if (data == null) return null as T;

    if (data is Map<String, dynamic>) {
      final bool looksEnveloped = data.containsKey('data') &&
          (data.containsKey('success') ||
              data.containsKey('status') ||
              data.containsKey('message')) &&
          data.length <= 4;

      if (looksEnveloped) {
        final Object? inner = data['data'];
        if (inner is T) return inner;
        return inner as T;
      }
    }

    if (data is T) return data;
    return data as T;
  }

  /// Drops null/empty query params so URLs stay clean.
  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final Map<String, dynamic> out = <String, dynamic>{};
    q.forEach((String k, dynamic v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      out[k] = v;
    });
    return out.isEmpty ? null : out;
  }
}
