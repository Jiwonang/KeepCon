# 로컬 실행 가이드

KeepCon을 처음 받는 사람을 위한 문서입니다. **Flutter도 Firebase도 몰라도** 순서대로 따라 하면 앱이 뜹니다.

---

## 0. 먼저: 두 가지 실행 방법이 있습니다

어느 쪽으로 띄울지부터 정해야 합니다. 하는 일이 다릅니다.

| | **A. 데모 모드** | **B. 에뮬레이터 모드** |
|---|---|---|
| 데이터가 어디 있나 | 앱 메모리 (껐다 켜면 초기화) | 내 PC에서 도는 가짜 Firebase |
| 로그인 | 이미 로그인된 상태로 시작 | 실제로 로그인해야 함 |
| 준비물 | Flutter만 | Flutter + Node.js + Java |
| 터미널 | 1개 | 2개 |
| 언제 쓰나 | **화면(UI) 작업** | **로그인·그룹·공유 등 데이터 작업** |

**화면만 만질 거면 A로 충분합니다.** A가 훨씬 간단하니, 처음이라면 A를 먼저 성공시키고 B로 넘어가세요.

> 실제 Firebase 서버는 아직 안 씁니다. 팀이 각자 개발하는 동안은 각자 PC의 에뮬레이터를 쓰는 게 맞습니다. 이유는 [README의 Firebase 연동](../README.md#-firebase-연동-백엔드-활성화) 참고.

---

## 1. 설치 (처음 한 번만)

### 모드 A만 쓸 거면 — 두 개

**Git** — https://git-scm.com/downloads
Windows는 설치 중 옵션을 그대로 두면 됩니다. **Git Bash가 같이 깔리는데, 이 프로젝트는 Git Bash를 기준으로 합니다** (3번 항목 참고).

**Flutter SDK 3.27 이상** — https://docs.flutter.dev/get-started/install
설치 후 확인:

```bash
flutter --version     # 3.27 이상이면 OK
flutter doctor        # 빨간 X 중 Android/iOS 관련은 웹으로만 돌릴 거면 무시해도 됩니다
```

### 모드 B도 쓸 거면 — 두 개 더

**Node.js 20 이상** — https://nodejs.org (LTS 버전)
Firebase 명령어 도구를 설치하는 데만 씁니다.

```bash
npm install -g firebase-tools
firebase --version    # 숫자가 나오면 OK
```

**Java 11 이상** — https://adoptium.net
Firestore 에뮬레이터가 Java로 돌아갑니다. **없으면 에뮬레이터가 안 뜹니다.**

```bash
java -version
```

> Firebase 계정 로그인은 **필요 없습니다.** 에뮬레이터는 `demo-` 로 시작하는 가짜 프로젝트를 쓰기 때문에 실제 Google 서버에 접속하지 않습니다.

---

## 2. 프로젝트 받기 (처음 한 번만)

```bash
git clone https://github.com/Jiwonang/KeepCon.git
cd KeepCon
flutter pub get
```

`flutter pub get`은 라이브러리를 받는 명령입니다. 여기서 에러가 나면 Flutter 설치가 덜 된 것이니 `flutter doctor`부터 보세요.

---

## 3. ⚠️ 어떤 터미널을 쓸지 (Windows 사용자 필독)

이 프로젝트의 스크립트(`.sh` 파일)는 **Git Bash에서 실행하는 것을 전제**합니다.

**cmd나 PowerShell에서 `bash`를 치면 Git Bash가 아니라 WSL이 실행되고, 대부분 이렇게 실패합니다:**

```
WSL (10 - Relay) ERROR: execvpe(/bin/bash) failed: No such file or directory
```

그래서 셋 중 하나를 고르세요:

- **(권장) Git Bash 쓰기** — 프로젝트 폴더에서 우클릭 → *Open Git Bash here*. 이 문서의 명령을 그대로 복사해 쓸 수 있습니다.
- **cmd/PowerShell을 쓰되 명령을 바꾸기** — 아래 4-B에 셸별 명령을 따로 적어뒀습니다.
- VS Code를 쓴다면 터미널 기본 셸을 Git Bash로 바꿔두면 편합니다.

macOS·Linux는 기본 터미널을 그냥 쓰면 됩니다.

---

## 4. 실행하기

### 4-A. 데모 모드 (터미널 1개)

```bash
flutter run -d chrome
```

크롬 창이 뜨고 기프티콘 목록이 바로 보이면 성공입니다. 로그인은 이미 되어 있습니다.

> `-d chrome`은 "크롬으로 띄워라"라는 뜻입니다. 빼면 어느 기기로 띄울지 물어봅니다.

### 4-B. 에뮬레이터 모드 (터미널 2개)

**터미널 2개를 동시에 띄워둬야 합니다.** 하나는 가짜 Firebase 서버, 하나는 앱입니다. 서버가 먼저 떠 있어야 앱이 붙습니다.

#### 터미널 A — 가짜 Firebase 서버

셸에 따라 명령이 다릅니다. **프로젝트 폴더(KeepCon)에서** 실행하세요.

```bash
# Git Bash / macOS / Linux
bash tool/emulators.sh
```

```
:: cmd
firebase emulators:start --project demo-keepcon --import=emulator-seed
```

```powershell
# PowerShell
firebase emulators:start --project demo-keepcon --import=emulator-seed
```

아래 화면이 나오면 성공입니다. **이 터미널은 그대로 두세요** (닫으면 서버가 꺼집니다):

```
✔  All emulators ready! It is now safe to connect your app.
   View Emulator UI at http://127.0.0.1:4000/
```

#### 터미널 B — 앱

**새 터미널을 열고**, 역시 프로젝트 폴더에서:

```bash
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
```

이 명령은 어느 셸에서든 똑같습니다. 뒤의 `--dart-define=...` 이 **"가짜 Firebase에 접속해라"** 라는 스위치입니다. 이걸 빼면 데모 모드로 돌아갑니다.

로그인 화면이 뜨면 아래 계정으로 들어가세요:

| 역할 | 이메일 | 비밀번호 |
|------|--------|----------|
| 방장 | `owner@keepcon.test` | `test1234` |
| 파티원 | `member@keepcon.test` | `test1234` |

두 계정은 **저장소에 미리 넣어둔 것**이라 팀원 모두가 똑같이 씁니다. 회원가입할 필요 없습니다. 기프티콘과 그룹('우리 가족')도 이미 들어 있습니다.

> 이 비밀번호는 테스트 전용입니다. 가짜 서버라 유출 위험은 없지만, **실제 계정에는 절대 쓰지 마세요.**

---

## 5. 잘 됐는지 확인하는 법

**터미널 B의 로그**에 이 줄이 있으면 에뮬레이터에 제대로 붙은 것입니다:

```
KeepCon: Firebase 에뮬레이터 연결됨 (localhost — auth:9099, firestore:8080)
```

**http://localhost:4000** 을 브라우저로 열면 저장된 계정과 데이터를 눈으로 볼 수 있습니다. 앱에서 뭔가 만들면 여기에 바로 나타납니다.

### 끄는 법

두 터미널에서 각각 `Ctrl + C`. 순서는 상관없습니다.

---

## 6. 알아둘 것

**에뮬레이터를 끄면 그동안 만든 데이터는 사라집니다.** 다시 켜면 항상 처음 시드 상태로 돌아갑니다. 고장이 아니라 의도된 동작입니다 — 각자 테스트하며 만든 데이터가 팀 공용 시드를 덮어쓰지 않게 하기 위한 것입니다.

**`--dart-define`은 앱을 재시작해야 바뀝니다.** 실행 중에 `r`(핫 리로드)을 눌러도 백엔드는 안 바뀝니다. 모드를 바꾸려면 `Ctrl+C`로 끄고 다시 실행하세요.

**모바일로 띄우려면** 플랫폼 폴더를 먼저 만들어야 합니다(현재 저장소엔 웹만 있습니다):

```bash
flutter create . --platforms=android,ios
flutter run --dart-define=USE_FIREBASE_EMULATOR=true
```

안드로이드 에뮬레이터에서는 접속 주소가 자동으로 `10.0.2.2`로 바뀝니다. 따로 설정할 것 없습니다.

---

## 7. 막혔을 때

| 증상 | 원인과 해결 |
|------|------------|
| `bash: command not found` 또는 `WSL ... execvpe(/bin/bash) failed` | cmd/PowerShell에서 `.sh`를 실행한 것. 3번 항목대로 Git Bash를 쓰거나, 4-B의 cmd용 명령을 쓰세요. |
| `Port 8080 is not open` / `Could not start Emulator UI, port taken` | 에뮬레이터가 이미 떠 있거나 다른 프로그램이 그 포트를 씀. 기존 터미널에서 `Ctrl+C`로 끄고 다시 시도하세요. 그래도 안 되면 PC를 재시작하는 게 빠릅니다. |
| 에뮬레이터가 뜨다 마는데 Java 얘기가 나옴 | Java 미설치. 1번 항목 참고. |
| 로그인 화면에서 계정이 안 먹음 | 시드가 안 올라온 것. 터미널 A 로그에 `Importing accounts from ...` 이 있는지 보세요. 없다면 **프로젝트 폴더가 아닌 곳**에서 실행했을 가능성이 큽니다. |
| 앱이 로그인 화면 없이 바로 목록으로 감 | `--dart-define=USE_FIREBASE_EMULATOR=true` 를 빠뜨린 것. 데모 모드로 뜬 상태입니다. |
| 앱에서 로그인하면 에러가 남 | 터미널 A(에뮬레이터)가 안 떠 있는 것. 서버를 먼저 띄우고 앱을 다시 실행하세요. |
| `flutter pub get` 에서 에러 | `flutter doctor` 로 Flutter 설치 상태부터 확인. 버전이 3.27 미만이면 업그레이드하세요. |

---

## 8. 다음 단계

앱이 떴다면 이제 작업을 시작할 수 있습니다. **코드를 고치기 전에** 아래를 읽어주세요:

- [README — 협업 규약](../README.md#-협업-규약-페이지별-담당--필독) — 브랜치·커밋·PR 규칙, 공유 계약(SSOT) 규칙
- [README — 프로젝트 구조](../README.md#-프로젝트-구조) — 어느 폴더가 무엇인지

특히 **작업 브랜치는 항상 최신 `develop`에서 따고**, `main`·`develop`에 직접 push하지 않는다는 두 가지는 먼저 알고 시작하는 게 좋습니다.
