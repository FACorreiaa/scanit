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
| Name | Home-screen name **ScanIt**, slug `scanit`. **App Store name: ScanItNow** ("ScanIt" was taken). App Store Connect apps: ScanItNow (`com.fernandocorreia.scanit`, id 6821292069) and ScanItNow Beta (`.beta`, id 6821292246), created 2026-10-10. Domain **OPEN** (`{{domain}}`). |
| Monetisation | Free plus a one-time "ScanIt Unlimited" unlock (2026-10-09). See REL-003. |
| TestFlight | Build 1 uploaded by CI (2026-10-10), state VALID. Internal group has auto-distribute on and 1 tester. Every green `main` uploads a new build. |
| Release plan | **Fast path (2026-10-10):** App Store v1.0 free, no IAP, no analytics SDKs, legal pages on facorreia.com. `scanit-web` is parked (built, not deployed). REL-003 and FND-004 move to v1.1. See `docs/release.md`. |
| App Store | **1.0 (build 1) submitted for review 2026-10-14**, manual release. Free, Data Not Collected, 175 territories. |
| Strangers count | 0 |
| P10 Plan and save | Opened 2026-11-16 by owner decision while the strangers count was 0. Local-only items may start; items marked **(after P2)** wait for GATE-002. |

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
| P10 | Plan and save | One person plans a week, shops from the plan, and sees "saved €X this month" that adds up from the trip lines |

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

**Status 2026-10-09:**

- **Ready:** the harness `tools/label-bench` runs Vision's accurate text recogniser plus the real `PriceParser` over a folder of photos and prints the hit rate. It got 4 of 4 synthetic labels right, which is a pipeline smoke test only.
- **Needs from the owner:** about 20 real label photos and `expected.json` (see the README).
- **Still to do:** decide on DataScanner's currency content type on device.

**Status 2026-10-22:** `ScanItCore.LabelReader` (Vision text + barcode on one still) is shared by the app and the
bench. `label-bench labels --record` saves the reads to `scanit-core/Fixtures/labels.json`, and `LabelSetTests` gates
it on Linux CI (empty, floor 0, until the real photos are in). The parser now ranks by barcode nearness, flags
multi-buys, merges superscript cents and gates the prefill on a confidence threshold. Still waiting for the owner's
label photos. On device: still capture + Vision (B) against DataScanner `.text(.currency)` (A).

### IOS-007 · Scanner: shelf price · M
**Needs:** IOS-006.
Candidate boxes, the top candidate prefilled, the **Type it** keypad always available, and the 3-second fallback prompt.

**Done when:** on the 20-label set, the correct price is the prefilled one on at least 70 % of labels (OCR accuracy target, confirmed by the owner 2026-10-09). A wrong prefill can be corrected in one tap.

**Status 2026-11-05: built, not yet proven on real labels.** The scanner asks for the shelf price when none is remembered: **Read price** takes one still from the running `DataScannerViewController` (option B, so the bench measures what ships), `ScanItCore.LabelReader` and `PriceParser` read it on the device, and the sheet opens with the price prefilled or chips. **Type it** is always there. Tap-to-read replaced the live candidate boxes and the 3-second prompt: one deliberate still rather than repeated captures. Vision's accurate text recogniser cannot run on the simulator, so UI tests stub the text with `UITEST_SHELF_TEXT`. **Still needs from the owner:** a real in-store test, and the 20-label set for the 70% target.

### IOS-012 · Analytics events · S
**Needs:** IOS-010.
The events in `ARCHITECTURE.md` → Analytics. No amounts or product names.

**Done when:** one test trip produces every event in the PostHog debug view, and none of them carries an amount.

**Status 2026-10-09:** `app_opened`, `trip_started`, `item_scanned`, `trip_finished`, `insights_viewed` are sent (to the
local log until FND-004). `price_ocr_result` comes with IOS-007, `signed_in` with P4.

**Status 2026-10-22:** `price_ocr_result` and `price_ocr_corrected` are defined, and the `ocr_edited` / `ocr_corrected`
price sources and `OCRStats` (debug Insights section) are in. The scanner emits `price_ocr_result` once IOS-007 is live.

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

**Status 2026-11-15: not started, waiting on real labels.** GS1 leaves the layout of 20–29 codes to each country
and, in practice, to each chain: some carry the price, some the weight, with different digit counts. No published
layout for Portuguese chains was found, and a guessed table would put wrong prices in the cart. **Needs from the
owner:** photos of about 5 weighed labels from 2 or more chains, with the printed price, weight and price per kg readable.


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

**Status 2026-10-09:**

- **Built, not deployed.**
  - **Stack:** SvelteKit 2.70 with adapter-cloudflare and Tailwind 4. Fully prerendered: home, privacy, terms, delete-your-data.
  - **Look:** system font, light and dark themes, and real app screenshots taken by the UI tests.
  - **Lighthouse** (local): 98–99 Performance, 100 Accessibility, 100 Best Practices, 100 SEO on every page.
- **Download button:** reads "Coming soon for iPhone" until `downloadUrl` is set (TestFlight link, then the App Store).
- **Still open:**
  - the domain (FND-001)
  - a Cloudflare account and `wrangler deploy` (owner)
  - the contact address

### WEB-002 · Privacy policy and terms content · S
**Needs:** WEB-001.
**OPEN:** the owner reviews the legal text. It must match the App Privacy labels (REL-001) and, later, the Play Data safety form.

**Done when:** the owner signs off.

**Status 2026-10-09:**

- **Drafted:** `/privacy`, `/terms` and `/delete-account` in `scanit-web`.
- **What they say:**
  - trips stay on the phone
  - only the barcode goes to Open Food Facts
  - anonymous usage events without amounts or products
  - crash reports, no location, no ad tracking
- **Before release:**
  - The analytics and crash wording assumes FND-004 (PostHog/Sentry) ships. Re-check it if that changes.
  - The terms mention the one-time unlock (REL-003).
- **Open:**
  - The contact address (`src/lib/config.ts → contactEmail`). Until it is set, the pages point to the App Store listing.
  - Owner sign-off on the wording. This is AI-drafted text, not legal advice.

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

**Status 2026-10-09: built, switched off** (`PaywallPolicy.launch.isEnabled = false`).

- **What's built:**
  - `PurchaseStore` (StoreKit 2: purchase, restore, `Transaction.updates`, revocation)
  - `PaywallPolicy` rules
  - the paywall sheet, gating only at Start trip
  - a locked "N older trips" row in History
  - local `ScanIt.storekit`, wired into the Run scheme
- **Verified:**
  - **5th trip:** shows the paywall (unit test plus UI test); "Not now" costs nothing.
  - **Purchase:** the sandbox purchase unlocks, and a fresh store reads the entitlement from the device, which is the offline case (StoreKit test session).
  - **Refund:** locks it again.
  - **History:** hidden trips come back.
  - **A bug found and fixed:** a trip at exactly 00:00 on the 1st counted against the previous month.
- **Still open:**
  - Restore on a second device needs a real sandbox account and App Store Connect.
  - Create the in-app product `com.fernandocorreia.scanit.unlimited` in App Store Connect.
  - **Owner decisions:** the price (placeholder €4,99), the free limits (4 trips per month, last 10 visible), and whether Insights should cover hidden trips.
  - Switch the flag on for the App Store build only.

### REL-004 · Submit and ship · S
**Needs:** REL-001…003, WEB-002.
**Done when:** the app is live on the App Store.

---

## Small adds (owner, 2026-11-15)

Local only: no backend, no account. Chosen by the owner while the strangers count was still 0, in
this order. LIVE-001 and INS-105 above are part of the same list (third and fourth).

### ADD-001 · Zero-tap scan and "cheaper elsewhere" · M
Scanning is the whole gesture. A price remembered for this store is added on the barcode lock. With
no remembered price the shelf label is read without a tap (up to 3 stills) and added when it shows
one clear price. Both show a banner with **Undo** and **Edit**, and "€1,79 at Aldi · 12 Oct" when
another store's newest price (90 days, real GTINs only) is lower. Several prices on a label, or
none, still go to the confirm sheet, which shows the same hint. Undo also forgets the price it
recorded, so a misread is not added again.

**Done when:** in a real shop, a known product is in the cart with no tap, a shelf label with one
price is added with no tap, and a wrong read is undone from the banner.

**Status 2026-11-15: built on `feat/zero-tap-scan`, not yet tried on a device.** Open: whether
`capturePhoto()` makes a shutter sound on each automatic still, and how often packaging text is
taken for a price when the label is out of frame (IOS-007's 20-label set still measures this).
The store screenshot "SKIP RETYPING" shows the confirm sheet, which a remembered price no longer opens.

### ADD-002 · Share a trip summary · S
An image card from the summary: total against the limit, items, store. System share sheet.

**Done when:** a finished trip can be shared to Messages as one image with no amounts cut off.

**Status 2026-11-15: built on `feat/zero-tap-scan`.** A 1080 × 1350 card (store, date, total, limit bar and result, item count, mascot) from the summary and from a past trip in History. Totals only, no product names. Not yet shared from a device.

### ADD-003 · Monthly grocery budget · S
**Needs:** INS-103.
A month limit on Insights, measured with `LimitStatus` over the month's finished trips.

**Done when:** the Insights tile shows spent and left for the month and turns amber and red at the trip thresholds.

**Status 2026-11-15: built on `feat/zero-tap-scan`.** "Monthly budget" section under the Insights tiles, one amount for every month, kept in `UserDefaults`. Shown only once Insights has its 3 trips.

### ADD-004 · "Start shopping" App Intent · S
Siri, Action Button and Control Center start a trip at the last store.

**Done when:** the Action Button opens the scanner on a new trip from a locked phone.

**Status 2026-11-15: built on `feat/zero-tap-scan`.** `StartShoppingIntent` with Siri phrases; it opens the scanner mid-trip and the start sheet otherwise, so the limit and the free-trip quota are still asked. Not yet run from Siri or the Action Button. A Control Center control needs the widget extension (LIVE-001).

### ADD-005 · Shopping list · M
A list written before the trip, ticked off when its product is scanned.

**Done when:** a scan ticks the matching line, and the trip screen shows what is still to get.

**Status 2026-11-15: built on `feat/zero-tap-scan`.** New `ListItem` model. A line picked from past purchases is ticked by its barcode; a typed line by the product name (every word starts a word of the name) or by hand. Ticked lines leave the list when the trip is finished.

### ADD-006 · Export trips as CSV · S
One file from Settings: trip, store, date, product, quantity, price.

**Done when:** the file opens in Numbers with one row per cart line.

**Status 2026-11-15: built on `feat/zero-tap-scan`.** In the About sheet. Not yet opened in Numbers.

---

## P10 — Plan and save

Opened 2026-11-16 by the owner. You plan the week's meals, the app tells you where the list is cheapest,
and it shows what you saved. Portugal comes first (chains, labels, pt-PT), other countries follow.

Owner decisions (2026-11-16):

- **Price data:** your own scans plus **Open Prices** (prices.openfoodfacts.org, open data). Read-only
  in the app; sending your own prices is opt-in and after P2. No scraping of chain websites.
- **Meals:** your own meals as ingredient lists. A week plan becomes the shopping list plus a cost
  estimate per store. No recipe catalogue, no AI.
- **Currency:** each currency is counted on its own. Savings are never converted.
- **Gate:** local-only items may start now. Items marked **(after P2)** wait for GATE-002.

**Exit condition:** one person plans a week, shops from the plan, and sees "saved €X this month" that
adds up from the trip lines.

**Start order:** SAVE-001 → BUD-001 → CMP-001 → MEAL-001 → MEAL-002 → MEAL-003 → OPX-001 →
SAVE-002/003 → MEAL-004 → CMP-002 → BUD-002 → OPX-002 → REG-001/002 → the rest.

*Savings: the base the rest builds on. SAVE-001 (the INS-11…14 maths) is done; see **Done**.*

### SAVE-003 · Savings on Insights · S
**Needs:** SAVE-001.

- A "Saved this month" tile with a 6-month trend.
- A "Where you'd save most" list built from INS-13.
- The 3-trip placeholder rule still applies.

**Done when:** the tile renders in light and dark mode with demo data and passes the `dataviz` validator.

*Budget: improvements to the trip limit and ADD-003. BUD-001 (a budget per currency) is done; see **Done**.*

### BUD-002 · Over-limit help during the trip · M
**Needs:** SAVE-001.
When the trip is `.near` or `.over`, the trip screen suggests what would bring it back under:

- lines that are not on the shopping list
- lines that cost less at another store you know (`PriceMemory.cheapestElsewhere`)

Suggestions only. The app never removes anything by itself.

**Done when:** a demo trip over its limit shows at least one suggestion, and acting on it brings the
state back to `.ok`.

### BUD-003 · Weekly budget and carry-over · S
**Needs:** BUD-001.

- The budget can be weekly or monthly.
- Optional carry-over adds what was not spent to the next period.
- The Live Activity and the widget (LIVE-002) show what is left this period.

**Done when:** fixture tests cover a week boundary, carry-over on and off, and a period with no trips.

### BUD-004 · Savings goal · S
**Needs:** SAVE-003.
An optional monthly savings target, with INS-14 measured against it, as a progress ring on the tile.

**Done when:** the ring fills from INS-14, and a month that reaches the target says so once.

*Meals. MEAL-001 (meals with their cost), MEAL-002 (the week plan) and MEAL-003 (plan to list) are done; see **Done**.*

### MEAL-004 · Plan cost per store · M
**Needs:** MEAL-003, SAVE-001. OPX-002 adds data later.

- From `PriceMemory` (and Open Prices once in), estimate the list's cost at each store you know:
  "€42 at Lidl · €47 at Continente · 3 unpriced".
- Offer **Start trip** at the cheapest store, with the estimate as a limit chip
  (`TripStartOptions.limitSuggestions`).

**Done when:** the demo list shows costs for 2 stores that equal the sum of the remembered prices,
and the limit chip equals the estimate rounded up.

### MEAL-005 · Planned vs actual · S
**Needs:** MEAL-004.
A trip started from a plan keeps a link to it. The summary shows the planned cost against the amount
spent, and the items that were not on the plan.

**Done when:** a planned trip with one extra item shows that item and the right difference.

*Compare stores. CMP-001 (a chain on each store) is done; see **Done**.*

### CMP-002 · Compare screen · M
**Needs:** CMP-001, SAVE-001.
A product view with the newest price at each chain, its age and its source (yours or Open Prices),
and a basket view (the list or your regulars) with the total per chain. Prices older than 90 days are
greyed out.

**Done when:** with demo data, the basket totals per chain match INS-07, and old prices are marked as old.

### CMP-003 · Unit price (€/kg, €/L) · M
**Needs:** CMP-002.
Read `quantity` / `product_quantity` from Open Food Facts into `Product`, so different pack sizes are
compared per kg or per litre. Unknown size: no unit-price comparison.

**Done when:** 500 g and 1 kg packs of the same product show the right price per kg.

*Open Prices. OPX-001 (the spike) is done; see **Done**.*

### OPX-002 · Read Open Prices (local cache) · M
**Needs:** OPX-001, CMP-001.
**Scope (owner, 2026-11-19):** Europe and the US; the app keeps only prices from its own country
(see `ARCHITECTURE.md` → OPX-001 spike).
Prices are fetched after the scan and cached in a new `ExternalPrice` model, not synced (like the OFF
cache). Only 13-digit GTINs are sent, up to 100 a request, never the cart or the country: each price
carries its store's country and `osm_brand`, and the app filters on the device. Chains come from
`osm_brand` first; a match on the store name is a guess. Batched and queued offline, following
`ProductEnricher`. Results feed CMP-002, MEAL-004 and INS-11 (marked as external). Attribution on the
About screen.

**Done when:** stubbed tests cover a hit, a miss with a cache time limit, and the offline queue; an
opt-in live test gets one real price; the privacy page and App Privacy labels are re-checked
(REL-001, WEB-002).

### OPX-003 · Send your prices to Open Prices (opt-in) · M · (after P2)
**Needs:** OPX-002, GATE-002.

- Off by default. Needs an Open Food Facts account.
- Sends only GTIN, price, currency, date and OSM shop.
- A preview shows what will be sent before it goes.
- Legal pages and App Privacy labels updated.

**Done when:** one test price shows on Open Prices, and turning the option off stops all sending.

*Region.*

### REG-001 · Portuguese (Portugal) · M
The app is English only. Add a String Catalog with pt-PT, plus pt-PT App Store metadata and
screenshots. Money formatting already follows the currency.

**Done when:** with the phone in pt-PT, no English remains on the trip, scan, list, meal and insights
screens, and the owner has checked a UI-test screenshot of each.

### REG-002 · Region defaults · S
Country and currency come from the phone's region on first launch. The chain list (CMP-001) and the
price-in-barcode table (INS-105) are chosen by the store's `countryCode`.

**Done when:** a fresh install in each of PT, ES and US gives that country's currency and chain list.

*Later (after P2). Listed so nobody re-litigates them.*

- **MEAL-101 · AI week-plan suggestions (Haiku).** Needs a server: the key cannot ship in the app.
  Read `platform/infra/docs/llm-haiku-trial.md` first.
- **CMP-101 · Chain catalogue prices for Portugal (scraping).** Not chosen (terms-of-service risk).
- **SAVE-101 · Savings on the web stats page (P9).**
- **OPX-101 · Claude web search for price gaps (parked by the owner 2026-11-19).** Use the Messages
  API `web_search` server tool, on the server, to fill prices that Open Prices lacks, mostly in
  Portugal. Needs the server and P2, like MEAL-101. Before it starts: measure the hit rate on real
  GTINs and the cost per lookup (searches are billed on top of tokens, and the trial workspace is
  capped at $20), and check that it is not CMP-101 by another route (chain sites' terms). Read
  `platform/infra/docs/llm-haiku-trial.md` first.

---

## P7 — Live Activity and widgets

### LIVE-001 · Trip Live Activity · M
**Needs:** IOS-002.
ActivityKit Live Activity with total, limit bar and remaining. Compact and expanded Dynamic Island. Updated locally on every add; no push server.

**Done when:** with the phone locked mid-trip, the Lock Screen shows the right total after an add, and the activity ends on Finish.

**Status 2026-11-15: built on `feat/zero-tap-scan`, works on the simulator, not yet signed.** New target
`scanitWidgets` (bundle IDs `…scanit.widgets` and `…scanit.beta.widgets`) draws the Lock Screen banner and the
Dynamic Island; `TripActivityController` starts, updates and ends it from `SessionStore`. A UI test sees the total
in the Dynamic Island and sees it go when the trip is finished. **Needs from the owner before this reaches `main`:**
run the `seed_signing` lane once (it creates the two App IDs and their profiles in the shared match repo). Until
then the `beta` and `release` lanes fail at `match`, because `Matchfile` now lists the two new IDs. Not yet seen on
a locked phone.

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

- **Crowd prices beyond Open Prices (our own pool).** Privacy, moderation, and needs scale first. Open Prices is read in OPX-002 and contributed to, opt-in, in OPX-003 (owner decision 2026-11-16).
- **Store auto-detect by location.** It needs a location permission. Manual store chips are fine for v1.
- **Receipt scanning.** Norviq already does it.
- **Export trips to Norviq** as grocery spend. Revisit only if both apps have users.
- **Multi-currency conversion.** Totals and savings are per currency, never converted (confirmed 2026-11-16).
- **Cross-platform unlock** (buy on iOS, unlocked on Android). It needs server-side receipt validation and entitlements.
- **"Sync on Wi-Fi only" toggle.** Payloads are a few KB, so any network is fine for now.
- **Shared household trips** (two phones, one cart).
- **AI insights / LLM.** If ever, read `platform/infra/docs/llm-haiku-trial.md` first.

## Done

### SAVE-002 · Saving on the trip summary and in History · S
**Needs:** SAVE-001.

- The finish sheet (`TripSummary.swift`) shows "Saved €3,40 vs other stores" and "Could have saved €1,10 at Lidl".
- History rows show each trip's saving.
- The share card (ADD-002) can include the saving.

**Done when:** a demo-data trip shows both numbers, and a trip with no reference prices shows neither.

**Closed 2026-11-19:** the finish sheet, a past trip and History rows show INS-12 and INS-13
(`TripSavingSummary`, `InsightsSource.tripSavings`, one calculator per trip currency). Demo trips,
worked by hand: 2 days ago +€0,60, 6 days ago −€1,46 with €1,46 missed at Lidl, 13 days ago +€0,90
on 3 of 4 products, the first trip shows nothing. UI test: a new store saves €0,25 and could have
saved €0,30 at Lidl; a trip with no other store shows neither. The share card adds the saving only
when positive. The missed line names the store that missed most with its own amount, never the
trip's total across stores (three-store test). Wording in `DESIGN.md` §6. Owner verdict pending on wording and the green tint
(dark-mode small-text contrast is the open DESIGN item).

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

### SAVE-001 · Savings definitions in ScanItCore · M
Pure functions for INS-11…14 (`DESIGN.md`), so the server can run the same maths in P9.

**Done when:** every INS-11…14 case has a fixture test, and a deliberately wrong expected value fails.

**Closed 2026-11-16:**

- **Code:** `ScanItCore/Savings.swift` extends `InsightsCalculator` with `tripSaving(_:)` (INS-11…13, per
  line and per trip, plus missed saving per store) and `savings(in:)` (INS-14). The "latest price per
  store" rule is now one helper shared with INS-07.
- **Definition pinned while building:** the 90-day window counts back from the trip's end, not from
  today, so a past trip's saving never moves. With an even number of stores, the reference is the mean of
  the two middle prices, rounded half up. Both are written in `DESIGN.md`.
- **Fixture:** `Fixtures/savings.json` holds 3 EUR trips and 1 USD trip over 4 + 2 stores, with the
  working for every line written next to the expected values. It covers an odd and an even median, a
  negative saving, an unpriced line, an in-store code, a price older than 90 days, a price after the
  trip's end, the trip's own store being left out, and a month boundary.
- **Checked:** `swift test` runs 44 tests, all passing. With T1's saving set to 83 and T2's milk
  reference set to 96, the suite failed on exactly those two values.

### BUD-001 · Budget per currency · S
`BudgetStore` held one `Money`. Keep one budget per currency, so a € and a $ budget can both exist.

**Done when:** a € budget and a $ budget each show on Insights against their own month's spend, and
an existing single budget survives the update.

**Closed 2026-11-16:**

- **Store:** `BudgetStore` keeps a budget per currency under `monthlyBudgets`. ADD-003's single budget
  (`monthlyBudget.minor` / `.currency`) is moved over on first launch and the old keys are removed.
- **Insights:** the "Monthly budget" section has one row for each currency the user has finished a
  trip in or has a budget in, the Insights currency first. Each row is measured against that
  currency's month (`InsightsSource.monthSpend`). With more than one row, each names its currency.
  Nothing is converted.
- **Tests:** unit tests cover € and $ side by side, removing one, the migration, and per-currency
  month spend (84 passing). UI test `testBudgetsInTwoCurrencies` sets €500 and $100 on demo data plus a
  dollar trip (`-ui-testing-demo-usd-trip`) and checks that each row shows its own currency.
- **Found on the way:** on the simulator the budget sheet sometimes opens with the field focused
  but no keyboard, so typed keys are lost. The UI test now taps the field and waits for the value
  before **Save**. Not seen on a device. Also, `testInsightsWithHistory` accepts any "of " text as
  proof the budget saved, and the "5 of 5" tile always matches, so it would not catch a broken save.

### CMP-001 · Chain on a store · S
`Store.chain` existed but was never filled in. Offer a chain list per country when a store is added.
Comparisons are by chain within a country, not by branch.

**Done when:** a new Portuguese store gets a chain in one tap, and older stores can be given one in Settings.

**Closed 2026-11-16:**

- **Catalogue:** `scanit-core/Sources/ScanItCore/Resources/chains.json`, read by `ChainCatalog`.
  Portugal: Continente, Pingo Doce, Lidl, Aldi, Auchan, Intermarché, Mercadona, Minipreço; 8 each for
  Spain and France, 10 for the US. One `id` per chain in every country (Auchan is "Alcampo" in Spain).
  Android reads the same file. Not checked: whether each chain still trades under that name in each
  country (Auchan Portugal is turning Minipreço shops into My Auchan; both names are kept).
- **Matching:** a typed name is matched on whole words after folding case, accents and punctuation,
  longest match first ("Pingo Doce Benfica" → Pingo Doce; "Lidlx" and "Super Mercado" match nothing).
- **New store:** the start sheet shows the country's chains under the name field. One tap tags the
  chain and names the store; typing a chain's name tags it too. The country is the phone's region.
- **Older stores:** About → Stores (until Settings exists) lists every store with a chain picker, and
  offers "Set to Lidl" when the name looks like a chain. Changing it marks the store for sync.
- **Tests:** `ChainCatalogTests` (Linux CI); UI tests `testNewStoreTakesAChainInOneTap` and
  `testOlderStoreGetsAChainInStores`, both with `-AppleLocale en_PT`.
- **Found on the way:** Swift 6.2.3 crashes in IRGen on `Binding(get:set: method)` in this target;
  `StoresView` passes a closure instead. `testStartWithLimitThenWithoutAndStoreIsRemembered` failed
  once because its first tap on **Start shopping** came during launch and the sheet never opened; it
  passed 3 of 3 reruns.

### OPX-001 · Spike: Open Prices for Portugal · S
Check the API (product lookup, place and date filters, paging, rate limits), the licence (ODbL:
attribution and share-alike), how many prices exist for the owner's 20 most-bought GTINs in Portugal,
and how places map to chains (OSM `brand` / `brand:wikidata`).

**Done when:** the hit rate on those 20 GTINs and the go/no-go are written in `ARCHITECTURE.md` →
Open Prices. If Portugal coverage is too thin, the owner decides whether OPX-002 ships for other
countries only or is dropped.

**Closed 2026-11-19:** findings in `ARCHITECTURE.md` → Open Prices → OPX-001 spike. Portugal: 404
prices all time, 78 in the last 90 days over 68 products, none at two or more chains; proxy hit rate
0 of 20 in 90 days. The owner's own 20-GTIN hit rate was skipped by the owner. API: keyless, batches
of 100 codes, 13-digit codes, country per price, no rate limit found; ODbL. Decision (owner): OPX-002
ships for Europe and the US.

### MEAL-003 · Plan to shopping list · S
**Needs:** MEAL-002, ADD-005.

- "Add to list" merges the plan's ingredients into `ListItem`s through `ShoppingList.add(_:code:)`.
- Duplicates are combined, and quantities are scaled by servings.
- An ingredient can be marked "in pantry" so it is left out.

**Done when:** two meals that share an ingredient produce one list line with the combined quantity,
and scanning still ticks it.

**Closed 2026-11-18:**

- **Merge:** `ScanItCore.PlanList` merges the week's ingredients on their GTIN, or on their folded
  words when typed ("Fruta" and "frúta " are one line), in the order they first appear. Each counts
  quantity × planned servings ÷ the meal's servings; a line's amounts are added as exact fractions
  and rounded up once to whole packs, so three thirds make one pack. Each line names the meals that
  need it. Fixture `Fixtures/plan-list.json`, hand-computed; planted wrong values fail.
- **List:** `ListItem.quantity` (default 1, so older stores open as they are), shown as
  "2 × Pão de forma". `ShoppingList.merge` raises a waiting line to what the week needs and never
  adds to it, so adding the same week twice does not double it and a line typed by hand is reused.
  A scan still ticks the whole line, by code or by name.
- **Pantry:** `MealIngredient.inPantry`. The **Add to shopping list** sheet on the Plan tab lists
  every line ticked; unticking one marks it at home in every meal that has it, so next week it starts
  unticked. Ticking it again clears the mark.
- **Tests:** `PlanListTests` (Linux CI); `PlanToListTests`: two meals sharing bread give one line of
  3 packs and a scan through `SessionStore` ticks it, at-home is remembered and undone, adding twice
  does not double, merge never lowers a quantity. UI test
  `testPlannedWeekGoesOnTheListAndAScanTicksIt` plans two meals, leaves the cheese at home, adds
  4 lines, and scanning the bread on a trip ticks "2 × Pão de forma".
- **Found on the way:** the Mac's internal disk filled up (3.6 GB free) and the simulator could not
  install the app. Builds and result bundles now go to the SSD with `-derivedDataPath`.
- **Found on the way:** `testPaywallAtStartAndLockedHistory` started failing on `main` too: a
  StoreKit test purchase of Unlimited was left on the simulator, and UI tests run on a throwaway
  store but not a throwaway StoreKit. Under `-ui-testing` the app now ignores the simulator's
  entitlements (`PurchaseStore(ignoresDeviceEntitlements:)`), and `PurchaseStoreTests` clears its
  transactions in a `defer`. The paywall test passed 3 of 3 after.

### MEAL-002 · Week plan · M
**Needs:** MEAL-001.
A `PlanEntry` model (date, slot, meal, servings). A **Plan** tab of its own (owner, 2026-11-16) holds a week view that puts meals into days; a meal can be
copied from last week.

**Done when:** a UI test builds a 7-day plan with 10 meals in under 2 minutes, and the plan survives a relaunch.

**Closed 2026-11-18:**

- **Model and rules:** `Domain/MealPlan.swift`: `PlanEntry` (`day` as `yyyy-MM-dd`, `slot`, `meal`,
  `servings`), `PlanWeek` and `MealPlan`. The day is a calendar day, not an instant, so time zones
  do not move the plan. Two slots, lunch and dinner, stored as raw strings so more can come without a
  migration. One meal per slot: planning another replaces it. A planned meal starts at the meal's own
  servings (1–12). The week starts on the phone's first weekday (CLDR gives Portugal Sunday; the iOS
  setting changes it). Deleting a meal soft-deletes its plan entries.
- **Copy last week:** fills only this week's empty slots from the same weekday and slot, with the same
  servings, and leaves last week alone. The button says how many it will copy and hides when there is
  nothing to copy.
- **Cost, for the mission:** `ScanItCore.PlanCost` scales each meal's total to the planned servings
  (half up) and adds up the rounded costs, so the rows add up to the week. A week with an unpriced
  ingredient says "At least". Never converts: another currency counts as unpriced. Fixture
  `Fixtures/plan-cost.json`, hand-computed; planted wrong values fail.
- **Screens:** a **Plan** tab between Trip and History: week switcher, the week's cost on top, then
  each day's lunch and dinner. An empty slot opens a meal picker that shows each meal's cost a
  serving and can make a new meal. A planned meal opens to servings, cost, edit, change and remove.
  **Meals moved from the Trip tab to the Plan tab**, which is where they are used now.
- **Tests:** `PlanCostTests` (Linux CI); `MealPlanTests`: week start across DST and the new year,
  10 meals on 7 days surviving a relaunch (a file store), one meal per slot, copy, deleted meals, the
  week's cost from demo prices. UI test `testWeekPlanWithTenMealsInUnderTwoMinutes` plans 10 meals
  in under 2 minutes (the whole test takes about 80 s) and copies them into next week. The relaunch
  half is the unit test, because UI tests run on a throwaway store. `testMealFromPastPurchasesShowsItsCost` now opens Meals from the Plan tab.

### MEAL-001 · Meal model · M
`Meal` (name, servings, note) and `MealIngredient` (meal, text, `code?`, quantity), both `nonisolated`
`SyncedRecord`s. Ingredients are picked from past purchases or typed. Screens: list, create, edit, delete.

**Done when:** a meal with 5 ingredients, 3 of them from past scans, survives a relaunch, and a
deleted meal is hidden (soft delete).

**Closed 2026-11-16:**

- **Models and rules:** `Domain/Meals.swift`: `Meal`, `MealIngredient` and `MealBook`. The same product or
  the same words add a pack instead of a second line. Servings 1–12, packs 1–20. Deleting soft-deletes
  the meal and its ingredients. A new meal left with no name and no ingredients is removed outright
  (it was never synced); one with ingredients but no name becomes "Untitled meal".
- **Cost, for the mission:** `ScanItCore.MealCost` prices each ingredient at the cheapest of the latest
  price per store over 90 days, in the home currency, times whole packs, and gives the meal's total and
  cost a serving (half up). Unpriced ingredients (typed, in-store codes, nothing seen in 90 days) are
  counted, and the meal then says "at least". On a price tie the most recently seen store wins.
  Fixture `Fixtures/meal-cost.json`, hand-computed, shared with Android.
- **Screens:** **Meals** beside **Shopping list** on the Trip tab (no new tab). The list shows cost a
  serving and in total, and can sort by cost a serving, cheapest first. The editor puts cost above the
  ingredients; each ingredient says where its price was seen ("at Lidl · 14 Nov"), and suggestions
  from past purchases show their price so the cheaper product is easy to pick.
- **Tests:** core 54 (wrong per-serving and line totals both failed when planted). Unit tests: relaunch
  through an on-disk store (`ScanItSchema.container(url:)`), soft delete, packs instead of duplicates,
  empty draft discarded, ranges, cheapest recent price. UI test `testMealFromPastPurchasesShowsItsCost`.
- **Fixed on the way:** sheets opened from the Trip tab's empty state inherited its centred text, so
  the shopping list's and meals' text fields were centred; both sheets now set leading alignment.
- **Owner, 2026-11-16:** the week plan (MEAL-002) gets its own tab. The pixels are drafts for the owner's verdict.
