#!/bin/sh
# server/publish.sh [v<version>] — a release on the download page and in the app's updates (server/README.md), run on the server.
#   The release Mac makes and signs it (./build.sh publish: both zips, from the installer release on the Windows installer, manifest.json and
#   manifest.sig on the GitHub release v<version>); this only mirrors it: those files are downloaded, `pokeserver verify-release` checks the
#   signature with the release key and each file's size and SHA-256 — anything off and nothing changes — and the page's patch notes come from the manifest's commit, its screenshots from that commit's
#   windows run (PokeWalker-renders). Default version: origin/main's.
# All files land in RELEASE_DIR at once, as the pokewalker user (sudo).
set -eu
cd "$(dirname "$0")/.."
DIR=${RELEASE_DIR:-/var/lib/pokewalker/release}
SUDO="sudo -u pokewalker"
PS=${PS:-/usr/local/bin/pokeserver}

git fetch -q origin
TAG=${1:-v$(git show origin/main:Info.plist | sed -n 's|.*<key>CFBundleShortVersionString</key><string>\([^<]*\)</string>.*|\1|p')}
IN=$(mktemp -d); trap 'rm -rf "$IN"' EXIT
chmod 755 "$IN"                                                        # the pokewalker user copies from it
gh release download "$TAG" -D "$IN" -p 'PokeWalker-*' -p manifest.json -p manifest.sig \
    || { echo "$TAG: not a signed release (on the release Mac: ./build.sh publish)"; exit 1; }
"$PS" verify-release "$IN"                                             # the signature, then each zip; non-zero (and nothing changes) when off
V=$(jq -r .version "$IN/manifest.json")                                # the tag's version and the signed one agree (a "v" with an empty version: never)
[ -n "$V" ] && [ "v$V" = "$TAG" ] || { echo "$TAG: its manifest says version \"$V\": not published"; exit 1; }

COMMIT=$(jq -r .commit "$IN/manifest.json")
git cat-file -e "$COMMIT^{commit}" 2>/dev/null || git fetch -q origin "$COMMIT"
git show "$COMMIT:docs/patch-notes.txt" > "$IN/patch-notes.txt"
jq --argjson t "$(date +%s)" '{version, build, commit, published: $t, mac, windows, windowsSetup}' "$IN/manifest.json" > "$IN/release.json"   # the page's

# the page's screenshots: the windows run's renders of this commit, as lossless WebP (python3-pil). Best effort: none, and the page goes without
RUN=$(gh run list --workflow windows.yml --commit "$COMMIT" --status success --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
if [ -n "$RUN" ] && gh run download "$RUN" -n PokeWalker-renders -D "$IN/renders" > /dev/null 2>&1 && mkdir "$IN/shots" && python3 - "$IN/renders" "$IN/shots" <<'EOF'
import sys, pathlib
from PIL import Image
src, dst = map(pathlib.Path, sys.argv[1:])
for p in sorted(src.glob("*.png")): Image.open(p).save(dst / (p.stem + ".webp"), lossless=True, method=6)
EOF
then echo "screenshots: $(ls "$IN/shots" | wc -l) from run $RUN"; else rm -rf "$IN/shots"; echo "no screenshots (no renders of $COMMIT): the page goes without"; fi
rm -rf "$IN/renders"
find "$IN" -type d -exec chmod 755 {} +; find "$IN" -type f -exec chmod 644 {} +

# in place at once: a new folder renamed over the old one
$SUDO sh -c "rm -rf '$DIR.new' '$DIR.old' && mkdir -p '$DIR.new' && cp -R '$IN'/. '$DIR.new/' && { [ ! -d '$DIR' ] || mv '$DIR' '$DIR.old'; } && mv '$DIR.new' '$DIR' && rm -rf '$DIR.old'"
echo "published $(jq -r .version "$IN/manifest.json") (signed): $(jq -c '{mac: .mac.size, windows: .windows.size, windowsSetup: .windowsSetup.size}' "$IN/manifest.json") → https://pokewalker.rulrulmo.work/ and the app's updates"
