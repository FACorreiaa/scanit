# ScanIt release runbook

**You** = owner (accounts, money, decisions). **Claude** = code and config in this repo.

**Order matters:**

1. TestFlight (internal)
2. Landing page live
3. TestFlight (external, the strangers gate)
4. App Store v1.0
5. Backend as v1.1

v1.0 needs **no backend**: the app is local-first. The backend only adds sign-in, sync and web stats, and per the
owner rules it waits until 10 strangers have used the app (BACKLOG P2 → P4).

**Costs:**

| Item | Cost |
| --- | --- |
| Apple Developer Program | €99/year (team `84X9WYBF36` is already in the project) |
| Domain | about €10/year |
| Cloudflare | free |
| Cluster | already running |

---

## Stage 1: TestFlight, internal (you on your own phone)

| # | Who | Step |
| --- | --- | --- |
| 1.1 | Claude | Add an **app icon**. The `AppIcon` asset is empty, and App Store Connect rejects uploads without one. Claude drafts a 1024×1024 icon; you approve it or supply your own. |
| 1.2 | Claude | Add `ITSAppUsesNonExemptEncryption = NO` to the Info.plist. The app only uses standard HTTPS, so this skips the export-compliance question on every build. |
| 1.3 | You | Check the name is free: App Store Connect → Apps → **+** → New App. Fill in iOS, name **ScanIt** (if taken, try "ScanIt: Shopping Total"), language, bundle ID `com.fernandocorreia.scanit`, SKU `scanit`. Creating the record reserves the name. |
| 1.4 | You | Xcode → Settings → Accounts: make sure you are signed in to the Apple ID for team `84X9WYBF36`. |
| 1.5 | You or Claude | Archive and upload. In Xcode: scheme `scanit`, destination **Any iOS Device**, Product → **Archive**, then Distribute App → **App Store Connect** → Upload. Or Claude runs `xcodebuild archive` + `-exportArchive` with your Xcode login. |
| 1.6 | You | App Store Connect → TestFlight: wait for "Processing" to finish (about 10–30 min), then add yourself under **Internal Testing**. Internal testing needs no review. |
| 1.7 | You | Install **TestFlight** from the App Store on your iPhone and install ScanIt. Do the first real test: one trip in a real supermarket **in airplane mode** (BACKLOG IOS-013), scanning EAN-13 and EAN-8 barcodes and a QR code (IOS-005). |
| 1.8 | You | Take about 20 shelf-label photos during that trip, for `tools/label-bench` (IOS-006). |

## Stage 2: Landing page live (needed before external TestFlight)

| # | Who | Step |
| --- | --- | --- |
| 2.1 | You | Buy a domain. Cloudflare Registrar sells at cost and keeps DNS in one place. |
| 2.2 | You | Set up a contact email: Cloudflare → your domain → **Email Routing**, create for example `hello@<domain>` forwarding to your inbox. Free. |
| 2.3 | Claude | Put the domain and contact email into `scanit-web/src/lib/config.ts` and the docs. This replaces every `{{domain}}`. |
| 2.4 | You | Read `/privacy`, `/terms` and `/delete-account` and sign off (WEB-002). They are AI-drafted, not legal advice. |
| 2.5 | You | `cd scanit-web && npx wrangler login`, then `npm run deploy`. That gives a `*.workers.dev` URL. |
| 2.6 | You | Cloudflare → Workers → `scanit-web` → Settings → **Domains & Routes** → add `<domain>` (and `www`). |
| 2.7 | You | App Store Connect → App Information: **Privacy Policy URL** `https://<domain>/privacy`. Under the version, set **Support URL** `https://<domain>`. |

## Stage 3: TestFlight, external (the 10 strangers)

| # | Who | Step |
| --- | --- | --- |
| 3.1 | You | Create a **PostHog** project ("ScanIt", EU cloud) and a **Sentry** project (iOS). Send Claude the PostHog project key and Sentry DSN. Without them you cannot count who finished a trip (FND-004). |
| 3.2 | Claude | Wire PostHog and Sentry, keeping the keys in a gitignored xcconfig. Bump the build number and upload a new build. |
| 3.3 | You | TestFlight → **External Testing** → new group "Strangers" → add the build. Fill in **Test Information**: what to test ("do one real shop with it"), feedback email, contact. |
| 3.4 | You | Submit for **Beta App Review** (usually under 24 h). Once approved, enable the **public link**. |
| 3.5 | You | Share the link outside friends and family (`demand-hour` skill). The gate passes when 10 strangers have each finished a trip, counted from `trip_finished` in PostHog (GATE-002). |
| 3.6 | Claude | Turn feedback into backlog items (GATE-003). |

## Stage 4: App Store v1.0

| # | Who | Step |
| --- | --- | --- |
| 4.1 | You | Decide the unlock **price** (placeholder €4,99), the **free limits** (proposed 4 trips per month, last 10 visible) and whether Insights includes hidden trips (REL-003). |
| 4.2 | You | App Store Connect → Business → **Agreements, Tax and Banking**: activate the **Paid Apps** agreement (bank account and tax forms). In-app purchases cannot go live without it, and it can take a few days. |
| 4.3 | You | App Store Connect → ScanIt → Monetization → **In-App Purchases** → **+** Non-Consumable. Product ID `com.fernandocorreia.scanit.unlimited`, reference name "ScanIt Unlimited", price, display name and description, plus a review screenshot of the paywall (Claude can produce it). |
| 4.4 | Claude | Switch the paywall on for release builds only (`PaywallPolicy`). Set the Open Food Facts User-Agent contact. |
| 4.5 | You | **App Privacy**. Data collected: **Usage Data → Product Interaction** and **Diagnostics → Crash Data**, both *not linked to you* and *not used for tracking*. Nothing else; the barcode lookup goes to Open Food Facts without identifiers (REL-001). |
| 4.6 | Claude | Produce App Store **screenshots**: 6.9" iPhone, 1320×2868, 3–5 of them, from demo data (`aso-appstore-screenshots` skill). Draft the subtitle, description and keywords. You approve. |
| 4.7 | You | Fill in the listing: category **Shopping** (or Finance), age rating questionnaire (all "None", so 4+), copyright, and the screenshots and texts from 4.6. |
| 4.8 | You | **Review notes**: "No login. The camera reads product barcodes; prices are typed or read from the shelf label. Any packaged product's barcode works for testing. The one-time purchase appears when starting a trip after the free trips in a month." Attach the IAP to this version. |
| 4.9 | You or Claude | Upload the release build, select it under the version, then **Add for Review** → **Submit**. Review usually takes 24–48 h. Choose manual release, so you pick the day. |
| 4.10 | You | Release. Put the App Store link in `config.ts → downloadUrl` (Claude), then redeploy the site. |

## Stage 5: Backend (v1.1, after the strangers gate)

| # | Who | Step |
| --- | --- | --- |
| 5.1 | Claude | Build `scanit-server` from the aaru template (Hummingbird 2, OpenAPI, Fluent): auth, sync and delete-account endpoints, with tests (SRV-001…, AUTH-001/002, SYNC-001). |
| 5.2 | You | Apple Developer → Identifiers → the ScanIt App ID → enable **Sign in with Apple**. Create a **Sign in with Apple key** (.p8) and send it to Claude privately. Apple requires revoking the user's Apple tokens when they delete their account, and that call needs this key. |
| 5.3 | You | Google Cloud Console → new project "ScanIt". Set up the **OAuth consent screen** (External; app name, support email, privacy URL), then create OAuth client IDs: **iOS** (bundle ID `com.fernandocorreia.scanit`) and **Web** (used as the server audience). |
| 5.4 | You | DNS: point `api.<domain>` at the cluster ingress. Set it to **DNS only** (grey cloud) so cert-manager's HTTP-01 check reaches Traefik. |
| 5.5 | Claude | In `platform/infra`:<br>• sealed secrets for namespace `horus` (JWT key, Apple, Google, Postgres)<br>• a new database and role on the shared Postgres<br>• `argocd/apps/scanit-production.yaml` and values with ingress `api.<domain>`<br>Merging to `main` deploys. |
| 5.6 | You | GitHub `FACorreiaa/scanit` → Settings → Secrets: add the token the deploy workflow uses to push image tags to `LuminaVault/LuminaVaultInfra`. Same as Norviq's workflow; Claude names the exact secret. |
| 5.7 | Claude | iOS: Account screen, Sign in with Apple and Google, offline-aware sync, delete account (keeps the local copy). Update the privacy policy (the account email is now collected) and the App Privacy labels (Contact Info → Email, *linked to user*). |
| 5.8 | You | Submit **v1.1** like Stage 4: update App Privacy, then submit for review. |

---

### What blocks what

- **Stage 1** needs: the icon (1.1) and the App Store Connect record (1.3).
- **Stage 3** needs: the privacy URL (Stage 2) and PostHog (3.1).
- **Stage 4** needs: the Paid Apps agreement (4.2, can take days, so start early) and the IAP product (4.3).
- **Stage 5** needs: 10 strangers (Stage 3), plus the Apple key and Google client IDs.
