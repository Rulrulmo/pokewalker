#!/bin/sh
# ./build.sh        build PokeWalker.app (this Mac only); runs --selftest first, so a broken rule or missing data fails the build
# ./build.sh run    build, then (re)launch
# ./build.sh dist   dist/PokeWalker.zip for other Macs: Apple Silicon + Intel, macOS 13+, ad-hoc signed (no Apple Developer ID)
# ./build.sh publish [--dry]   the signed release, for auto-update and the download page (committed and pushed first; gh logged in): dist's Mac zip,
#                      the windows workflow's build of this commit (one already going is joined, else started first; the Mac's is built meanwhile), manifest.json (version, build, commit,
#                      each zip's sha256 and size) and manifest.sig (Ed25519 by the release key: tools/release-key.swift, this Mac only) on the GitHub
#                      release v<version>; then the server's Claude publishes it. --dry stops before the upload (and never starts a windows build)
set -e
cd "$(dirname "$0")"
if [ "$1" = publish ]; then
    case "$2" in "") DRY= ;; --dry) DRY=1 ;; *) echo "usage: ./build.sh publish [--dry]"; exit 1 ;; esac   # a typo never publishes for real
    [ -z "$(git status --porcelain)" ] || { echo "commit first: the release is this commit's version, build and patch notes"; exit 1; }
    git fetch -q origin && git merge-base --is-ancestor HEAD origin/main || { echo "push first: the windows build and the server take what they can fetch"; exit 1; }
    plist() { sed -n "s|.*<key>$1</key><string>\([^<]*\)</string>.*|\1|p" Info.plist; }
    V=$(plist CFBundleShortVersionString) B=$(plist CFBundleVersion) SHA=$(git rev-parse HEAD)
    RUN=$(gh run list --workflow windows.yml --commit "$SHA" --status success --limit 1 --json databaseId -q '.[0].databaseId') WAIT=
    if [ -z "$RUN" ] && [ -n "$DRY" ]; then                                       # a dry run spends no Actions minutes: the last good build stands in
        RUN=$(gh run list --workflow windows.yml --status success --limit 1 --json databaseId -q '.[0].databaseId'); echo "dry: no windows build of $SHA; run $RUN's stands in"
    elif [ -z "$RUN" ]; then                                                       # the windows build first (~10 minutes), the Mac's alongside it
        RUN=$(gh run list --workflow windows.yml --commit "$SHA" --limit 1 --json databaseId,status -q '.[] | select(.status != "completed") | .databaseId')
        if [ -n "$RUN" ]; then echo "the windows build of $SHA: run $RUN already going"
        else
            [ "$SHA" = "$(git rev-parse origin/main)" ] || { echo "no windows build of $SHA, and it isn't main's head: run the windows workflow on it first"; exit 1; }
            gh workflow run windows.yml --ref main; echo "the windows build of $SHA: started"
            while [ -z "$RUN" ]; do sleep 5; RUN=$(gh run list --workflow windows.yml --commit "$SHA" --event workflow_dispatch --limit 1 --json databaseId -q '.[0].databaseId'); done
        fi
        WAIT=1
    fi
    "$0" dist                                                                     # (meanwhile)
    cp dist/PokeWalker.zip dist/PokeWalker-mac.zip
    if [ -n "$WAIT" ]; then echo "waiting for the windows build (run $RUN)"; gh run watch "$RUN" --exit-status > /dev/null || { echo "the windows build failed: gh run view $RUN"; exit 1; }; fi
    gh run download "$RUN" -n PokeWalker-windows-x64 -D dist/win/PokeWalker                   # a PokeWalker folder at the zip's top
    (cd dist/win && zip -qrX ../PokeWalker-windows-x64.zip PokeWalker)
    sum() { shasum -a 256 "$1" | cut -d' ' -f1; }; size() { stat -f %z "$1"; }
    printf '{"build":"%s","commit":"%s","mac":{"file":"PokeWalker-mac.zip","sha256":"%s","size":%s},"version":"%s","windows":{"file":"PokeWalker-windows-x64.zip","sha256":"%s","size":%s}}' \
        "$B" "$SHA" "$(sum dist/PokeWalker-mac.zip)" "$(size dist/PokeWalker-mac.zip)" "$V" "$(sum dist/PokeWalker-windows-x64.zip)" "$(size dist/PokeWalker-windows-x64.zip)" > dist/manifest.json   # compact, keys sorted, no newline: these bytes are signed and uploaded
    swift tools/release-key.swift sign dist/manifest.json > dist/manifest.sig
    KEY=$(sed -n 's|^let releaseKey.*unhex("\([0-9a-f]*\)").*|\1|p' Sources/Model/Ed25519.swift)
    [ ${#KEY} = 64 ] || { echo "no releaseKey in Model/Ed25519.swift to check the signature with"; exit 1; }
    swift tools/release-key.swift verify dist/manifest.json "$(cat dist/manifest.sig)" "$KEY" > /dev/null || { echo "the signature doesn't check with the app's releaseKey (Model/Ed25519.swift)"; exit 1; }
    if [ -n "$DRY" ]; then echo "dry: nothing uploaded"; cat dist/manifest.json; echo; cat dist/manifest.sig; exit; fi
    set -- dist/PokeWalker-mac.zip dist/PokeWalker-windows-x64.zip dist/manifest.json dist/manifest.sig
    if gh release view "v$V" >/dev/null 2>&1; then gh release upload "v$V" "$@" --clobber
    else gh release create "v$V" "$@" --target "$SHA" --title "PokeWalker $V" \
        --notes "$(awk -v h="■ $V " 'index($0, h) == 1 { on = 1; next } /^■ / { on = 0 } on' docs/patch-notes.txt)"; fi
    echo "v$V ($SHA) is on GitHub, signed. Next: tell the server's Claude \"publish v$V\""
    exit
fi
SRC=$(find Sources Tests -name "*.swift")
OPT="-O -wmo -num-threads $(sysctl -n hw.ncpu) -swift-version 6"   # whole-module, codegen on every core
bundle() {   # $1 = .app path
    mkdir -p "$1/Contents/MacOS" "$1/Contents/Resources"
    cp Info.plist "$1/Contents/Info.plist"
    cp Resources/hgss.bin Resources/icons.bin Resources/frames.bin Resources/anims.bin Resources/walk.bin Resources/fonts/Galmuri9.ttf Resources/fonts/Galmuri7.ttf "$1/Contents/Resources/"
}
if [ "$1" = dist ]; then
    A=dist/PokeWalker.app; rm -rf dist; bundle $A
    for arch in arm64 x86_64; do swiftc $OPT -target $arch-apple-macos13 $SRC -o dist/PokeWalker-$arch; done
    lipo -create dist/PokeWalker-arm64 dist/PokeWalker-x86_64 -output $A/Contents/MacOS/PokeWalker; rm dist/PokeWalker-*
    $A/Contents/MacOS/PokeWalker --selftest > /dev/null
    codesign --force --deep -s - $A
    ditto -c -k --keepParent $A dist/PokeWalker.zip
    echo "dist/PokeWalker.zip ($(du -h dist/PokeWalker.zip | cut -f1)) — $(lipo -archs $A/Contents/MacOS/PokeWalker), macOS 13+"
    exit
fi
A=PokeWalker.app; bundle $A
swiftc $OPT $SRC -o $A/Contents/MacOS/PokeWalker
$A/Contents/MacOS/PokeWalker --selftest
if [ "$1" = run ]; then pkill -x PokeWalker || true; open PokeWalker.app; fi
