#!/bin/sh
# server/test.sh — the whole HTTP flow with curl (docs/plans/08b-server-home.md §8).
#   local:  server/test.sh                                   a temporary database, the release build on 127.0.0.1:8799 (APP_KEY=test)
#   remote: BASE=https://api.<domain> KEY=<APP_KEY> server/test.sh
#           on the mini PC: the rollback (step 4) and the cleanup go through sudo -u pokewalker (printed instead when sudo asks for a password)
set -u
cd "$(dirname "$0")"
TMP=$(mktemp -d); PASS=0; FAILS=0; PID=
cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

ok() {   # ok <what> <command…>: counts and prints
    what=$1; shift
    if "$@"; then PASS=$((PASS + 1)); echo "OK    $what"
    else FAILS=$((FAILS + 1)); echo "FAIL  $what — HTTP $CODE $(printf '%.300s' "$BODY")"; fi
}
is() {   # is <status> [<jq filter> <value>]
    [ "$CODE" = "$1" ] || return 1
    [ $# -lt 3 ] && return 0
    [ "$(printf '%s' "$BODY" | jq -r "$2" 2>/dev/null)" = "$3" ]
}
post() { # post <path>: the request in $TMP/req (not a pipe: a pipeline's last command is a subshell in sh, CODE / BODY would stay behind)
    CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' -H 'Content-Type: application/json' -H "X-App-Key: $KEY" --data-binary @"$TMP/req" "$BASE/v1/$1")
    BODY=$(cat "$TMP/body" 2>/dev/null)
}
get() { CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' "$BASE/v1/$1"); BODY=$(cat "$TMP/body" 2>/dev/null); }

if [ -z "${BASE:-}" ]; then
    MODE=local; KEY=test; BASE=http://127.0.0.1:8799; DB=$TMP/test.db; PS=./.build/release/pokeserver
    [ -x "$PS" ] || { echo "no $PS: run server/build.sh first"; exit 2; }
    admin() { "$PS" --db "$DB" "$@"; }
    CODE=; BODY=
    APP_KEY=test PORT=8799 "$PS" serve --db "$TMP/missing.db" >/dev/null 2>&1
    ok "serve: no database file → exit 1" [ $? -eq 1 ]
    ok "serve: nothing made in its place" [ ! -e "$TMP/missing.db" ]
    admin init >/dev/null
    APP_KEY=test PORT=8799 DB_PATH=$DB "$PS" serve > "$TMP/server.log" 2>&1 &
    PID=$!
    for _ in $(seq 100); do curl -s "$BASE/v1/ping" >/dev/null 2>&1 && break; sleep 0.1; done
else
    MODE=remote; : "${KEY:?KEY=<APP_KEY> goes with BASE}"; PS=/usr/local/bin/pokeserver
    admin() { sudo -n -u pokewalker "$PS" "$@" 2>/dev/null; }
fi
"$PS" sample > "$TMP/sample.json" || { echo "pokeserver sample failed"; exit 2; }
ID=zz$(printf '%06d' $(( $(date +%s) % 1000000 )))
echo "$MODE $BASE · test ID $ID"
login() { # login <device> [force]
    jq -n --arg id "$ID" --arg d "$1" --argjson f "${2:-false}" '{id: $id, device: $d, device_name: ($d | ascii_upcase), app: "2.1", force: $f, pin: "1234"}' > "$TMP/req"
    post login
}
save() {  # save <session> <base> [<app> [<walk file>]]
    jq -n --arg id "$ID" --arg s "$1" --argjson b "$2" --arg app "${3:-2.1}" --rawfile w "${4:-$TMP/sample.json}" \
        '{id: $id, session: $s, app: $app, base: $b, walk: $w}' > "$TMP/req"
    post save
}

# 1 — ping, the key, create
get ping;                                   ok "ping" is 200 .ok true
CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' -H 'Content-Type: application/json' --data-binary '{"id":"zz0","device":"x","device_name":"x"}' "$BASE/v1/login")
BODY=$(cat "$TMP/body");                    ok "no app key → 401" is 401 .error app_key
login test-a;                               ok "login: no such ID yet" is 200 .exists false
jq -n --arg id "$ID" '{id: $id, device: "test-a", device_name: "TEST-A", app: "2.1", pin: "1234"}' > "$TMP/req"
post create;                                ok "create → rev 0" is 200 .rev 0
SA=$(printf '%s' "$BODY" | jq -r .session)
post create;                                ok "create again → 409 exists" is 409 .error exists

# 2 — saves, a lost reply, another PC (2.x's: a server with MIN_APP=3.0 turns them all away, which is checked instead)
save "$SA" 0
if [ "$CODE" = 426 ]; then
    ok "MIN_APP: a 2.x save → 426 (need 3.0)" is 426 .need 3.0
    echo "SKIP  2.x's save flow (2–4): this server turns 2.x away (MIN_APP); server/test.sh without BASE runs it"
else
ok "A saves on rev 0 → rev 1" is 200 .rev 1
save "$SA" 0;                               ok "the same again (its reply lost) → rev 2" is 200 .rev 2
login test-b;                               ok "B logs in → busy (A saved just now)" is 200 .busy true
login test-b true;                          ok "B, force → B has it" is 200 .rev 2
SB=$(printf '%s' "$BODY" | jq -r .session)
ok "B got a session" [ -n "$SB" -a "$SB" != null ]
save "$SA" 2;                               ok "A saves → 409 replaced" is 409 .reason replaced
save "$SB" 2;                               ok "B saves on rev 2 → rev 3" is 200 .rev 3

# 3 — an old app, sizes, a save the app can't load
save "$SB" 3 2.0;                           ok "app 2.0 after 2.1 → 426" is 426 .need 2.1
head -c 3000000 /dev/zero | tr '\0' x > "$TMP/big"
save "$SB" 3 2.1 "$TMP/big";                ok "a 3 MB save → 413" is 413 .error too_big
{ printf '{"id":"%s","session":"%s","app":"2.1","base":3,"walk":"' "$ID" "$SB"; head -c 5000000 /dev/zero | tr '\0' x; printf '"}'; } > "$TMP/req"
post save;                                  ok "a 5 MB body → 413" is 413
printf '{}' > "$TMP/empty"
save "$SB" 3 2.1 "$TMP/empty";              ok "walk {} → 400 bad_walk" is 400 .error bad_walk

# 4 — an admin's rollback, legacy
if admin rollback "$ID" 1 hourly >/dev/null; then
    save "$SB" 3;                           ok "after a rollback, B's base 3 → 409 stale" is 409 .rev 4
    save "$SB" 4;                           ok "B saves on the server's rev 4 → rev 5" is 200 .rev 5
else
    echo "SKIP  rollback (needs: sudo -u pokewalker $PS rollback $ID 1 hourly)"
fi
jq -n --arg id "$ID" --rawfile w "$TMP/sample.json" '{id: $id, device: "test-a", walk: $w}' > "$TMP/req"
post legacy;                                ok "legacy → stored" is 200 .stored true
post legacy;                                ok "legacy again → kept as it was" is 200 .stored false
fi

# 5 — 3.0 (plan 11): /v2/act — the server makes the save; a resend, a gap, a refusal, the radar, the tower; 2.x turned away after
ID3=zz$(printf '%06d' $(( ($(date +%s) + 500000) % 1000000 )))
act() {  # act <seq> <act JSON> [<steps>]
    jq -n --arg id "$ID3" --arg s "$S3" --argjson q "$1" --argjson a "$2" --argjson n "${3:-null}" \
        '{id: $id, session: $s, seq: $q, act: $a} + (if $n == null then {} else {steps: $n} end)' > "$TMP/req"
    CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' -H 'Content-Type: application/json' -H "X-App-Key: $KEY" --data-binary @"$TMP/req" "$BASE/v2/act")
    BODY=$(cat "$TMP/body" 2>/dev/null)
}
jq -n --arg id "$ID3" '{id: $id, device: "test-c", device_name: "TEST-C", app: "3.0", pin: "1234"}' > "$TMP/req"
post create;                                ok "3.0 create → the starter issued" is 200 .starter 1000000
S3=$(printf '%s' "$BODY" | jq -r .session)
act 1 '{"steps":{}}' 3;                     ok "act 1: steps → the server's first save" is 200 '.walk.companion.uid' 1000000
FIRST=$(printf '%s' "$BODY" | jq -c '[.rev, .taken, .walk.total]')                        # (taken: what the allowance had, a moment after create)
act 1 '{"steps":{}}' 3;                     ok "act 1 again → its reply (nothing twice)" is 200 '[.rev, .taken, .walk.total] | tostring' "$FIRST"
act 3 '{"steps":{}}';                       ok "act 3 after 1 → 409 seq" is 409 .error seq
act 2 '{"radar":{}}';                       ok "the radar without 10 W → a refusal, 200" is 200 '.out.cannot | startswith("W가 부족하다")' true
if admin set "$ID3" '$.watts' 200 >/dev/null; then
    act 3 '{"radar":{}}';                   ok "the radar → a bush, 10 W paid" is 200 '[.out.radar.bush < 4, .walk.watts] | tostring' '[true,190]'
    act 4 '{"radarPick":{"bush":-1}}';      ok "given up → missed" is 200 .out.missed true
    act 5 '{"tower":{}}';                   ok "the tower → a trainer's fight" is 200 '.out.battle.trainer != null' true
    act 6 '{"mon":{"op":{"store":{"uid":1000000}}}}'; ok "mid-fight, anything else → a refusal" is 200 .out.cannot "배틀 중이에요"
    act 7 '{"battle":{"cmd":{"forfeit":{}}}}'; ok "forfeit → the run's over" is 200 .out.end.result forfeit
    SEQ3=8
else
    echo "SKIP  radar · tower (needs: sudo -u pokewalker $PS set $ID3 '\$.watts' 200)"; SEQ3=3
fi
jq -n --arg id "$ID3" '{id: $id, device: "test-d", device_name: "TEST-D", app: "2.2", force: true, pin: "1234"}' > "$TMP/req"
post login;                                 ok "a 2.2 login to a trainer on 3.0 → 426" is 426 .need 3.0
act $SEQ3 '{"steps":{}}';                   ok "its 3.0 session acts on" is 200

if [ $MODE = remote ]; then
    # the test ID, its legacy row and the save delete keeps as a file: nothing of the test stays in the real database
    if admin delete "$ID" --yes >/dev/null && sudo -n -u pokewalker sqlite3 /var/lib/pokewalker/pokewalker.db "DELETE FROM legacy WHERE key = '$ID'" \
        && admin delete "$ID3" --yes >/dev/null \
        && sudo -n -u pokewalker sh -c "rm -f /var/lib/pokewalker/deleted-$ID-*.json /var/lib/pokewalker/deleted-$ID3-*.json"; then echo "      $ID $ID3 removed"
    else echo "      remove the test ID: sudo -u pokewalker $PS delete $ID --yes; sudo -u pokewalker sqlite3 /var/lib/pokewalker/pokewalker.db \"DELETE FROM legacy WHERE key = '$ID'\"; sudo rm /var/lib/pokewalker/deleted-$ID-*.json"; fi
fi
echo "$PASS ok, $FAILS failed"
[ $FAILS -eq 0 ]
