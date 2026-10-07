# PokeWalker 서버

팀이 쓰는 PokeWalker의 **세이브 · 게임 서버**다. 앱은 세이브를 보내지 않고 행동만 보낸다. 서버가 앱과 같은 게임 엔진으로 세이브를 만들고, 친구 · 교환 · 레이드 · 실시간 대전을 잇는다. 팀 다운로드 페이지와 앱 자동 업데이트도 이 서버가 맡는다.

집 미니 PC(Ubuntu 24.04)에서 돌고, 바깥에서는 `https://pokewalker.rulrulmo.work`로 들어온다.

## 목차

1. [한눈에 보기](#한눈에-보기)
2. [하는 일](#하는-일)
3. [API](#api)
4. [설정 (server.env)](#설정-serverenv)
5. [빌드 · 테스트 · 설치](#빌드--테스트--설치)
6. [새 버전 올리기 (릴리스 미러)](#새-버전-올리기-릴리스-미러)
7. [서버가 정하는 규칙](#서버가-정하는-규칙)
8. [깔린 것 (이 PC)](#깔린-것-이-pc)
9. [관리 명령](#관리-명령)
10. [운영](#운영)
11. [데이터](#데이터)
12. [고칠 때 주의할 점](#고칠-때-주의할-점)

## 한눈에 보기

```
앱 ──HTTPS──▶ https://pokewalker.rulrulmo.work ──(Cloudflare Tunnel)──▶ 127.0.0.1:8787
                cloudflared-pokewalker.service                          pokewalker.service = /usr/local/bin/pokeserver serve
                                                                        /var/lib/pokewalker/pokewalker.db (SQLite, WAL)
```

| 항목 | 내용 |
|---|---|
| 언어 · 프레임워크 | Swift 6.1.2(swiftly), Hummingbird 2, SQLite |
| 게임 규칙 | 앱과 같은 소스(`Sources/{Model,Data,Battle}`)를 빌드할 때 복사해 쓴다. 규칙이 앱과 서버에서 똑같다 |
| 코드 | `server/Sources/PokeCore/` (서버), `server/Sources/pokeserver/` (명령줄), `server/Tests/PokeCoreTests/` (테스트) |
| 설계 문서 | `docs/plans/08`(세이브 서버), `08b`(이 PC 설치), `10`(부정 방지), `11`(서버가 세이브를 만든다, 3.0), `12`(멀티), `13`(도구), `14`(3.8) |
| 지금 버전 (2026-10-07) | 앱 3.8.6, 서버는 main과 같다. `MIN_APP=3.0`(2.x 앱은 막힌다) |

## 하는 일

| 기능 | 서버가 하는 일 | 코드 |
|---|---|---|
| 세이브 | 앱이 보낸 행동(`/v2/act`)을 엔진으로 처리해 세이브를 만든다. 세션 · 순번(seq) · 저장된 답으로 같은 요청을 두 번 처리하지 않는다. 걸음 허용량과 하루 상한, 포켓몬 발급 장부, rev · history | `ServerPlay.swift` |
| 로그인 · PIN | 트레이너 ID + PC마다 PIN. 한 계정은 한 PC에서만 행동한다(다른 PC가 들어오면 앞 PC는 "다른 PC에서 접속") | `ServerDB.swift` |
| 친구 | 신청 → 수락, 친구 카드(동료 · 걸음 · 도감 · 타워 · 전적), `VIEW_ALL` 계정은 전체 탭 | `ServerTeam.swift` |
| 교환 게시판 | 글 올리기(한마디) · 제안 · 수락. 올리거나 제안한 포켓몬은 상자에서 빠져 맡겨지고, 받을 포켓몬은 **받기 함**에서 받는다 | `ServerMarket.swift`, `ServerClaims.swift` |
| 맡겨 키우기 | 친구에게 포켓몬을 5시간 맡기면 친구 걸음만큼 경험치, 키운 쪽은 BP | `ServerVisit.swift` |
| 협동 레이드 | 주마다 전설 보스 하나, 팀 HP를 모두 함께 깎는다. 깨면 볼로 잡기 | `ServerRaid.swift` |
| 실시간 대전 | 대전 파티 등록, 친구 신청 · 랜덤 매칭, 서로 6마리 보고 3마리 고르기, 한 수 30초, 전적 | `ServerDuel.swift` |
| 옛 1:1 교환 | 3.5 이전 앱의 교환(지금 앱은 게시판) | `ServerTrade.swift` |
| 다운로드 페이지 | 팀 비밀번호로 여는 소개 · 다운로드 · 패치 내역 페이지 | `ServerPage.swift` |
| 자동 업데이트 | 서명된 릴리스를 앱에 내준다. 앱이 서명을 직접 확인한다 | `ServerUpdate.swift` |
| 관리 명령 | 목록 · 세이브 보기 · 되돌리기 · 값 바꾸기 · 삭제 · 행동 기록 … | `ServerAdmin.swift` |

## API

`/v1/ping`과 다운로드 페이지를 빼면 모두 `X-App-Key` 헤더(앱 키)가 있어야 한다. 몸통은 JSON이다.

| 경로 | 하는 일 |
|---|---|
| `GET /v1/ping` | 살아 있는지(외부 감시용) |
| `POST /v1/create` · `/v1/login` · `/v1/pin` | 새 트레이너, 로그인(세션), PIN |
| `POST /v2/act` | **모든 게임 행동**: 걸음, 레이더, 배틀, 상점, 도구, 포켓몬, 친구, 교환 게시판, 받기, 맡기기, 레이드, 대전 … → `{rev, walk?, taken?, out}` |
| `POST /v2/team` | 친구 화면: 나와 친구 카드, 친구 신청, 맡기기(`visits`), `VIEW_ALL` 계정은 `all` |
| `POST /v2/market` | 교환 게시판: 글 · 제안 · 받기 함(`claims`) · 안 본 제안 수(`unseen`) |
| `POST /v2/raid` | 레이드 로비: 이번 주 보스, 남은 HP, 싸운 사람, 내 볼 |
| `POST /v2/duel` | 실시간 대전 상태(최대 25초 기다리는 롱폴), `record: true`면 전적 |
| `POST /v2/box` | 친구 상자 보기 |
| `POST /v2/trades` | 옛 1:1 교환 (3.5 이전 앱) |
| `POST /v1/update` · `GET /v1/download/mac` · `/v1/download/windows` | 자동 업데이트: 서명된 `manifest.json` + 서명, zip |
| `GET /` · `POST /login` · `GET /download/:kind` · `/shot/:name` · `/robots.txt` | 다운로드 페이지 |
| `POST /v1/save` · `/v1/legacy` · `/v1/radar` · `/v1/radar/result` · `/v1/hatch` · `/v1/buy` · `/v1/evolve` | 2.x 시절 경로. `MIN_APP=3.0`이라 2.x 앱은 426 |

`/v2/act`의 행동과 답의 모양은 앱과 같이 쓰는 `Sources/Model/Engine.swift`(Act, Outcome, News)와 `Sources/Model/Team.swift`(친구 · 게시판 · 레이드 · 대전의 답)에 있다.

## 설정 (server.env)

`/etc/pokewalker/server.env` (root:pokewalker 640). 예시는 `ops/server.env.example`. **값(키 · 비밀번호)은 커밋하지 않는다.**

| 이름 | 뜻 |
|---|---|
| `APP_KEY` | 앱 키. 앱의 `Cloud.swift`에 같은 값이 들어간다 (비밀) |
| `PORT` · `DB_PATH` | 8787, `/var/lib/pokewalker/pokewalker.db` |
| `DOWNLOAD_PASSWORD` | 다운로드 페이지 팀 비밀번호. 비면 페이지가 없다 (비밀) |
| `RELEASE_DIR` | 릴리스 파일 자리, `/var/lib/pokewalker/release` |
| `MIN_APP` | 이보다 오래된 앱은 426. 지금 `3.0` |
| `VIEW_ALL` | 친구 화면에 **전체** 탭이 보이는 계정(쉼표로 여럿). 지금 한 명 |
| `CHECK_MODE` · `CHECK_REJECT_TESTS` | 2.x 세이브 검사(docs/plans/10). 3.0부터는 세이브가 들어오지 않아 거의 쓰이지 않는다 |

바꾼 뒤에는 `sudo systemctl restart pokewalker`.

## 빌드 · 테스트 · 설치

```sh
. ~/.local/share/swiftly/env.sh     # 먼저! 빠지면 install이 조용히 실패하고 옛 서버가 그대로 돈다
server/build.sh                     # 릴리스 빌드 → server/.build/release/pokeserver
server/build.sh test                # 단위 테스트 (엔진 · 행동 · 친구 · 게시판 · 레이드 · 대전 · 도구 …)
server/test.sh                      # HTTP 전체 흐름: 임시 DB, 127.0.0.1:8799 (먼저 build.sh)
BASE=https://pokewalker.rulrulmo.work KEY=<APP_KEY> server/test.sh    # 실서버로. 테스트 ID는 끝나면 지운다
server/build.sh install             # 빌드 → /usr/local/bin에 설치 → 서비스 재시작 (sudo)
```

- `build.sh`는 매번 앱의 `Sources/{Model,Data,Battle}`을 `server/Sources/PokeCore/Game/`에 새로 복사한다(커밋하지 않음).
- 테스트 ID는 **`zz` + 숫자 6자리**(예: `zz123456`)다. 테스트 ID끼리만 보이고(게시판 · 레이드 · 전체 탭), 진짜 팀 데이터에 섞이지 않는다.
- 트레이너 ID는 2~12자다.

## 새 버전 올리기 (릴리스 미러)

자동 업데이트가 받는 것과 같은, 서명된 릴리스다. Claude 세션끼리 나눠서 한다.

| 순서 | 어디서 | 무엇 |
|---|---|---|
| 1 | 릴리스 Mac | `./build.sh publish`: Mac zip과 그 커밋의 Windows 워크플로 결과물로 `manifest.json`(버전 · 빌드 · 커밋 · zip 크기 · SHA-256)을 만들고 릴리스 키로 서명(`manifest.sig`). GitHub release `v<버전>`에 네 파일을 올린다. 비밀 키는 그 Mac에만 있다 |
| 2 | 이 PC | 게임 규칙(엔진)이나 서버가 바뀐 릴리스면 **서버를 먼저** `server/build.sh install` |
| 3 | 이 PC | `server/publish.sh v<버전>`: 네 파일을 받아 `pokeserver verify-release`로 서명 · 크기 · SHA-256을 확인하고, 통과해야만 페이지와 업데이트를 한 번에 바꾼다. 화면 사진은 그 커밋의 Windows 렌더를 WebP로 바꿔 쓴다 |
| 4 | 확인 | `POST /v1/update`가 새 버전을 답하는지 |

- 공개 키는 `Sources/Model/Ed25519.swift`의 `releaseKey`. 서버가 뚫려도 서명 없는 업데이트는 앱이 설치하지 않는다.
- 미러하기 전에 태그 · Windows CI · `manifest.json`의 커밋이 모두 같은지 본다.
- Mac 빌드는 Apple 하드웨어에서만, Windows 빌드는 GitHub Actions(`gh workflow run windows.yml --ref main`)다.

### 다운로드 페이지

- `https://pokewalker.rulrulmo.work/`: 게임 소개(실제 화면), 최신 Mac · Windows zip, 시작하기, 패치 내역(`docs/patch-notes.txt`).
- 팀 비밀번호 하나로 연다(쿠키 30일). 비밀번호를 바꾸면 서비스를 재시작하고 모두 다시 입력한다.
- 앱 그림이 닌텐도 저작물이라 **공개하지 않는다**. 검색 엔진도 막는다(`robots.txt`, `noindex`).
- 페이지가 보여 주는 것은 `RELEASE_DIR`의 파일뿐이고, 채우는 것은 `publish.sh`뿐이다.

## 서버가 정하는 규칙

앱이 아니라 서버가 판정하는 것들이다(값은 `Sources/Model`과 `server/Sources/PokeCore`에 있다).

| 분야 | 규칙 |
|---|---|
| 걸음 | 마지막 행동부터 초당 15걸음씩 허용량이 쌓인다(최대 하루치). 하루(한국 시간) 100,000걸음까지. 넘는 만큼은 잘린다 |
| 세션 | 새 로그인은 앞 세션을 끝낸다. 진행 중이던 배틀 · 레이더 · 연쇄는 버린다(타워는 배틀과 배틀 사이면 이어진다) |
| 교환 게시판 | 글 3개 · 제안 5개까지, 글은 3일. 거래되면 지닌 도구도 같이 간다. 교환 진화는 받을 때, 지닌 도구로 |
| 맡겨 키우기 | 5시간, 친구 1명당 1마리, 맡는 쪽은 2마리까지. 2,000걸음마다 1BP(최대 5) |
| 레이드 | 주마다(월요일 0시) 전설 보스 Lv.70. 팀 HP = 지난주 싸운 사람 × 4줄. 파워 10,000걸음 = 1칸(최대 3칸), 한 판에 최대 3줄, 턴 제한 없음 |
| 실시간 대전 | 대전 파티 3~6마리, 친구 신청(60초) 또는 랜덤 매칭(60초), 3마리 고르기 60초, 한 수 30초(두 번 놓치면 기권), 이기면 +3BP. 3.8 이전 앱끼리는 옛 방식 |
| 배틀 타워 | Lv.50 복사본으로 싸운다. 14연승부터 상대가 도구를 든다 |
| 육성 | 영양제는 스탯당 255, 총합 510까지. 노력치 내리는 열매는 10씩 |

## 깔린 것 (이 PC)

| 무엇 | 어디 |
|---|---|
| 시스템 사용자 | `pokewalker` (nologin). 관리자 계정은 `pokewalker` 그룹(백업 읽기용) |
| 설정 | `/etc/pokewalker/server.env` |
| DB | `/var/lib/pokewalker/pokewalker.db`. `pokeserver init`만 만든다. 파일이 없으면 서버가 시작하지 않는다 |
| 릴리스 | `/var/lib/pokewalker/release` (`publish.sh`가 채운다) |
| 서버 | `pokewalker.service` (`ops/pokewalker.service`) |
| 백업 | `pokewalker-backup.timer` 매일 04:30 → `/var/lib/pokewalker/backup/pw-YYYY-MM-DD.db.gz`, 14일 보관 (`ops/backup.sh`) |
| 터널 | `cloudflared-pokewalker.service`, 설정 `/etc/cloudflared/pokewalker.yml` (`ops/cloudflared.yml.example`) |

**터널은 따로 둔다.** 이 PC에는 다른 용도의 기본 `cloudflared.service`가 이미 있다. 서버용 터널은 별도 서비스라서 재시작해도 다른 접속이 끊기지 않는다.
- DNS 연결은 반드시 이 터널의 설정으로: `cloudflared tunnel --config /etc/cloudflared/pokewalker.yml route dns --overwrite-dns <UUID> pokewalker.rulrulmo.work`
- `cloudflared service install`은 쓰지 않는다(기존 서비스와 부딪힌다).
- cloudflared 업데이트(한 달에 한 번): `sudo apt-get install --only-upgrade cloudflared` → `sudo systemctl restart cloudflared-pokewalker`.

## 관리 명령

먼저 `alias pw='sudo -u pokewalker /usr/local/bin/pokeserver'`. **반드시 pokewalker 사용자로** 실행한다(root로 DB를 열면 -wal/-shm이 root 것이 되어 서버가 못 쓴다). 다른 DB는 `--db <path>`.

| 명령 | 하는 일 |
|---|---|
| `pw list` | 전원: 오늘 걸음 순, rev, total, watts, 마지막 저장, PC |
| `pw show <id>` | 한 명: 요약, history, legacy |
| `pw actions <id> [n]` | 최근 행동(잘린 걸음 · 거절 포함), 지금 하는 것, 오늘 걸음 |
| `pw mons <id>` | 서버가 발급한 포켓몬 장부(uid, 종, 출처, 상태) |
| `pw walk <id> [<rev> <reason>]` | 세이브 JSON(또는 history 사본) → `\| jq` |
| `pw set <id> '<json-path>' '<json-value>'` | 값 하나 바꾸기. 예: `pw set 민수 '$.watts' 0`. 앱이 못 읽는 결과면 바꾸지 않는다 |
| `pw rollback <id> <rev> <reason>` | history 사본을 새 rev로 되돌린다 |
| `pw rename <id> <새 id>` | 이름 바꾸기(키가 바뀌면 그 PC는 다시 ID 입력) |
| `pw delete <id> --yes` | 삭제. 세이브는 `/var/lib/pokewalker/deleted-<key>-<unix>.json`으로 남긴다. 그 트레이너가 맡고 있던 남의 포켓몬은 주인의 받기 함으로 돌아간다 |
| `pw pin-reset <id>` | PIN과 모든 PC의 신뢰를 지운다(다음 로그인에서 새 PIN) |
| `pw suspects [days]` · `pw flags <id>` | 검사에 걸린 세이브(2.x 시절) |
| `pw legacy [<id>]` · `pw prune` · `pw sample` | 서버 이전 세이브 · history 정리(서버가 매시 함) · 새 세이브 JSON |
| `pw verify-release <dir>` | 릴리스 폴더 서명 · zip 확인(`publish.sh`가 씀) |

비상시 `sudo -u pokewalker sqlite3 /var/lib/pokewalker/pokewalker.db`로 직접 고칠 때는 `rev = rev + 1, writer = 'admin'`도 같이 한다.

## 운영

| 할 일 | 명령 |
|---|---|
| 로그 | `journalctl -u pokewalker -f`, `journalctl -u cloudflared-pokewalker` |
| 상태 | `systemctl status pokewalker cloudflared-pokewalker`, `systemctl --failed`, `du -sh /var/lib/pokewalker` |
| 서버 업데이트 | `git pull` → `. ~/.local/share/swiftly/env.sh` → `server/build.sh install`. 1~2초 끊기고, 앱은 다음 요청에서 다시 붙는다 |
| 외부 감시 | `GET /v1/ping` |

**복원** (순서를 지킨다: 낡은 WAL이 되살린 DB를 망가뜨린다)

```sh
sudo systemctl stop pokewalker
sudo rm -f /var/lib/pokewalker/pokewalker.db-wal /var/lib/pokewalker/pokewalker.db-shm
sudo -u pokewalker sh -c 'gunzip -c /var/lib/pokewalker/backup/pw-YYYY-MM-DD.db.gz > /var/lib/pokewalker/pokewalker.db'
sudo systemctl start pokewalker
```

## 데이터

SQLite 한 파일. 표는 처음 열 때 만들어지고, 새 칸은 `ALTER TABLE`로 더한다(`ServerDB.swift`).

| 묶음 | 표 |
|---|---|
| 트레이너 · 세이브 | `trainers`(세이브 JSON, rev, 앱 버전), `history`(되돌리기용 사본), `legacy`(서버 이전 세이브) |
| 접속 | `pins`, `trust`(PC별), `pin_fails`, `play`(세션 · seq · 저장된 답 · 진행 중인 배틀 · 걸음 허용량) |
| 기록 | `steps_day`(하루 걸음), `actions`(행동 기록), `mons`(포켓몬 발급 장부), `chains`, `grants`, `flags` |
| 친구 · 소식 | `friends`, `inbox`(친구에게 가는 소식) |
| 교환 | `listings`, `bids`(게시판), `claims`(받기 함), `trades`(옛 1:1) |
| 맡겨 키우기 | `visits` |
| 레이드 | `raids`, `raid_hits`, `raid_catch` |
| 대전 | `duels`(상태 · 배틀 · 턴 · 파티 · 고른 것 · 결과) |

## 고칠 때 주의할 점

- **엔진은 앱과 같이 쓴다.** `Sources/{Model,Data,Battle}`을 바꾸면 서버와 앱 둘 다 바뀐다. 앱이 그 값을 화면에 쓰면(예: 레이드 파워 · 턴 수) 서버 설치를 앱 릴리스와 맞춘다.
- **저장되는 구조체에 새 칸은 옵셔널로.** Swift의 Codable은 기본값을 무시해서, 옵셔널이 아니면 예전에 저장된 세이브나 배틀을 못 읽는다.
- **파일 이름이 겹치면 서버 빌드가 깨진다.** `Model` · `Data` · `Battle`이 한 모듈로 합쳐지기 때문이다.
- **새 소식(News) 종류**는 그것을 아는 앱에만 보낸다(`inbox`의 `min_app`, `appKnows`). 모르는 종류가 오면 옛 앱이 답을 못 읽는다.
- 새 기능은 `server/build.sh test`와 `server/test.sh`에 테스트를 더하고, 배포 뒤 실서버 `test.sh`로 확인한다.
