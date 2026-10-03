#!/bin/sh
# server/build.sh [test|install] — Game = a fresh copy of the app's Model/Data/Battle; test = swift test;
# install = release build → /usr/local/bin (pokeserver + the backup script), restart the service (the restart fails before 6장's first setup)
set -e; cd "$(dirname "$0")"; rm -rf Sources/PokeCore/Game; mkdir -p Sources/PokeCore/Game
cp -R ../Sources/Model ../Sources/Data ../Sources/Battle Sources/PokeCore/Game/
if [ "$1" = test ]; then swift test; exit; fi
swift build -c release --static-swift-stdlib
[ "$1" = install ] || exit 0
sudo install -m 755 .build/release/pokeserver /usr/local/bin/pokeserver
sudo install -m 755 ops/backup.sh /usr/local/bin/pokewalker-backup
sudo systemctl restart pokewalker
