# ScanItNow: App Store listing (v1.0)

Paste into App Store Connect → **ScanItNow** (the production app, not ScanItNow Beta). Field limits were checked
in code (2026-10-10). v1.0 is **free, has no in-app purchase, and collects no data**.

## App Information

| Field | Value |
| --- | --- |
| Name | ScanItNow |
| Subtitle (28/30) | Grocery total & budget limit |
| Category | Primary: **Shopping**. Secondary: **Finance** |
| Content rights | **Yes**, it shows third-party content, **and you have the rights**. Product names and photos come from Open Food Facts under ODbL (data) and CC BY-SA (images); the app credits them on the confirm sheet and in the description. |
| Age rating | Answer **None / No** to every question → **4+** |
| Privacy Policy URL | https://facorreia.com/privacy/scanitnow |
| License agreement | Apple's standard EULA (our `/terms/scanitnow` is linked from the support page) |

## Pricing and Availability

- Price: **Free**
- Availability: all countries (or start with Portugal and the EU)
- No in-app purchases in this version

## App Privacy

**Data Types: "No, we do not collect data from this app."**

Why that is accurate for v1.0:

- Trips, prices, stores and limits stay on the device. There is no server.
- The camera is processed on the device.
- Product lookups send only a barcode number to Open Food Facts, in real time, with no identifiers. Apple does not count real-time servicing without retention as collection.
- There are no analytics, crash or advertising SDKs. Apple's own opt-in analytics don't count.

Re-do this section when v1.1 adds PostHog, Sentry or the purchase.

## Version 1.0

**Promotional text (135/170)**

> Scan each product as you shop and see your running total against your limit. Prices are remembered per store, and it all works offline.

**Description**

> Know your total before the till.
>
> ScanItNow adds up your shopping as you go. Scan a product's barcode, confirm the price, and watch your running total update. Set a limit for the trip and the bar turns amber as you get close and red when you go over, so the surprise happens in the aisle, not at the checkout.
>
> MADE FOR THE AISLE
> • Scan EAN and UPC barcodes and product QR codes
> • Set an optional limit per trip, with a gentle buzz at 80% and 100%
> • Prices are remembered per store: a product you bought before is two taps, scan and add
> • Works fully offline. Product names and photos fill in once you are back online
>
> SEE WHERE YOUR MONEY GOES
> • Spend this week and this month, compared with the last
> • Your average trip and how often you stay under your limit
> • Spending by store and by category
> • Which prices went up, and where the things you buy often cost less
>
> PRIVATE BY DESIGN
> • No account, no sign-up
> • Your trips stay on your iPhone
> • No ads and no tracking
>
> Product names and photos come from Open Food Facts, the free and open food database.

**Keywords (99/100)**

```
grocery,shopping,budget,barcode,scanner,price,supermarket,spending,limit,cart,food,checkout,expense
```

**Support URL**: https://facorreia.com/support/scanitnow
**Marketing URL**: https://facorreia.com/projects/scanitnow
**Copyright**: 2026 Fernando Correia

**Screenshots (6.9" display)**: five in `brand/store/aso/` (1320×2868), **uploaded on 2026-10-14**:

1. TRACK: your total vs your limit
2. SEE: where your money goes
3. SPOT: prices that went up
4. SKIP: retyping prices you've seen
5. SHOP: offline, no account needed

They are made from the `AppStoreScreenshots` UI test (raw captures in `brand/store/raw/`) and
`brand/tools/store-compose.py`, adapted from the aso-appstore-screenshots skill. To re-upload, re-render
and run `fastlane deliver --skip_metadata true --overwrite_screenshots true` from `scanit/`.

**What's New**: leave empty for 1.0.

## App Review Information

- **Sign-in required:** No
- **Contact:** Fernando Correia, your phone, fernando@facorreia.com
- **Notes:**

> ScanItNow has no login and no in-app purchases.
>
> To test: tap "Start shopping", type any store name (for example "Lidl"), optionally set a limit such as 20, and tap Start. Tap Scan and point the camera at any packaged product's barcode (EAN-13, EAN-8, UPC or a product QR code). Type the shelf price in the sheet and tap Add. The running total and the limit bar update. Scan the same product again: the price is remembered for that store. Tap Finish to see the summary; past trips are under History, and Insights appear after three finished trips.
>
> The camera is used only to read barcodes on the device. Barcode numbers are sent to Open Food Facts (openfoodfacts.org) to look up product names. No personal data is collected.
