# Live probe — `api.fueltracks.in`

Probed 2026-07-28 against the production host. `401` means the route **exists**
but needs a token; `404` means it genuinely is not mounted.

Server: `nginx/1.28.3 (Ubuntu)` → Express + Helmet. Valid TLS. CORS with
credentials enabled.

## Response envelope

Errors are **not** the `{ message }` shape I originally assumed:

```json
{ "success": false, "error": "Authentication required. No token provided.", "code": "NO_TOKEN" }
```

Codes seen: `NO_TOKEN`, `VALIDATION_ERROR`, `INVALID_CREDENTIALS`, `NOT_FOUND`.
`ApiException` now reads `error` first and keeps `code` for programmatic checks.

## Login takes `identifier`, not `email`

This was the single most important find — the original client would have failed
every sign-in.

| Body | Result |
|---|---|
| `{"email":"…","password":"…"}` | `VALIDATION_ERROR` — "Email/Username and password are required." |
| `{"username":"…","password":"…"}` | `VALIDATION_ERROR` |
| `{"identifier":"…","password":"…"}` | `INVALID_CREDENTIALS` ✅ — reached the password check |

So the field is `identifier` and it accepts **either an email or a username**.
The login screen was relabelled accordingly and no longer forces email-format
validation.

## Route inventory

### Present (401 = exists)
```
POST /api/auth/login              GET  /api/auth/me
POST /api/auth/logout             POST /api/auth/forgot-password   (400: "Email is required")
POST /api/auth/reset-password     (400: "Token and new password are required")
GET  /api/profile
GET  /api/vehicles                (router prefix confirmed)
GET  /api/reports/trip · /distance · /route-history · /overspeeding
     /stoppages · /ignition · /activity · /consolidated
GET  /api/billing/…               (renewal-plans, renewals, renewal/verify)
```

### Absent (404)
```
POST /api/auth/refresh            ← no refresh-token flow
POST /api/auth/change-password
POST /api/auth/device-token       ← no FCM token registration yet
GET  /api/alerts                  ← and /alert /notifications /events /alarms …
GET  /api/geofences               ← and /geofence /zones /areas …
```

Alerts and geofences were probed across ~15 path variants (including
non-`/api` roots). They are not deployed.

## Socket.io ✅

```
GET https://api.fueltracks.in/socket.io/?EIO=4&transport=polling
→ 200 {"sid":"…","upgrades":["websocket"],"pingInterval":25000,"pingTimeout":20000}
```

Mounted at the **root** path (`/socket.io/`), not under `/api`. Websocket
upgrade is offered, which is what `SocketService` requests directly.

## How the app was adapted

| Finding | Handling |
|---|---|
| `identifier` login field | `AuthRepository.login` sends `identifier`; UI relabelled "Email or username" |
| `{success,error,code}` envelope | `ApiException` parses `error` + exposes `code` |
| No `/auth/refresh` | Interceptor detects a missing refresh route and goes straight to a clean logout instead of retry-looping |
| No `/auth/change-password` | Hidden behind `BackendCapabilities.changePassword` |
| No `/auth/device-token` | FCM registration is best-effort and silently skipped |
| No `/alerts` | Alerts tab shows a "not enabled yet" state instead of a red error; socket `alert:new` still renders live in-session |
| No `/geofences` | Geofences entry hidden from Settings |

All gated by `lib/core/config/backend_capabilities.dart` — flip one flag per
feature the day the endpoint ships.
