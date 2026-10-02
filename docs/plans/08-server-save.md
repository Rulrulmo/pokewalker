# 08 서버 세이브 (멀티의 바탕)

> **호스팅이 바뀌었다 (2026-10-02):** Cloudflare Workers + D1 대신 **집 미니 PC(Ubuntu)의 Swift + SQLite 서버를 Cloudflare Tunnel로** 연다 → [08b 서버 구현 지시서](08b-server-home.md). 서버 쪽(wrangler, `index.ts`, D1 `batch()`, Cron, 무료 한도, `workers.dev`)은 **08b가 우선**이다. 앱 쪽 계약(API, 판정, 켤 때 규칙)도 08b §4·§10을 따른다.
>
> 2026-10-02 · **확정**. 1차 초안(세 설계를 채점해 합친 안)을 사용자 결정으로 다시 썼다. 결정은 0장과 맨 아래 "확정한 결정"에 있다. 다음은 P0.

## 0. 정해진 것 (사용자, 2026-10-02)

| 항목 | 결정 |
|---|---|
| 기존 세이브 | 서버를 도입할 때 **전원 한 번 초기화**한다. 지금 세이브는 PC에 백업 파일로만 남긴다 |
| 호스팅 | **개인 Cloudflare 계정** (Workers + D1) |
| 로그인 | **ID만** 쓴다. 비밀번호와 OAuth는 없다. ID를 아는 사람은 누구나 그 세이브로 들어올 수 있고, 그래도 괜찮다 |
| 연결 | **필수**다. 세이브 원본은 서버에 있다 |
| 위반 처리 | **지금 클라이언트에 있는 것만 유지한다**(StepGate, 하루 100,000, 감사, `.sig`). 서버는 검사하지 않는다. 필요하면 관리자가 직접 조치한다 |
| 서버에 저장할 것 | 걸음, 잡은 포켓몬, 도구, W, BP, 도감, 알, 타워 기록 등 **게임 상태 전부**(`Walk` 전체) |
| 저장 시점 | **2분마다**, 그리고 **특정 동작 직후**(배틀, 포획 등) |
| 오프라인 | 한 번 로그인한 PC는 잠깐 끊겨도 계속 하고, 연결되면 올린다 |
| ID 규칙 | 한글·영문·숫자·`_` 2~12자, 대소문자 구분 없음 |
| 중복 로그인 | 나중에 로그인한 PC가 가져간다. 먼저 있던 PC는 걸음 세기와 조작을 멈추고 **여기서 계속** 버튼만 띄운다(2-1) |
| 세션 만료 | 없음. 다른 PC가 가져갈 때만 끝난다 |
| PC 설정 | PC마다 따로 둔다(기기 색, 크기, 화면, 배틀 속도, 알림) |
| 지금 세이브 | 서버에 **옛 기록**으로만 올린다(플레이에는 쓰지 않음). PC에도 백업 파일을 남긴다 |

## 1. 한눈에

```
 Mac / Windows 앱
 +--------------------------------------------------------------+
 | 첫 실행: "트레이너 ID" 입력창 → 있으면 불러오기 / 없으면 새로 시작   |
 | Walker.tick (10Hz) ─ Cloud.tick: 2분마다 · 동작 직후 3초 안에 올림  |
 | state.json = 서버 사본의 캐시 (.sig로 손댄 캐시는 버림)              |
 +------------------------------│-------------------------------+
        HTTPS  X-App-Key   POST /v1/login · /v1/create · /v1/save
                                ▼
 +------ Cloudflare Worker (TS 약 150줄) --------------------------+
 | rev 확인 → 저장(rev+1). 검사는 없고 크기와 형식만 본다              |
 +------------------------------│-------------------------------+
                                ▼
 D1(SQLite): trainers(ID · rev · 세이브 JSON) · history(복구용 사본)
 관리: wrangler d1 execute 로 SQL 몇 줄 (롤백 · 삭제 · 값 고치기)
```

- 서버는 **창고**다. 받은 세이브를 판단하지 않고 그대로 둔다. 치트 판단은 지금처럼 앱이 하고, 넘어온 것은 관리자가 기록(history)을 보고 처리한다.
- `rev`(정수 하나) 덕분에 PC 두 대가 같은 ID를 쓸 때 서로의 기록을 몰래 덮어쓰지 않는다.

## 2. 로그인: ID만

**ID 규칙**: 2~12자, 한글·영문·숫자·`_`.
- 비교는 NFC로 정규화하고 영문 소문자로 바꾼 키(`key`)로 한다. Mac은 한글을 NFD로 넘길 때가 있다(드라이브 파일 이름 사건과 같은 원인).
- 화면에는 입력한 그대로(`name`) 보여 준다.

**흐름**
1. 2.0을 처음 켜면 네이티브 입력창 "트레이너 ID를 입력해 주세요"가 뜬다.
   - Mac: `NSAlert`에 텍스트 칸을 붙인다.
   - Windows: EDIT 칸과 확인·취소 버튼이 있는 작은 창이다. 한글 IME가 그대로 된다.
2. `POST /v1/login {id}`를 보낸다.
   - **있는 ID**: `{rev, walk}`를 받아 그 세이브로 시작한다.
   - **없는 ID**: "새 트레이너 '민'으로 시작할까요?"(`Host.confirm`)를 묻는다. 예를 고르면 `POST /v1/create`를 보내고, 새 세이브(피카츄 Lv.5)를 rev 1로 올린다. 오타로 계정이 새로 생기지 않게 한 번 묻는다.
3. ID는 PC 설정(`settings` 키 `trainerID`)에 저장한다. 다음 실행부터는 묻지 않고 바로 불러온다.
4. 취소하면 LCD에 "로그인이 필요해요"가 뜨고, 패널의 **ID 입력** 버튼으로 다시 연다. 게임 화면은 열리지 않는다.
5. 우클릭 메뉴에 `트레이너: 민 · 1분 전 저장`, `지금 저장`, `ID 바꾸기…`를 넣는다.
   - ID를 바꿀 때는 지금 세이브를 먼저 올리고 나서 바꾼다.
6. 트레이너 카드 1쪽에 ID를 보여 준다. 나중에 랭킹이나 교환에서 이름으로 쓴다.

### 2-1. 중복 로그인과 세션

ID만으로 로그인하므로 세션은 **"누가 들어올 수 있나"가 아니라 "지금 어느 PC가 저장할 권한을 갖나"**를 정한다.

- **세션** = 로그인할 때 서버가 내주는 임의 문자열 하나다. 서버는 `trainers.session`에 한 개만 가진다. 저장(`/v1/save`)은 그 세션을 가진 PC만 할 수 있다.
- **다른 PC에서 같은 ID로 로그인하면** (추천안, 남은 결정 3)
  1. 로그인 응답에 "다른 PC가 n분 전까지 쓰고 있었다"(`last_device`, `updated_at`)가 같이 온다. 5분 안이면 이렇게 묻는다: "다른 PC(KHMIN-MAC)에서 3분 전까지 하고 있었어요. 여기로 가져올까요?"
  2. **예**를 고르면 새 세션이 발급되고 이전 세션은 끝난다. 이 PC는 서버의 최신 세이브를 받아 이어서 한다.
  3. **먼저 있던 PC**는 다음 저장(최대 2분, 동작 직후면 3초 안) 때 `409 {reason: "replaced"}`를 받는다.
     - LCD에 "다른 PC에서 접속했어요"가 뜨고, 패널에 **여기서 계속** 버튼 하나가 남는다. 게임 조작은 막힌다.
     - **걸음도 세지 않는다.** 입력 카운터의 기준값만 계속 따라가고(`take()`는 돌리되 `walk()`는 하지 않음), 그 사이 입력은 버린다.
       - 이유: 계속 세면 화면의 걸음 수가 두 PC에서 달라진다. 나중에 더하면 같은 ID를 다른 사람이 쓰는 PC의 걸음까지 합쳐져서 부푼다.
     - **여기서 계속**을 누르면 다시 로그인해서 세션을 가져온다. 서버의 최신 세이브(다른 PC가 쓴 것)를 **그대로** 받고, 걸음은 더하지 않는다. 그때부터 다시 센다.
  - 결과: 걸음을 세는 PC도, 저장하는 PC도 늘 하나다. 두 PC의 숫자가 갈라지지 않는다.
  - 잃는 것: 쫓겨난 PC가 마지막 저장 뒤에 한 걸음과 행동이다(2분 이내, 동작은 보통 3초 이내). 그 사본은 `history('conflict')`에 남아서 관리자가 살릴 수 있다.
- **세션 만료** (추천안, 남은 결정 6): **두지 않는다.**
  - ID만 알면 언제든 새로 로그인할 수 있으니, 만료는 보안을 더하지 못하고 ID를 다시 치게만 만든다.
  - 세션은 다른 PC가 가져갈 때만 끝난다. ID는 PC 설정에 계속 남는다.
  - 오래 꺼 둔 PC를 다시 켜면 그냥 로그인해서 새 세션을 받는다. 그 사이에 다른 PC가 썼다면 서버 것을 받는다.
- **오프라인과 세션**: 끊긴 동안 다른 PC가 세션을 가져갔다면, 다시 연결될 때 409 replaced를 받는다. 오프라인 동안의 걸음과 행동은 **서버 기록에 지고** history에만 남는다(위와 같은 규칙).
  - 그래서 오래 오프라인으로 한 PC가 있다면 다른 PC에서 가져오기 전에 먼저 연결해서 올려야 한다. "가져올까요?" 문구에 마지막 저장 시각이 나오므로 알아챌 수 있다.

**보호 수준(감수)**
- ID를 알면 누구나 들어와서 덮어쓸 수 있다.
  - 대신 history가 있어서 관리자가 몇 분 안에 되돌릴 수 있다.
  - 나중에 필요하면 4자리 PIN 한 칸을 더한다(서버에 해시 한 줄, 입력창 하나).
- `X-App-Key` 헤더: 앱에 들어 있는 상수다. **보안이 아니라** 인터넷의 아무 스캐너가 계정을 만들지 못하게 거르는 정도다.

## 3. 서버에 저장하는 것

`Walk` 전부를 JSON 그대로 저장한다. 서버는 JSON을 다시 인코딩하지 않는다.

| 어디 | 무엇 |
|---|---|
| 서버 (원본) | `Walk` 전체: companion, caught, box, items, bag, watts, earned, total, today, day, history, days, course, courseSteps, remainder, egg, seen, owned, shinyOwned, bp, towerStreak, towerBest, towerPick, bought, learning, evolving, lastUID, weather… |
| PC에만 (올릴 때 비우고, 받을 때 이 PC 값 유지) | `counter`, `boot`, `syncedAt`, `counterKind`: 이 PC의 입력 카운터 기준값이다. 다른 PC 값을 받으면 앱이 꺼져 있던 동안의 걸음이 사라진다. 새 칸 `cloudRev`, `cloudTotal`도 여기에 둔다 |
| PC 설정 (동기화 안 함) | 기기 색 선택, 크기, 화면, 수첩 배경, 배틀 속도, 알림, 접힘 → 남은 결정 4 |

- `cloudRev`(마지막으로 서버가 받은 rev)와 `cloudTotal`(그때의 total)을 `Walk`에 Optional 칸으로 둔다. 걸음과 같은 `Store.save` 한 번에 저장되므로 둘이 어긋나지 않는다.
- 세이브 크기: 지금 약 18KB(포켓몬 210마리)다. 상자에 5,000마리가 있어도 약 400KB라서 D1 행 한도(2MB)에 한참 못 미친다.

```sql
-- server/schema.sql
CREATE TABLE trainers (key TEXT PRIMARY KEY, name TEXT, rev INTEGER, walk TEXT, app TEXT,
                       session TEXT, last_device TEXT /*이름*/, created_at INTEGER, updated_at INTEGER);
CREATE TABLE history  (key TEXT, rev INTEGER, walk TEXT, at INTEGER, reason TEXT,   -- hourly | daily | conflict | admin
                       PRIMARY KEY (key, rev, reason));
CREATE TABLE legacy   (key TEXT, device TEXT, walk TEXT, at INTEGER, PRIMARY KEY (key, device));   -- 서버 이전 전 세이브(옛 기록, 읽기 전용)
```

## 4. 저장 시점과 동기화

**올리는 때**

| 언제 | 어떻게 |
|---|---|
| 2분마다 | 지난번에 받아들여진 뒤 바뀐 게 있을 때만 보낸다(`state.shared != acked`). 걸음만 늘어도 바뀐 것이다 |
| **동작 직후** (3초 동안 모아서 한 번) | 배틀이 끝날 때(승리·포획·패배·도망·타워 승패·기권), 진화, 부화, 동료가 주워 온 것, 상점·BP 교환, 놓아주기, 함께 걷기·워커로·상자로, 기술 배우기·바꾸기, 도구 사용·특훈, 코스 이동, 타워 참가비, 레이더 10W |
| 켤 때 | 먼저 받는다(아래 "받기") |
| 잠에서 깰 때 | 받고, 바뀐 게 있으면 올린다(Mac `didWakeNotification`, Windows `PBT_APMRESUMEAUTOMATIC`) |
| 끌 때 | 최대 2초 기다리며 올린다. 실패하면 다음 실행 때 올린다 |

- 동작 직후 저장은 훅 두 곳이면 된다.
  - **버튼으로 바뀐 것:** `press` 앞뒤로 `state`를 비교한다. 다르면 `cloud.soon()`을 부른다. press 중에는 걸음이 들어오지 않으므로, 상태가 달라졌다면 곧 플레이어의 행동이다. 구매, 놓아주기, 기술, 도구가 이 한 곳에서 잡힌다.
  - **틱에서 생기는 것:** `after()`(배틀 끝·포획), `startEvolving`, 부화, 줍기에서 `cloud.soon()` 한 줄씩.
- 요청은 `URLSession.dataTask`(completion handler)로 보낸다. 응답은 `NSLock`으로 보호한 inbox에 넣고 `Walker.tick`(메인 스레드, 두 플랫폼 모두 10Hz)이 꺼낸다. Windows에서는 `Task`나 `MainActor`로 돌아오는 방식이 안 돌 수 있어서 쓰지 않는다.

**API**

```
POST /v1/login  {id, device}                  → 200 {exists:true, name, rev, walk, session, last_device, updated_at} | {exists:false}
POST /v1/create {id, device}                  → 200 {rev:0, session}   (이미 있으면 409)
POST /v1/save   {id, session, app, base, walk} → 200 {rev}              받음: rev+1
                                              → 409 {reason:"replaced"} 다른 PC가 세션을 가져감 → "다른 PC에서 접속했어요"
                                              → 409 {reason:"stale", rev, walk}  관리자가 되돌림 등으로 서버가 앞섬 → 받기
                                              → 426                    앱이 너무 옛 버전
POST /v1/legacy {id, device, walk}             → 200                    옛 기록(한 번, 이미 있으면 그대로 둠)
```

**판정** (서버, D1 `batch()` 하나로 원자 처리)
- 세션이 다르면 `409 replaced`를 주고, 보낸 것은 `history('conflict')`에 남긴다.
- 세션이 맞으면 `base`가 `rev`와 같거나 응답이 사라진 뒤 같은 세션이 다시 보낸 경우에 받는다. 세션이 PC 하나를 뜻하므로 둘 다 안전하다.
  - 예외: 관리자가 되돌려서 rev를 올렸을 때는 `409 stale`을 주고, 앱이 서버 것을 받는다.
- `device`는 PC마다 처음 한 번 만드는 임의 문자열이고(설정에 저장), 이름(`ProcessInfo.hostName`)과 함께 보낸다. "어느 PC가 쓰고 있었나"를 보여 주는 데만 쓴다.
- `app`이 그 ID에 마지막으로 쓴 앱 중 최고 버전보다 낮으면 426이다.
  - 이유: Codable은 모르는 키를 버리므로, 옛 앱이 새 칸을 조용히 지운다.
  - 앱은 "새 버전이 필요해요"를 띄운다.
- 그 시간의 첫 rev는 `history('hourly')`에 복사한다. 매일 Cron이 정리해서 48시간은 매시, 90일은 하루 하나만 남긴다.

**받기** (409, 켤 때, 깰 때: 같은 함수)

```swift
extension Walk {
    var shared: Walk { var w = self; (w.counter, w.boot, w.syncedAt, w.counterKind, w.cloudRev, w.cloudTotal) = (0, 0, nil, nil, nil, nil); return w }
    /// 서버 것을 받고, 서버에 아직 없는 이 PC의 걸음을 그 위에 다시 걷는다(EXP·W·알 걸음이 평소처럼 오른다).
    mutating func adopt(_ head: Walk, rev: Int, at now: Date) {
        let pend = max(0, total - (cloudTotal ?? total))
        var w = head; (w.counter, w.boot, w.syncedAt, w.counterKind) = (counter, boot, syncedAt, counterKind)
        w.cloudRev = rev; w.cloudTotal = head.total
        w.rollover(now); w.walk(w.roomToday(pend), at: now); self = w
    }
}
```

- **받는 시점**: `screen == .home`이고, 타워 런 중이 아니고, 배틀이 끝나 쌓아 둔 걸음(`heldSteps`)도 없을 때만 받는다. 배틀 중에는 복사본이 나중에 uid로 다시 써 넣기 때문이다. 받은 뒤에는 축하 화면이 다시 뜨지 않게 `rewarded`, `unlockedAt`, `lastSeason`을 맞춘다.
- **PC 두 대**: 2-1의 세션 규칙을 따른다. 저장하는 PC는 늘 하나다.
- **켤 때 캐시 처리**
  - 온라인이면 서버 것과 `cloudRev`를 비교한다.
    - 서버가 앞서면: 받는다.
    - 같고 캐시에 안 올린 진행이 있으면: 올린다.
  - 캐시의 `.sig`가 틀리면(앱 밖에서 고친 파일) 캐시를 버리고 서버 것을 쓴다. 그래서 세이브 파일을 고쳐도 소용이 없다.
- **오프라인**: 남은 결정 1.

**사용량** (50명, 하루 9시간 기준)
- 한 사람이 하루에 2분 주기로 약 270번, 동작 직후 약 100번을 보낸다. 합치면 하루 약 1.9만 요청이고, Workers 무료 한도는 하루 10만이다.
- D1 쓰기는 요청 한 건에 1~2행이라 하루 약 2만 행이다. 무료 한도는 하루 10만 행이다.
- 저장 공간: 18KB × history(48 + 90) × 50명 ≈ 125MB. 무료는 5GB다.
- 200명이 넘으면 한도에 다가간다. 그때는 Workers Paid(월 $5)로 올린다.
- 한도를 넘으면 쓰기가 실패한다. 앱은 로컬에 두고 간격을 늘려 다시 시도한다(아래 위험 3).

## 5. 초기화 (2.0 = 서버 버전)

1. 2.0을 처음 켜면 지금 `state.json`과 `.sig`를 `state.pre-server.json(.sig)`로 옮기고, 게임에서는 다시 읽지 않는다. 지우지는 않는다.
   - 로그인한 뒤 그 백업을 **옛 기록**으로 한 번 올린다: `POST /v1/legacy {id, device, walk}`, 서버 `legacy` 테이블.
   - 플레이에는 쓰지 않는다. 나중에 "1.x 시절 트레이너" 기념(카드 표시, 볼 기기 색 같은 꾸미기)이나 관리자 확인용이다.
   - 같은 ID에 PC마다 하나씩 남는다(Mac과 Windows 둘 다 있었다면 둘 다).
   - 올라가면 `state.pre-server.json`에 표시하고(`legacyUploaded` 설정), 다시 올리지 않는다.
   - 옛 세이브는 1.7 감사 전의 부푼 값일 수 있다. 그래서 기념 보상은 꾸미기 정도로만 쓴다.
2. ID로 로그인한다. 새 ID는 새 세이브로 시작한다. 1.7 감사, 1.10 볼 환불 같은 일회성 처리는 새 세이브에서 이미 끝난 것으로 표시한다(`audited = 2`, `ballsRefunded = true`, `counterKind = 2`).
3. 패치 내역과 가이드에 **"서버 도입으로 모두 새로 시작해요"**를 크게 적는다. 지금 키우는 펫도 처음부터 다시 시작한다.
4. 관리자 본인이 먼저 Mac에서 ID를 만들고, 같은 ID로 Windows에 들어가 이어지는지 확인한다. 그다음 팀원에게 배포한다.

## 6. 치트와 관리

- **앱 쪽(지금 그대로)**: StepGate(초당 15, 분당 600, 기계 리듬), 하루 100,000, `.sig`(이제는 캐시 보호), 1.7 감사 코드(새 세이브에서는 돌지 않음).
- **서버 쪽**: 검사는 없다. JSON이 디코드되는지, 크기가 2MB 이하인지, `version == 1`인지만 본다.
- **관리자 조치** (`server/README.md`에 SQL로 정리):
  - 누가 얼마나 걸었나: `SELECT name, json_extract(walk,'$.today'), json_extract(walk,'$.total'), json_extract(walk,'$.watts') FROM trainers ORDER BY 2 DESC`
  - 되돌리기: history의 사본을 새 rev로 올린다. 앱은 base가 낡았으므로 다음 동기화 때 저절로 따라온다.
  - 값 고치기: `UPDATE trainers SET walk = json_set(walk,'$.watts',0), rev = rev + 1 WHERE key = ?`
  - ID 삭제·이름 바꾸기.
- 멀티에 보상이 걸려서 검증이 필요해지면, 1차 초안에 있던 서버 규칙(걸음 허용량, 불가능한 값, 전설 예산, uid 불변값)을 그때 붙인다. 이번에는 만들지 않는다.

## 7. 바꿀 파일

| 파일 | 변경 |
|---|---|
| **새** `Sources/Core/Cloud.swift` (약 200줄) | API 세 개, 2분 주기와 `soon()`(3초 모으기), `flush(timeout:)`, 실패하면 2분부터 30분까지 간격 늘리기, `NSLock` inbox, 받기, 409·426 처리, 메뉴 문구. `persist == false`(셀프테스트, 렌더)면 네트워크를 쓰지 않음 |
| `Model/Walk.swift` | `cloudRev`, `cloudTotal`(Optional), `shared`, `adopt` |
| `Model/Store.swift` | `state.pre-server.json` 옮기기 |
| `Core/Platform.swift` | `Host.askText(title:message:) -> String?`, `let appVersion` |
| `Mac/MacHost.swift` | `askText`(NSAlert + NSTextField), 깨어날 때 `cloud.soon()` |
| **새** `Windows/WinInput.swift` (약 70줄) | `askText`: EDIT 칸과 확인·취소가 있는 작은 모달 창 |
| `Windows/WinCard.swift` | `PBT_APMRESUMEAUTOMATIC`에서 `soon()` |
| `Core/Walker.swift`, `Core/Flow.swift` | tick에서 `cloud.tick(now)`, press 앞뒤 비교, `after`/진화/부화/줍기에서 `soon()`, `quitSave`에서 `flush` |
| `Core/Menu.swift` | `트레이너: ID · n분 전 저장`, `지금 저장`, `ID 바꾸기…` |
| `Core/Compose.swift`, `Core/Page.swift` | "로그인이 필요해요" LCD와 **ID 입력** 버튼, 트레이너 카드에 ID |
| `App/main.swift`, `Windows/WinApp.swift` | 켤 때 캐시를 띄우고 → 로그인·받기 → 끌 때 flush |
| `Tests/SelfTest.swift` | `shared`/`adopt` 왕복, 다시 걷기가 상한을 지킴, ID 정규화(NFD → NFC, 대소문자), inbox 비우기, `persist == false`면 네트워크 안 씀, press 비교로 `soon()` |
| **새** `server/` | `wrangler.toml`, `schema.sql`, `src/index.ts`(약 150줄), `README.md`(배포, 관리 SQL). `Package.swift`에서 `exclude` |

손대지 않는 것: `StepGate.swift`, `Sign.swift`, `Shop.swift`, 배틀 전부.

## 8. 멀티로 가는 길

ID가 곧 트레이너 이름이고 친구 목록이다. 서버가 세이브를 직접 고치는 것은 관리자 조치뿐이다. 서버가 주는 것(교환으로 받은 포켓몬, 레이드 보상)은 sync 응답의 `inbox`로 내려보내고, 앱이 `keep()`으로 받는다. 그래서 플레이 중인 PC와 부딪히지 않는다.

| 기능 | 더할 것 | 품 |
|---|---|---|
| 랭킹 | `json_extract`로 주간 걸음, 타워 최고 연승, 도감 수. 트레이너 카드 탭 하나 | 1일 |
| 주간 레이드 | 03 레이드 §8 B안 그대로(같은 스택) | 03 1단계 뒤 2일 |
| 교환 | `trades`·`inbox` 테이블, 모든 포켓몬에 uid(`keep`에서 부여) | 2.5일 |
| 팀원 대결 | 상대 세이브의 `party()`를 고스트로 가져와 Lv.50으로 맞춰 싸움 | 2~3일 |

## 9. 단계와 일정

| 단계 | 내용 | 품 | 끝났다는 기준 |
|---|---|---|---|
| P0 | Cloudflare 계정, 빈 Worker 배포. **Windows 사내망 확인을 가장 먼저**: CI 빌드에 HTTPS GET 하나를 넣고, zip에 `FoundationNetworking.dll`이 들어가는지, 사내망·VPN에서 `workers.dev`에 닿는지 본다 | 0.5일 | Windows에서 HTTPS 200 |
| P1 서버 | schema, login/create/save, rev 판정, history와 Cron, app key, 관리 SQL | 0.5~1일 | curl로 만들기·저장·충돌·426이 모두 됨 |
| P2 클라이언트 | 7장 전부, 셀프테스트 | 2~2.5일 | 같은 ID로 Mac과 Windows를 번갈아 써도 걸음과 포켓몬이 이어짐. 오프라인과 충돌을 손으로 시험 |
| P3 배포 | 2.0, 초기화 공지, 가이드, 드라이브 | 0.5일 | 관리자 Mac → Windows → 팀원 |
| **합계** | | **약 4일** | |

## 10. 위험

1. **Windows 네트워크**: libcurl 기반 FoundationNetworking이 사내 프록시(PAC)나 TLS 검사 인증서를 따르지 않을 수 있다. P0에서 확인하고, 안 되면 같은 함수를 WinHTTP(약 60줄)로 만든다.
2. **ID 도용·실수**: 남의 ID로 들어와 덮어쓸 수 있다(감수). 관리자가 history로 되돌린다.
3. **무료 한도 초과**: 쓰기가 실패해도 앱은 로컬에 두고 계속 돌다가 나중에 올린다. 사람이 늘면 월 $5.
4. **옛 앱이 새 칸을 지움**: 426 버전 문턱으로 막는다. 대신 팀원에게 업데이트를 강제하게 된다.
5. **`workers.dev` 사내 차단**: 회사 망에서 막히면 개인 도메인(연 $10 정도)을 붙인다.
6. **개인정보**: ID와 걸음 수가 개인 Cloudflare 계정에 저장된다. 이메일이나 실명은 받지 않는다.

## 확정한 결정 (2026-10-02)

| # | 항목 | 결정 |
|---|---|---|
| 1 | 오프라인 | 한 번 로그인한 PC는 끊겨도 계속하고, 연결되면 올린다 |
| 2 | ID 규칙 | 한글·영문·숫자·`_` 2~12자, 대소문자 구분 없음 |
| 3 | 중복 로그인 | 나중 PC가 가져간다. 먼저 PC는 걸음과 조작을 멈추고 **여기서 계속**만 남는다 |
| 4 | PC 설정 | PC마다 따로 |
| 5 | 지금 세이브 | 서버에 옛 기록으로만 올리고, PC 백업도 남긴다 |
| 6 | 세션 만료 | 없음 |
