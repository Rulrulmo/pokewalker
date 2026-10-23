#!/bin/sh
# server/check52.sh [off|on] — 5.2's switch (docs/plans/19 §11.6) over HTTP, with test IDs: a 5.1.5 app plays as 5.1.5 did (no 5.2 원정, no
# 기술머신, no 일루전 in its duel); a 5.2 app on a test ID has 5.2 whatever the switch (토네로스 met with its HP, 기술머신10 bought and taught,
# 테라키온's boss and its balls, 일루전 in a duel of two 5.2 apps). off (the default) / on: what `pokeserver content52` should say.
#   local:  server/check52.sh [off|on]      a temporary database, the release build on 127.0.0.1:8798 (content5 · 51 on, content52 as asked) —
#           and a trainer that isn't a test ID too (the switch's own: 5.2 off as 5.1.5, on as 5.2)
#   remote: BASE=https://pokewalker.rulrulmo.work server/check52.sh [off|on]   on the mini PC (the key from server.env, the admin through
#           sudo -u pokewalker); the test IDs are deleted at the end
set -u
cd "$(dirname "$0")"
PHASE=${1:-off}; [ "$PHASE" = off ] || [ "$PHASE" = on ] || { echo "check52.sh [off|on]"; exit 2; }
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
    admin init >/dev/null && admin content5 on >/dev/null && admin content51 on >/dev/null && admin content52 "$PHASE" >/dev/null || { echo "the database: init failed"; exit 2; }
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
echo "$MODE $BASE · content52 $PHASE · test IDs $A (5.1.5) $B $C (5.2)$([ $MODE = local ] && echo " · $X (5.2, not a test ID)")"
appof() { [ "$1" = "$A" ] && echo 5.1.5 || echo 5.2; }
call() { # call <path> <app>: the request in $TMP/req
    CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' -H 'Content-Type: application/json' -H "X-App-Key: $KEY" -H "User-Agent: PokeWalker/$2 (mac)" --data-binary @"$TMP/req" "$BASE$1")
    BODY=$(cat "$TMP/body" 2>/dev/null)
}
create() { jq -n --arg id "$1" --arg app "$(appof "$1")" '{id: $id, device: "zz-check52", device_name: "ZZ-CHECK52", app: $app, pin: "2468"}' > "$TMP/req"; call /v1/create "$(appof "$1")"
    printf '%s' "$BODY" | jq -r .session > "$TMP/s-$1"; echo 0 > "$TMP/q-$1"; }
act() {  # act <id> <act JSON>
    q=$(( $(cat "$TMP/q-$1") + 1 )); echo $q > "$TMP/q-$1"
    jq -n --arg id "$1" --arg s "$(cat "$TMP/s-$1")" --argjson q $q --argjson a "$2" --arg app "$(appof "$1")" '{id: $id, session: $s, seq: $q, act: $a, app: $app}' > "$TMP/req"
    call /v2/act "$(appof "$1")"
}
look() { jq -n --arg id "$1" --arg s "$(cat "$TMP/s-$1")" '{id: $id, session: $s, since: 0}' > "$TMP/req"; call /v2/duel "$(appof "$1")"; }
has() { printf '%s' "$BODY" | grep -q "$1"; }
day=$(date +%F)

# 0 — the server
CODE=$(curl -s -o "$TMP/body" -w '%{http_code}' "$BASE/v1/ping"); BODY=$(cat "$TMP/body")
ok "ping" is 200 .ok true
SW=$(admin content52); ok "pokeserver content52 → $PHASE ($SW)" [ "$SW" = "content52 $PHASE" ]

# 1 — a 5.1.5 app (a test ID: the request's app decides): as 5.1.5
create "$A";                                ok "5.1.5: create" is 200 .content51 true
act "$A" '{"steps":{}}';                    ok "5.1.5: its first act" is 200
admin set "$A" '$.watts' 20000 >/dev/null
act "$A" '{"expStart":{"id":"토네로스"}}';  ok "5.1.5: 토네로스 → refused" is 200 '.out.cannot != null' true
act "$A" '{"buy":{"bp":false,"item":"기술머신10","qty":1}}'; ok "5.1.5: 기술머신10 → refused, no tms" is 200 '[.out.cannot != null, .walk.tms] | tostring' '[true,null]'
act "$A" '{"expFight":{"id":"토네로스"}}';  ok "5.1.5: expFight → refused" is 200 '.out.cannot != null' true
act "$A" '{"expStart":{"id":"지가르데"}}';  ok "5.1.5: 지가르데 as 5.1" is 200 '[.out.cannot, .walk.expeditions["지가르데"].on] | tostring' '[null,true]'

# 1b — local: a 5.2 app that isn't a test ID — the switch's own
if [ $MODE = local ]; then
    create "$X"
    if [ "$PHASE" = off ]; then ok "not a test ID, 5.2, off: no content52 in the reply" is 200 '.content52 // false' false
    else ok "not a test ID, 5.2, on: content52" is 200 .content52 true; fi
    act "$X" '{"steps":{}}'; admin set "$X" '$.watts' 20000 >/dev/null
    act "$X" '{"buy":{"bp":false,"item":"기술머신10","qty":1}}'
    if [ "$PHASE" = off ]; then ok "not a test ID, off: 기술머신10 → refused" is 200 '.out.cannot != null' true
    else ok "not a test ID, on: 기술머신10 bought" is 200 '[.out.cannot, (.walk.tms | index(10) != null)] | tostring' '[null,true]'; fi
    act "$X" '{"expStart":{"id":"토네로스"}}'
    if [ "$PHASE" = off ]; then ok "not a test ID, off: 토네로스 → refused" is 200 '.out.cannot != null' true
    else ok "not a test ID, on: 토네로스 started" is 200 '.walk.expeditions["토네로스"].on' true; fi
fi

# 2 — a 5.2 app on a test ID: 5.2 whatever the switch
create "$B";                                ok "5.2: create → content52" is 200 .content52 true
act "$B" '{"steps":{}}';                    ok "5.2: its first act" is 200
U=$(printf '%s' "$BODY" | jq '.walk.companion.uid // 1000000')
admin set "$B" '$.watts' 20000 >/dev/null
act "$B" '{"expStart":{"id":"토네로스"}}';  ok "5.2: 토네로스 started" is 200 '[.out.cannot, .walk.expeditions["토네로스"].on] | tostring' '[null,true]'
admin set "$B" '$.expeditions."토네로스".meets' 1 >/dev/null; admin set "$B" '$.expeditions."토네로스".hp' 30 >/dev/null
act "$B" '{"expFight":{"id":"토네로스"}}';  ok "5.2: a meeting (used) → its fight with HP 30, no 야생" eval 'is 200 "[.out.battle.theirs[0].hp, .out.battle.expedition, .walk.expeditions[\"토네로스\"].meets] | tostring" "[30,\"토네로스\",0]" && ! has "야생"'
for _ in 1 2 3 4 5; do act "$B" '{"battle":{"cmd":{"run":{}}}}'; [ "$(printf '%s' "$BODY" | jq '.out.end != null')" = true ] && break; done
ok "5.2: 도망 — over" is 200 '.out.end != null' true
act "$B" '{"buy":{"bp":false,"item":"기술머신10","qty":1}}'; ok "5.2: 기술머신10 bought (tms, W)" is 200 '[.out.cannot, (.walk.tms | index(10) != null), .walk.watts < 20000] | tostring' '[null,true,true]'
act "$B" "{\"mon\":{\"op\":{\"move\":{\"uid\":$U,\"slot\":0,\"move\":237}}}}"; ok "5.2: 잠재파워 taught (Walk.relearnable)" is 200 '[.out.cannot, (.walk.companion.known | index(237) != null)] | tostring' '[null,true]'
act "$B" '{"expStart":{"id":"테라키온"}}';  ok "5.2: 테라키온 started (토네로스 stopped)" is 200 '[.walk.expeditions["테라키온"].on, .walk.expeditions["토네로스"].on] | tostring' '[true,false]'
admin set "$B" '$.expeditions."테라키온".stage' 1 >/dev/null
act "$B" "{\"expFight\":{\"id\":\"테라키온\",\"party\":[$U]}}"; ok "5.2: 테라키온's boss — 3 bars, Lv.60, today's fight, no 야생" eval 'is 200 "[(.out.battle.theirs | length), .out.battle.raidTier, .out.battle.theirs[0].mon.level, .walk.expeditions[\"테라키온\"].fought] | tostring" "[3,3,60,\"$day\"]" && ! has "야생"'
act "$B" '{"battle":{"cmd":{"ball":{}}}}';  ok "5.2: no ball at the boss" is 200 '.out.cannot // ([.out.beats[]? | tostring] | join(" ")) | contains("볼로")' true
act "$B" '{"battle":{"cmd":{"run":{}}}}';   ok "5.2: 후퇴 — over" is 200 '.out.end != null' true
act "$B" "{\"expFight\":{\"id\":\"테라키온\",\"party\":[$U]}}"; ok "5.2: once a day" is 200 .out.cannot "오늘은 이미
싸웠어요"
admin set "$B" '$.expeditions."테라키온".balls' 5 >/dev/null
n=0; while [ $n -lt 5 ]; do n=$((n + 1)); act "$B" '{"expBall":{"id":"테라키온"}}'
    [ "$(printf '%s' "$BODY" | jq '.out.raidThrow.caught == true or .out.raidThrow.balls == 0 or .out.cannot != null')" = true ] && break; done
ok "5.2: the ball stage — $n thrown" is 200 '(.out.raidThrow.caught == true and .walk.expeditions["테라키온"].done == 1) or (.out.raidThrow.balls == 0 and .walk.expeditions["테라키온"].balls == null)' true

# 3 — 일루전 in a duel: two 5.2 apps (조로아크 leads, as 구구); a 5.1.5 app in it: none
create "$C";                                ok "5.2 (C): create" is 200
act "$C" '{"steps":{}}'
mon() { jq -nc --argjson d $1 --argjson u $2 '{dex: $d, level: 50, female: false, uid: $u}'; }
for x in $A $B $C; do admin set "$x" '$.box' "[$(mon 571 1000101),$(mon 25 1000102),$(mon 16 1000103)]" >/dev/null; admin set "$x" '$.lastUID' 1000103 >/dev/null; done
for p in "$B $C" "$A $B"; do set -- $p; act "$1" "{\"friendRequest\":{\"to\":\"$2\"}}"; act "$2" "{\"friendAccept\":{\"from\":\"$1\"}}"; done
for x in $A $B $C; do act "$x" '{"duelParty":{"uids":[1000101,1000102,1000103]}}'; done
start() { act "$1" "{\"duelChallenge\":{\"to\":\"$2\"}}"; D=$(printf '%s' "$BODY" | jq .out.duel.id)
    act "$2" "{\"duelAccept\":{\"id\":$D}}"; act "$2" "{\"duelPick\":{\"id\":$D,\"slots\":[0,1,2]}}"; act "$1" "{\"duelPick\":{\"id\":$D,\"slots\":[0,1,2]}}"; }
finish() { for _ in 1 2 3 4 5 6; do for x in $1 $2; do look "$x"; [ "$(printf '%s' "$BODY" | jq -r .duel.state)" = active ] || continue
        case $(printf '%s' "$BODY" | jq -r .duel.need) in
        move) act "$x" "{\"duelMove\":{\"id\":$D,\"cmd\":{\"forfeit\":{}}}}" ;;
        replace) to=$(printf '%s' "$BODY" | jq '.duel.battle as $b | [range(0; $b.mine | length) | select($b.mine[.].hp > 0 and . != $b.me)][0] // 0')
                 act "$x" "{\"duelMove\":{\"id\":$D,\"cmd\":{\"replace\":{\"to\":$to}}}}" ;;
        esac; done
        look "$1"; [ "$(printf '%s' "$BODY" | jq -r .duel.state)" = over ] && return 0; done; return 1; }
start "$B" "$C";                            ok "5.2 × 5.2: the duel on" is 200 .out.duel.state active
look "$C";                                  ok "5.2 × 5.2: 일루전 — C sees 조로아크 as 구구" eval 'is 200 "[.duel.battle.theirs[0].mon.dex, .duel.battle.theirs[0].disguise.dex] | tostring" "[571,16]" && ! has "조로아크"'
finish "$B" "$C";                           ok "5.2 × 5.2: over (forfeit)" true
start "$A" "$B";                            ok "5.1.5 × 5.2: the duel on" is 200 .out.duel.state active
look "$A";                                  ok "5.1.5 × 5.2: no 일루전" is 200 '[.duel.battle.theirs[0].mon.dex, .duel.battle.theirs[0].disguise] | tostring' '[571,null]'
finish "$A" "$B";                           ok "5.1.5 × 5.2: over (forfeit)" true

# the test IDs gone (remote: and the saves delete keeps as files)
if [ $MODE = remote ]; then
    gone=0; for x in $IDS; do admin delete "$x" --yes >/dev/null && gone=$((gone + 1)); done
    sudo -n -u pokewalker sh -c "rm -f $(for x in $IDS; do printf '/var/lib/pokewalker/deleted-%s-*.json ' "$x"; done)"
    left=$(admin list 2>/dev/null | grep -cE "$(echo $IDS | tr ' ' '|')")
    ok "the test IDs deleted ($gone), none left" [ "$left" = 0 ]
fi
echo "$PASS ok, $FAILS failed"
[ $FAILS -eq 0 ]
