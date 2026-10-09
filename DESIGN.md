# ScanIt — Design

Status: first draft by an agent, 2026-10-09. **Every visual decision here is a proposal; the owner
keeps the verdict.** ScreensDesign research was not possible (the MCP needs a Pro subscription), so
the references below come from well-known patterns, not recorded screens. Re-check them when the
MCP is available (backlog item DES-002).

## Design rule

The user is standing in an aisle, often with one hand on a trolley. So:

1. **The total is the hero.** It is visible on every trip screen, big and in tabular digits.
2. **One-handed.** Primary actions sit in the bottom third. Nothing important is top-left.
3. **Two taps per item at most** when the price is remembered: scan, then confirm.
4. **The limit speaks in colour and haptics, not in modals.** Never block a scan to warn about the limit.
5. **Calm, not gamified.** No streaks, no confetti for spending less. Numbers, plainly.

## Information architecture

Tab bar with 3 tabs. Settings live behind the avatar in the History and Insights headers.

| Tab | Purpose |
| --- | --- |
| **Trip** | Start a trip. The active trip becomes the whole tab. |
| **History** | Past trips, newest first, grouped by month with the month's total. |
| **Insights** | Numbers and charts (catalogue below). |

## Flows

### 1. First launch (no account)

1. One welcome screen: "See what your trolley costs before the till". Single **Start** button.
2. **Camera primer** screen explaining why, shown before the system prompt (we get one chance at the system prompt).
3. Land on the Trip tab, empty state with a large **Start a trip** button.

There is no sign-in on first launch. Sign-in is offered later, in Settings and once on the first trip summary ("Back up your trips").

### 2. Start a trip (sheet, medium detent)

| Field | Behaviour |
| --- | --- |
| Store | Recent stores as chips, plus "New store". The last one used is preselected. |
| Limit | Optional. Number pad, with quick chips from the user's own history (last limit, average trip). Can be left empty. |
| Currency | Taken from the store, and editable. |

The **Start** button sits at the bottom.

### 3. Active trip (Trip tab)

```
┌─────────────────────────────┐
│ Lidl · 14 items        ⋯    │
│                             │
│        €42.80               │  ← hero total, tabular digits
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓░░░  of €60   │  ← limit bar, green → amber ≥80% → red >100%
│  €17.20 left                │
├─────────────────────────────┤
│ Cart (newest first)         │
│  Milk 1L        2 × €0.99   │  swipe: delete · tap: edit qty/price
│  Bread          €1.49   ⟳   │  ⟳ = remembered price
│  …                          │
├─────────────────────────────┤
│   [  ⌁  Scan  ]   Finish    │  ← big scan button bottom-centre
└─────────────────────────────┘
```

### 4. Scanner (full-screen cover)

- The camera fills the screen.
- **Top HUD** is a compact total and limit bar, so the number stays visible while scanning.
- A reticle shows the barcode lock. On lock: a light haptic, the reticle snaps, and the code shows under it.
- **Step 2, price:**
  - **Remembered price:** the confirm sheet comes up straight away with the price filled in and marked "seen 12 d ago". Scanning the shelf price is optional, to refresh it.
  - **Not remembered:** the prompt is "Point at the shelf price". Candidate prices get highlighted boxes, and the top candidate pre-fills. The **Type it** keypad button is always visible.
- **Confirm sheet** (small detent):
  - product name and photo from Open Food Facts once they arrive, otherwise "Product 5601234…"
  - price, editable
  - quantity stepper
  - big **Add** button at the bottom

  After **Add**, the scanner stays open for the next item, and the HUD total animates up.
- Barcode with no price found after about 3 s: the prompt changes to "Type the price".
- Unsupported device (older than A12): barcode-only scanner plus keypad, with the same confirm sheet.

### 5. Limit states

| State | HUD | Haptic | Copy |
| --- | --- | --- | --- |
| No limit | neutral | — | "€42.80" |
| OK (< 80 %) | accent | — | "€17.20 left" |
| Near (≥ 80 %) | amber | `.warning` once on crossing | "€6.10 left · about 2 items" (items estimated from the user's average item price) |
| Over (> 100 %) | red | `.error` once on crossing | "€3.40 over" |

Removing an item that brings the total back under the limit is allowed and silent.

### 6. Finish trip

The **Finish** button shows a summary:

- total
- limit result
- number of items
- difference from the last trip at the same store
- the three biggest-ticket lines

From there, **Done** or **Undo finish**.

Optional field: "Actual till total". It lets the user record what they really paid (the gap is an insight: missed items, wrong prices).

### 7. History → Trip detail

A read-only list of a finished trip. Editing is allowed (people fix prices afterwards). It reuses the cart rows.

### 8. Account (Settings)

- Sign in with Apple and Sign in with Google buttons (both in their official styles). Apple goes first, following the platform norm.
- Sync status line: "Backed up 2 min ago", "3 changes waiting, will sync when you're online", or "Offline".
  It is never shown as an alert. Offline is normal in a supermarket.
- **ScanIt Unlimited** row: shows "Unlocked", or the price and a **Restore purchases** link.
- Export CSV.
- **Delete account**, as a destructive action with a confirmation. The copy says: "Your account and
  cloud backup are deleted. Your trips stay on this phone." The local data is kept.
- Privacy policy and terms links.

### 9. Unlock (paywall)

- **When it appears:** only when the user taps **Start trip** after using the month's free trips, or taps a hidden older trip in History. Never during an active trip, never on launch.
- **Layout:** one sheet. It shows:
  - what the user has done ("You've done 4 trips this month")
  - what unlocking gives: unlimited trips and the full history
  - the one-time price, with "No subscription"
  - a **Unlock** button
  - **Not now** and **Restore purchases** links

  It is dismissable with no penalty. The history list shows hidden trips as a single locked "12 older trips" row, not as missing data.

## Insights catalogue

These definitions are the contract. iOS `InsightsCalculator` and the server's `/v1/stats` (P9)
must compute the same thing. "Trip" means a finished session. Amounts are summed per currency
and never converted.

| ID | Number | Definition |
| --- | --- | --- |
| INS-01 | Spent this week / month | Σ trip totals with `endedAt` in the period; delta vs previous period, in % and absolute |
| INS-02 | Average trip | mean trip total over last 90 days |
| INS-03 | Trips under limit | finished trips with a limit where total ≤ limit, ÷ finished trips with a limit, last 90 days |
| INS-04 | Spend by store | Σ trip totals per store, period selectable |
| INS-05 | Top products by spend | Σ (qty × unit price) per GTIN, top 10, period selectable |
| INS-06 | Price change | per GTIN per store: latest observation vs first in the last 180 days, in %. Shown on product rows ("+12 % since May") and as a "biggest risers" list |
| INS-07 | Cheapest store for your regulars | for GTINs bought ≥ 3 times, latest price per store; show where it is lowest and the saving |
| INS-08 | Category split | Σ spend by first Open Food Facts category; unknown is shown as "Other" |
| INS-09 | Till gap | mean (actual till total − scanned total) over trips where the till total was entered |
| INS-10 | Personal basket inflation | weighted price change of the user's regular basket (INS-07 GTINs) over 90 days. Norviq's `PersonalInflationCalculator` is the reference for method |

A chart is shown only when its data is meaningful. The minimum is 3 finished trips. Below that, show a plain "after 3 trips you'll see…" placeholder. Charts follow the `dataviz` skill.

## Visual direction (proposal)

- **Native first:** SwiftUI system components, SF Pro (one font design everywhere, including widgets), Dynamic Type everywhere. The hero total is SF Pro **light** at 48 pt scaled with Dynamic Type (`@ScaledMetric`), with `.monospacedDigit()`. Changed from SF Pro Rounded on 2026-10-09 so the app uses a single font design.
- **Colour:** one accent, green `#248A3D` in both modes (Apple's accessible green; white button text on it passes contrast), plus amber and red reserved strictly for the limit states. Neutral greys otherwise. Full dark mode.
- **Materials:** the scanner HUD uses `.ultraThinMaterial` over the camera, so the total stays legible on any background.
- **Motion:**
  - The total rolls up with `.contentTransition(.numericText())`.
  - The limit bar animates width and colour together.
  - Reduce Motion turns both into crossfades.
- **Accessibility:**
  - VoiceOver reads the total and remaining after every add.
  - Colour is never the only signal; there is always a text state.
  - Hit targets are at least 44 pt.

## References (steal tone, not layout)

Unverified via ScreensDesign. Check them in DES-002.

| Reference | What to take |
| --- | --- |
| Apple Wallet / Apple Card | calm money summary, category colours |
| Copilot Money | insights density without clutter |
| Yuka | scan-first product card from a barcode, fast confirmation |
| Bring! / AnyList | shopping-context ergonomics |

## Do not

- Do not force sign-in. Do not paywall the scanner, and never interrupt an active trip with the paywall.
- Do not show offline or sync errors during a trip.
- Do not show a modal while the camera is open, except the confirm sheet.
- Do not convert currencies or guess prices from the internet.
- Do not use red anywhere except "over limit" and destructive actions.
