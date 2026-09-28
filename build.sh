#!/bin/sh
# ./build.sh        build PokeWalker.app; runs --selftest first, so a broken rule or missing sprite data fails the build
# ./build.sh run    build, then (re)launch
set -e
cd "$(dirname "$0")"
A=PokeWalker.app/Contents
mkdir -p $A/MacOS $A/Resources
cp Info.plist $A/Info.plist
cp sprites.bin color.bin fonts/Galmuri9.ttf fonts/Galmuri7.ttf $A/Resources/
swiftc -O -swift-version 6 Walker.swift Data.swift Test.swift main.swift -o $A/MacOS/PokeWalker
$A/MacOS/PokeWalker --selftest
if [ "$1" = run ]; then pkill -x PokeWalker || true; open PokeWalker.app; fi
