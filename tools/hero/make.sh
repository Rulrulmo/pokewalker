#!/bin/bash
# docs/images/hero.png: the download page's top with the Mac renders (a dev build: `./build.sh` first), shot by headless Chrome at 2×.
# Needs the network for the page's fonts (Pretendard, Galmuri from jsDelivr).
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
./PokeWalker.app/Contents/MacOS/PokeWalker --shots "$tmp/shots" > /dev/null
cp tools/hero/hero.html "$tmp/"; cp "$tmp/shots/hero_home.png" "$tmp/home.png"; cp "$tmp/shots/hero_battle.png" "$tmp/battle.png"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1040,548 --virtual-time-budget=10000 \
    --screenshot="$tmp/hero.png" "file://$tmp/hero.html" 2> /dev/null
mkdir -p docs/images; cp "$tmp/hero.png" docs/images/hero.png
sips -g pixelWidth -g pixelHeight docs/images/hero.png | tail -2; ls -l docs/images/hero.png
