# FuelTracks v1.0.0 — Install & Test

Signed release APKs, wired to **https://api.fueltracks.in**.

| File | Size | Use |
|---|---|---|
| `FuelTracks-v1.0.0-arm64.apk` | 22 MB | **Recommended** — every phone from ~2017 on |
| `FuelTracks-v1.0.0-arm32.apk` | 19 MB | Older 32-bit devices |
| `FuelTracks-v1.0.0-universal.apk` | 56 MB | Works anywhere; use if unsure |

## Install

1. Copy the APK to your phone (USB, Drive, or email to yourself).
2. Tap it → Android will ask to allow installs from this source → **Allow**.
3. The "unknown developer" warning is expected: this is signed with a
   self-signed release key, not a Play Store key.

Via adb:
```bash
adb install -r FuelTracks-v1.0.0-arm64.apk
```

## Verified in the shipped binary

```
package            com.fueltracks.app
label              FuelTracks
versionName        1.0.0
targetSdk          34
signing            v1 + v2 schemes ✓  (CN=FuelTracks, valid 30 years)
baked-in API       https://api.fueltracks.in
socket path        /socket.io
tiles              tile.openstreetmap.org, basemaps.cartocdn.com
Google Maps refs   0
```

**Permissions requested (7):**
`INTERNET`, `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS`, `VIBRATE`,
`WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, plus FCM's `c2dm.RECEIVE`.

No location permission at all — vehicle positions come from the trackers via
your API, so the app never reads the phone's GPS. No background location,
which is the most common Play Store rejection reason for fleet apps.

---

## What to test

### 1. Login — the critical path
Sign in with a real customer account.

Your backend expects an **`identifier`** field that accepts *either* an email
or a username, so the field is labelled "Email or username". This was found
by probing production; the earlier build sent `email` and would have failed
every login.

Expected failures look like clean red text, not a crash:
* wrong password → "Invalid email/username or password."
* offline → "No internet connection."

> **If login fails with a valid account, tell me the exact on-screen message.**
> That message is the server's own `error` string, so it pinpoints the issue
> immediately.

### 2. Dashboard
Vehicle count, the online ring, and the four status tiles (Moving / Idle /
Stopped / Offline). Tiles are tappable filters. Pull to refresh.

Status is derived client-side: no packet within 10 min → **Offline**;
ignition off → **Stopped**; ignition on + speed > 2 → **Moving**; otherwise
**Idle**. If your backend defines these differently, that rule is one place
in `vehicle.dart`.

### 3. Live map (OpenStreetMap)
Markers cluster at low zoom and split as you zoom in. Layers button switches
Dark / Standard / Satellite / Terrain. Tap a marker → live peek sheet →
Follow.

### 4. The battery rule — please actually try this
1. Open the live map, confirm the green **LIVE** pill.
2. Background the app for ~30 s.
3. Return.

Expected: the pill drops out on background (socket closed), then on resume
the app re-fetches `/api/vehicles` over HTTP **first** and only then
reconnects the socket. Ordering is deliberate — reconnecting first can race
the HTTP response and strand a marker at a stale position.

### 5. Reports
Eight report types, all confirmed live on your API. Date presets +
custom range, and CSV export via the share sheet.

### 6. Vehicle detail
Live / History / Info tabs. History replays the route with a scrubber and
1×–16× speed.

---

## Known gaps — not bugs

Probed live on 2026-07-28; these routes return **404**, so they are gated off
rather than showing errors (see `docs/BACKEND_PROBE.md`):

| Missing route | What you'll see |
|---|---|
| `GET /api/alerts` | "Alert history coming soon". Live socket alerts still appear in-session |
| `GET /api/geofences` | Geofences hidden from Settings |
| `POST /api/auth/change-password` | Settings offers "Reset password" by email instead |
| `POST /api/auth/refresh` | A 401 signs you out cleanly (no retry loop) |
| `POST /api/auth/device-token` | FCM token kept locally; not registered server-side |

Each is one boolean in `lib/core/config/backend_capabilities.dart` — flip it
the day the endpoint ships, no other change needed.

**Push notifications** need `google-services.json` before they work end to
end. The app runs fine without it; FCM init fails soft and is caught.

---

## If something breaks

Grab the log while reproducing:

```bash
adb logcat -c && adb logcat | grep -iE "flutter|fueltracks|socket|dio"
```

The most useful lines are prefixed `[socket]`, `[fleet]`, `[lifecycle]`
and `[push]`.
