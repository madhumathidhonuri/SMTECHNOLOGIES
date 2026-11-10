import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../config/backend_capabilities.dart';
import '../storage/secure_store.dart';

/// Attaches `Authorization: Bearer <JWT>` to every `/api/*` request and
/// centrally handles session expiry.
///
/// On a 401 the interceptor attempts **one** silent refresh (if the backend
/// issued a refresh token) and replays the original request. Concurrent 401s
/// are coalesced behind a single refresh future so we never fire N refresh
/// calls when a dashboard makes N parallel requests.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required SecureStore store,
    required Dio tokenDio,
    required Future<void> Function() onSessionExpired,
  })  : _store = store,
        _tokenDio = tokenDio,
        _onSessionExpired = onSessionExpired;

  final SecureStore _store;

  /// A bare Dio (no interceptors) used only for the refresh call, to avoid
  /// an infinite interceptor loop.
  final Dio _tokenDio;
  final Future<void> Function() _onSessionExpired;

  Future<String?>? _refreshInFlight;

  /// Endpoints that must never carry a stale Authorization header.
  static const Set<String> _anonymousPaths = <String>{
    '/auth/login',
    '/auth/forgot-password',
    '/auth/reset-password',
    '/auth/refresh',
  };

  bool _isAnonymous(String path) =>
      _anonymousPaths.any((String p) => path.contains(p));

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_isAnonymous(options.path)) {
      final String? token = await _store.readToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    options.headers.putIfAbsent('Accept', () => 'application/json');
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions req = err.requestOptions;
    final bool is401 = err.response?.statusCode == 401;
    final bool alreadyRetried = req.extra['__retried__'] == true;

    if (!is401 || alreadyRetried || _isAnonymous(req.path)) {
      return handler.next(err);
    }

    // This deployment has no `/auth/refresh` (verified 404). A 401 is
    // therefore terminal — sign out immediately rather than burn a retry
    // round-trip on a route that cannot exist.
    if (!BackendCapabilities.refreshToken) {
      await _onSessionExpired();
      return handler.next(err);
    }

    final String? newToken = await _refreshToken();

    if (newToken == null) {
      await _onSessionExpired();
      return handler.next(err);
    }

    try {
      req.extra['__retried__'] = true;
      req.headers['Authorization'] = 'Bearer $newToken';

      final Response<dynamic> clone = await _tokenDio.fetch<dynamic>(req);
      return handler.resolve(clone);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// Coalesced refresh — many callers, one network round-trip.
  Future<String?> _refreshToken() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String?> _performRefresh() async {
    final String? refresh = await _store.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return null;

    try {
      final Response<dynamic> res = await _tokenDio.post<dynamic>(
        '${AppConfig.apiRoot}/auth/refresh',
        data: <String, dynamic>{'refreshToken': refresh},
        options: Options(headers: <String, dynamic>{'Accept': 'application/json'}),
      );

      final dynamic body = res.data;
      final Map<String, dynamic> payload = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
              ? body['data'] as Map<String, dynamic>
              : body)
          : <String, dynamic>{};

      final String? token =
          (payload['token'] ?? payload['accessToken']) as String?;
      final String? nextRefresh = payload['refreshToken'] as String?;

      if (token == null || token.isEmpty) return null;

      await _store.writeToken(token);
      if (nextRefresh != null && nextRefresh.isNotEmpty) {
        await _store.writeRefreshToken(nextRefresh);
      }
      return token;
    } catch (_) {
      return null;
    }
  }
}
