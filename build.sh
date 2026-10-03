#!/bin/sh
# ./build.sh        build PokeWalker.app (this Mac only); runs --selftest first, so a broken rule or missing data fails the build
# ./build.sh run    build, then (re)launch
# ./build.sh dist   dist/PokeWalker.zip for other Macs: Apple Silicon + Intel, macOS 13+, ad-hoc signed (no Apple Developer ID)
# ./build.sh publish   dist, then onto the download page: the zip goes up as PokeWalker-mac.zip on the GitHub release v<version> (made at this commit,
#                      with its patch notes; gh logged in), which the server's publish.sh takes with the Windows build (committed and pushed first)
set -e
cd "$(dirname "$0")"
if [ "$1" = publish ]; then
    [ -z "$(git status --porcelain)" ] || { echo "commit first: the page takes this commit's version and patch notes"; exit 1; }
    git fetch -q origin && git merge-base --is-ancestor HEAD origin/main || { echo "push first: the server builds the page from what it can fetch"; exit 1; }
    V=$(sed -n 's|.*<key>CFBundleShortVersionString</key><string>\([^<]*\)</string>.*|\1|p' Info.plist)
    "$0" dist
    cp dist/PokeWalker.zip dist/PokeWalker-mac.zip
    if gh release view "v$V" >/dev/null 2>&1; then gh release upload "v$V" dist/PokeWalker-mac.zip --clobber
    else gh release create "v$V" dist/PokeWalker-mac.zip --target "$(git rev-parse HEAD)" --title "PokeWalker $V" \
        --notes "$(awk -v h="■ $V " 'index($0, h) == 1 { on = 1; next } /^■ / { on = 0 } on' docs/patch-notes.txt)"; fi
    echo "v$V: the Mac zip is on GitHub. The page: server/publish.sh --ref $(git rev-parse HEAD) on the server (or ask its Claude)"
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
