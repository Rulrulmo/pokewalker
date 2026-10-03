# PokeWalker 세이브 서버

집 미니 PC(Ubuntu 24.04)에서 도는 세이브 서버다. 설계는 `docs/plans/08-server-save.md`, 구현 지시는 `docs/plans/08b-server-home.md`를 따른다. 이 문서는 실제로 깐 모양과 자주 쓰는 명령만 적는다.

```
앱 ──HTTPS──▶ https://pokewalker.rulrulmo.work ──(Cloudflare Tunnel "pokewalker")──▶ 127.0.0.1:8787
              cloudflared-pokewalker.service                                        pokewalker.service = /usr/local/bin/pokeserver serve
                                                                                    /var/lib/pokewalker/pokewalker.db (SQLite, WAL)
```

- API 주소: `https://pokewalker.rulrulmo.work` (`/v1/ping`, `/v1/login`, `/v1/create`, `/v1/save`, `/v1/legacy`). 08b의 `api.<domain>` 자리다.
- `APP_KEY`: `/etc/pokewalker/server.env`에 있다. 커밋하지 않는다. 앱의 `Cloud.swift`에는 `sudo cat /etc/pokewalker/server.env`로 본 값을 넣는다.
- 트레이너 ID는 2~12자다. 08·08b의 예시 ID "민"은 한 글자라서 서버가 `bad_id`로 거절한다. 앱 테스트에는 "민수"처럼 두 글자 이상을 쓴다.

## 다운로드 페이지

`https://pokewalker.rulrulmo.work/`는 팀 배포 페이지다. 최신 버전의 Mac·Windows zip, 설치 방법, 패치 내역(`docs/patch-notes.txt`)을 보여 준다(`Sources/PokeCore/ServerPage.swift`).
- 팀 비밀번호 하나로 연다: `/etc/pokewalker/server.env`의 `DOWNLOAD_PASSWORD`. 바꾸면 `sudo systemctl restart pokewalker` 뒤 모두 다시 입력한다(쿠키는 비밀번호의 HMAC, 30일). 비어 있으면 페이지가 없다.
- 앱 스프라이트가 닌텐도 저작물이라 공개하지 않는다. 검색 엔진도 막는다(`robots.txt`, `noindex`).
- 페이지는 `RELEASE_DIR`(`/var/lib/pokewalker/release`)의 `release.json` · `patch-notes.txt` · zip 두 개를 그대로 보여 준다. 채우는 것은 `publish.sh`뿐이다.

**새 버전 올리기** (Info.plist 버전과 패치 내역을 커밋하고 push한 뒤) — 자동 업데이트가 받는 것과 같은, 서명된 릴리스다.
- 릴리스 Mac에서 `./build.sh publish`: Mac dist와 그 커밋의 windows 워크플로 결과물을 zip으로 만들고, `manifest.json`(버전·빌드·커밋·zip마다 크기와 SHA-256)을 릴리스 키로 서명해(`manifest.sig`, `tools/release-key.swift`) GitHub release `v<버전>`에 네 파일을 올린다. 비밀 키는 그 Mac에만 있다(`~/.config/pokewalker/release-ed25519.key`, 백업 필수).
- 서버에서 `server/publish.sh [v<버전>]`: 네 파일을 받아 `pokeserver verify-release`로 서명(공개 키 `Sources/Model/Ed25519.swift`의 `releaseKey`)·크기·SHA-256을 확인하고, 통과해야만 페이지와 업데이트를 한 번에 바꾼다. 서버가 뚫려도 서명 없는 업데이트는 앱이 설치하지 않는다.
- 앱의 업데이트: `POST /v1/update`(앱 키) → 서명된 manifest 그대로와 서명, `GET /v1/download/mac|windows`(앱 키) → zip. 앱이 서명과 해시를 직접 확인한다(`Sources/PokeCore/ServerUpdate.swift`).
- 둘 사이는 Claude 세션끼리 Remote Control 메시지로 잇는다: Mac의 Claude가 release를 올리고 서버의 Claude에게 알리면, 서버의 Claude가 publish.sh를 돌려 결과를 돌려준다.
- Mac은 Apple 하드웨어에서만 빌드한다(macOS SDK 라이선스). Windows 빌드는 GitHub Actions(비공개 저장소: 1분이 2분으로 차감)다.

## 빌드와 테스트

Swift 6.1.2는 swiftly로 설치되어 있다(`server/.swift-version`). `build.sh`는 매번 `../Sources/{Model,Data,Battle}`을 `Sources/PokeCore/Game/`에 새로 복사한다(커밋하지 않음).

```sh
server/build.sh            # 릴리스 빌드 → server/.build/release/pokeserver
server/build.sh test       # 단위 테스트 (판정표 13줄, busy, 바이트 보존, history·정리, legacy, 관리 명령)
server/test.sh             # curl 전체 흐름: 임시 DB와 127.0.0.1:8799에서 (먼저 build.sh)
BASE=https://pokewalker.rulrulmo.work KEY=<APP_KEY> server/test.sh   # 실제 서버로. 테스트 ID(zz…)는 끝나면 지운다
server/build.sh install    # 빌드 → /usr/local/bin에 설치 → 서비스 재시작 (sudo)
```

앱의 `Walk`에서 칸 이름이나 형을 바꾸거나 칸을 지우면 서버를 먼저 다시 빌드한다. Optional 칸을 더하는 것은 서버를 바꾸지 않아도 된다.

## 깔린 것 (08b §6, 이 PC)

| 무엇 | 어디 |
|---|---|
| 시스템 사용자 | `pokewalker` (nologin). 관리자 `rulmo`는 `pokewalker` 그룹(백업 읽기용, 다시 로그인해야 적용) |
| 설정 | `/etc/pokewalker/server.env` (root:pokewalker 640): `APP_KEY`, `PORT=8787`, `DB_PATH` |
| DB | `/var/lib/pokewalker/pokewalker.db`. `pokeserver init`만 만든다. 파일이 없으면 서버는 시작하지 않는다 |
| 서버 | `pokewalker.service` (`ops/pokewalker.service`) |
| 백업 | `pokewalker-backup.timer` 매일 04:30 → `/var/lib/pokewalker/backup/pw-YYYY-MM-DD.db.gz`, 14일 보관 |
| 터널 | 터널 `pokewalker`, 설정 `/etc/cloudflared/pokewalker.yml`, 서비스 `cloudflared-pokewalker.service` (`ops/`) |

**터널은 따로 둔다.** 이 PC에는 원래 `cloudflared.service`(`/etc/cloudflared/config.yml`, 터널 `n8n-tunnel` → `terminal.rulrulmo.work` SSH)가 있다. 서버용 터널은 별도 서비스라서, 재시작해도 터미널 접속이 끊기지 않는다.
- `cloudflared tunnel route dns`는 기본 설정 파일의 `tunnel:`(n8n-tunnel)을 따라간다. 반드시 `--config`로 이 터널의 설정을 준다:
  `cloudflared tunnel --config /etc/cloudflared/pokewalker.yml route dns --overwrite-dns <UUID> pokewalker.rulrulmo.work`
- 08b의 `cloudflared service install`은 쓰지 않는다(기존 `cloudflared.service`와 부딪힌다).
- cloudflared 업데이트(한 달에 한 번): `sudo apt-get install --only-upgrade cloudflared` 뒤 `sudo systemctl restart cloudflared-pokewalker`.

## 관리 명령 (08b §7)

먼저 `alias pw='sudo -u pokewalker /usr/local/bin/pokeserver'`. 반드시 pokewalker 사용자로 실행한다(root로 열면 -wal/-shm이 root 것이 되어 서버가 쓰지 못한다).

| 명령 | 하는 일 |
|---|---|
| `pw list` | 전원: 오늘 걸음 순, rev, total, watts, 마지막 저장, PC |
| `pw show <id>` | 한 명: 요약, history(rev, reason, 시각, total, watts), legacy |
| `pw walk <id> [<rev> <reason>]` | 세이브 JSON(또는 history 사본) → `\| jq` |
| `pw rollback <id> <rev> <reason>` | history 사본을 새 rev로. 지금 것은 history('admin')에 남는다 |
| `pw set <id> '<json-path>' '<json-value>'` | 예: `pw set 민수 '$.watts' 0`. 앱이 못 읽는 결과면 아무것도 바꾸지 않는다 |
| `pw rename <id> <새 id>` | key가 바뀌면 세션이 끝나고, 그 PC는 다음 저장에서 404 → ID 입력창 |
| `pw delete <id> --yes` | 세이브를 `/var/lib/pokewalker/deleted-<key>-<unix>.json`으로 남기고 지운다. legacy는 남긴다 |
| `pw legacy [<id>]` · `pw prune` · `pw sample` | 옛 세이브 목록 · history 정리(서버가 매시 함) · 새 세이브 JSON |

다른 DB는 `--db <path>`로 가리킨다(`sudo -u`가 환경 변수를 지운다). 비상시 `sudo -u pokewalker sqlite3 /var/lib/pokewalker/pokewalker.db`로 직접 고칠 때는 `rev = rev + 1, writer = 'admin'`도 같이 한다.

## 운영

- 로그: `journalctl -u pokewalker -f` (replaced·stale·426·새 트레이너는 key와 함께), `journalctl -u cloudflared-pokewalker`.
- 상태: `systemctl status pokewalker cloudflared-pokewalker`, `systemctl --failed`, `du -sh /var/lib/pokewalker`.
- 업데이트: `git pull && server/build.sh install`. 서버는 1~2초 끊기고, 실패한 저장은 앱이 다음 주기에 다시 올린다.
- 복원(순서 지킴: 낡은 WAL이 되살린 DB를 망가뜨린다):
  ```sh
  sudo systemctl stop pokewalker
  sudo rm -f /var/lib/pokewalker/pokewalker.db-wal /var/lib/pokewalker/pokewalker.db-shm
  sudo -u pokewalker sh -c 'gunzip -c /var/lib/pokewalker/backup/pw-2026-10-01.db.gz > /var/lib/pokewalker/pokewalker.db'
  sudo systemctl start pokewalker
  ```
  복원한 날에는 `pw show <id>`로 conflict 행을 보고 가장 새 것을 `pw rollback <id> <rev> conflict`로 올린다(08b §6).
- 백업을 밖으로(rclone → 개인 Google Drive)와 감시(UptimeRobot `/v1/ping`)는 08b §6대로 한다.
