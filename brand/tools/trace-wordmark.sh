#!/bin/sh
# Traces the "ScanItNow" wordmark into brand/wordmark.svg (and a currentColor variant for the web).
# Needs potrace (brew install potrace).
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
swift "$ROOT/brand/tools/wordmark-masks.swift" "$ROOT/brand/source/brand-sheet.png" "$WORK"
for layer in dark green; do
	potrace "$WORK/$layer.pbm" --svg --turdsize 40 --alphamax 1.0 --opttolerance 0.2 --flat -o "$WORK/$layer.svg"
done
python3 - "$WORK" "$ROOT/brand" <<'PY'
import re, sys, pathlib
work, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
def parts(name):
    s = (work / f"{name}.svg").read_text()
    width = float(re.search(r'width="([\d.]+)pt"', s).group(1))
    height = float(re.search(r'height="([\d.]+)pt"', s).group(1))
    group = re.search(r'(<g transform="[^"]+"[^>]*>)(.*?)</g>', s, re.S)
    transform = re.search(r'transform="([^"]+)"', group.group(1)).group(1)
    return width, height, transform, group.group(2).strip()
w, h, t_dark, dark = parts("dark")
_, _, t_green, green = parts("green")
def svg(dark_fill):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:g} {h:g}" role="img" aria-label="ScanItNow">\n'
            f'<g transform="{t_dark}" fill="{dark_fill}">{dark}</g>\n'
            f'<g transform="{t_green}" fill="#10AA51">{green}</g>\n</svg>\n')
(out / "wordmark.svg").write_text(svg("#1B2430"))
(out / "wordmark-dark.svg").write_text(svg("#EEF1F5"))
(out / "wordmark-currentcolor.svg").write_text(svg("currentColor"))
print(f"wordmark {w:g}x{h:g}, dark paths {dark.count('<path')}, green paths {green.count('<path')}")
PY
rm -rf "$WORK"
