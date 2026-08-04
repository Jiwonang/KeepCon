---
name: keepcon-run
description: "KeepCon 앱을 로컬에서 실행하는 스킬. 트리거 — '프로젝트 실행해줘', '앱 실행/켜줘', '띄워줘', '로컬에서 돌려봐', 'flutter run 해줘', '실행해서 확인해줘' 등 KeepCon을 구동하라는 요청. 백엔드를 먼저 묻는다: ①로컬 에뮬레이터(플래그 없음, 기본) ②팀 공유 dev DB(--dart-define=USE_FIREBASE=true). 개발자가 고른 경로로 띄우고, 실패하거나 조건이 안 맞으면 차선책(데모·포트 변경·재시도)을 제시한다. 후속 작업 — '다른 백엔드로 다시', '에뮬레이터로 바꿔', '껐다 켜줘'에도 사용."
---

# KeepCon 실행 — 백엔드를 먼저 고르고 띄운다

KeepCon은 백엔드가 네 갈래(에뮬레이터·dev·실서비스·데모)다. **어디에 붙는지가 데이터가 어디에 쌓이고 무엇이 날아가는지를 결정하므로, 임의로 골라 실행하지 않는다.** 이 스킬은 항상 **선택지를 먼저 제시**하고, 고른 경로로만 띄운다.

## 0. 원칙

- **묻기 전에 실행하지 않는다.** 사용자가 이미 백엔드를 지목했으면(예: "에뮬레이터로 실행해줘") 묻지 말고 그 경로로 바로 간다.
- **실서비스(`keepcon-ab660`)는 절대 기본값이 아니다.** 사용자가 "실서비스로"라고 명시적으로 말했을 때만 실행한다. 선택지에도 기본으로 넣지 않는다.
- **웹으로 띄울 때 `flutter run`을 Bash로 직접 실행하지 않는다.** `preview_start`(`.claude/launch.json`의 구성 이름)를 쓴다. 장수 프로세스 관리·로그 조회·브라우저 확인이 전부 거기에 붙어 있다. 백엔드 네 갈래 모두 구성이 있다 — `keepcon-emulator`(8082) · `keepcon-dev`(8083) · `keepcon-demo`(8085) · `keepcon-prod`(8084).
  - **예외:** 실기기(Android·iOS) 실행은 `preview_start`로 표현할 수 없다. 이때만 Bash로 `flutter devices` → `flutter run …`을 쓰거나, 사용자에게 명령을 안내한다.
- **에뮬레이터는 Ctrl+C로 꺼야 데이터가 저장된다.** 프로세스를 강제 종료하면 그 세션 데이터가 사라진다. 사용자에게 이 점을 알린다.

## 1. 두 갈래를 제시한다

`AskUserQuestion`으로 묻는다. 헤더는 `백엔드`, 선택지는 아래 둘을 이 순서로.

| 선택지 | 설명에 반드시 담을 것 |
|--------|----------------------|
| **① 로컬 에뮬레이터 (권장)** | 내 PC에만 쌓임 · 파괴적 테스트 자유 · 터미널 2개(에뮬레이터 + 앱) · 공용 시드 계정 있음 · **혼자서는 그룹 공유 검증 불가** |
| **② 팀 공유 dev DB** | `keepcon-dev` 서버 · 팀원과 **같은 그룹**에 들어가는 공유 시나리오 검증 가능 · 터미널 1개 · **남의 데이터도 같이 날아가므로 파괴적 테스트 금지** · 각자 회원가입 |

질문 문구 예: `"어느 백엔드로 실행할까요?"`

`AskUserQuestion`의 "Other"로 사용자가 데모·실서비스를 요청할 수 있으니, 아래 4장(차선책)의 명령을 그대로 쓴다.

## 2-A. 경로 ①: 로컬 에뮬레이터

플래그가 **없는 게 맞다** — 앱의 기본 백엔드가 에뮬레이터다(`lib/main.dart`의 `_resolveTarget()`).

1. **에뮬레이터를 먼저 띄운다 — 원칙적으로 사용자가 자기 터미널에서.** 앱보다 먼저 떠 있어야 한다.
   - 아래 명령을 안내하고, 떴다고 알려줄 때까지 기다린다. cmd: `tool\emulators.cmd` · PowerShell: `.\tool\emulators.cmd` · Git Bash·macOS·Linux: `bash tool/emulators.sh`
   - **⚠️ Claude가 백그라운드로 대신 띄우지 않는다.** 에뮬레이터는 **Ctrl+C 정상 종료 때만** `--export-on-exit`로 데이터를 `.emulator-local/`에 저장한다. 백그라운드 프로세스는 세션 종료·`TaskStop`에서 kill로 죽어 그 신호가 가지 않으므로, **그 세션에 만든 계정·그룹·기프티콘이 통째로 사라진다.** 사용자가 소유한 터미널이어야 사용자가 Ctrl+C를 누를 수 있다(`lib/app/emulator_unavailable_page.dart`도 "별도 터미널에서 먼저" 띄우라고 안내한다).
   - 사용자가 "네가 띄워줘"라고 명시적으로 요청하면 그때만 `run_in_background: true`로 실행하되, **위 데이터 소실 조건을 먼저 알리고** 동의를 받는다.
2. **떴는지 확인한다.** 터미널 출력에 `All emulators ready` 또는 Emulator UI 주소(`http://127.0.0.1:4000`)가 보이면 준비된 것. 포트: Auth 9099 · Firestore 8080 · UI 4000.
   - `firebase CLI not found` → `npm install -g firebase-tools` 안내 후 중단.
   - `Port 8080 is not open` / `port taken` → 이미 떠 있는 에뮬레이터가 있다. 그 프로세스를 재사용하거나, 기존 터미널에서 Ctrl+C 후 재시도하도록 안내한다.
3. **앱을 띄운다.** `preview_start` → `{"name": "keepcon-emulator"}` (포트 8082, `--dart-define=USE_FIREBASE_EMULATOR=true`로 기본값이 바뀌어도 에뮬레이터를 고정).
4. **확인.** `read_console_messages`에 `KeepCon: Firebase 에뮬레이터 연결됨 …`이 찍히면 연결된 것. 화면 배지는 없다(에뮬레이터는 배지 없음이 정상).
   - 앱이 **"에뮬레이터가 떠 있지 않습니다"** 안내 화면(`lib/app/emulator_unavailable_page.dart`)을 띄우면 1번이 아직 안 뜬 것이다 — 기다렸다가 새로고침.
5. **사용자에게 알릴 것:** 접속 URL, 공용 시드 계정(`owner@keepcon.test` / `member@keepcon.test`, 비번 `test1234`), **끌 때는 에뮬레이터 터미널에서 Ctrl+C**(창을 닫으면 그 세션 데이터 소실), 초기화는 `--fresh`.

## 2-B. 경로 ②: 팀 공유 dev DB

1. `preview_start` → `{"name": "keepcon-dev"}` (포트 8083, `--dart-define=USE_FIREBASE=true`). 에뮬레이터를 띄울 필요가 없다. 인터넷 필요.
2. **확인.** 화면 우측에 주황색 **'공유 dev' 배지**가 보이면 dev에 붙은 것(`_backendBanner`). 배지가 없으면 에뮬레이터로 붙은 것이니 플래그를 다시 확인한다.
3. **사용자에게 알릴 것:** 접속 URL, **시드 계정이 없으니 회원가입부터** 할 것, 그룹 공유 테스트는 한 명이 그룹을 만들고 초대코드를 공유할 것, **여기서 파괴적 테스트 금지**(팀원 데이터도 같이 날아간다 — 리셋이 필요하면 `tool/reset_dev.sh`를 팀에 알린 뒤).

## 3. 실행 후 검증

앱을 띄웠으면 여기서 끝내지 말고 살아 있는지까지 확인한다.

1. `read_console_messages` — 빨간 에러 없는지.
2. `preview_logs` — 빌드 실패·컴파일 에러 없는지.
3. 화면 확인이 필요하면 `read_page` 또는 `computer {action:"screenshot"}`.

실패하면 원인을 진단해 소스를 고치고 다시 확인한다. **"사용자가 직접 확인해보세요"로 넘기지 않는다.**

## 4. 차선책 — 위 둘이 막혔거나 다른 목적일 때

| 상황 | 대안 | 명령 / 구성 이름 |
|------|------|-----------------|
| Java·firebase CLI가 없어 에뮬레이터가 안 뜬다 | **데모 모드** — 백엔드 없이 in-memory 시드로 즉시 실행 | `preview_start` → `keepcon-demo` (포트 8085, `--dart-define=USE_DEMO=true`) |
| 화면·UI만 손보는 중이라 백엔드가 필요 없다 | 같은 데모 모드 (가장 빠름) | 위와 같음 |
| 이미 빌드된 결과만 보고 싶다 | 정적 서버. **`flutter build web`을 먼저 돌려야 한다** — 이 구성은 `build/web`을 서빙만 하므로, 빌드가 없으면 404이고 오래된 빌드면 지금 코드와 무관한 화면이 뜬다 | `flutter build web` → `preview_start` → `keepcon-web` (포트 8090) |
| 시연·배포 확인 (**명시 요청 시에만**) | 실서비스 | `preview_start` → `keepcon-prod` (포트 8084, 빨간 '실서비스' 배지) |
| 실기기(Android·iOS) | dev 서버에 붙여 실행. **실기기 + 로컬 에뮬레이터 조합은 지원하지 않는다** | `flutter devices` → `flutter run --dart-define=USE_FIREBASE=true` |
| 포트가 이미 물려 있다 | `.claude/launch.json`의 포트를 바꾸지 말고, 기존 프로세스를 `preview_list`로 찾아 재사용하거나 `preview_stop` | — |
| 에뮬레이터 데이터가 엉켰다 | 시드 상태로 초기화(에뮬레이터를 먼저 끈 뒤) | `tool\emulators.cmd --fresh` / `bash tool/emulators.sh --fresh` |

데모 모드는 **그룹 공유를 검증할 수 없다**(메모리에만 존재). 공유 기능 작업 중이라면 데모를 차선책으로 권하지 말고, 에뮬레이터를 띄우는 쪽을 도와라.

## 5. 흔한 함정

- **`--dart-define`은 핫 리로드로 안 바뀐다.** 백엔드를 바꾸려면 앱을 껐다 다시 띄워야 한다(`preview_stop` → `preview_start`).
- **플래그 충돌 시 안전한 쪽이 이긴다** — 데모 > 에뮬레이터 > dev > prod 순으로 우선(`_resolveTarget()`). 여러 플래그를 동시에 주지 말 것.
- **`google-services.json`·`GoogleService-Info.plist`를 추가하지 말 것.** 네이티브가 백엔드를 하나로 고정해 나머지 경로가 `[core/duplicate-app]`으로 죽는다.
- Firestore 에뮬레이터가 **8080**을 쓴다. 다른 로컬 웹 서버를 그 포트에 띄우지 말 것.

## 참고

- 사람이 읽는 실행 가이드: `docs/GETTING_STARTED.md`, `README.md`의 "실행하기".
- 백엔드 분기 구현: `lib/main.dart`, `lib/shared/firebase/firebase_bootstrap.dart`.
