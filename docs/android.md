# ScanIt for Android

Status: specification only. The build starts in BACKLOG phase P8, after iOS is on the App Store and
the strangers gate (P2) has passed. The Android app is a **port of the same product**, not a
redesign: the same flows (`DESIGN.md`), the same insights definitions, and the same API (`docs/api.md`).

Reference code in this workspace: `apps/skyvisor/skyvisor-android` (Kotlin + Compose). Skyvisor
is frozen, so read it only; do not change it.

## Stack

| Concern | Choice | iOS equivalent |
| --- | --- | --- |
| Language / UI | Kotlin, Jetpack Compose, Material 3 (dynamic colour off, so the limit colours stay fixed) | Swift, SwiftUI |
| Min / target SDK | minSdk 26. targetSdk = whatever Google Play requires at release time | iOS 18+ |
| Camera | CameraX `ImageAnalysis` | DataScannerViewController |
| Barcode | ML Kit `barcode-scanning`, bundled model (works offline, no Play Services download wait). Formats EAN-13, EAN-8, UPC-A, UPC-E, Code 128, QR | `.barcode(symbologies:)` |
| Shelf price | ML Kit `text-recognition` (Latin, on-device). Run both detectors on the same frame with `MlKitAnalyzer` | `.text()` |
| Local DB | Room (same tables and columns as SwiftData, see `ARCHITECTURE.md`), money as `Long` minor units | SwiftData |
| State | ViewModel + `StateFlow`, Hilt for DI | `@Observable` |
| Network | Ktor client or Retrofit + kotlinx.serialization, generated from `openapi.yaml` (openapi-generator `kotlin`) | swift-openapi-generator |
| Sync | WorkManager: a periodic worker plus a one-off worker on trip finish, with a network constraint | `SyncEngine` |
| Secrets on device | EncryptedSharedPreferences, or DataStore + Keystore | Keychain |
| Charts | Vico (Compose) | Swift Charts |
| Analytics / crash | PostHog Android + Sentry Android, same event names | PostHog + Sentry |
| Purchases | Play Billing one-time product "ScanIt Unlimited", same free-tier limits, entitlement cached for offline | StoreKit 2 non-consumable |
| Connectivity | `ConnectivityManager.NetworkCallback` triggers a one-off sync worker. Workers use the `NetworkType.CONNECTED` constraint and exponential backoff | `NWPathMonitor` + `BGAppRefreshTask` |
| Limit while locked | Ongoing notification showing total, limit and remaining. On Android 16+, use the progress-style "Live Update" notification | Live Activity |

## Shared logic

Port these pure functions, with the **same test vectors** as iOS. Keep the vectors as JSON
fixtures in `scanit-core/Fixtures/`, so both platforms run the same cases:

- barcode normaliser: GTIN-14, GS1 Digital Link, in-store 2x prefixes
- price parser: locale money patterns, largest-glyph ranking, nearness to the barcode box, unit-price rejection, multi-buy flagging (never prefilled), superscript-cents merge, prefill threshold (`Fixtures/prices.json`; items may carry a `box`, vectors a `barcode`)
- limit maths: `LimitStatus` / `LimitState.feedback` (80 % near, > 100 % over, haptic only on upward crossings)
- insights calculator: INS-01 … INS-10

## Auth

- **Google:** Credential Manager with `GetGoogleIdOption` (Sign in with Google). Send the ID token to `POST /v1/auth/google`. The server accepts the Android client ID as `aud`.
- **Apple:** there is no native SDK on Android. The flow:
  1. Open `GET /v1/auth/apple/start` in a Custom Tab.
  2. Apple `form_post`s to `/v1/auth/apple/callback`.
  3. The server redirects to an App Link (`https://{{domain}}/auth/done?code=…`).
  4. The app exchanges the code at `POST /v1/auth/exchange`.

  This needs an Apple **Services ID** and a return URL configured in the Apple developer portal. The web stats page (P9) uses the same Services ID.
- **Account deletion:** in-app, and Google Play also requires a public web URL (`{{domain}}/delete-account`, built in P5).

## Play Store release checklist

- Data safety form:
  - collected: account email (if signed in), shopping data (prices, products, stores)
  - shared: none
  - encrypted in transit: yes
  - deletion: yes
- Account deletion URL.
- Privacy policy URL (from P5).
- Camera permission rationale string, and a pre-permission screen as on iOS.
- Closed testing track first. Google Play requires a minimum number of testers over a minimum period before a new personal developer account can go to production. Check the current numbers at P8 start, because it also feeds the strangers count.
- Store listing, with screenshots from a real device in a shop.
- Signed with Play App Signing. Upload key kept out of the repo.

## Differences from iOS to accept

| iOS | Android |
| --- | --- |
| Live Activity / Dynamic Island | Ongoing notification. Lives in the notification shade, with a progress chip on newer Android. |
| Haptics: `.warning` / `.error` | `HapticFeedbackConstants.REJECT` and `CONFIRM`, with a fallback to `VibrationEffect` |
| Sign in with Apple is native | Web flow through the API |
| DataScanner highlights items by itself | Draw our own overlay from the ML Kit bounding boxes |
