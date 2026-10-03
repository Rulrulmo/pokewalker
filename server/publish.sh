#!/bin/sh
# server/publish.sh [v<version>] — a release on the download page and in the app's updates (server/README.md), run on the server.
#   The release Mac makes and signs it (./build.sh publish: both zips, manifest.json, manifest.sig on the GitHub release v<version>); this
#   only mirrors it: the four files are downloaded, `pokeserver verify-release` checks the signature with the release key and each zip's size and
#   SHA-256 — anything off and nothing changes — and the page's patch notes come from the manifest's commit. Default version: origin/main's.
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
gh release download "$TAG" -D "$IN" -p PokeWalker-mac.zip -p PokeWalker-windows-x64.zip -p manifest.json -p manifest.sig \
    || { echo "$TAG: not a signed release (on the release Mac: ./build.sh publish)"; exit 1; }
"$PS" verify-release "$IN"                                             # the signature, then each zip; non-zero (and nothing changes) when off

COMMIT=$(jq -r .commit "$IN/manifest.json")
git cat-file -e "$COMMIT^{commit}" 2>/dev/null || git fetch -q origin "$COMMIT"
git show "$COMMIT:docs/patch-notes.txt" > "$IN/patch-notes.txt"
jq --argjson t "$(date +%s)" '{version, build, commit, published: $t, mac, windows}' "$IN/manifest.json" > "$IN/release.json"   # the page's
chmod 644 "$IN"/*

# in place at once: a new folder renamed over the old one
$SUDO sh -c "rm -rf '$DIR.new' '$DIR.old' && mkdir -p '$DIR.new' && cp '$IN'/* '$DIR.new/' && { [ ! -d '$DIR' ] || mv '$DIR' '$DIR.old'; } && mv '$DIR.new' '$DIR' && rm -rf '$DIR.old'"
echo "published $(jq -r .version "$IN/manifest.json") (signed): $(jq -c '{mac: .mac.size, windows: .windows.size}' "$IN/manifest.json") → https://pokewalker.rulrulmo.work/ and the app's updates"
