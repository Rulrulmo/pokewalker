#!/bin/sh
# ./build.sh        build PokeWalker.app (this Mac only); runs --selftest first, so a broken rule or missing data fails the build
# ./build.sh run    build, then (re)launch
# ./build.sh dist   dist/PokeWalker.zip for other Macs: Apple Silicon + Intel, macOS 13+, ad-hoc signed (no Apple Developer ID)
set -e
cd "$(dirname "$0")"
SRC=$(find Sources Tests -name "*.swift")
OPT="-O -wmo -num-threads $(sysctl -n hw.ncpu) -swift-version 6"   # whole-module, codegen on every core
bundle() {   # $1 = .app path
    mkdir -p "$1/Contents/MacOS" "$1/Contents/Resources"
    cp Info.plist "$1/Contents/Info.plist"
    cp Resources/hgss.bin Resources/fonts/Galmuri9.ttf Resources/fonts/Galmuri7.ttf "$1/Contents/Resources/"
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
