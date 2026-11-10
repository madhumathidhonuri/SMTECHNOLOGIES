# FuelTracks — Customer Fleet App

A production-ready Flutter rebuild of the FuelTracks customer experience,
replacing the legacy Capacitor/web wrapper. Native, Material 3, and built
strictly for the **Customer (End-User)** role.

> **Status:** `flutter analyze` → **0 issues**. `flutter test` → **34/34 passing**.
> Release compile verified.

---

## 1. Scope

**In scope (customer):** authentication, profile, dashboard, live map,
vehicle detail + playback, alerts, reports, geofences, renewals & billing.

**Explicitly excluded:** device onboarding, user/organisation management,
dealer or admin tooling. `AuthRepository._assertCustomer()` actively rejects
`admin` / `dealer` / `reseller` principals at login with a clear message
pointing them to the web console — the app cannot be accidentally shipped as
a half-built admin client.

---

## 2. Running it

```bash
flutter pub get

# Defaults already point at production, so this is enough:
flutter run

# …or override explicitly:
flutter run \
  --dart-define=API_BASE_URL=https://api.fueltracks.in \
  --dart-define=SOCKET_URL=https://api.fueltracks.in \
  --dart-define=ENV=development
```

Release build:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.fueltracks.in \
  --dart-define=SOCKET_URL=https://api.fueltracks.in \
  --dart-define=ENV=production
```

**No maps API key is required** — tiles come from OpenStreetMap.

### Before first run

| Step | What |
|------|------|
| 1 | Add `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` (both gitignored) |
| 2 | Apply the Google Services Gradle plugin in `android/app/build.gradle` |
| 3 | Enable Push Notifications + Background Modes → Remote notifications in Xcode capabilities |

Maps need no setup at all — no key, no billing account, no SDK init.

---

## 3. Architecture

```
lib/
├── core/
│   ├── config/          AppConfig — dart-define driven, no committed secrets
│   ├── network/         ApiClient (Dio) · AuthInterceptor (JWT + refresh) · ApiException
│   ├── realtime/        SocketService  ← battery contract lives here
│   ├── connectivity/    ConnectivityService (connectivity_plus)
│   ├── notifications/   PushService (FCM + local notifications)
│   ├── permissions/     PermissionService — store-compliant rationale sheets
│   ├── payments/        PaymentService interface + DummyPaymentService
│   ├── storage/         SecureStore (Keychain / EncryptedSharedPreferences)
│   ├── theme/           Colors · Typography · Spacing · Material 3 themes
│   ├── router/          go_router with auth redirect + FCM deep links
│   └── utils/           Fmt (all display formatting) · VehicleIcons
├── data/
│   ├── models/          Vehicle · AppUser · FleetAlert · Trip/TrackPoint ·
│   │                    Geofence · Report* · Billing  (+ json_utils)
│   └── repositories/    auth · vehicle · alert · report · geofence · billing
├── providers/           Riverpod: core · auth · fleet · lifecycle
├── features/            splash · auth · shell · dashboard · live_map ·
│                        vehicle · alerts · reports · geofences · billing · profile
└── shared/widgets/      GlassCard · SurfaceCard · StatusChip · states · banner
```

**State management:** Riverpod (`Notifier` / `Provider` / `StreamProvider`).
Repositories are pure and injectable, so every provider is overridable in tests.

---

## 4. The three constraints that shaped the code

### 4.1 Battery — the socket is never alive in the background

Enforced in exactly one place: `AppLifecycleObserver`
(`lib/providers/lifecycle_provider.dart`).

```
paused / hidden / detached
    └─→ socket.pauseForBackground()
          • reconnection flag disabled FIRST (so socket_io_client
            does not immediately redial)
          • transport closed
          • fleet controller detaches its listener + flush timer

resumed
    ├─ 1. GET /api/vehicles          ← authoritative REST re-sync
    ├─ 2. socket.resumeFromForeground()
    └─ 3. re-join org:{orgId} / vehicle:{id} rooms on connect
```

Details that matter in production:

* **Ordering is deliberate.** REST first, socket second. Reconnecting first
  races the HTTP response and can leave a marker at a stale position.
* `AppLifecycleState.inactive` is ignored — otherwise pulling down the
  notification shade would thrash the connection.
* Absences under 2 seconds skip the REST round-trip entirely.
* Because the socket is dead in background, **FCM is the only alert channel**
  — which is exactly why push is wired to a high-importance channel.

### 4.2 Offline — banner, never a blocked screen

`ConnectivityBanner` slides in under the status bar, is non-blocking, and
auto-confirms with a green "Back online" before dismissing.
`ConnectivityReconnector` resumes the socket and refetches when the network
returns. No SQLite report caching, per spec.

### 4.3 Payments — one swappable seam

Nothing above `PaymentService` knows which gateway is in use.

```dart
// Today
paymentServiceProvider → DummyPaymentService()

// Later — one line, zero UI changes
paymentServiceProvider.overrideWithValue(RazorpayPaymentService())
```

`DummyPaymentService` simulates a realistic authorisation delay and returns a
`PaymentResult` whose `toVerificationPayload()` is posted to
`/api/billing/renewal/verify`. **The client never treats a local success as
entitlement** — only the verify response extends a subscription.

---

## 5. Store compliance

| Requirement | Implementation |
|---|---|
| **Apple 5.1.1(v)** account deletion | `AccountDeletionSheet` — in-app, typed `DELETE` confirmation, discloses what is removed vs. legally retained, calls `/api/profile/delete-request`, with a mailto fallback so the button is never dead |
| **Location rationale** | `PermissionService` shows a purpose sheet *before* the OS dialog, with a real "Not now" |
| **No background location** | `ACCESS_BACKGROUND_LOCATION` is never requested; iOS declares `WhenInUse` only. Vehicle positions come from trackers via the API |
| **Background modes** | iOS declares `remote-notification` only — no `location`, no `fetch` |
| **Notification permission** | Requested contextually with a fleet-safety rationale, not on first launch |
| **Privacy / Terms** | Linked from Settings |

---

## 6. Performance decisions

| Concern | Approach |
|---|---|
| High-frequency socket frames | Updates land in a pending buffer, flushed on a 450 ms timer. 300 vehicles at 1 Hz → ~2 rebuilds/sec instead of 300 |
| Long lists | `ListView.builder` / `SliverList.builder` everywhere, keyed by vehicle id |
| Map at low zoom | O(n) grid clustering — deterministic, so clusters don't flicker between frames |
| Marker bitmaps | Drawn on canvas and memoised by (status, 15° heading bucket, selected) — a few unique rasters for the whole fleet |
| Vehicles going stale | A 30 s timer re-renders so `status` can flip to `offline` without any packet arriving |
| Camera churn | Sub-metre jitter ignored; follow mode suspends while the user is panning |
| Room hygiene | `vehicle:{id}` is left on detail-screen dispose so the server stops streaming |

---

## 7. Design system

Dark-first "night operations console": deep midnight surfaces so the map and
status colour carry the visual weight.

* **Sora** display/headline · **Inter** body · **JetBrains Mono** for telemetry
  (tabular figures so digits never jitter as values tick).
* Semantic status colour is defined once (`AppColors.forStatus`) and reused by
  the list, map markers, chips and detail header — they can never disagree.
* 4 pt spacing scale (`Gap`), shared radii (`Corners`), shared easing (`Motion`).
* Every component is themed centrally in `AppTheme`; feature widgets contain no
  hard-coded colours.

---

## 8. Endpoint coverage

| Area | Endpoints |
|---|---|
| Auth | `POST /auth/login` · `GET /auth/me` · `forgot-password` · `reset-password` · `change-password` · `logout` · `device-token` |
| Profile | `GET/PUT /profile` · `POST /profile/delete-request` |
| Vehicles | `GET /vehicles` · `/vehicles/:id` · `/:id/history` · `/:id/route` · `/:id/report` |
| Reports | `/trip` `/distance` `/activity` `/route-history` `/ignition` `/overspeeding` `/stoppages` `/consolidated` `/individual` |
| Geofences | `GET/POST /geofences` · `PUT/DELETE /geofences/:id` |
| Billing | `/billing/renewal-plans` · `/billing/vehicle-price/:id` · `/billing/renewal/verify` |
| Sockets | `fleet:update` `vehicle:update` `location:update` `alert:new` `geofence:event` · rooms `org:{orgId}` `vehicle:{vehicleId}` |

**Parsing is deliberately lenient.** Real fleet backends return `speed` as
`42.5` or `"42.5 km/h"`, ids as `_id` or `id`, and coordinates flat, nested,
or as GeoJSON `[lng, lat]`. `json_utils.dart` absorbs all of it, and
`Vehicle.fromJson` is unit-tested against every shape — including junk input,
which must never throw.

---

## 9. Tests

```bash
flutter test     # 34 passing
```

Covers the logic most likely to break silently in production:

* `vehicle_model_test` — flat / nested / GeoJSON parsing, string numerics,
  junk payloads, derived status transitions, `mergeLive` preserving metadata
  across partial socket frames, expiry maths
* `fleet_stats_test` — status bucketing, offline vehicles excluded from the
  overspeeding count, empty-fleet division safety
* `payment_service_test` — the swappable interface and the exact
  `/renewal/verify` payload shape
* `report_parsing_test` — bare list, enveloped, server-summary precedence,
  internal-id stripping, malformed input

---

## 10. Known follow-ups

1. `firebase_options.dart` via `flutterfire configure` (intentionally gitignored)
2. Real gateway implementation behind `PaymentService`
3. Release signing keystore (currently debug-signed)
4. App icon and splash artwork (`flutter_launcher_icons` / `flutter_native_splash`
   are configured in `pubspec.yaml` and need the source PNGs)
5. Crashlytics/Sentry — the hook is already in `FlutterError.onError`

---

## 11. App identity

| Field | Value |
|---|---|
| Display name | **FuelTracks** |
| Dart package | `fueltracks` |
| Android `applicationId` | `com.fueltracks.app` |
| Android namespace | `com.fueltracks.app` |
| iOS bundle id | `com.fueltracks.app` |
| Deep-link scheme | `fueltracks://reset?token=…` |
| FCM channels | `fueltracks_alerts` · `fueltracks_critical` |
| Secure-storage prefix | `ft_` |

**Renaming caveats, if this ships and is renamed again later:**

* `applicationId` / bundle id are **permanent once published** — the stores key
  the listing on them. Changing either creates a brand-new app and orphans
  existing installs.
* Notification channel ids are immutable per install. Renaming a channel on an
  upgrade silently creates a second one and users keep the old channel's
  settings, so an in-place rename would need a migration.
* The secure-storage prefix moved `vt_` → `ft_`. That is safe **only because
  this is pre-release** — on an installed base it would log every user out.
  A shipped rename needs a one-time read-old/write-new migration in
  `SecureStore`.

---

## 12. Maps — OpenStreetMap via flutter_map

Google Maps was removed entirely. `flutter_map` is the Flutter port of
Leaflet, so this is the Leaflet rendering model with native performance.

**Why this is better here, not just cheaper:**

* No API key, no billing account, no per-load quota, nothing to leak.
* Markers are **real Flutter widgets**, so heading is a true
  `Transform.rotate` instead of a bitmap snapped to a 15° bucket, and status
  colour comes straight from `AppColors` — the map and the list physically
  cannot disagree.
* Selection, labels and the overspeed badge animate with no extra rasters.

### Styles (`MapStyle`)

| Style | Source |
|---|---|
| Standard | `tile.openstreetmap.org` |
| Dark *(default)* | CARTO dark basemap — muted so vehicle colour dominates |
| Satellite | Esri World Imagery |
| Terrain | OpenTopoMap |

Switchable from the map's layers button and persisted per user.

### Two things that are legal/policy requirements, not polish

1. **Attribution.** ODbL requires visible credit; `OsmAttribution` renders a
   tappable credit on every map surface.
2. **User-Agent.** OSM's tile policy blocks generic UAs, so every tile
   request sends `AppConfig.tileUserAgent`.

`CancellableNetworkTileProvider` aborts tile fetches that scroll out of
view — a real bandwidth and battery win when panning a fleet map.

> **Scaling note:** the public OSM endpoint is fine for development and light
> use, but its policy discourages heavy commercial traffic. For a large fleet,
> point `MapStyle.standard` at a paid host (MapTiler, Thunderforest, Stadia)
> or your own tile server. That is a one-line URL change in `map_tiles.dart`.

---

## 13. Live backend — `api.fueltracks.in`

Probed against production before wiring; full results in
**`docs/BACKEND_PROBE.md`**. Three findings changed the code materially.

### Login takes `identifier`, not `email`

The single most important discovery — the previous client would have failed
**every** sign-in.

```
{"email":"…","password":"…"}       → VALIDATION_ERROR
{"identifier":"…","password":"…"}  → reaches the password check ✅
```

It accepts an email *or* a username, so the field is labelled
"Email or username" and no longer enforces email format — that would have
locked out username accounts.

### Error envelope is `{success, error, code}`

Not the `{message}` shape originally assumed. `ApiException` now reads
`error` and exposes `code` (`NO_TOKEN`, `VALIDATION_ERROR`,
`INVALID_CREDENTIALS`, `NOT_FOUND`).

### Several routes are not deployed

`/auth/refresh`, `/auth/change-password`, `/auth/device-token`, `/alerts`
and `/geofences` all return 404 (alerts and geofences were probed across
~15 path variants). Rather than show red errors, each is gated in
`lib/core/config/backend_capabilities.dart`:

| Missing route | Behaviour today | To enable |
|---|---|---|
| `/auth/refresh` | 401 is terminal → clean sign-out, no retry loop | `refreshToken = true` |
| `/auth/change-password` | Settings offers "Reset password" by email instead | `changePassword = true` |
| `/auth/device-token` | FCM token stored locally, registration skipped | `deviceTokenRegistration = true` |
| `/alerts` | "Alert history coming soon"; live socket alerts still show | `alertsHistory = true` |
| `/geofences` | Hidden from Settings | `geofences = true` |

Flip one bool per feature the day it ships. A 404 is also caught defensively
at the repository layer, so a stale flag can never crash a screen.

### Socket.io ✅

Handshake verified. Mounted at the **server root** (`/socket.io/`), not under
`/api` — `AppConfig.socketPath` encodes this, and a test locks it in so a
future "tidy-up" can't silently break real-time.
