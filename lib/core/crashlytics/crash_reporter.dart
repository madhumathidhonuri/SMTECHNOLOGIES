import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../data/models/user.dart';

/// Central abstraction over Firebase Crashlytics.
///
/// Rules:
/// - NEVER log passwords, tokens, API keys, payment data, or PII.
/// - Use [log] for app lifecycle breadcrumbs, NOT for data values.
/// - Use [setUserContext] after login and [clearUserContext] after logout.
/// - [recordError] is for non-fatal exceptions only — fatal crashes are
///   captured automatically by the native crash handler.
///
/// Usage:
/// ```dart
/// // In a provider, repository, or widget
/// CrashReporter.log('Fetching vehicles for org $orgId');
/// CrashReporter.setScreen('live_map');
/// CrashReporter.recordError(e, st, reason: 'Vehicle fetch failed');
/// ```
class CrashReporter {
  CrashReporter._();

  static FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  // ── Initialisation ───────────────────────────────────────────────────────

  /// Called once from main() after Firebase.initializeApp().
  /// Enables collection only in production so dev/test noise never reaches
  /// the Crashlytics dashboard.
  static Future<void> init() async {
    final bool inProd = AppConfig.isProduction;
    await _c.setCrashlyticsCollectionEnabled(inProd);
    await _c.setCustomKey('app_environment', AppConfig.environment.name);
  }

  // ── Error capture ────────────────────────────────────────────────────────

  /// Reports a non-fatal exception to Crashlytics.
  ///
  /// [reason] appears as the "reason" field in the Crashlytics UI,
  /// helping distinguish where the error originated without embedding
  /// raw data into the message string.
  ///
  /// [fatal] should only be true when you are about to call [crash] or
  /// re-throw; setting it incorrectly inflates the crash-free-sessions %.
  static Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    try {
      await _c.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: fatal,
      );
    } catch (_) {
      // Never let the reporter itself crash the app.
    }
  }

  // ── Breadcrumb logs ──────────────────────────────────────────────────────

  /// Appends a breadcrumb string to the Crashlytics log.
  ///
  /// Logs appear in the Firebase Console under the crash report → Logs tab.
  /// Max 64 KB per session; old entries are dropped automatically.
  ///
  /// ✅ Good: 'Checkout flow started', 'Socket reconnect attempt 3'
  /// ❌ Never: tokens, passwords, email addresses, coordinates, payment info.
  static void log(String message) {
    if (!kIsWeb) {
      _c.log(message);
    }
  }

  // ── Custom keys (contextual metadata) ───────────────────────────────────

  /// Records the current screen/route name.
  /// Appears in the Crashlytics report as [key: screen].
  static Future<void> setScreen(String routeName) =>
      _c.setCustomKey('screen', routeName);

  /// Records which feature the user was using when the crash occurred.
  static Future<void> setFeature(String feature) =>
      _c.setCustomKey('feature', feature);

  /// Records a named operation (e.g. 'vehicle_fetch', 'report_export').
  static Future<void> setOperation(String operation) =>
      _c.setCustomKey('operation', operation);

  // ── User context ─────────────────────────────────────────────────────────

  /// Associates subsequent crash reports with an internal user identifier.
  ///
  /// We send only the opaque database ID and role — never name, email,
  /// phone, or any PII. Compliance: GDPR Art. 25 (data minimisation).
  static Future<void> setUserContext(AppUser user) async {
    try {
      await _c.setUserIdentifier(user.id);
      await _c.setCustomKey('user_role', user.role);
      await _c.setCustomKey('org_id', user.orgId);
    } catch (_) {}
  }

  /// Clears user context on logout so subsequent reports are anonymous.
  static Future<void> clearUserContext() async {
    try {
      await _c.setUserIdentifier('');
      await _c.setCustomKey('user_role', '');
      await _c.setCustomKey('org_id', '');
    } catch (_) {}
  }

  // ── Debug-only test trigger ──────────────────────────────────────────────

  /// Forces a native crash to verify the Crashlytics pipeline end-to-end.
  ///
  /// SAFETY: Only callable in non-production environments. In production
  /// this method is a no-op so a stray call can never take down the app.
  ///
  /// How to verify:
  /// 1. Run the app in RELEASE mode (not debug — Crashlytics only sends in release).
  /// 2. Call this method from a hidden debug menu or flutter test driver.
  /// 3. Reopen the app (the crash is sent on next launch).
  /// 4. Wait ~1 minute, then check Firebase Console → Crashlytics → Issues.
  static void testCrash() {
    assert(
      !AppConfig.isProduction,
      'testCrash() must never be called in production!',
    );
    if (!AppConfig.isProduction) {
      _c.crash();
    }
  }
}
