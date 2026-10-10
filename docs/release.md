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

## Stage 1: TestFlight, internal (automatic from `main`)

The setup mirrors Norviq:

- **Signing:** fastlane match reads **Khepri's** certificates repo (`NorthAIProject/north-ios-certificates`, certificate `BC73LRR48W`, expires 2027-09-23) with Khepri's match password. The team is at Apple's limit of three distribution certificates, so ScanIt must not create one. It only adds its own profiles to that repo.
- **Two App Store Connect apps:**
  - **ScanIt** (`com.fernandocorreia.scanit`) for the App Store
  - **ScanIt Beta** (`com.fernandocorreia.scanit.beta`) for TestFlight builds, installable next to the store app
- **Automatic uploads:** `.github/workflows/ios-beta.yml` uploads to ScanIt Beta every time `CI` passes on `main`.

| # | Who | Step |
| --- | --- | --- |
| 1.1 | Claude ✅ | **App icon and brand** (2026-10-10): the icon is the owner's ScanItNow logo mark, redrawn as vector, in light, dark and tinted versions. The launch screen shows the mark. The mascot is in the app and on the website. See `brand/README.md`. |
| 1.2 | Claude ✅ | `ITSAppUsesNonExemptEncryption = NO` set. The app only uses standard HTTPS, so no export-compliance question on uploads. |
| 1.3 | Claude ✅ | Pipeline in place (2026-10-10):<br>• a `Beta` build configuration (bundle ID `com.fernandocorreia.scanit.beta`, display name "ScanIt Beta")<br>• `scanit/fastlane/` with the `beta` and `seed_signing` lanes<br>• the `Gemfile` from Norviq<br>• the `iOS beta` workflow |
| 1.4 | Claude ✅ | Both App IDs registered through the App Store Connect API (2026-10-10): `com.fernandocorreia.scanit` ("ScanIt") and `com.fernandocorreia.scanit.beta` ("ScanIt Beta"). |
| 1.5 | You ✅ | Done 2026-10-10 as **ScanItNow** and **ScanItNow Beta** ("ScanIt" was taken). **Create the two apps.** App Store Connect → Apps → **+** → New App, twice:<br>• Platform iOS, name **ScanIt**, primary language English (U.K.) or Portuguese, bundle ID `com.fernandocorreia.scanit`, SKU `scanit`, User Access Full.<br>• Platform iOS, name **ScanIt Beta** (if taken, "ScanIt TestFlight"), same language, bundle ID `com.fernandocorreia.scanit.beta`, SKU `scanit-beta`.<br>The beta app is never released, so its name only matters on TestFlight. |
| 1.6 | Claude ✅ + You ✅ | Secrets on `FACorreiaa/scanit`. Set by Claude (2026-10-10): `ASC_KEY_ID` (46PLPRZ868), `ASC_ISSUER_ID` and `ASC_KEY_P8`, from the team-wide key. **You** set the two Khepri values; each command prompts for the value, so nothing lands in your shell history:<br>`gh secret set MATCH_PASSWORD -R FACorreiaa/scanit` (Khepri's match password)<br>`gh secret set MATCH_GIT_BASIC_AUTHORIZATION -R FACorreiaa/scanit` (paste the same value as Khepri's secret of that name: base64 of `x-access-token:<PAT>`, where the PAT can read and write `NorthAIProject/north-ios-certificates`). |
| 1.7 | You ✅ | Done 2026-10-10: profiles for both bundle IDs were created in Khepri's repo with certificate BC73LRR48W, and no new certificate. **Seed signing once.** Actions → **iOS beta** → Run workflow → lane `seed_signing`. It adds the App Store profiles for both bundle IDs to Khepri's match repo, using certificate `BC73LRR48W`; Khepri's profiles are untouched. Or run it locally, since your git login can already push to that repo:<br>`! cd scanit && MATCH_PASSWORD='…' ASC_KEY_ID=46PLPRZ868 ASC_ISSUER_ID=7382d47b-5a08-4122-a9ed-4ded697ade84 ASC_KEY_P8="$(base64 -i ~/Downloads/AuthKey_46PLPRZ868.p8)" "$(ruby -e 'puts Gem.bindir')/fastlane" seed_signing` |
| 1.8 | You ✅ | Done 2026-10-10: build 1 uploaded and processed (VALID). **First upload.** Actions → **iOS beta** → Run workflow → lane `beta` (or just push to `main`). About 15 minutes later the build appears under App Store Connect → ScanIt Beta → TestFlight. From now on, every push to `main` that passes CI uploads a new build automatically. |
| 1.9 | You ✅ | Done 2026-10-10: internal group with auto-distribute and 1 tester. It is named "External Testers" but is internal; create a real external group in Stage 3. **Internal testers.** ScanIt Beta → TestFlight → Internal Testing → **+** group "Team" → add yourself → turn on **Automatically distribute builds**. Internal testing needs no Apple review. |
| 1.10 | You | Install **TestFlight** from the App Store, then **ScanIt Beta**. Do the first real test: one trip in a real supermarket **in airplane mode** (BACKLOG IOS-013), scanning EAN-13 and EAN-8 barcodes and a QR code (IOS-005). |
| 1.11 | You | Take about 20 shelf-label photos during that trip, for `tools/label-bench` (IOS-006). |

**Cost note.** On a private repo, macOS runner minutes count ×10 against the GitHub plan. Each beta build is about 15 macOS minutes, on top of CI's iOS job. If that adds up, switch the trigger to tags (`v*`) instead of every push. It is a one-line change in `ios-beta.yml`.

**Local alternative** (no CI): `cd scanit && bundle install`, export the same five variables, then `bundle exec fastlane beta`.

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
| 3.3 | You | **ScanIt Beta** → TestFlight → **External Testing** → new group "Strangers" → add the build. Fill in **Test Information**: what to test ("do one real shop with it"), feedback email, contact. |
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
| 4.9 | You or Claude | Claude adds a manual `release` lane plus a dispatch job (with a required reviewer, like Norviq's `app-store` environment) for the `com.fernandocorreia.scanit` app. Then upload the release build, select it under the version, then **Add for Review** → **Submit**. Review usually takes 24–48 h. Choose manual release, so you pick the day. |
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
