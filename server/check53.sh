#!/bin/sh
# server/check53.sh [off|on] — 5.3's switch (docs/plans/19 §12.5) over HTTP, with test IDs: a 5.2.2 app plays as 5.2.2 did (no 협동 · 스토리,
# no pairs); a 5.3 app on a test ID has 5.3 whatever the switch (칼로스 이야기's trainer and pick, /v2/expedition's story, a pair asked, taken,
# seen and ended). off (the default) / on: what `pokeserver content53` should say.
#   local:  server/check53.sh [off|on]      a temporary database, the release build on 127.0.0.1:8798 (content5 · 51 · 52 on, content53 as asked) —
#           and a trainer that isn't a test ID too (the switch's own: off as 5.2.2, on as 5.3)
#   remote: BASE=https://pokewalker.rulrulmo.work server/check53.sh [off|on]   on the mini PC (the key from server.env, the admin through
#           sudo -u pokewalker); the test IDs are deleted at the end
set -u
cd "$(dirname "$0")"
PHASE=${1:-off}; [ "$PHASE" = off ] || [ "$PHASE" = on ] || { echo "check53.sh [off|on]"; exit 2; }
TMP=$(mktemp -d); PASS=0; FAILS=0; PID=
cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

ok() {   # ok <what> <command…>
    what=$1; shift
    if "$@"; then PASS=$((PASS + 1)); echo "OK    $what"
    else FAILS=$((FAILS + 1)); echo "FAIL  $what — HTTP $CODE $(printf '%.300s' "$BODY")"; fi
}
is() {   # is <status> [<jq filter> <value>]
    [ "$CODE" = "$1" ] || return 1
    [ $# -lt 3 ] && return 0
    [ "$(printf '%s' "$BODY" | jq -r "$2" 2>/dev/null)" = "$3" ]
}
CODE=; BODY=
if [ -z "${BASE:-}" ]; then
    MODE=local; KEY=test; BASE=http://127.0.0.1:8798; DB=$TMP/check.db; PS=./.build/release/pokeserver
    [ -x "$PS" ] || { echo "no $PS: run server/build.sh first"; exit 2; }
    admin() { "$PS" --db "$DB" "$@"; }
    admin init >/dev/null && admin content5 on >/dev/null && admin content51 on >/dev/null && admin content52 on >/dev/null && admin content53 "$PHASE" >/dev/null || { echo "the database: init failed"; exit 2; }
    APP_KEY=test PORT=8798 DB_PATH=$DB "$PS" serve > "$TMP/server.log" 2>&1 &
    PID=$!
    for _ in $(seq 100); do curl -s "$BASE/v1/ping" >/dev/null 2>&1 && break; sleep 0.1; done
else
    MODE=remote; PS=/usr/local/bin/pokeserver
    KEY=${KEY:-$(sudo -n grep -E '^APP_KEY=' /etc/pokewalker/server.env | cut -d= -f2- | tr -d '"')}
    [ -n "$KEY" ] || { echo "no APP_KEY (KEY=… or sudo for server.env)"; exit 2; }
    admin() { sudo -n -u pokewalker "$PS" "$@" 2>/dev/null; }
fi
N=$(date +%s)
A=zz$(printf '%06d' $(( N % 1000000 ))); B=zz$(printf '%06d' $(( (N + 1) % 1000000 ))); C=zz$(printf '%06d' $(( (N + 2) % 1000000 )))
X=chk$(printf '%06d' $(( N % 1000000 )))                                      # local only: not a test ID
IDS="$A $B $C"; [ $MODE = local ] && IDS="$IDS $X"
echo "$MODE $BASE · content53 $PHASE · test IDs $A (5.2.2) $B $C (5.3)$([ $MODE = local ] && echo " · $X (5.3, not a test ID)")"
appof() { [ "$1" = "$A" ] && echo 5.2.2 || echo 5.3; }
call() { # call <path> <app>: the request in $TMP/req
    CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' -H 'Content-Type: application/json' -H "X-App-Key: $KEY" -H "User-Agent: PokeWalker/$2 (mac)" --data-binary @"$TMP/req" "$BASE$1")
    BODY=$(cat "$TMP/body" 2>/dev/null)
}
create() { jq -n --arg id "$1" --arg app "$(appof "$1")" '{id: $id, device: "zz-check53", device_name: "ZZ-CHECK53", app: $app, pin: "2468"}' > "$TMP/req"; call /v1/create "$(appof "$1")"
    printf '%s' "$BODY" | jq -r .session > "$TMP/s-$1"; echo 0 > "$TMP/q-$1"; }
act() {  # act <id> <act JSON>
    q=$(( $(cat "$TMP/q-$1") + 1 )); echo $q > "$TMP/q-$1"
    jq -n --arg id "$1" --arg s "$(cat "$TMP/s-$1")" --argjson q $q --argjson a "$2" --arg app "$(appof "$1")" '{id: $id, session: $s, seq: $q, act: $a, app: $app}' > "$TMP/req"
    call /v2/act "$(appof "$1")"
}
exp() { jq -n --arg id "$1" --arg s "$(cat "$TMP/s-$1")" '{id: $id, session: $s}' > "$TMP/req"; call /v2/expedition "$(appof "$1")"; }
has() { printf '%s' "$BODY" | grep -q "$1"; }
day=$(date +%F)

# 0 — the server
CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' "$BASE/v1/ping"); BODY=$(cat "$TMP/body")
ok "ping" is 200 .ok true
SW=$(admin content53); ok "pokeserver content53 → $PHASE ($SW)" [ "$SW" = "content53 $PHASE" ]

# 1 — a 5.2.2 app (a test ID: the request's app decides): as 5.2.2
create "$A";                                ok "5.2.2: create" is 200 .content52 true
act "$A" '{"steps":{}}';                    ok "5.2.2: its first act" is 200
act "$A" '{"expStart":{"id":"레시라무"}}';  ok "5.2.2: 레시라무 → refused" is 200 '.out.cannot != null' true
act "$A" '{"expStart":{"id":"칼로스 이야기"}}'; ok "5.2.2: 칼로스 이야기 → refused" is 200 '.out.cannot != null' true
act "$A" '{"pairInvite":{"to":"'"$B"'","id":"레시라무"}}'; ok "5.2.2: pairInvite → 5.3부터예요" is 200 .out.cannot "5.3부터예요"
act "$A" '{"expStart":{"id":"토네로스"}}';  ok "5.2.2: 토네로스 as 5.2" is 200 '[.out.cannot, .walk.expeditions["토네로스"].on] | tostring' '[null,true]'

# 1b — local: a 5.3 app that isn't a test ID — the switch's own
if [ $MODE = local ]; then
    create "$X"
    if [ "$PHASE" = off ]; then ok "not a test ID, 5.3, off: no content53 in the reply" is 200 '.content53 // false' false
    else ok "not a test ID, 5.3, on: content53" is 200 .content53 true; fi
    act "$X" '{"steps":{}}'
    act "$X" '{"expStart":{"id":"레시라무"}}'
    if [ "$PHASE" = off ]; then ok "not a test ID, off: 레시라무 → refused" is 200 '.out.cannot != null' true
    else ok "not a test ID, on: 레시라무 started" is 200 '.walk.expeditions["레시라무"].on' true; fi
    exp "$X"
    if [ "$PHASE" = off ]; then ok "not a test ID, off: /v2/expedition without pairs · story" is 200 '[.pairs, .story] | tostring' '[null,null]'
    else ok "not a test ID, on: /v2/expedition's story" is 200 '.story | length > 10' true; fi
fi

# 2 — a 5.3 app on a test ID: 칼로스 이야기 whatever the switch
create "$B";                                ok "5.3: create → content53" is 200 .content53 true
act "$B" '{"steps":{}}';                    ok "5.3: its first act" is 200
U=$(printf '%s' "$BODY" | jq '.walk.companion.uid // 1000000')
act "$B" '{"expStart":{"id":"칼로스 이야기"}}'; ok "5.3: 칼로스 이야기 started (제르네아스 until the pick)" is 200 '[.out.cannot, .walk.expeditions["칼로스 이야기"].on, .walk.expeditions["칼로스 이야기"].mon.dex] | tostring' '[null,true,716]'
admin set "$B" '$.expeditions."칼로스 이야기".stage' 1 >/dev/null
act "$B" "{\"expFight\":{\"id\":\"칼로스 이야기\",\"party\":[$U]}}"; ok "5.3: 1장's trainer — 플레어단 조무래기, two, Lv.35" is 200 '[.out.battle.trainer, (.out.battle.theirs | length), .out.battle.theirs[0].mon.level, .out.battle.expedition] | tostring' '["플레어단 조무래기",2,35,"칼로스 이야기"]'
act "$B" '{"battle":{"cmd":{"forfeit":{}}}}'; ok "5.3: 기권 — over, the step kept" is 200 '[.out.end != null, .walk.expeditions["칼로스 이야기"].stage] | tostring' '[true,1]'
admin set "$B" '$.expeditions."칼로스 이야기".stage' 9 >/dev/null
act "$B" '{"expPick":{"id":"칼로스 이야기","dex":717}}'; ok "5.3: the pick — 이벨타르, the final fight next" is 200 '[.out.cannot, .walk.expeditions["칼로스 이야기"].pick, .walk.expeditions["칼로스 이야기"].mon.dex, .walk.expeditions["칼로스 이야기"].stage] | tostring' '[null,717,717,10]'
act "$B" "{\"expFight\":{\"id\":\"칼로스 이야기\",\"party\":[$U]}}"; ok "5.3: the final fight — 이벨타르 Lv.70, 3 bars" is 200 '[.out.battle.theirs[0].mon.dex, .out.battle.theirs[0].mon.level, (.out.battle.theirs | length)] | tostring' '[717,70,3]'
act "$B" '{"battle":{"cmd":{"run":{}}}}';   ok "5.3: 후퇴 — over" is 200 '.out.end != null' true
exp "$B";                                   ok "5.3: /v2/expedition — the story's scenes, no pairs yet" is 200 '[(.story | length > 10), (.pairs | length)] | tostring' '[true,0]'

# 3 — a pair: B asks C (레시라무), C takes it (제크로무), both on their dragons; ended by C
create "$C";                                ok "5.3 (C): create" is 200
act "$C" '{"steps":{}}'
act "$B" '{"pairInvite":{"to":"'"$C"'","id":"레시라무"}}'; ok "5.3: not friends → refused" is 200 .out.cannot "친구에게만
청할 수 있어요"
act "$B" "{\"friendRequest\":{\"to\":\"$C\"}}"; act "$C" "{\"friendAccept\":{\"from\":\"$B\"}}"
act "$B" '{"pairInvite":{"to":"'"$C"'","id":"레시라무"}}'; ok "5.3: B asks C (레시라무)" is 200 '.out.cannot' null
act "$C" '{"steps":{}}';                    ok "5.3: C hears the ask" eval 'is 200 && has pairAsked'
exp "$C";                                   ok "5.3: C's /v2/expedition — got, 레시라무" is 200 '[.pairs[0].state, .pairs[0].theirs, .pairs[0].goal] | tostring' '["got","레시라무",300000]'
P=$(printf '%s' "$BODY" | jq '.pairs[0].id')
act "$C" '{"pairAccept":{"pair":'"$P"',"id":"제크로무"}}'; ok "5.3: C takes it (제크로무 on)" is 200 '[.out.cannot, .walk.expeditions["제크로무"].on] | tostring' '[null,true]'
act "$B" '{"steps":{}}';                    ok "5.3: B hears it — 레시라무 on, 칼로스 이야기 stopped" eval 'is 200 "[.walk.expeditions[\"레시라무\"].on, .walk.expeditions[\"칼로스 이야기\"].on] | tostring" "[true,false]" && has pairOn'
exp "$B";                                   ok "5.3: B's /v2/expedition — on, 14 days" is 200 '[.pairs[0].state, .pairs[0].mine, .pairs[0].theirs] | tostring' '["on","레시라무","제크로무"]'
PR=$(admin pairs); ok "pokeserver pairs shows it" sh -c "printf '%s' \"\$1\" | grep -q '$B'" _ "$PR"
act "$C" '{"pairCancel":{"pair":'"$P"'}}'; ok "5.3: C ends it" is 200 '.out.cannot' null
act "$B" '{"steps":{}}';                    ok "5.3: B hears 풀림" eval 'is 200 && has 풀림'

# the test IDs gone (remote: and the saves delete keeps as files)
if [ $MODE = remote ]; then
    gone=0; for x in $IDS; do admin delete "$x" --yes >/dev/null && gone=$((gone + 1)); done
    sudo -n -u pokewalker sh -c "rm -f $(for x in $IDS; do printf '/var/lib/pokewalker/deleted-%s-*.json ' "$x"; done)"
    left=$(admin list 2>/dev/null | grep -cE "$(echo $IDS | tr ' ' '|')")
    ok "the test IDs deleted ($gone), none left" [ "$left" = 0 ]
fi
echo "$PASS ok, $FAILS failed"
[ $FAILS -eq 0 ]
