# 서버 구현 지시서 (집 미니 PC)

> 2026-10-02 · `docs/plans/08b-server-home.md`. 집 미니 PC(Ubuntu)에서 이 저장소를 클론해 작업할 Claude Code 세션이 읽는다. **`docs/plans/08-server-save.md`를 먼저 끝까지 읽는다.**
> 08에서 정한 것은 모두 그대로 간다: ID만으로 로그인, 세션은 저장 권한, rev, 409/426, history, legacy, 서버 쪽 검사 없음. 바뀌는 것은 호스팅 하나다. Workers + D1 대신 **미니 PC의 Swift 서버 + SQLite + Cloudflare Tunnel**을 쓴다.
> 08의 wrangler, `src/index.ts`, D1 `batch()`, Cron, 무료 한도, `workers.dev` 이야기는 이 문서로 대체한다. 서버 쪽에서 08과 이 문서가 다르면 이 문서를 따른다. **(정함)**은 08에서 비어 있던 부분을 이 문서가 정했다는 뜻이다.
> 자리표시: `<domain>`은 사용자가 Cloudflare에 등록해 둔 도메인이다. API 주소는 `https://api.<domain>`, 포트는 `8787`이다. 기준 코드는 커밋 ac86e26(1.13)이고, 서버를 쓰는 앱은 2.0이다(08 §5).

## 1. 한눈에

```
Mac / Windows 앱 (Core/Cloud.swift — 앱 쪽 세션이 만든다. 로그인 창, 2분 주기·동작 직후 저장, 409/426, 치트 검사. 08 §7)
   │ HTTPS POST /v1/* · X-App-Key · JSON
https://api.<domain> ── Cloudflare edge (TLS 인증서, DNS, 선택: rate limit. 코드는 없다)
   │ 미니 PC가 먼저 열어 둔 아웃바운드 터널 (포트포워딩 없음, 집 IP가 드러나지 않음)
미니 PC ─ cloudflared.service ──▶ http://127.0.0.1:8787
          pokewalker.service = /usr/local/bin/pokeserver serve (Swift 6.1.2 · Hummingbird 2; API와 관리 CLI가 한 바이너리; 프로세스 하나, DB 연결 하나)
          /var/lib/pokewalker/pokewalker.db (SQLite, WAL)
          pokewalker-backup.timer → backup/pw-YYYY-MM-DD.db.gz → rclone(필수) → 개인 Google Drive
관리: 같은 PC에서 sudo -u pokewalker pokeserver list|show|rollback|… (같은 DB 파일)
```

## 2. 저장소 배치

```
server/
  Package.swift  Package.resolved(커밋)  .swift-version(6.1.2, swiftly가 따른다)  build.sh  test.sh  README.md(6·7장 명령 요약)
  ops/pokewalker.service  ops/pokewalker-backup.{service,timer}  ops/backup.sh  ops/server.env.example  ops/cloudflared.yml.example
  Sources/CSQLite/module.modulemap  Sources/CSQLite/shim.h    Tests/PokeCoreTests/ServerTests.swift
  Sources/PokeCore/Server*.swift    서버 코드 전부 (ServerRoutes, ServerDB, ServerAdmin)
  Sources/PokeCore/Game/            build.sh가 ../Sources/{Model,Data,Battle}을 복사한다. gitignore
  Sources/pokeserver/main.swift     import Foundation; import PokeCore; exit(await run(CommandLine.arguments))
```

- **브랜치**: 작업은 `server-home`에서 하고, 끝나면 main으로 PR을 연다. 머지 뒤 미니 PC는 main을 따른다(6장 업데이트).
- **server/ 밖에서 고치는 곳은 세 군데뿐이다**(앱 쪽 세션과 충돌하지 않게): 루트 `Package.swift`의 `exclude`에 `"server"`(Windows CI의 `swift build`가 server/를 보지 않게), `.gitignore`에 `server/Sources/PokeCore/Game/`, 새 파일 `Sources/Model/TrainerID.swift`(4장 코드 그대로).
  - 앱 쪽 세션도 TrainerID.swift를 같은 내용으로 만든다. 시작할 때 `git fetch && git show origin/main:Sources/Model/TrainerID.swift`가 나오면 그 파일을 쓰고 새로 만들지 않는다(머지 충돌 방지).

**공유 방식: 빌드할 때 복사한다 (정함)**
- SwiftPM은 한 소스 파일을 두 타깃에 넣지 못하고, 타깃 경로도 패키지 안에 있어야 한다. 심볼릭 링크는 Windows 체크아웃(`core.symlinks=false`)에서 깨진다. 앱은 build.sh가 모든 파일을 한 모듈로 swiftc 하므로 Model/Data/Battle의 선언은 전부 `internal`이고, 따로 모듈로 떼면 수백 곳에 `public`을 붙여야 한다.
- 그래서 `server/build.sh`가 빌드할 때마다 지우고 다시 복사해서 PokeCore 모듈 **안에** 넣는다. 서버 코드는 `Walk`, `Mon`, `hex()`를 앱과 똑같이 쓴다. 복사본은 커밋하지 않으므로 낡을 일이 없다.

**읽어서 확인한 것 (커밋 ac86e26 기준)**
- Model(9개)과 Battle(6개)은 `import Foundation`만 쓰고, Data(생성 파일 2개)는 import가 없다. AppKit, WinSDK, Darwin, `NSLock`, `DispatchQueue`, 전역 가변 상태가 없고, Core·Mac·Windows·App·Tests의 심볼을 참조하지 않는다(`wares(bp:shells:)`는 기기 색 목록을 매개변수로 받는다).
- `#if os`는 `Store.swift`의 저장 폴더 한 곳(Linux는 `~/.local/share` 쪽)이고, `@MainActor`는 셀프테스트 `stepGateChecks()` 하나다. 둘 다 컴파일만 되고 서버는 부르지 않는다. `Walk.key`와 `rollover`는 `Calendar.current`와 `TimeZone.current`를 쓴다. 서버는 지금 부르지 않지만 시스템 시간대를 Asia/Seoul로 둔다(9장 1단계).
- `Data.swift`(186KB)와 `BattleData.swift`(178KB)의 전역 `let`은 `@_optimize(none)` 함수로 감싸여 지연 초기화되므로 `Walk`를 디코드하는 것만으로는 만들어지지 않는다. `Walk`와 `Mon`이 `courses`, `expTable` 등을 참조하므로 링크하려면 같이 넣는다.
- **corelibs Foundation에서는 이미 컴파일된다.** Windows CI(`windows.yml`, Swift 6.1.2)가 릴리스마다 `workflow_dispatch`로 **main**을 빌드하고 셀프테스트까지 돌리는데, Windows의 Foundation은 Linux와 같은 swift-corelibs-foundation이다(push 트리거만 옛 `win-port`로 남아 있다). Linux만의 차이(헤더, glibc)는 9장 2단계에서 처음 확인한다. **Game에서 실패하면 Sources/의 앱 파일을 고치지 말고, 오류 전문을 사용자에게 보고한다(앱 세션의 몫).**
- 한 모듈이라 이름이 겹치면 안 된다. Game 파일 이름(Course, Items, Mon, Shop, Sign, StepGate, Store, Util, Walk, TrainerID, Data, BattleData, Battle, Damage, Effects, EndOfTurn, Turn, Types)을 쓰면 "filename used twice"로 실패하므로 서버 파일은 `Server*.swift`로 짓는다. 타입도 `Store`, `Status`, `Move`, `Battle`, `Side`, `Walk` 대신 `SaveDB`, `Reply`, `LoginReq`처럼 짓는다.

**Swift를 고른 이유는 지금 필요한 만큼만 살린다.**
- 저장 요청의 `walk`를 진짜 `Walk` 타입으로 디코드해서 형식을 검사한다(08 §6). 나중에 서버 검증이나 멀티(랭킹, 레이드, 대결)를 만들 때는 같은 모듈에서 `Walk`와 `Battle`을 그대로 부르면 된다. 지금은 그 이상 아무것도 만들지 않는다.
- **지금은 Game의 계산(`here`, `bonus`, `points`, `encounter`, `party`, 배틀)을 부르지 않는다.** 범위 검사 없이 인덱스하므로(Walk.swift:40 `courses[course]`, :42 `monTypes[companion.dex]`, Mon.swift:15 `expTable[growthRate[dex]]`) 조작된 세이브 하나가 trap으로 서버를 죽이고, systemd 재시작과 앱의 재전송으로 되풀이된다. 나중에 부를 때는 먼저 course(`0..<courses.count`), 모든 Mon의 dex(1...493)와 level(1...100), `egg.dex`를 검사하고 통과한 것만 넘긴다.

```swift
// swift-tools-version:6.0
// server/Package.swift — the save server (Linux, systemd, behind cloudflared). Sources/PokeCore/Game = build.sh's copy of ../Sources/{Model,Data,Battle}.
import PackageDescription
let package = Package(name: "PokeServer", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")],
    targets: [.systemLibrary(name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
              .target(name: "PokeCore", dependencies: ["CSQLite", .product(name: "Hummingbird", package: "hummingbird")]),
              .executableTarget(name: "pokeserver", dependencies: ["PokeCore"]), .testTarget(name: "PokeCoreTests", dependencies: ["PokeCore"])])
```
- `module.modulemap`: `module CSQLite [system] { header "shim.h" link "sqlite3" export * }`, `shim.h`: `#include <sqlite3.h>`. PokeCore가 밖으로 내보내는 것은 `public func run(_ args: [String]) async -> Int32` 하나다. 테스트는 `@testable import PokeCore`로 들어간다.

```sh
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
```
- `--static-swift-stdlib`: swiftly 툴체인은 사용자 홈에 깔린다. 이 옵션이 없으면 `pokewalker` 사용자로 도는 바이너리(`ProtectHome`)가 Swift 런타임을 찾지 못한다. 미니 PC 메모리가 4GB 이하면 빌드에 `-j 2`를 붙인다.

## 3. 의존성

- **Ubuntu 24.04 LTS**(22.04도 된다, Swift 공식 지원 대상)에 **Swift 6.1.2**(swiftly): 앱 컴파일러(Apple Swift 6.1.2, Windows CI 설정도 같다)와 맞춘다. manifest는 `swift-tools-version:6.0`, Swift 6 언어 모드다. 테스트는 툴체인에 든 Swift Testing(`import Testing`)이다.
- **HTTP는 Hummingbird 2**: swift-nio 위의 얇은 층이라 Vapor보다 의존성과 빌드가 훨씬 가볍다. 라우트 다섯 개에 ORM, 템플릿, 인증은 필요 없다. `Package.resolved`는 커밋한다. SwiftPM은 툴체인보다 높은 tools-version을 요구하는 버전을 건너뛰므로, `from: "2.0.0"`은 6.1.2에서 되는 최신 2.x를 고른다.
- **SQLite는 시스템 libsqlite3의 C API 직접**(`CSQLite`): 쿼리가 10개 남짓이다. GRDB는 Linux가 공식 지원 대상이 아니고 의존성이 하나 는다. 래퍼(open, exec, query, bind)는 60줄 정도면 된다.
- **apt**: `swiftly init`가 출력하는 목록 + `libsqlite3-dev sqlite3 jq curl git rclone`(sqlite3 CLI는 백업과 비상 수리, jq는 test.sh, rclone은 백업을 밖으로).

## 4. API 계약

**공통**
- 형식은 `Content-Type: application/json`, UTF-8이다. 시각은 모두 서버 시계 기준 unix 초다. 크기 한도는 요청 본문 4 MiB(넘으면 413), `walk` 문자열은 UTF-8로 2,000,000바이트(08의 2MB)다.
- `X-App-Key: <APP_KEY>`는 `/v1/ping`을 뺀 모든 요청에 붙인다. 없거나 다르면 401이다(보안이 아니라 스캐너 거르기). `User-Agent: PokeWalker/<버전> (mac|windows)`는 로그용이고, 버전 판정은 본문의 `app`으로 한다.
- **`walk`는 JSON 문자열이다 (정함).** 앱이 `JSONEncoder`(sortedKeys)로 인코드한 `Walk.shared` 텍스트를 문자열 값으로 넣는다. 서버는 바이트 그대로 저장하고 그대로 돌려주며, 디코드는 검사할 때만 한다. 그래서 서버의 `Walk` 사본이 앱보다 옛 버전이어도 새 칸이 사라지지 않고, `json_extract(walk,'$.total')`도 그대로 쓸 수 있다.
- 기기 칸(`counter`, `boot`, `syncedAt`, `counterKind`, `cloudRev`, `cloudTotal`, `sentHash`)은 앱이 `shared`로 비워서 보낸다. 서버는 비우지도 검사하지도 않는다.
- `GET /v1/ping`은 200 `{"ok":true}`이고 키가 필요 없다(헬스체크용).
- 오류 본문은 `{"error":"<code>"}`이고, 경우에 따라 칸이 더 붙는다.
  - 400: `bad_request`(JSON이 아니거나 칸이 빠졌거나 형이 틀림, device가 비었거나 64자 초과, base가 음수), `bad_id`(ID 규칙 위반), `bad_walk`(`Walk`로 디코드되지 않거나 `version != 1`; legacy는 JSON 객체가 아님), `bad_app`(app이 `숫자(.숫자){0,3}` 꼴이 아님).
  - 401 `app_key`. 404 `no_trainer`(없는 ID, login은 제외). 409 `exists`(create) / `conflict`(save, `reason`이 `replaced`나 `stale`). 413 `too_big`(본문 4 MiB나 walk 2,000,000바이트 초과). 426 `old_app`(`{"error":"old_app","need":"2.1"}`). 500 `internal`(SQLite 오류, 디스크 상한의 SQLITE_FULL 포함. 로그에 남긴다).

**ID 규칙 (공유 파일)**
```swift
// Sources/Model/TrainerID.swift — shared with server/ (build.sh copies Sources/Model). docs/plans/08-server-save.md §2.
import Foundation
/// A trainer ID as typed: 2-12 of 가-힣, A-Z a-z, 0-9, _ — after trimming and NFC (the Mac may hand Hangul over as NFD).
/// name = what screens show; key = name lowercased, the server's primary key. nil = not a valid ID.
func trainerID(_ raw: String) -> (name: String, key: String)? {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    let ok = name.unicodeScalars.allSatisfy { s in let v = s.value
        return (0xAC00...0xD7A3).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0x30...0x39).contains(v) || v == 0x5F }
    return ok && (2...12).contains(name.unicodeScalars.count) ? (name, name.lowercased()) : nil
}
```
- NFC로 바꾼 뒤 `^[가-힣A-Za-z0-9_]{2,12}$`와 같다. 낱자(ㅋㅋ), 공백, 전각 문자는 받지 않는다 (정함: 08의 "한글"을 완성형 음절로 읽었다).
- 서버는 모든 요청의 `id`를 이 함수에 통과시키고 `key`로만 찾는다. `name`은 create 때 저장하고, 그 뒤에는 관리자 rename으로만 바뀐다.
- Linux Foundation의 `precomposedStringWithCanonicalMapping`이 없거나 틀리면 8장 테스트 1이 잡는다. 그때만 한글 조합 공식(`0xAC00 + (L*21+V)*28+T`)을 직접 넣는다.

**POST /v1/login**
```
요청 {"id":"민","device":"<PC마다 한 번 만든 임의값>","device_name":"KHMIN-MAC","app":"2.0","force":false}
→ 200 {"exists":false}
→ 200 {"exists":true,"busy":true,"name":"민","last_device":"KHMIN-WIN","updated_at":1790000000}
→ 200 {"exists":true,"name":"민","rev":42,"walk":"{…}"|null,"session":"<32 hex>","last_device":"KHMIN-WIN","updated_at":1790000000}
→ 426 old_app   (app이 그 ID의 최고 버전보다 낮으면, 세션을 가져가기 전에 막는다)
```
- **busy (정함)**: 08 §2-1은 "가져올까요?"에 **예**를 고른 뒤에야 세션을 바꾸므로 서버가 먼저 확인한다. `force`가 아니고, 세션을 가진 PC(`trainers.device`)가 요청의 `device`와 다르고, `now - updated_at < 300`이면 아무것도 바꾸지 않고 busy를 준다. 앱은 묻고, 예면 `force:true`로 다시 보낸다. **여기서 계속**도 `force:true`다.
- busy가 아니면 새 세션을 만들고 `session`, `device`, `last_device`(= device_name 앞 64자)를 덮어쓴다. 이전 세션은 다음 저장에서 409 replaced를 받는다. 응답의 `last_device`와 `updated_at`은 **덮어쓰기 전** 값이다(누가 언제까지 썼나). `updated_at`은 마지막으로 받아들인 저장 시각이고 로그인으로는 바뀌지 않는다.
- 세션은 시간으로 끝나지 않는다(만료 칸도, 세션 정리도 없다). `walk`가 null이면 create 뒤 첫 저장 전(rev 0)이다. `app`과 `force`는 08에 없던 칸이다 (정함). `app`이 빠지면 버전 검사를 건너뛴다.

**POST /v1/create** `{"id":"민","device":"…","device_name":"KHMIN-MAC"}` → 200 `{"rev":0,"session":"<32 hex>"}`(새 행: rev 0, walk·app·writer NULL, updated_at = created_at = now) 또는 409 `{"error":"exists"}`.

**POST /v1/save**
```
요청 {"id":"민","session":"…","app":"2.0","base":42,"walk":"{…}"}
→ 200 {"rev":43}
→ 409 {"error":"conflict","reason":"replaced"}
→ 409 {"error":"conflict","reason":"stale","rev":45,"walk":"{…}"}
→ 426 {"error":"old_app","need":"2.1"}
```
판정은 위에서부터 처음 맞는 줄을 따른다. 1~6번은 DB가 필요 없으므로 라우트 핸들러에서 actor에 들어가기 전에 한다(2MB 디코드가 DB actor를 막지 않게). 7번부터는 `SaveDB` 안에서 한 트랜잭션(`BEGIN IMMEDIATE`)으로 처리한다.

| # | 조건 | 응답 | DB |
|---|---|---|---|
| 1 | X-App-Key가 다름 | 401 | — |
| 2 | 본문이나 칸이 틀림 (4 MiB 초과는 413) | 400 bad_request | — |
| 3 | `trainerID(id)`가 nil | 400 bad_id | — |
| 4 | walk가 2,000,000바이트 초과 | 413 too_big | — |
| 5 | `Walk`로 디코드되지 않거나 version ≠ 1 | 400 bad_walk | — |
| 6 | app 형식이 틀림 | 400 bad_app | — |
| 7 | 행이 없음 | 404 no_trainer | — |
| 8 | `app` < `trainers.app` (NULL이면 통과) | 426, need = trainers.app | — |
| 9 | `session` ≠ `trainers.session` | 409 replaced | history conflict |
| 10 | `base == rev` | 200, rev + 1 | 저장 |
| 11 | `base > rev` | 200, base + 1 | 저장 |
| 12 | `base < rev`이고 `trainers.writer == session` | 200, rev + 1 | 저장 |
| 13 | 그 밖 (writer가 `'admin'`이거나 이전 세션) | 409 stale + 지금의 rev와 walk | history conflict |

- **11번**은 서버가 기록을 잃은 뒤(백업 복원, 정전)다. 세션은 9번에서 이미 맞았으므로 writer는 보지 않는다. rev는 줄지 않는다. rev 0(walk NULL)에 base 3이 와도 여기서 받으므로, stale에 `"walk":null`이 나가는 일이 없다.
- **`writer` (정함, 08 스키마에 더한 칸)**: 지금 rev를 쓴 세션이고, 관리자가 고치면 `'admin'`이 된다. 08의 "응답이 사라진 뒤 같은 세션이 다시 보냄"은 12번, "관리자가 되돌림"은 13번이다. 12번은 앱이 save를 한 번에 하나만 보낸다는 전제(10장)에서만 안전하다. 그래야 늦게 온 요청이 늘 더 새 상태다.
- **저장**: `UPDATE trainers SET walk=?, rev=?, app=?, writer=?, updated_at=? WHERE key=?`를 하고 hourly와 daily 사본을 남긴다(5장). **`app`은 Swift에서 고른다**: `newApp = old.map { verCmp($0, r.app) >= 0 ? $0 : r.app } ?? r.app`. SQL `max()`는 인자에 NULL이 끼면 NULL이고(create 직후 app은 NULL) 문자열로 비교하므로(`max('1.9','1.13')='1.9'`) 쓰면 426이 영영 걸리지 않는다. 버전 비교(`verCmp`)는 숫자로 한다: `2.10 > 2.9`, `2.0 == 2.0.0`.
- **history conflict**는 5장 "conflict 쓰기"대로 한다. stale(13번)도 남긴다 (정함). 복원 뒤에 잃은 걸음을 관리자가 살릴 수 있게 하려는 것이다.

**POST /v1/legacy** `{"id":"민","device":"…","walk":"<state.pre-server.json 내용 그대로>"}` → 200 `{"stored":true}`(처음 올림), 200 `{"stored":false}`((key, device)가 이미 있거나 그 key의 legacy가 이미 4행. 덮어쓰지 않는다), 404 no_trainer.
- 검사는 크기(2,000,000바이트)와 "JSON 객체인가"(`JSONSerialization`)만 한다 (정함). 옛 세이브를 `Walk` 디코드로 까다롭게 보면 버려질 수 있어서 일부러 느슨하게 둔다. 세션은 필요 없다(08 그대로). 읽는 API는 아직 없고, 관리 CLI로만 본다.

**코드 모양 (요약)**
```swift
struct LoginReq: Codable { let id, device, device_name: String; let app: String?; let force: Bool? }; struct CreateReq: Codable { let id, device, device_name: String }
struct SaveReq: Codable { let id, session, app: String; let base: Int; let walk: String };        struct LegacyReq: Codable { let id, device, walk: String }
struct Reply: Sendable { let status: Int; let body: Data }        // init(_ status: Int, _ value: some Encodable)
actor SaveDB {                                                    // 판정 7~13번. HTTP 없이 테스트할 수 있다
    init(path: String, create: Bool = false) throws               // create는 init 명령과 테스트만. 아니면 파일이 없을 때 throw
    static func precheck(_ r: SaveReq) -> Reply?                  // 판정 3~6번 (DB 없음, actor 밖에서 부른다)
    func login(_ r: LoginReq, now: Int) -> Reply; func create(_ r: CreateReq, now: Int) -> Reply
    func save(_ r: SaveReq, now: Int) -> Reply;   func legacy(_ r: LegacyReq, now: Int) -> Reply
    func prune(now: Int)                                          // 관리 명령도 이 actor의 메서드로 둔다
}
// serve: let router = Router(); router.addMiddleware { LogRequestsMiddleware(.info) }
//   POST 라우트 공통: X-App-Key 확인 → var req = req; let buf = try await req.collectBody(upTo: 4 << 20)
//     try?로 묶지 않는다. 4 MiB 초과 오류만 413, 그 밖의 읽기 오류는 400. 오류 형은 HB 버전에 따라 HTTPError(.contentTooLarge)나 NIOTooManyBytesError다(test.sh의 5MB 줄이 확인한다)
//   → JSONDecoder로 *Req, 실패하면 400 → save면 SaveDB.precheck(r) → await db.xxx(r, now:) → Response(status: .init(code: reply.status), headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(bytes: reply.body)))
// Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: port))); Task { while true { await db.prune(now: now()); try? await Task.sleep(for: .seconds(3600)) } }; try await app.runService()
```

## 5. DB 스키마와 트랜잭션

`walk`는 모든 테이블의 **맨 끝 칸**이다. SQLite는 뒤쪽 칸을 읽으려면 앞쪽 큰 TEXT의 overflow 페이지를 끝까지 따라가기 때문이다. INSERT는 칸 이름을 적어서 쓴다.
```sql
PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL; PRAGMA busy_timeout = 5000;   -- 연결할 때마다
PRAGMA max_page_count = 2621440;   -- 연결할 때마다: 4 KiB × 2621440 = 10 GiB (디스크 여유의 절반 이하로 고른다). 넘으면 SQLITE_FULL → 500
CREATE TABLE IF NOT EXISTS trainers (key TEXT PRIMARY KEY, name TEXT NOT NULL, rev INTEGER NOT NULL, app TEXT,
  session TEXT, writer TEXT, device TEXT, last_device TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, walk TEXT);
CREATE TABLE IF NOT EXISTS history (key TEXT NOT NULL, rev INTEGER NOT NULL, reason TEXT NOT NULL, at INTEGER NOT NULL, walk TEXT NOT NULL,
  PRIMARY KEY (key, rev, reason));   -- reason: hourly | daily | conflict | admin
CREATE TABLE IF NOT EXISTS legacy (key TEXT NOT NULL, device TEXT NOT NULL, at INTEGER NOT NULL, walk TEXT NOT NULL, PRIMARY KEY (key, device));
```
- **trainers 칸**: `key` = `trainerID().key`, `name` = 화면에 보일 이름, `rev` 0 = 만든 뒤 아직 저장 전, `app` = 이 ID에 저장한 앱 중 최고 버전(NULL = 아직 없음), `session` = 지금 저장 권한, `writer` = 지금 rev를 쓴 세션 또는 `'admin'`, `device` / `last_device` = 세션을 가진 PC의 임의 ID / 그 PC 이름, `updated_at` = 마지막으로 받은 저장, `walk` = 받은 텍스트 그대로(rev 0이면 NULL).
- **열기**: `serve`와 관리 명령은 `SQLITE_OPEN_READWRITE`로만 열고, 파일이 없으면 만들지 않고 exit 1 한다. `pokeserver init`만 `SQLITE_OPEN_CREATE`로 만들고 CREATE TABLE을 한다. DB_PATH가 틀려 빈 DB가 생기면 모든 앱이 404를 받고 ID를 다시 치게 되기 때문이다.
- **연결**: 서버 프로세스에는 연결이 하나만 있고 `actor SaveDB`가 쥔다. 그래서 쓰는 쪽은 늘 하나다. 관리 CLI는 다른 프로세스로 같은 파일을 열고, 순서는 WAL과 busy_timeout이 맞춘다. 서버는 행을 메모리에 캐시하지 않는다(관리자가 고친 것이 바로 보여야 한다).
- **트랜잭션**: 요청 하나가 actor 메서드 하나이고 트랜잭션 하나다(`BEGIN IMMEDIATE … COMMIT`). 오류가 나면 `ROLLBACK` 하고 500을 준다. sqlite 호출은 동기로 한다(한 번에 1ms 안팎, 50명이면 충분). 코드에 `// ponytail: one connection, one writer; a reader pool if it ever matters`를 남긴다. `synchronous = FULL`인 이유: WAL + NORMAL은 전원이 나가면 마지막 커밋(로그인 포함)을 되돌린다. 쓰기가 초당 1건 미만이라 비용이 없다.
- `SQLITE_TRANSIENT` 매크로는 Swift로 들어오지 않으므로 `unsafeBitCast(-1, to: sqlite3_destructor_type.self)`로 만든다. 세션 값은 `hex((0..<16).map { _ in UInt8.random(in: 0...255) })`(Model/Sign.swift의 `hex`)로 만든다.

**history 쌓기**: 저장을 받아들일 때 같은 트랜잭션 안에서 한다. 그 시간의 첫 rev와 그날(KST)의 첫 rev를 남긴다.
```sql
INSERT OR IGNORE INTO history (key, rev, reason, at, walk) SELECT :key, :rev, 'hourly', :now, :walk
  WHERE NOT EXISTS (SELECT 1 FROM history WHERE key = :key AND reason = 'hourly' AND at >= :now - :now % 3600);
INSERT OR IGNORE INTO history (key, rev, reason, at, walk) SELECT :key, :rev, 'daily', :now, :walk
  WHERE NOT EXISTS (SELECT 1 FROM history WHERE key = :key AND reason = 'daily' AND at >= :now - (:now + 32400) % 86400);   -- KST 하루
```
- `OR IGNORE`라서 PK가 우연히 겹쳐도 저장 전체가 500이 되지 않는다. 08의 "48시간은 매시, 90일은 하루 하나"를 정리할 때 골라내지 않고 쌓을 때부터 나눠 둔다 (정함). 그래서 정리는 DELETE 세 줄로 끝난다.

**conflict 쓰기** (9번, 13번): base는 클라이언트가 정하므로, 그 key의 conflict를 최근 10개만 남기고 넣는다(안 그러면 2MB 행이 끝없이 쌓일 수 있다).
```sql
DELETE FROM history WHERE key = :key AND reason = 'conflict'
  AND rev NOT IN (SELECT rev FROM history WHERE key = :key AND reason = 'conflict' ORDER BY at DESC LIMIT 9);
INSERT OR REPLACE INTO history (key, rev, reason, at, walk) VALUES (:key, :base, 'conflict', :now, :walk);
```

**정리 (prune)**: 서버가 켤 때와 그 뒤 1시간마다 돈다. `pokeserver prune`으로 지금 돌릴 수도 있다.
```sql
DELETE FROM history WHERE reason = 'hourly'   AND at < :now - 48*3600;
DELETE FROM history WHERE reason = 'daily'    AND at < :now - 90*86400;
DELETE FROM history WHERE reason = 'conflict' AND at < :now - 30*86400;   -- 정함: 30일
```
- admin 행은 지우지 않는다(관리자가 고치기 전 사본이라 몇 개 안 된다). 용량: 18KB × (48 + 90) × 50명 ≈ 125MB다. legacy는 `INSERT OR IGNORE`로만 쓰고 key당 4행까지다. 플레이에는 쓰지 않는다. rename 하면 key를 따라 옮기고, delete 해도 남긴다.

## 6. 운영

**사용자, 설정 파일, DB, 서비스**
```sh
sudo useradd --system --user-group --home-dir /var/lib/pokewalker --shell /usr/sbin/nologin pokewalker
sudo usermod -aG pokewalker $USER          # 관리자 계정이 백업 파일을 읽게 (rclone). 다시 로그인해야 적용된다
sudo install -d -m 750 -o pokewalker -g pokewalker /var/lib/pokewalker
sudo install -d -m 750 -o root -g pokewalker /etc/pokewalker
sudo install -m 640 -o root -g pokewalker server/ops/server.env.example /etc/pokewalker/server.env
# server.env:  APP_KEY=<사용자가 넣음>  PORT=8787  DB_PATH=/var/lib/pokewalker/pokewalker.db
server/build.sh install                                   # 처음에는 마지막 restart만 실패한다
sudo -u pokewalker /usr/local/bin/pokeserver init         # DB를 만드는 유일한 명령
sudo cp server/ops/pokewalker*.service server/ops/pokewalker-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now pokewalker pokewalker-backup.timer
```
`serve`는 APP_KEY가 비어 있거나 DB 파일이 없으면 시작하지 않는다(exit 1). 바인드는 늘 `127.0.0.1`이다.
```ini
# ops/pokewalker.service
[Service]
User=pokewalker
EnvironmentFile=/etc/pokewalker/server.env
Environment=TZ=Asia/Seoul
ExecStart=/usr/local/bin/pokeserver serve
Restart=always
RestartSec=2
StateDirectory=pokewalker
StateDirectoryMode=0750
UMask=0027
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
[Install]
WantedBy=multi-user.target
```
- `ops/pokewalker-backup.service`: `[Service]`에 `Type=oneshot`, `User=pokewalker`, `UMask=0027`, `ExecStart=/usr/local/bin/pokewalker-backup`. `ops/pokewalker-backup.timer`: `[Timer]`에 `OnCalendar=*-*-* 04:30`(시스템 시간대가 Asia/Seoul이라 KST), `Persistent=true`, `[Install]`에 `WantedBy=timers.target`.
```sh
#!/bin/sh
# ops/backup.sh → /usr/local/bin/pokewalker-backup: a consistent copy, kept only if it checks ok, gzipped, 14 days here
set -e; D=/var/lib/pokewalker/pokewalker.db; B=/var/lib/pokewalker/backup; F=$B/pw-$(date +%F).db
[ -f $D ]                                  # sqlite3 would create an empty one
mkdir -p $B; rm -f $F
sqlite3 $D ".backup $F"
[ "$(sqlite3 $F 'PRAGMA integrity_check')" = ok ]
gzip -f $F
find $B -name 'pw-*.db.gz' -mtime +14 -delete
```

**백업을 밖으로 (필수)**: 모든 사람의 원본이 디스크 하나에 있다. 실패한 백업은 `systemctl --failed`에 남는다.
- 미니 PC에는 브라우저가 없다. Mac에서 `rclone authorize "drive"`를 돌려 나온 토큰을 미니 PC의 `rclone config`(리모트 이름 `gmail`, 종류 drive)에 붙인다. 반드시 **개인** Google 계정이다(회사 드라이브가 아님).
- 관리자 계정 crontab(휴지통도 용량을 먹으므로 `--drive-use-trash=false`): `0 5 * * * rclone copy /var/lib/pokewalker/backup gmail:pokewalker-backup --max-age 48h && rclone delete gmail:pokewalker-backup --min-age 30d --drive-use-trash=false`
- **복원 순서**: 순서를 지킨다. 낡은 WAL이 남아 있으면 되살린 DB에 덧씌워져 망가진다.
  ```sh
  sudo systemctl stop pokewalker
  sudo rm -f /var/lib/pokewalker/pokewalker.db-wal /var/lib/pokewalker/pokewalker.db-shm
  sudo -u pokewalker sh -c 'gunzip -c /var/lib/pokewalker/backup/pw-2026-10-01.db.gz > /var/lib/pokewalker/pokewalker.db'
  sudo systemctl start pokewalker
  ```
- **복원 뒤**: 세션이 백업과 같은 PC와 앱을 다시 켠 PC(10장 켤 때 ④)는 11번(base > rev)으로 자기 상태를 다시 올린다. 백업 뒤에 로그인해서 켜져 있던 PC는 409 replaced를 받고, 그 PC의 마지막 상태는 history('conflict')에 남는다. 복원한 날에는 `pw show <id>`로 conflict 행을 보고 가장 새 것을 `pw rollback <id> <rev> conflict`로 올린다.

**Cloudflare Tunnel** (터널 이름 `pokewalker`)
```sh
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install -y cloudflared
cloudflared tunnel login                         # (사용자) 브라우저를 기다리며 멈추므로 사용자 터미널에서 돌린다 → ~/.cloudflared/cert.pem
cloudflared tunnel create pokewalker             # → ~/.cloudflared/<UUID>.json
cloudflared tunnel route dns pokewalker api.<domain>   # CNAME api → <UUID>.cfargotunnel.com (프록시)
sudo install -d /etc/cloudflared && sudo cp ~/.cloudflared/<UUID>.json /etc/cloudflared/
sudo cp server/ops/cloudflared.yml.example /etc/cloudflared/config.yml   # <UUID>, <domain>을 채운다
cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate
sudo cloudflared --config /etc/cloudflared/config.yml service install && sudo systemctl enable --now cloudflared
chmod 600 ~/.cloudflared/cert.pem                # 이 파일로 그 도메인의 터널과 DNS를 바꿀 수 있다
```
- `ops/cloudflared.yml.example`: `tunnel: <UUID>`, `credentials-file: /etc/cloudflared/<UUID>.json`, `ingress:`는 `- hostname: api.<domain>` + `service: http://127.0.0.1:8787` 한 항목과 마지막 `- service: http_status:404`.
- `api` 레코드가 이미 있으면 `route dns`가 실패한다. 그 레코드를 지우거나 다른 이름을 쓴다. Universal SSL은 한 단계 서브도메인만 덮는다(`api.<domain>`은 되고 `a.b.<domain>`은 안 된다). apt로 깐 cloudflared는 unattended-upgrades가 올리지 않는다. 한 달에 한 번 `sudo apt-get install --only-upgrade cloudflared`.

**Cloudflare 설정과 그 밖**
- (선택) Rate limit: Security → WAF → Rate limiting rules(무료는 1개). `http.host eq "api.<domain>"`, 같은 IP에서 10초에 100회를 넘으면 10초 차단. 회사는 NAT로 IP 하나로 나오므로 낮게 잡지 않는다.
- Bot Fight Mode와 Under Attack 모드는 이 존에서 켜지 않는다. 앱은 JS 챌린지를 풀지 못한다. 앱이 403 챌린지(HTML)를 받으면 Rules → Configuration Rules에서 `api.<domain>`의 Browser Integrity Check를 끈다.
- 로그: `journalctl -u pokewalker -f`. 요청마다 한 줄(LogRequestsMiddleware), replaced·stale·426은 key와 함께 info로 남긴다. 터널은 `journalctl -u cloudflared`.
- 업데이트: `cd ~/pokewalker && git switch main && git pull && server/build.sh install`. 서버는 1~2초 끊기고, 그동안 실패한 저장은 앱이 다음 주기에 다시 올린다.
- 감시: UptimeRobot 무료 HTTP 모니터를 `https://api.<domain>/v1/ping`에 5분 간격으로 걸고 메일로 알림을 받는다. 손으로는 `systemctl status pokewalker cloudflared`, `systemctl --failed`, `du -sh /var/lib/pokewalker`. 정전과 인터넷 끊김에는 앱이 오프라인으로 계속 돌다가 연결되면 올린다(08 결정 1). BIOS의 "전원이 돌아오면 켜기"를 권장한다(사용자가 설정).

## 7. 관리자 도구 (같은 바이너리의 하위 명령)

먼저 `alias pw='sudo -u pokewalker /usr/local/bin/pokeserver'`를 만든다. 스크립트에서는 alias가 펼쳐지지 않으므로 전체 명령을 쓴다.
- **반드시 pokewalker 사용자로 실행한다.** root로 열면 -wal/-shm 파일이 root 소유가 되어 서버가 쓰지 못한다. 시각은 SQL `datetime(x,'unixepoch','localtime')`로 보여 준다(시스템 시간대 기준).
- 모든 하위 명령은 `--db <path>`를 받는다. 우선순위는 `--db`, `DB_PATH`, `/var/lib/pokewalker/pokewalker.db` 순이다. `sudo -u`는 환경 변수를 지우므로(env_reset) 다른 DB는 늘 `--db`로 가리킨다.

| 명령 | 하는 일 |
|---|---|
| `pw init` | DB 파일과 표를 만든다. 이미 있으면 그대로 둔다 |
| `pw list` | name, key, rev, day, today, total, watts, 마지막 저장, last_device. today 내림차순. today는 `json_extract(walk,'$.day') = date('now','localtime')`일 때만, 아니면 0 |
| `pw show <id>` | 한 명 요약, history 목록(rev, reason, 시각, total, watts), legacy 목록 |
| `pw walk <id> [<rev> <reason>]` | 지금의 walk(또는 history 사본) JSON을 stdout으로 (`\| jq`) |
| `pw rollback <id> <rev> <reason>` | 그 history 사본을 새 rev로 올린다 |
| `pw set <id> '<json-path>' '<json-value>'` | 예: `pw set 민 '$.watts' 0`. SQLite `json_set(walk, ?, json(?))` |
| `pw rename <id> <새 id>` | key가 바뀌면 trainers와 history의 key를 옮기고, legacy는 `UPDATE OR IGNORE`로 옮긴다(PK가 겹치는 옛 행은 옛 key에 둔다). session과 device를 NULL로 만든다. 새 key가 이미 있으면 거절한다. 대소문자만 다르면 name만 바꾼다 |
| `pw delete <id> --yes` | walk를 `/var/lib/pokewalker/deleted-<key>-<unix>.json`으로 남긴 뒤 trainers와 history 행을 지운다. legacy는 남긴다 |
| `pw legacy [<id>]` | legacy 행: key, device, 시각, total, watts |
| `pw prune` | 5장 정리를 지금 돌린다 |
| `pw sample` | 08 §5의 새 세이브 JSON: `Walk()`에 `audited = 2`, `ballsRefunded = true`(기기 칸은 빈 채. counterKind는 앱이 자기 값을 쓴다). 테스트용이고, `pw set <id> '$' "$(pw sample)"`로 초기화에도 쓴다 |

- **rollback과 set**은 한 트랜잭션이다. ① 지금의 walk를 `history(key, rev, 'admin', now, walk)`에 남긴다. ② walk를 바꾸고 `rev = rev + 1`, `writer = 'admin'`으로 한다(`updated_at`은 그대로). ③ 결과가 `Walk`로 디코드되지 않으면 ROLLBACK 하고 실패를 출력한다. 그러면 앱은 다음 저장에서 409 stale을 받고 서버 것을 받는다(08 §6).
- 비상시 sqlite3 CLI로 직접 고칠 수도 있다(`sudo -u pokewalker sqlite3 /var/lib/pokewalker/pokewalker.db`). walk를 직접 바꿀 때는 반드시 `rev = rev + 1, writer = 'admin'`도 같이 한다. 개발 빌드가 높은 버전 번호로 저장해서 다른 PC가 426을 받으면 `UPDATE trainers SET app = NULL WHERE key = '…';`로 푼다.

## 8. 테스트

**단위 테스트** (`server/build.sh test`): `SaveDB(path: 임시파일, create: true)`로 열고 `now`를 직접 넘긴다. save는 `SaveDB.precheck(r) ?? db.save(r, now:)`로 부른다.
1. trainerID: "Min"과 "min"은 같은 key. NFD "민"(U+1106 U+1175 U+11AB)의 key는 U+BBFC. " 민수 "는 앞뒤 공백을 잘라 받는다. "a", 13자, "민 수", "ㅋㅋ", "min!", 전각 "ＡＢ"는 거절한다.
2. 버전 비교: `2.10 > 2.9`, `2.0 == 2.0.0`, `"2.x"`는 nil.
3. 판정표 13줄을 한 줄씩 확인한다.
   - create → save base 0 → rev 1. 같은 요청을 다시 보냄 → rev 2 (12번).
   - B가 force로 로그인 → A의 저장은 replaced이고 conflict 행이 생긴다. B가 base 2 → rev 3.
   - 관리자 rollback → rev 4, writer admin → B가 base 3 → stale(rev 4, walk)과 conflict 행. B가 base 4 → rev 5.
   - 11번: rollback 직후(writer admin) B가 base 9 → rev 10. rev 0(walk NULL)인 새 ID에 base 3 → rev 4. 8번: 새 ID에 create(app NULL) → 2.1로 저장 → 2.0으로 저장 → 426(need 2.1), login도 2.0이면 426.
   - walk `"{}"` → bad_walk. version 2 → bad_walk. 2,000,000바이트 초과 → 413. conflict를 12번 만들면 그 key의 conflict는 10행.
4. busy: A가 저장한 지 299초 → busy이고 session은 그대로, 301초 → 로그인된다. force → 바로 로그인된다. 같은 device → busy가 아니다. 없는 ID → `exists:false`.
5. 바이트 보존: 보낸 walk, login 응답의 walk, DB 값이 같아야 한다. **`Array(a.utf8) == Array(b.utf8)`로 비교한다**(Swift `String ==`는 NFD와 NFC를 같다고 본다). NFD 글자, 공백, 키 순서가 든 텍스트로 한다.
6. history와 정리: 같은 시간에 두 번 저장 → hourly 1행, 시간이 넘어가면 2행. daily는 KST 0시(UTC 15시)에 넘어간다. `prune(now + 49h)` → hourly는 0행, daily는 남는다. 31일 지난 conflict는 지워지고 admin 행은 남는다.
7. legacy: 같은 device로 두 번째 → `stored:false`이고 내용은 그대로. 다른 device → 2행. 다섯 번째 device → `stored:false`. 없는 ID → 404.
8. 열기: `SaveDB(path: 없는파일)`은 throw 하고 파일을 만들지 않는다.

**curl 전체 흐름** (`server/test.sh`)
- `BASE`가 없으면 임시 DB에 `pokeserver init --db`를 하고 포트 8799로 서버를 띄운다(`APP_KEY=test`, trap으로 종료).
- `BASE`와 `KEY`가 있으면 그 주소로 보낸다. 미니 PC에서 돌린다(4번 rollback과 마지막 delete가 같은 DB를 쓴다). ID는 `zz` + 숫자 6자리이고, 끝나면 `sudo -u pokewalker /usr/local/bin/pokeserver delete <id> --yes`로 지운다. sudo를 쓸 수 없으면 그 명령을 출력하고 사용자에게 맡긴다.
- walk는 `jq -n --arg w "$(pokeserver sample)" '{…, walk: $w}'`로 만든다. 저장의 app은 `"2.1"`이다.
1. ping → 200. 키 없이 login → 401. (로컬 모드) 없는 `--db`로 serve → exit 1. login → `exists:false`. create → 200 rev 0. 한 번 더 → 409 exists.
2. A가 base 0 → rev 1. 같은 요청 다시 → rev 2. B login → busy. B login force → session2. A 저장 → 409 replaced. B가 base 2 → rev 3.
3. app 2.0으로 저장 → 426. 3MB walk → 413. 5MB 본문 → 413. `"{}"` → 400.
4. `pokeserver rollback` → B가 base 3 → stale. B가 base 4 → 200. legacy 두 번 → `stored` true, false.

**앱 쪽에서 나중에 할 시험** (앱 세션의 몫)
- Mac에서 `curl https://api.<domain>/v1/ping`, 회사망 Windows에서 `curl.exe`로 같은 확인(VPN 켠 것과 끈 것 둘 다). 08의 P0이다. 403 챌린지가 보이면 6장 Browser Integrity Check. Windows CI에 ping GET 하나를 넣는다(키가 필요 없어 CI에 비밀이 없다). `zz…` 테스트 ID로 Mac → Windows 이어하기, 오프라인, 충돌, 응답 잃음(10장 켤 때 ②)을 시험한다. 관리자는 `pw show zz…`로 rev와 history를 보면서 확인하고, 끝나면 delete 한다.

## 9. 단계별 체크리스트 (서버 Claude)

| # | 할 일 | 끝났다는 기준 |
|---|---|---|
| 1 | `sudo timedatectl set-timezone Asia/Seoul`, swiftly로 Swift 6.1.2, apt 패키지 | `timedatectl`이 Asia/Seoul, `swift --version`이 6.1.2, `sqlite3 --version`이 나옴 |
| 2 | `server-home` 브랜치, server/ 뼈대, build.sh, CSQLite, `sample` 명령만 | `server/build.sh && server/.build/release/pokeserver sample \| jq .version`이 1 (Game을 Linux에서 처음 컴파일한다. 실패하면 2장대로 보고) |
| 3 | `Sources/Model/TrainerID.swift`(origin/main에 있으면 그것), 테스트 1·2 | `build.sh test` 통과 |
| 4 | SaveDB(스키마, init, login/create/save/legacy, history, prune), 테스트 3~8 | 통과 |
| 5 | Hummingbird 라우트, 키 검사, 413, 로그, prune 루프 | 로컬 `curl 127.0.0.1:8787/v1/ping`이 200 |
| 6 | 관리 CLI 전부, test.sh | 임시 DB(`--db`)에서 7장 명령이 모두 돎. test.sh 로컬 모드 전부 OK |
| 7 | 시스템 사용자, env, `pokeserver init`, 서비스 두 개, 타이머 | `systemctl is-active pokewalker`. 재부팅 뒤에도 ping이 됨 |
| 8 | cloudflared (login은 사용자가 함) | 휴대폰 LTE에서 `https://api.<domain>/v1/ping`이 200 |
| 9 | 백업 한 번(`systemctl start pokewalker-backup`). 복원 연습: `gunzip -c`로 `/var/lib/pokewalker/restore-test.db`를 만들고 `pw --db /var/lib/pokewalker/restore-test.db list` | `backup/pw-오늘.db.gz`가 생김. 사본의 `list`가 `pw list`와 같음(백업 뒤 저장만큼만 다름). 사본은 지운다 |
| 10 | rclone 리모트(사용자와 함께), crontab | 다음 날 `rclone ls gmail:pokewalker-backup`에 파일이 있음 |
| 11 | `BASE=https://api.<domain> KEY=… server/test.sh` | 전부 OK, zz ID가 지워짐 |
| 12 | server/README.md, 루트 Package.swift exclude, .gitignore, 커밋 → `server-home` push → main으로 PR(`gh pr create`) | 사용자에게 주소, PR, 결과, 남은 손 작업을 보고. APP_KEY 값은 커밋하지 않는다 |

**사용자가 손으로 할 일** (sudo 비밀번호를 직접 칠 수 없으면, 준비한 sudo 명령을 사용자에게 붙여 넣게 하고 결과를 확인한 뒤 다음 단계로 간다)
1. 이 문서와 `docs/plans/08-server-save.md`를 커밋하고 push 한다. **08은 지금 커밋되지 않은 상태다.** 08 맨 위에 "호스팅은 08b(미니 PC, Swift, Tunnel)로 바뀌었다. 서버 부분은 08b가 우선이다" 한 줄을 넣는다(앱 세션은 08을 읽는다). 미니 PC에서 이 비공개 저장소에 접근할 수 있게 한다(`gh auth login` 또는 SSH 키, push 권한 포함).
2. 도메인 이름을 알려 준다(`api`가 이미 쓰이고 있으면 다른 서브도메인을 고른다). `cloudflared tunnel login`을 자기 터미널에서 돌리고, 출력된 URL을 브라우저로 열어 도메인을 고른다.
3. `openssl rand -hex 16`으로 APP_KEY를 만들어 `/etc/pokewalker/server.env`에 넣는다. 같은 값을 앱 세션에 전한다.
4. Mac에서 `rclone authorize "drive"`(개인 계정)로 토큰을 만들어 미니 PC의 `rclone config`에 붙인다. 필요할 때 sudo 명령을 붙여 넣는다. 선택: WAF rate limit, UptimeRobot, BIOS 자동 켜기.
5. 회사 Windows PC에서 `curl.exe https://api.<domain>/v1/ping`이 200인지 확인한다.

## 10. 앱 쪽에 알려 줄 것 (Core/Cloud.swift 작성자에게)

- **주소와 키**: `https://api.<domain>`과 사용자에게 받은 APP_KEY를 `Cloud.swift`의 상수로 둔다. 키는 비밀이 아니다(08 §2-1). 헤더는 `Content-Type: application/json`, `X-App-Key`, `User-Agent: PokeWalker/<버전> (mac|windows)`.
- **walk는 JSON 문자열로 보낸다.** 보낼 때 `String(data: JSONEncoder(sortedKeys).encode(walk.shared), encoding: .utf8)`. login과 stale 응답의 `walk`는 문자열이거나 null이고, UTF-8로 바꿔 `Walk`로 디코드한다.
- **login과 create**에는 `device_name`을 꼭 넣는다(빠지면 400). login에는 `app`도 보낸다. `busy:true`가 오면 `last_device`와 `updated_at`(서버 시계라 "n분 전"은 대략)으로 묻고, 예면 `force:true`로 다시 보낸다. **여기서 계속**도 `force:true`다. create가 409 exists면(응답을 잃고 다시 보낸 경우 포함) login으로 넘어간다.
- **session은 설정에 저장한다.** 온라인으로 켤 때는 login(force 없이)을 한다. 오프라인으로 켰다가 연결되면 login 없이 저장된 세션으로 save 한다. 그래야 08 §2-1처럼 replaced를 받는다. 다시 login 하면 오히려 다른 PC의 세션을 빼앗는다.
- **save는 한 번에 하나만 보낸다.** 앞 요청이 응답, 오류, 타임아웃 중 하나로 끝나야 다음 save를 만든다. 2분 주기, `soon()`, flush가 겹치면 끝난 뒤에 한 번만 더 보낸다. 서버 12번은 이 규칙을 전제로 한다. 읽기 API는 없다: 08의 "깰 때 받기"는 바뀐 게 있을 때 save만 하는 것으로 대신하고, 서버가 앞서면 stale로 알게 된다.
- **켤 때 login 응답 처리** (08 §4 "켤 때 캐시 처리"를 구체화한다)
  - ① `cloudRev` 옆에 기기 칸 `sentHash`를 둔다: 마지막으로 보낸 walk 텍스트의 `hex(sha256(Array(text.utf8)))`(Model/Sign.swift). `shared`가 비운다.
  - ② login의 walk 해시가 sentHash와 같으면 내 저장의 응답만 잃은 것이다. `cloudRev = rev`, `cloudTotal` = 그 walk의 total로 하고 adopt 하지 않는다(adopt 하면 이미 들어간 걸음을 한 번 더 걷는다). 서버가 바이트를 그대로 돌려주므로 정확히 맞는다.
  - ③ 아니고 rev > cloudRev면 adopt 한다.
  - ④ rev == cloudRev면 바뀐 게 있을 때 base = rev로 올린다(서버 10번). rev < cloudRev(서버가 기록을 잃음)면 바뀐 게 없어도 base = cloudRev로 올린다(서버 11번).

| 응답 | 앱이 할 일 |
|---|---|
| save 200 | `cloudRev = rev`, `cloudTotal` = 보낸 walk의 total |
| 409 replaced | 걸음과 조작을 멈추고 **여기서 계속** |
| 409 stale | `adopt(walk, rev)` |
| 426 | "새 버전이 필요해요" (login에서도 온다) |
| 404 no_trainer | 관리자가 지웠거나 바꿨다. state.json은 지우지 않고 `state.orphan-<unix>.json`으로 남긴 뒤, 저장한 ID를 지우고 ID 입력창을 연다 |
| 400, 401, 413 | 버그나 빌드 문제(401은 키 불일치)다. 로그를 남기고 다음 주기까지 다시 보내지 않는다 |
| 5xx, 네트워크 오류, 그 밖의 상태, JSON이 아닌 본문 | 오프라인으로 보고 2분에서 30분까지 간격을 늘려 다시 시도한다. Cloudflare가 직접 내는 530/1033(터널 끊김), 502(서버 재시작 중), 403(챌린지)은 본문이 HTML이다 |

- **첫 저장**: create 직후, 그리고 login의 `walk`가 null이면 base 0으로 올린다. **legacy**: `state.pre-server.json` 내용을 그대로 walk 문자열로 보낸다. `stored`가 true든 false든 성공이므로 `legacyUploaded`를 표시한다.
- **ID 검사**: 입력창 검사와 설정 저장에 `trainerID()`를 쓴다(`Sources/Model/TrainerID.swift`, 서버와 같은 파일). 루트 `Package.swift`의 exclude는 서버 쪽이 고치므로 앱 쪽은 건드리지 않는다. **공유 폴더 규칙**: 서버가 Model/Data/Battle을 복사해서 Linux에서 컴파일한다. 이 폴더에는 Foundation만 쓴다(AppKit, WinSDK, Darwin 전용 API, `@MainActor` 상태는 넣지 않는다). `Walk`의 칸 이름이나 형을 바꾸거나 칸을 지울 때는 서버를 먼저 다시 빌드한다(`server/build.sh install`). Optional 칸을 더하는 것은 서버를 바꾸지 않아도 된다(모르는 키는 디코드에서 무시되고, 텍스트는 그대로 저장된다).

## 검토에서 바뀐 것

- `app` 최고 버전은 SQL `max()` 대신 Swift `verCmp`로 고른다(NULL과 문자열 비교 때문에 426이 걸리지 않던 문제). 버전 예시는 2.0/2.1로 바꿨다.
- 판정표를 13줄로 나눴다. `base > rev`(서버가 기록을 잃음)는 writer와 상관없이 받고, 같은 세션의 재전송은 `base < rev`일 때만 받는다. 앱 쪽에는 `sentHash`로 응답 잃음을 알아보는 켤 때 규칙(①~④)과 "save는 한 번에 하나"를 더했다.
- 내구성과 디스크: `synchronous = FULL`, `max_page_count` 10 GiB, conflict는 key당 10개, legacy는 key당 4행, `walk`는 모든 테이블의 맨 끝 칸.
- 빈 DB를 저절로 만들지 않는다(`pokeserver init`만 만든다). 404를 받은 앱은 state.json을 orphan으로 남긴다. 시스템 시간대를 Asia/Seoul로 두고 daily는 KST 하루로 쌓는다. 관리 명령은 `--db`를 받는다(sudo가 DB_PATH를 지우므로).
- 백업은 필수가 됐다: rclone 설치와 헤드리스 인증, integrity_check 뒤 gzip, Drive 30일 정리. 복원 뒤 동작 설명을 바로잡고 conflict 행으로 살리는 절차를 더했다.
- 문서 경로(08b), 브랜치(`server-home` → PR → main), TrainerID.swift 주인, Linux 컴파일이 아직 확인되지 않았다는 점과 실패할 때의 보고 규칙, 서버 파일 이름(`Server*.swift`), Game 계산을 부르지 않는 이유를 적었다.
- Hummingbird 스케치(`addMiddleware`, 413 처리, precheck를 actor 밖으로), Cloudflare가 직접 내는 응답, cloudflared 운영 잔손질, 테스트(UTF-8 바이트 비교, sample 칸, sudo 없는 정리)를 고쳤다.