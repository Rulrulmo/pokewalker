#!/bin/sh
# ops/backup.sh → /usr/local/bin/pokewalker-backup: a consistent copy, kept only if it checks ok, gzipped, 14 days here
set -e; D=/var/lib/pokewalker/pokewalker.db; B=/var/lib/pokewalker/backup; F=$B/pw-$(date +%F).db
[ -f $D ]                                  # sqlite3 would create an empty one
mkdir -p $B; rm -f $F
sqlite3 $D ".backup $F"
[ "$(sqlite3 $F 'PRAGMA integrity_check')" = ok ]
gzip -f $F
find $B -name 'pw-*.db.gz' -mtime +14 -delete
