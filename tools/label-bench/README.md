# label-bench

IOS-006 spike: how often does the shelf price get prefilled correctly?

Runs Apple's Vision text recogniser (the engine behind DataScanner's `.text()`) on label photos and
feeds the result through `ScanItCore.PriceParser`, the same code the app uses.

## Run it on real photos

1. Take about 20 photos of shelf labels from 2 or more chains, the way you'd point the phone in a shop.
2. Put them in `tools/label-bench/labels/` (gitignored: photos stay out of the repo).
3. Write `labels/expected.json` with the price you'd want prefilled:

   ```json
   {
     "IMG_0001.jpg": { "currency": "EUR", "totalMinor": 199 },
     "IMG_0002.jpg": { "currency": "EUR", "totalMinor": null }
   }
   ```

   `totalMinor` is in cents. Use `null` when the right answer is "ask the user", for example when only a per-kg price is shown.
4. `swift run -c release label-bench labels` (add `--dump` to see every recognised line).

The target is a correct prefill on at least 70% of labels (BACKLOG IOS-007). Misses print what Vision
read, sorted by text height, which is what `PriceParser` ranks on. A miss usually becomes either a new
`Fixtures/prices.json` vector plus a parser fix, or proof that a label layout needs the user to tap the
price.

## Record the set for CI

`swift run -c release label-bench labels --record` also writes what Vision read on each photo (text, boxes,
the barcode box and the expected price) to `scanit-core/Fixtures/labels.json`. The photos are not committed.
`LabelSetTests` replays that file through `PriceParser` on Linux CI and fails when accuracy drops below its
`floor`. A recording keeps the committed floor; raise it by hand when the parser gets better.

Recognition is `ScanItCore.LabelReader`, the same code the app runs on a captured still.

`swift run -c release label-bench --make-samples <dir>` renders synthetic labels. That is only a smoke test of
the pipeline, not evidence about real labels.
