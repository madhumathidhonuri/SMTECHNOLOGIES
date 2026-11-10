import '../../core/config/backend_capabilities.dart';
import '../../core/config/brand_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/notifications/push_service.dart';
import '../../core/storage/secure_store.dart';
import '../models/json_utils.dart';
import '../models/user.dart';

class AuthRepository {
  AuthRepository(this._api, this._store);

  final ApiClient _api;
  final SecureStore _store;

  /// `POST /api/auth/login` → persists JWT and returns the customer profile.
  ///
  /// IMPORTANT: this backend expects **`identifier`**, not `email`. Verified
  /// against production — sending `email` returns VALIDATION_ERROR
  /// ("Email/Username and password are required"), while `identifier`
  /// reaches the password check. It accepts an email *or* a username.
  ///
  /// Guardrail: this app is customer-only. If the backend returns an admin or
  /// dealer principal we refuse the session rather than rendering a half-built
  /// experience with missing screens.
  Future<AppUser> login({
    required String identifier,
    required String password,
  }) async {
    final String id = identifier.trim();

    final dynamic res = await _api.post<dynamic>(
      '/auth/login',
      body: <String, dynamic>{
        // Lower-case only when it looks like an email; usernames may be
        // case-sensitive server-side.
        'identifier': id.contains('@') ? id.toLowerCase() : id,
        'password': password,
      },
    );

    final Map<String, dynamic> payload = _asMap(res);

    final String? token = asStringOrNull(payload, <String>[
      'token', 'accessToken', 'jwt', 'authToken', 'access_token',
    ]);

    if (token == null || token.isEmpty) {
      throw const ApiException(
        message: 'Login succeeded but no session token was returned. '
            'Please contact support.',
      );
    }

    await _store.writeToken(token);

    final String? refresh =
        asStringOrNull(payload, <String>['refreshToken', 'refresh_token']);
    if (refresh != null) await _store.writeRefreshToken(refresh);

    AppUser user = AppUser.fromJson(payload);

    // Some backends omit the user object on login; fall back to /auth/me.
    if (user.id.isEmpty) {
      user = await me();
    }

    _assertCustomer(user);
    await _store.writeUser(user.toJson());
    return user;
  }

  /// `GET /api/auth/me` — validates the stored token on cold boot.
  Future<AppUser> me() async {
    final dynamic res = await _api.get<dynamic>('/auth/me');
    final AppUser user = AppUser.fromJson(_asMap(res));
    _assertCustomer(user);
    await _store.writeUser(user.toJson());
    return user;
  }

  Future<void> forgotPassword(String email) => _api.post<dynamic>(
        '/auth/forgot-password',
        body: <String, dynamic>{'email': email.trim().toLowerCase()},
      );

  Future<void> resetPassword({
    required String token,
    required String password,
  }) =>
      _api.post<dynamic>(
        '/auth/reset-password',
        body: <String, dynamic>{
          'token': token.trim(),
          'newPassword': password,
          'password': password,
        },
      );

  /// Not deployed yet (`/auth/change-password` → 404). Gated so the UI can
  /// hide the option rather than surface a confusing failure.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!BackendCapabilities.changePassword) {
      throw const ApiException(
        message: 'Changing your password in the app is not available yet. '
            'Use "Forgot password" to receive a reset link.',
        statusCode: 404,
      );
    }
    await _api.post<dynamic>(
      '/auth/change-password',
      body: <String, dynamic>{
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  /// Registers the FCM token so the backend can target this device.
  Future<void> registerDevice({
    required String fcmToken,
    required String platform,
  }) async {
    // `/auth/device-token` is not deployed (404) — skip silently.
    if (!BackendCapabilities.deviceTokenRegistration) {
      await _store.writeFcmToken(fcmToken);
      return;
    }
    try {
      await _api.post<dynamic>(
        '/alerts/fcm-token',
        body: <String, dynamic>{
          'fcmToken': fcmToken,
          'deviceInfo': <String, dynamic>{
            'platform': platform,
            'appVersion': '1.0.0',
          },
        },
      );
      await _store.writeFcmToken(fcmToken);
    } on ApiException {
      // Never block login because token registration failed.
    }
  }

  Future<void> unregisterDevice(String fcmToken) async {
    try {
      await _api.delete<dynamic>(
        '/alerts/fcm-token',
        body: <String, dynamic>{'fcmToken': fcmToken},
      );
    } on ApiException {/* best effort */}
  }

  /// Best-effort server logout, then a guaranteed local wipe.
  Future<void> logout() async {
    try {
      await _api.post<dynamic>('/auth/logout');
    } on ApiException {/* offline logout must still work */}
    await _store.clearSession();
    try {
      await PushService.clearLocalAlerts();
    } catch (_) {}
  }

  // ── Profile ──────────────────────────────────────────────────────

  Future<AppUser> getProfile() async {
    try {
      return await me();
    } catch (_) {
      final AppUser? cached = await cachedUser();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<AppUser> updateProfile({
    String? name,
    String? phone,
    String? timezone,
  }) async {
    final AppUser? current = await cachedUser();

    await _api.put<dynamic>(
      '/profile',
      body: <String, dynamic>{
        if (name != null) 'name': name,
        if (name != null) 'contact_person': name,
        if (phone != null) 'phone': phone,
        if (phone != null) 'mobile': phone,
        if (timezone != null) 'timezone': timezone,
      },
    );

    // Refresh canonical user state from server or merge with cached profile
    // to prevent blanking out email, orgName, or defaulting to "Customer".
    AppUser updated;
    try {
      updated = await me();
    } catch (_) {
      updated = (current ?? const AppUser(id: '', name: 'Customer', email: '')).copyWith(
        name: name,
        phone: phone,
        timezone: timezone,
      );
    }

    if (name != null && name.isNotEmpty && updated.name != name) {
      updated = updated.copyWith(name: name);
    }
    if (phone != null && updated.phone != phone) {
      updated = updated.copyWith(phone: phone);
    }
    if (timezone != null && updated.timezone != timezone) {
      updated = updated.copyWith(timezone: timezone);
    }

    await _store.writeUser(updated.toJson());
    return updated;
  }

  /// App Store Guideline 5.1.1(v) — in-app account deletion.
  ///
  /// Tries the real endpoint first; if the backend has not shipped it yet the
  /// caller falls back to a support-ticket flow, which Apple also accepts as
  /// long as it is initiated in-app.
  Future<void> requestAccountDeletion({String? reason}) async {
    await _api.post<dynamic>(
      '/profile/delete-request',
      body: <String, dynamic>{
        'reason': reason ?? 'User requested deletion from mobile app',
        'requestedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<AppUser?> cachedUser() async {
    final Map<String, dynamic>? raw = await _store.readUser();
    if (raw == null) return null;
    try {
      return AppUser.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasToken() async {
    final String? t = await _store.readToken();
    return t != null && t.isNotEmpty;
  }

  void _assertCustomer(AppUser user) {
    const Set<String> blocked = <String>{
      'admin', 'superadmin', 'super_admin', 'dealer', 'reseller', 'distributor',
    };
    if (blocked.contains(user.role)) {
      throw ApiException(
        message: 'This app is for fleet customers. Admin and dealer accounts '
            'should use the ${BrandConfig.appName} web console.',
        statusCode: 403,
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return <String, dynamic>{};
  }
}
