# Supermarket scanner with a spending limit and stats

Scan the barcode with VisionKit's DataScannerViewController, which reads EAN/UPC and QR. 
Read the price from the shelf label with the same scanner's text recognition, or let the user type it in. 
Save the barcode and price for each store in SwiftData, so the next scan fills the price in automatically.
Optionally, get the product name and photo from the free Open Food Facts API, which needs no key.

the website will most be to check stats

---

## Read first

- `ARCHITECTURE.md`: system, iOS modules, data model, sync, server, infra.
- `DESIGN.md`: flows, screens, limit states, and the **Insights catalogue** (INS-xx definitions, which are the contract for iOS and the server).
- `docs/api.md`: the `/v1` contract shared by iOS, Android and web.
- `docs/android.md`: the Android port spec (phase P8).
- `BACKLOG.md`: ordered work with stable IDs. Start at the first open item whose `Needs` are done.

## Hard rules

- **The product is ScanIt (`scanit`).** `maat` is only this folder's name and the cluster's name. Never use it in bundle IDs, releases or secrets. The domain is still `{{domain}}` (FND-001).
- **Offline is the normal case** (bad supermarket Wi-Fi). A whole trip works with no network. Sync and Open Food Facts lookups queue up and flush when the network returns. Never block a scan on the network, and never show sync errors during a trip.
- **Monetisation:** free, plus a one-time "ScanIt Unlimited" unlock (unlimited trips and full history). The paywall appears only at Start trip, and never mid-trip.
- **Deleting the account keeps the trips on the phone.**
- **Money is integer minor units plus an ISO currency.** Never `Double`.
- **Strangers gate:** do not start backend, auth, web stats or Android (P4, P8, P9) before BACKLOG GATE-002 passes.
- **Infra changes go only in `~/Work/production/platform/infra`** (namespace `horus`). Never create a local `*-infra/` copy.
- **Tests never use real API keys or real ID tokens.** Use stub JWKS and stub HTTP servers.

## Layout and commands

```
scanit/          iOS app (scanit.xcodeproj, scheme `scanit`; folders are synchronised groups)
scanit-core/     shared Swift package ScanItCore (iOS now, server in P4)
scanit-core/Fixtures/   JSON test vectors, also for the Android port
docs/            api.md, android.md
```

- Core tests: `cd scanit-core && swift test`
- App unit tests: `xcodebuild test -project scanit/scanit.xcodeproj -scheme scanit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:scanitTests`
- CI: `.github/workflows/ci.yml` (core on Linux, iOS on macOS). Repo: `FACorreiaa/scanit`.
