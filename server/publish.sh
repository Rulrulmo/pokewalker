#!/bin/sh
# server/publish.sh [--ref <commit>] [<PokeWalker.zip>] — a new release on the download page (server/README.md: 다운로드 페이지), run on the server:
#   the version and the patch notes of <commit> (default: origin/main), the Windows zip from the windows workflow's successful run on that commit
#   (on origin/main's head with none yet, it's started and waited for), and the Mac zip given (./build.sh publish on the Mac uploads it and calls this).
#   No Mac zip: the page's current one stays if it's the same version, else the Mac button says 준비 중.
# All files land in RELEASE_DIR at once, as the pokewalker user (sudo).
set -eu
cd "$(dirname "$0")/.."
REF=origin/main
[ "${1:-}" = --ref ] && { REF=${2:?--ref needs a commit}; shift 2; }
MAC=${1:-}
DIR=${RELEASE_DIR:-/var/lib/pokewalker/release}
SUDO="sudo -u pokewalker"

git fetch -q origin
SHA=$(git rev-parse --verify "$REF^{commit}")
plist() { git show "$SHA:Info.plist" | sed -n "s|.*<key>$1</key><string>\([^<]*\)</string>.*|\1|p"; }
VERSION=$(plist CFBundleShortVersionString); BUILD=$(plist CFBundleVersion)
[ -n "$VERSION" ] || { echo "no version in $SHA:Info.plist"; exit 1; }
echo "release $VERSION (build $BUILD) from $(git log -1 --format='%h %s' "$SHA" | cut -c1-90)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
chmod 755 "$TMP"                                                       # the pokewalker user copies from it
git show "$SHA:docs/patch-notes.txt" > "$TMP/patch-notes.txt"

# Windows: the artifact of the windows workflow's successful run on this commit
run_on() { gh run list --workflow windows.yml --commit "$SHA" ${1:+--status "$1"} -L 1 --json databaseId -q '.[0].databaseId // empty'; }
RUN=$(run_on success)
if [ -z "$RUN" ]; then
    [ "$SHA" = "$(git rev-parse origin/main)" ] || { echo "no successful Windows build of $SHA (the workflow runs on main's head: gh workflow run windows.yml --ref main)"; exit 1; }
    RUN=$(run_on in_progress); [ -n "$RUN" ] || RUN=$(run_on queued)
    if [ -z "$RUN" ]; then
        echo "no Windows build of $SHA yet: starting the windows workflow"
        gh workflow run windows.yml --ref main
        for _ in $(seq 30); do sleep 5; RUN=$(run_on); [ -n "$RUN" ] && break; done
        [ -n "$RUN" ] || { echo "the workflow run didn't show up"; exit 1; }
    fi
    echo "waiting for Windows build run $RUN (about 10 minutes)"
    gh run watch "$RUN" --exit-status --interval 30 > /dev/null
fi
echo "Windows: run $RUN"
gh run download "$RUN" -n PokeWalker-windows-x64 -D "$TMP/PokeWalker"
(cd "$TMP" && zip -qr PokeWalker-windows-x64.zip PokeWalker && rm -rf PokeWalker)

# Mac: the zip given (its version must be this one), else the page's current one when it's this version
MACJSON=null
if [ -n "$MAC" ]; then
    MACV=$(unzip -p "$MAC" PokeWalker.app/Contents/Info.plist | sed -n 's|.*<key>CFBundleShortVersionString</key><string>\([^<]*\)</string>.*|\1|p')
    [ "$MACV" = "$VERSION" ] || { echo "the Mac zip is version '${MACV:-?}', $SHA is $VERSION"; exit 1; }
    cp "$MAC" "$TMP/PokeWalker-mac.zip"
elif $SUDO test -f "$DIR/PokeWalker-mac.zip" && [ "$($SUDO jq -r .version "$DIR/release.json" 2>/dev/null)" = "$VERSION" ]; then
    $SUDO cat "$DIR/PokeWalker-mac.zip" > "$TMP/PokeWalker-mac.zip"; echo "Mac: the page's current $VERSION zip stays"
else
    echo "Mac: none for $VERSION yet (the page says 준비 중)"
fi
build() { [ -f "$TMP/$1" ] && jq -n --arg f "$1" --argjson s "$(stat -c %s "$TMP/$1")" --arg h "$(sha256sum "$TMP/$1" | cut -d' ' -f1)" '{file: $f, size: $s, sha256: $h}' || echo null; }
jq -n --arg v "$VERSION" --arg b "$BUILD" --arg c "$SHA" --argjson t "$(date +%s)" --argjson mac "$(build PokeWalker-mac.zip)" --argjson win "$(build PokeWalker-windows-x64.zip)" \
    '{version: $v, build: $b, commit: $c, published: $t, mac: $mac, windows: $win}' > "$TMP/release.json"
chmod 644 "$TMP"/*

# in place at once: a new folder renamed over the old one
$SUDO sh -c "rm -rf '$DIR.new' '$DIR.old' && mkdir -p '$DIR.new' && cp '$TMP'/* '$DIR.new/' && { [ ! -d '$DIR' ] || mv '$DIR' '$DIR.old'; } && mv '$DIR.new' '$DIR' && rm -rf '$DIR.old'"
echo "published $VERSION: $(jq -c '{mac: (.mac.size // "none"), windows: .windows.size}' "$TMP/release.json") → https://pokewalker.rulrulmo.work/"
