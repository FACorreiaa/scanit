# ScanItNow brand

Source: `source/brand-sheet.png` (owner-supplied, 2026-10-10). Everything else here is generated from it by the
scripts in `tools/`, so it can be regenerated and never drifts between web and iOS.

## Assets

| File | What | How it was made |
| --- | --- | --- |
| `logo-mark.svg`, `logo-mark-dark.svg` | The mark: green viewfinder brackets around a 2×2 grid of dark squares | Redrawn as exact geometry from measured proportions (`tools/measure.swift`, `tools/make-mark.swift`) |
| `logo-mark-currentcolor.svg` | Mark whose squares follow the CSS text colour | same |
| `wordmark.svg`, `wordmark-dark.svg`, `wordmark-currentcolor.svg` | "ScanItNow" lettering, "It" in green | Traced with potrace from the sheet at 4× (`tools/trace-wordmark.sh`) |
| `png/mascot.png` | The mascot, transparent, 795×752 | Vision subject lifting (`tools/lift-mascot.swift`) |
| `png/logo-mark-1024.png` | Mark, transparent, 1024² | `tools/make-mark.swift` |
| `tools/og.html` | Social card for link previews (`scanit-web/static/og.png`, 1200×630) | Rendered with headless Chrome (command in the file) |

`make-mark.swift` also writes the iOS app icons (light, dark, tinted) and the launch-screen mark.

## Colours

| Name | Hex | Use |
| --- | --- | --- |
| Brand green | `#10AA51` | Logo, mascot backdrop, illustration. **Not** for text or button fills: white on it is 2.9:1. |
| Accent green | `#23843B` | Buttons and tints in the app and on the web (white text 4.65:1, WCAG AA). |
| Link green (dark) | `#3CC565` | Web links on dark backgrounds (8.4:1). |
| Ink | `#222A35` | Mark squares and wordmark on light backgrounds. |
| Ink on dark | `#EEF1F5` | Mark squares and wordmark on dark backgrounds. |

## Rules

- **Mascot on dark backgrounds** always sits on the soft green disc (`MascotView` in iOS, `.mascot-disc` on the web). Its
  black body disappears on dark otherwise.
- **The mascot is for welcome moments**: empty Trip screen, paywall, website hero, social card. It does not go on every
  screen. History and Insights keep plain system symbols.
- **Lockup:** mark plus wordmark, mark height = 1.2 × wordmark cap height, gap ≈ 0.35 × mark height. Leave clear space
  of half the mark's height on every side.
- **App icon:** the mark alone at 70% of the canvas: white background (light), `#10141A` (dark), grayscale (tinted). Never
  the mascot; it is too detailed at 60 px.
- **Names:** the product is **ScanItNow** in every user-facing string. The code, repo and bundle IDs stay `scanit`.

## Regenerate

```sh
swift brand/tools/make-mark.swift .              # marks, app icons, launch mark
brand/tools/trace-wordmark.sh                    # wordmark SVGs (needs potrace)
swift brand/tools/lift-mascot.swift brand/source/brand-sheet.png brand/png/mascot.png
```

Then copy the outputs into `scanit-web/static/brand/` and the asset catalog. Shrink the web mascot with
`sips -Z 720` and encode the AVIF (48 KB vs 571 KB PNG).
