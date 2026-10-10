#!/bin/sh
# Renders brand/store/framed/0N-*.png (1320×2868) from brand/tools/store-frames.html.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$ROOT/brand/store/framed"
for n in 1 2 3 4; do
	"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
		--force-device-scale-factor=1 --window-size=1320,2868 --virtual-time-budget=3000 \
		--screenshot="$ROOT/brand/store/framed/0$n.png" "file://$ROOT/brand/tools/store-frames.html?n=$n" >/dev/null 2>&1
done
ls "$ROOT/brand/store/framed"
