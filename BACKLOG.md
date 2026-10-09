# ScanIt backlog

Derived from `AGENTS.md`, `ARCHITECTURE.md`, `DESIGN.md`, `docs/api.md` and `docs/android.md`.
This file is the ordered work list. It does not introduce product decisions; where a decision is still
open it is marked **OPEN** and left for a human.

## How to read this

- IDs are stable. Never renumber. Close an item by moving it to **Done** with its ID.
- Order inside a phase is dependency order. Do not start an item whose `Needs` is open.
- `Size`: S = under a day, M = 1–3 days, L = a week or more.
- Every item names a **Done when** condition that can be checked, not "implemented".
- Items marked **Deferred** exist so nobody re-litigates them. They are not v1 work.

Owner rules that bound every item (`~/.claude/CLAUDE.md`):

- This was a brand-new idea when started (2026-10-09). The owner chose to proceed.
- **Measurement before supply-side.** Backend, auth, web and Android come after real strangers have used the local app (P2 gate).
- No renames, rebrands or re-architectures until 10 strangers have used the current version.
- Agents draft pixels, the owner keeps verdicts.
- Infra changes go in `~/Work/production/platform/infra` only.

## Status snapshot (2026-10-09)

| Area | State |
| --- | --- |
| Docs | `ARCHITECTURE.md`, `DESIGN.md`, `docs/api.md`, `docs/android.md`, this file |
| Code | Repo `FACorreiaa/scanit` (private). `scanit-core` done (Money, barcodes, price parser, sync DTOs, fixtures). iOS shell: 3 tabs, iPhone-only, iOS 18, Swift 6. CI: core on Linux, iOS unit tests on macOS. |
| Name | **ScanIt** / `scanit` (2026-10-09). Domain **OPEN** (`{{domain}}`). Store-name availability unchecked. |
| Monetisation | Free plus a one-time "ScanIt Unlimited" unlock (2026-10-09). See REL-003. |
| Strangers count | 0 |

---

## Phase map

| Phase | Goal | Exit condition |
| --- | --- | --- |
| P0 | Foundations | Named, repo exists, empty app builds in CI |
| P1 | Local MVP | One person can do a whole shop with the app, offline, without an account |
| P2 | **Strangers gate** | 10 strangers have finished at least one real trip (TestFlight) |
| P3 | Enrichment + insights | Product names and photos, and the Insights tab with INS-01…08 |
| P4 | Accounts + backend | Sign in with Apple or Google, sync, delete account, server on the cluster |
| P5 | Landing | Public site with legal pages and download links |
| P6 | App Store release | Approved and live |
| P7 | Live Activity | Total visible on the Lock Screen and Dynamic Island |
| P8 | Android | Play Store production release at parity with P1–P4 |
| P9 | Web stats | Signed-in web dashboard over `/v1/stats` |

⛔ **P4, P8 and P9 do not start until P2 passes.** P3 and P5 may start during P2, because they make the
tester experience and the App Store submission possible. P5's legal pages are needed for TestFlight
external testing review too, so pull P5 forward if external TestFlight review asks for a privacy URL.

---

## P0 — Foundations

### FND-001 · Lock the name and domain · S
Name chosen: **ScanIt**, slug `scanit`, bundle ID `com.<owner>.scanit`. Still to do:

- Check that the App Store and Play names are available. "ScanIt" and "Scan It" are common, so
  a subtitle-style fallback may be needed, for example "ScanIt: Shopping Total". The name in the store can differ from the name on the icon.
- Pick and buy the domain (**OPEN**).

**Done when:** the App Store Connect app record exists with its final name, the domain is bought,
and `rg '\{\{domain\}\}' apps/maat` returns nothing after one find-and-replace.

### FND-004 · PostHog and Sentry · S
**Needs:** owner creates a ScanIt PostHog project and a Sentry project (**OPEN**). Events must not go into another app's project.
The rest of the skeleton is done (see **Done**). Replace `LogAnalytics` in `scanit/scanit/Services/Analytics.swift`
with a PostHog-backed `AnalyticsClient`, init Sentry as in `LuminaVaultClientApp.swift`, and keep the keys in a
gitignored `Config.*.xcconfig` with a committed `.sample` (LuminaVaultClient pattern).

**Done when:** PostHog receives `app_opened` from a debug build, and a forced test crash shows in Sentry.

---

## P1 — Local MVP (offline, no account)

### IOS-005 · Scanner: barcode · M
**Needs:** IOS-004.
`DataScannerViewController` wrapper started from Norviq's `ReceiptScannerView.swift`, with the symbologies from
`ARCHITECTURE.md`, `isSupported` / `isAvailable` handling, camera primer, and an AVFoundation fallback.

**Done when:** on a physical device, EAN-13 and EAN-8 products and a GS1 Digital Link QR each produce the right GTIN in the confirm sheet. A denied camera permission shows a recovery path to Settings.

**Status 2026-10-09:**

- **Built:** VisionKit scanner, AVFoundation fallback, camera primer, denied-camera recovery to Settings, and a simulated scanner for UI tests.
- **Not yet verified on a physical device.** Building to the paired iPhone timed out waiting for the device; it is probably locked or connected over the network rather than by cable.

### IOS-006 · Spike: currency text recognition · S
**Needs:** IOS-005.
Check the iOS 18+ SDK for a currency `textContentType` in DataScanner. Compare it with plain `.text()` and the core price parser on 20 photos of real shelf labels from 2 or more chains.

**Done when:** the result is written in `ARCHITECTURE.md` (which approach, and its hit rate on the 20 labels).

### IOS-007 · Scanner: shelf price · M
**Needs:** IOS-006.
Candidate boxes, the top candidate prefilled, the **Type it** keypad always available, and the 3-second fallback prompt.

**Done when:** on the 20-label set, the correct price is the prefilled one on at least 70 % of labels (OCR accuracy target, confirmed by the owner 2026-10-09). A wrong prefill can be corrected in one tap.

### IOS-012 · Analytics events · S
**Needs:** IOS-010.
The events in `ARCHITECTURE.md` → Analytics. No amounts or product names.

**Done when:** one test trip produces every event in the PostHog debug view, and none of them carries an amount.

**Status 2026-10-09:** `app_opened`, `trip_started`, `item_scanned`, `trip_finished`, `insights_viewed` are sent (to the
local log until FND-004). `price_ocr_result` comes with IOS-007, `signed_in` with P4.

### IOS-013 · TestFlight internal build · S
**Needs:** IOS-001…012.
**Done when:** the owner does one real supermarket trip **in airplane mode**, start to finish, with nothing failing. The friction found is logged here as new items.

---

## P2 — Strangers gate

### GATE-001 · External TestFlight · S
**Needs:** IOS-013 (and P5's privacy URL if the review asks).
**Done when:** the external TestFlight group is approved and a public link exists.

### GATE-002 · Recruit and measure · L
**Needs:** GATE-001.
Use the `demand-hour` skill ritual. Count only people who are not friends or family and who **finished at least one trip** (PostHog `trip_finished`).

**Done when:** strangers count ≥ 10, recorded in the status snapshot with the date.

### GATE-003 · Read the feedback · S
**Needs:** GATE-002.
Turn feedback into items. Re-order P3 and later if testers ask for something else.

**Done when:** every piece of feedback is either a backlog item or explicitly dismissed, with a reason.

---

## P3 — Enrichment and insights

### INS-105 · In-store price-embedded barcodes · M
**Needs:** IOS-005.
Per-country table for 20–29 prefix EANs (start with the owner's country). Price or weight is extracted, with source `embedded`.

**Done when:** 5 real weighed-produce labels parse to the printed price.


---

## P4 — Accounts and backend (⛔ after P2)

### SRV-001 · Server skeleton from the aaru template · M
**Needs:** FND-003, GATE-002.
Hummingbird 2, `openapi.yaml` generated from `docs/api.md`, error contract, `/healthz`, `/readyz`, Fluent and Postgres config, migrations gated by a flag, and a docker-compose Postgres for local dev.

**Done when:** `swift test` passes, a deliberate 404 returns the error shape, and `/readyz` fails when the DB is down.

### SRV-002 · Data layer and migrations · M
**Needs:** SRV-001.
Store protocols with Fluent implementations. Tables `users`, `auth_identities`, `refresh_tokens`, `stores`, `sessions`, `cart_items`, `price_observations`, plus the `server_seq` sequence. No SQL in handlers.

**Done when:** migrations run twice without error against docker-compose, and a handler test runs on a fake store.

### AUTH-001 · Apple and Google token exchange · M
**Needs:** SRV-002.
Copy and adapt the LuminaVault OAuth providers, JWT and middleware (paths in `ARCHITECTURE.md`). Refresh rotation and logout.

**Done when:** tests run against stubbed JWKS servers, with no real tokens and no real keys. They cover: a valid token gives a session; wrong `aud`, wrong `iss`, expired, and bad signature are each rejected; a reused refresh token is rejected.

### AUTH-002 · Delete account · S
**Needs:** AUTH-001.
`DELETE /v1/me` hard-deletes the user and cascades.

**Done when:** after deletion, no row with that `user_id` remains in any table (test queries every table).

### SYNC-001 · Push and pull endpoints · M
**Needs:** SRV-002, AUTH-001.
LWW, tombstones, `server_seq` cursor, `missing_parent` rejection, batch limit 500.

**Done when:** tests cover an older write ignored, a newer write applied, a delete propagated, paging via `hasMore`, and an orphan item rejected.

### INF-001 · Infra: deploy the server · M
**Needs:** SRV-001.
In `platform/infra`, following Khepri:

- `argocd/apps/scanit-production.yaml`
- `apps/scanit/web/values-production.yaml` (namespace `horus`, ingress `api.{{domain}}`, `migrate:` PreSync)
- a new DB and role on `apps/data/postgres.yaml`
- sealed secrets in `secrets/scanit/`, with a README, sealed for `horus` and the exact secret names

CI copied from Norviq's `deploy-k3s.yml`.

**Done when:** merging to `main` deploys, `https://api.{{domain}}/v1/readyz` returns 200, and the app shows on the homepage dashboard.

### IOS-101 · Sign in (Apple and Google) · M
**Needs:** AUTH-001, INF-001.
Services copied from LuminaVaultClient (Apple with nonce, Google, Keychain). An Account screen as in `DESIGN.md` §8.

**Done when:** both providers sign in on a device, the session survives an app restart, and sign-out clears the Keychain.

### IOS-102 · SyncEngine · L
**Needs:** SYNC-001, IOS-101.
Dirty-row outbox, push parents first, pull with cursor. Triggers: foreground, trip finish, network back (IOS-104), background refresh. On first sign-in, upload everything. Pushes are idempotent, so a retried batch never duplicates rows.

**Done when:** two devices on the same account converge after offline edits on both. A row deleted on one device disappears on the other. Signing in with 50 local trips uploads all 50. Killing the network mid-push and retrying leaves no duplicate rows on the server.

### IOS-104 · Offline sync triggers · M
**Needs:** IOS-102.
As in `ARCHITECTURE.md` → Offline:

- `ConnectivityMonitor` (`NWPathMonitor`): a `.satisfied` path triggers `SyncEngine.flush()` and the OFF queue.
- `BGAppRefreshTask` `scanit.sync`.
- Exponential backoff with jitter, capped at 5 min, reset on a path change.
- An expired token while offline never signs the user out.
- A sync-status line in Settings, with no alerts during a trip.

**Done when:**

- A full trip done in airplane mode, followed by the network being turned back on with the app in the foreground, is on the server within 10 s.
- With the app backgrounded, the trip arrives on the next foreground or background refresh.
- A whole day offline with an expired access token keeps the user signed in, and it syncs once online.

### IOS-103 · Delete account and export · S
**Needs:** AUTH-002, IOS-101.
Destructive confirm, then `DELETE /v1/me`. **Local data is kept** (owner decision 2026-10-09): clear the Keychain, mark all rows dirty, reset the sync cursor, and continue as a signed-out, local-only app. Also CSV export.

**Done when:** after deletion, every trip is still on the phone and the server has no rows for that user. Signing in again creates a fresh account and uploads the kept trips. The exported CSV opens in Numbers with correct amounts.

---

## P5 — Landing page

### WEB-001 · `scanit-web` landing · M
**Needs:** FND-001.
SvelteKit 5 on Cloudflare (aaru-client pattern). One page plus `/privacy`, `/terms` and `/delete-account`. No analytics cookies, so no cookie banner is needed.

**Done when:** it is live on `{{domain}}`, Lighthouse scores ≥ 95 on every category, and the App Store badge links to the TestFlight or App Store URL.

### WEB-002 · Privacy policy and terms content · S
**Needs:** WEB-001.
**OPEN:** the owner reviews the legal text. It must match the App Privacy labels (REL-001) and, later, the Play Data safety form.

**Done when:** the owner signs off.

---

## P6 — App Store release

### REL-001 · App Privacy labels · S
**Needs:** IOS-012 (and IOS-102 if accounts are in the release).
**Done when:** the labels match exactly what PostHog, Sentry and the API collect.

### REL-002 · Store listing · M
**Needs:** INS-103.
Screenshots from real trips (`aso-appstore-screenshots` skill), subtitle, keywords, review notes explaining that the camera is used for barcodes and price labels, plus a demo account if sign-in is in the build.

**Done when:** the listing is submitted.

### REL-003 · ScanIt Unlimited (one-time unlock) · M
**Needs:** IOS-011.
Decided 2026-10-09: free, plus a one-time non-consumable that unlocks unlimited trips and the full history (`ARCHITECTURE.md` → Purchases, `DESIGN.md` §9).

- **StoreKit 2:** products, purchase, `currentEntitlements`, a `Transaction.updates` listener, restore. A StoreKit configuration file for tests.
- **Free-tier limits:** N trips per month, last M trips visible. Proposed N = 4 and M = 10, **OPEN**: the owner tunes them from P2 data.
- **Price:** **OPEN**, set by the owner.
- **Flag:** the paywall is behind a flag that is off until this item ships, so P2 testers never see it.

**Done when:**

- The 5th trip in a month shows the paywall at **Start trip**, and an active trip is never interrupted.
- Buying in the sandbox unlocks everything at once, including while offline afterwards.
- **Restore** works on a second device.
- Hidden trips come back after unlocking.

### REL-004 · Submit and ship · S
**Needs:** REL-001…003, WEB-002.
**Done when:** the app is live on the App Store.

---

## P7 — Live Activity and widgets

### LIVE-001 · Trip Live Activity · M
**Needs:** IOS-002.
ActivityKit Live Activity with total, limit bar and remaining. Compact and expanded Dynamic Island. Updated locally on every add; no push server.

**Done when:** with the phone locked mid-trip, the Lock Screen shows the right total after an add, and the activity ends on Finish.

### LIVE-002 · Home Screen widget · S
**Needs:** INS-102.
"This month: €312 · 6 trips" (INS-01).

**Done when:** the widget updates after a trip is finished.

---

## P8 — Android (⛔ after P2, and after REL-004)

### AND-001 · Project and core port · M
**Needs:** REL-004.
Compose project per `docs/android.md`. Port the normaliser, the price parser and the insights, running the same `scanit-core/Fixtures/` vectors.

**Done when:** every shared fixture passes on the JVM.

### AND-002 · Local MVP parity · L
**Needs:** AND-001.
Room, start trip, active trip, CameraX + ML Kit scanner with both detectors, confirm, price memory, finish, history.

**Done when:** one real supermarket trip on a mid-range Android device is completed.

### AND-003 · Auth and sync · M
**Needs:** AND-002, IOS-102.
Credential Manager for Google. Apple through the web flow (API `auth/apple/start` and `callback`, plus `auth/exchange`, added server-side here). WorkManager sync.

**Done when:** a trip made on iOS appears on Android on the same account, and the reverse.

### AND-004 · Insights and ongoing notification · M
**Needs:** AND-002.
Vico charts. Ongoing trip notification as the Live Activity equivalent.

**Done when:** it reaches parity with INS-103, and the notification updates on every add.

### AND-005 · Play release · M
**Needs:** AND-003, AND-004, AND-006, WEB-001.
Data safety, deletion URL, closed testing track (meet Google's tester minimums for new accounts), production.

**Done when:** the app is live on Google Play.

---

### AND-006 · Play Billing unlock · M
**Needs:** AND-002, REL-003.
A one-time in-app product with the same free-tier limits and paywall rules as REL-003. Entitlements are cached for offline use.

**Done when:** the REL-003 acceptance checks pass on Android with Play test purchases.

---

## P9 — Web stats (⛔ after P2)

### WEB-101 · Stats endpoints · M
**Needs:** SYNC-001.
`/v1/stats/*` from `docs/api.md`, in SQL, matching the `DESIGN.md` definitions.

**Done when:** tests load the shared fixtures into Postgres and get the same numbers as `InsightsCalculator`.

### WEB-102 · Web sign-in · M
**Needs:** WEB-001, AUTH-001.
Apple (Services ID, web flow) and Google web client.

**Done when:** a user signs in on the web and sees their own email.

### WEB-103 · Stats dashboard · M
**Needs:** WEB-101, WEB-102.
Read-only charts following the `dataviz` skill.

**Done when:** a user with 10 synced trips sees the same numbers as in the iOS Insights tab.

### WEB-104 · Categories server-side · S
**OPEN.** INS-08 needs Open Food Facts categories on the server. Options: the client includes `categories` in the `cart_item` data, or the server fetches and caches OFF. Recommendation: the client sends them (no new outbound dependency).

---

## Design

### DES-001 · Visual pass on P1 screens · M
**Needs:** IOS-004, IOS-008.
An agent drafts, following `DESIGN.md` and the `swiftui-design-principles` skill. **The owner gives the verdict.**

**Done when:** the owner approves the trip screen, the scanner HUD and the confirm sheet.

### DES-002 · Reference research · S
**Needs:** ScreensDesign Pro access (**OPEN**).
Validate the references in `DESIGN.md` against recorded screens of budgeting and scan-first apps.

**Done when:** the reference table has links and the lessons taken.

---

## Deferred

- **Shared crowd prices between users.** Privacy, moderation, and needs scale first.
- **Store auto-detect by location.** It needs a location permission. Manual store chips are fine for v1.
- **Receipt scanning.** Norviq already does it.
- **Export trips to Norviq** as grocery spend. Revisit only if both apps have users.
- **Multi-currency conversion.** Totals are per currency, never converted.
- **Cross-platform unlock** (buy on iOS, unlocked on Android). It needs server-side receipt validation and entitlements.
- **"Sync on Wi-Fi only" toggle.** Payloads are a few KB, so any network is fine for now.
- **Shared household trips** (two phones, one cart).
- **AI insights / LLM.** If ever, read `platform/infra/docs/llm-haiku-trial.md` first.

## Done

### FND-001a · Name · 2026-10-09
ScanIt / `scanit`, bundle ID `com.fernandocorreia.scanit`. Store availability and domain remain in FND-001.

### FND-002 · Repo · S
**Needs:** FND-001.
`git init` in `apps/maat`, then create the GitHub repo under the same owner as the other apps. Add `.gitignore` for Xcode, SPM, Gradle and Node.

**Done when:** the docs are committed and pushed, and the default branch is `main`.

**Closed 2026-10-09:** one repo at `apps/maat` (Xcode's nested `.git` with its template commit was removed),
pushed to `FACorreiaa/scanit` (private), default branch `main`.

### FND-003 · `scanit-core` SPM package · S
**Needs:** FND-002.
Money type (minor units and currency), entity DTOs from `docs/api.md`, the barcode normaliser
and the price parser as pure functions, and a `Fixtures/` folder of JSON test vectors (also used by Android later).

**Done when:** `swift test` passes, with these vectors at minimum:

- barcodes: EAN-13, EAN-8, UPC-E to GTIN-14; GS1 Digital Link URL to GTIN; opaque QR
- prices: `1,99`, `€ 1,99`, `1,99 €`, `$1.99`, `2 x 0,99`, and a label with both a unit price and a price

**Closed 2026-10-09:** `swift test` passes, 17 tests over 16 barcode and 19 price vectors plus the sync fixture.
A deliberately wrong vector fails.

### FND-004a · iOS skeleton · 2026-10-09
`scanit/scanit.xcodeproj`: iPhone only, iOS 18.0, Swift 6, local package `../scanit-core`, shared scheme,
camera usage string, display name ScanIt. 3-tab shell (Trip, History, Insights) with empty states. `Money.formatted`
and the analytics seam are tested. It builds and launches in the simulator, and `app_opened` is logged.
PostHog and Sentry are split out to FND-004.

### FND-005 · CI build · S
`.github/workflows/ci.yml`: `scanit-core` tests on Linux (`swift:6.2`), iOS unit tests on macOS (Xcode 26.4).

**Done when:** a PR shows a green check, and a deliberately broken test makes it red.

**Closed 2026-10-09:** the first push to `main` ran green: core on Linux 1 min, iOS ~6 min. A throwaway branch with a
broken check-digit assertion went red on exactly that expectation (run 37935622183). The branch was deleted.
CI skips Markdown-only and `docs/` changes.

### IOS-001 · SwiftData models · M
**Needs:** FND-004.
`Store`, `ShoppingSession`, `CartItem`, `Product`, `PriceObservation` exactly as in
`ARCHITECTURE.md`, including `updatedAt`, `deletedAt` and `syncState`, so P4 needs no migration of shape.

**Done when:** unit tests create a session with items in an in-memory container, compute the total
in minor units, and soft-delete an item, which is excluded from the total.

### IOS-002 · SessionStore and limit states · S
**Needs:** IOS-001.
`@Observable SessionStore`, with `totalMinor`, `remainingMinor`, `progress` and `state` (`noLimit` / `ok` / `near` / `over`).

**Done when:** tests cover every state boundary (79.99 %, 80 %, 100 %, 100.01 %), and a state change fires the haptic exactly once per crossing.

### IOS-003 · Start trip sheet · S
**Needs:** IOS-002.
Store chips and new store, optional limit with history chips, currency.

**Done when:** a trip starts with and without a limit, and the last store is preselected next time.

**Closed 2026-10-09 (IOS-001…003):**

- **Models:** in `scanit/scanit/Domain/Models.swift`. A test covers the total in minor units, and that a soft-deleted item is excluded from the total but its row is kept for sync.
- **Limit maths:** `LimitStatus` lives in `ScanItCore`, so it is shared with Android. Tests cover the 79.99 / 80 / 100 / 100.01 % boundaries.
- **SessionStore:**
  - one haptic per upward crossing, none when going back under, and it fires again on re-crossing
  - an active trip survives a relaunch
  - editing a price marks it `manual`
- **Start-trip sheet:**
  - recent stores as chips, the last one preselected
  - "New store" as an inline field
  - optional limit, with "Last" and "Usual" chips from the user's history
  - currency picker
- **UI test** `TripFlowUITests`: a trip starts with a limit, gets cancelled, then a trip starts without a limit with the store preselected and the last-limit chip offered. Screenshots are attached to the result bundle.
- **Interim active-trip screen:** total, limit bar and cart rows. IOS-004 replaces it.

Real haptics need a device; their logic is unit-tested.

### IOS-004 · Active trip screen · M
**Needs:** IOS-003.
Hero total, limit bar, cart list (swipe delete, tap to edit quantity and price), Scan and Finish buttons, layout as in `DESIGN.md` §3.

**Done when:** adding, editing and deleting items updates the total live. VoiceOver reads the total after a change. Dynamic Type XXL does not clip the total.

### IOS-008 · Confirm sheet and add · S
**Needs:** IOS-007.
Price, quantity stepper, **Add**. The scanner stays open afterwards. Writes a `CartItem` and a `PriceObservation`.

**Done when:** scanning 5 items in a row without closing the scanner works, and the HUD total is right after each one.

### IOS-009 · Price memory · S
**Needs:** IOS-008.
Prefill from the newest `(store, gtin)` observation, with an "N days ago" label and source `remembered`.

**Done when:** scanning the same product twice in the same store adds it the second time in 2 taps. A different store does not prefill.

### IOS-010 · Finish trip and summary · S
**Needs:** IOS-008.
Summary as in `DESIGN.md` §6, the optional "actual till total" field, and Undo finish.

**Done when:** a finished trip shows in History, and Undo restores it to active.

### IOS-011 · History and trip detail · S
**Needs:** IOS-010.
Grouped by month with the month total. Trip detail is editable.

**Done when:** editing a price in a past trip changes that trip's total and the month total.

**Closed 2026-10-09 (IOS-004, 008–011):**

- **Trip screen:** swipe to delete, tap to edit, Scan and Finish buttons. VoiceOver announces the total after every change.
- **Large text:** at Accessibility XXL the total never truncates (it shrinks instead), and the limit row, action bar and cart rows stack.
- **Confirm sheet:** quantity stepper and typed price.
- **Price memory:**
  - every confirmed price is recorded per store
  - a remembered price is prefilled, with "Seen here …"
  - other stores never prefill
- **Finish:** summary showing the delta vs the last trip at the same store, the 3 biggest lines and the till total, plus Undo finish.
- **History:** trips grouped by month with per-currency totals; past trips can still be edited.
- **UI tests:** `testScanFinishAndRememberedPrice` covers the full loop, including over-limit, delete, finish, History and a remembered price as two taps. `testLargestTextSizeKeepsTotalReadable` covers Dynamic Type; its screenshots were reviewed.

### INS-101 · Open Food Facts client · S
**Needs:** IOS-008.
Async lookup after add, with the `User-Agent` from `ARCHITECTURE.md`, a negative cache with TTL, and name and photo filled into the row.

Offline, lookups are queued (`offFetchedAt == nil`) and retried when `ConnectivityMonitor` reports the network is back.

**Done when:** a known EAN gets its name and photo within 2 s on a good network. Airplane mode does not slow down adding. Five items scanned in airplane mode get their names within 10 s of the network returning.

**Closed 2026-10-09:**

- **Code:** `ProductEnricher` + `OpenFoodFactsClient` + `ConnectivityMonitor` (`NWPathMonitor`).
- **Behaviour:**
  - looks up the 13-digit code printed on the pack
  - "not found" is cached for 7 days
  - in-store and opaque codes are never looked up
  - a name the user typed is never overwritten
- **Flush triggers:** after each add, on foreground, and on network reconnect.
- **Tests** (stubbed, no network) cover:
  - name and photo filled after an add
  - offline: queued, stops at the first network error, filled once back online
  - a known product named instantly offline
  - miss retry
  - skipped codes
- A live opt-in test (`TEST_RUNNER_SCANIT_LIVE_OFF=1`) got Nutella from the real API in < 2 s.
- The UI test asserts the name appears in the cart.

**OPEN:** OFF asks for a contact in the User-Agent. Today it is `ScanIt/<version> (iOS)`; add a contact address (owner's choice) before the App Store release.

### INS-102 · InsightsCalculator · M
**Needs:** IOS-011.
Pure implementation of INS-01…08 from `DESIGN.md`, with fixtures shared in `scanit-core/Fixtures/`.

**Done when:** every INS ID has a fixture test with a hand-computed expected value.

**Closed 2026-10-09:**

- **Code:** `InsightsCalculator` in `ScanItCore/Insights.swift`, working over `TripSnapshot` / `PriceSnapshot` values, so the server can reuse the same definitions in P9.
- **Fixture:** `Fixtures/insights.json` holds 6 trips over 2 stores, including a USD trip to prove currencies never mix, an in-store code and an opaque code. Every expected value for INS-01…08 was worked out by hand.
- **Checked:** two deliberately wrong expectations both failed.

### INS-103 · Insights tab · M
**Needs:** INS-102.
Swift Charts, following the `dataviz` skill, with the 3-trip minimum placeholder.

**Done when:** with fixture data loaded, every INS card renders in light and dark mode. With 2 trips, only the placeholder shows.

**Closed 2026-10-09:**

- **Layout:**
  - headline tiles: this month and this week vs the previous period, average trip, trips under the limit
  - week/month filter in one row above the bars
  - spend by store and by category as single-colour bars, with name and value printed on each row
  - lists: top products, prices that went up, cheapest store for regulars
- **Placeholder:** shown below 3 finished trips.
- **Colour:** the accent passes the dataviz validator in both modes.
- **Charts:** Swift Charts was dropped for these short ranked lists, because its axis labels collided. They are plain rows now.
- **Demo data:** debug-only `DemoData` (`-ui-testing-demo-data`) seeds history for UI tests and screenshots.
- **Analytics:** the `insights_viewed` event is sent.

### INS-104 · Price-change badges · S
**Needs:** INS-102.
"+12 % since May" on cart rows and trip-detail rows (INS-06).

**Done when:** a product whose price rose shows the badge, and one with no history does not.

### INS-106 · Till gap and basket inflation · S
**Needs:** INS-102.
INS-09 and INS-10. Port the method from Norviq's `PersonalInflationCalculator.swift`.

**Done when:** fixture tests pass, and the cards are hidden when there is no data.

**Closed 2026-10-09 (INS-104, INS-106):**

- **Badge:** `PriceTrend` puts "↑ 12% since May" on cart and history rows:
  - per store, over 180 days
  - only shown when the change rounds to at least 1%
  - in secondary ink, not red
- **INS-09 till gap and INS-10 basket inflation** live in `ScanItCore`:
  - basket inflation is spend-weighted per product and store, after Norviq's `expense_weighted_cpi_v1`
  - both have hand-computed fixture expectations
  - both are shown under "Your prices" on Insights, hidden when there is no data
