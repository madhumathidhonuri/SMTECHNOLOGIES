/// ─────────────────────────────────────────────────────────────────────
///  BACKEND CAPABILITY FLAGS
/// ─────────────────────────────────────────────────────────────────────
///
/// Probed live against `api.fueltracks.in` on 2026-07-28 (see
/// `docs/BACKEND_PROBE.md`). Several endpoints the original spec listed are
/// not deployed yet.
///
/// Rather than let the UI throw a red error for a route that simply does not
/// exist, each optional feature is gated here. The app degrades to an honest
/// "not enabled yet" state, and the day an endpoint ships you flip one bool —
/// no other code changes.
///
/// A `404` from any gated call is also caught defensively at the repository
/// layer, so an out-of-date flag can never crash a screen.
class BackendCapabilities {
  const BackendCapabilities._();

  // ── Confirmed present (verified 401 = exists, needs auth) ────────
  static const bool auth = true; // POST /auth/login, GET /auth/me
  static const bool profile = true; // GET/PUT /profile
  static const bool vehicles = true; // GET /vehicles
  static const bool reports = true; // GET /reports/*
  static const bool billing = true; // GET /billing/*
  static const bool forgotPassword = true; // POST /auth/forgot-password
  static const bool resetPassword = true; // POST /auth/reset-password
  static const bool logout = true; // POST /auth/logout
  static const bool socket = true; // /socket.io/ handshake OK

  // ── Confirmed absent (404) ───────────────────────────────────────

  /// `POST /api/auth/refresh` → 404.
  /// Without it a 401 is terminal: the interceptor must not retry-loop, it
  /// should sign the user out cleanly and send them to the login screen.
  static const bool refreshToken = false;

  /// `POST /api/auth/change-password` → 404. Option hidden in Settings.
  static const bool changePassword = false;

  /// `POST /api/auth/device-token` → 404.
  /// FCM still *receives* pushes; we just cannot register this device's token
  /// with the backend yet, so targeting is server-side only.
  static const bool deviceTokenRegistration = true;

  /// `GET /api/alerts` → Deployed and active with pagination and filters.
  static const bool alertsHistory = true;

  /// `GET /api/geofences` → 404 (if absent). Entry point now enabled.
  static const bool geofences = true;

  /// No documented account-deletion route yet, so the compliance flow falls
  /// back to its email path — which Apple accepts, as long as it is
  /// initiated in-app.
  static const bool accountDeletionEndpoint = false;
}
