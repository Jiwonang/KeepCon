# 로컬 실행 가이드

KeepCon을 처음 받는 사람을 위한 문서입니다. **Flutter도 Firebase도 몰라도** 순서대로 따라 하면 앱이 뜹니다.

---

## 0. 먼저: 세 가지 실행 방법이 있습니다

어느 쪽으로 띄울지부터 정해야 합니다. **데이터가 어디에 저장되는지가 다릅니다.**

| | **A. 데모** | **B. 에뮬레이터 (기본)** | **C. 팀 개발 서버** |
|---|---|---|---|
| 실행 명령 (뒤에 붙일 것) | `--dart-define=USE_DEMO=true` | **없음 (기본값)** | `--dart-define=USE_FIREBASE=true` |
| 데이터가 어디 있나 | 앱 메모리 | 내 PC에서 도는 가짜 Firebase | **인터넷 너머 `keepcon-dev`** |
| 껐다 켜면 | **사라짐** | **남아 있음** (`Ctrl+C`로 껐을 때) | **남아 있음** |
| 팀원과 공유되나 | ❌ | ❌ (내 PC에만 있음) | ✅ **같은 그룹에 들어갈 수 있음** |
| 로그인 | 이미 된 상태로 시작 | 처음엔 공용 계정, 이후 **내가 만든 계정도 유지** | **각자 회원가입** |
| 준비물 (셋 다 Chrome 필요) | Flutter만 | Flutter + Node.js + Java | Flutter + 인터넷 |
| 터미널 | 1개 | 2개 | 1개 |
| 언제 쓰나 | 화면(UI) 작업 | **파괴적 테스트**(그룹 삭제 등)·규칙 검증·오프라인 | **팀원과 함께 하는 공유 시나리오** |

**평소 작업은 B입니다 — 플래그가 필요 없는 기본값입니다.** 대신 **터미널 2개**가 필요합니다(에뮬레이터는 자동으로 뜨지 않습니다). 안 띄운 채 실행하면 앱이 무엇을 해야 하는지 안내하는 화면을 보여줍니다.

**화면(UI)만 만질 거면 A**가 가장 가볍습니다 — 준비물이 없습니다. 단 데이터가 앱 메모리에만 있어 그룹 공유는 검증할 수 없습니다.

**팀원과 같이 테스트할 때는 C입니다.** A와 B는 데이터가 내 PC 밖으로 나가지 않아서, 팀원이 만든 그룹이 보이지 않습니다.

> ⚠️ **C에서는 그룹 삭제 같은 파괴적 테스트를 하지 마세요.** 데이터가 팀 공유라 **남이 쓰던 것도 같이 사라집니다.** 그런 테스트는 B에서 하세요 — B는 내 PC에만 있어서 뭘 지우든 남에게 영향이 없고, 엉켰으면 `--fresh`로 처음 상태로 되돌리면 됩니다.
>
> 💡 **플래그를 깜빡하면 B(내 PC)로 뜹니다.** 그래서 팀원이 만든 그룹은 안 보이는 게 정상입니다 — 같은 그룹에 들어가려면 **양쪽 다** C로 띄워야 합니다. C·실서비스에 붙어 있으면 **화면 오른쪽 위에 배지**가 뜨고, 콘솔에도 `KeepCon: Firebase 연결됨 (dev — keepcon-dev)` 가 찍힙니다.
>
> 시연·배포 확인용 실서비스 서버(`keepcon-ab660`)는 플래그가 또 다릅니다(`--dart-define=USE_FIREBASE_PROD=true`). 평소에 쓸 일은 없습니다. 자세한 건 [README의 Firebase 연동](../README.md#-firebase-연동-백엔드-활성화) 참고.

---

## 1. 설치 (처음 한 번만)

### 모드 A만 쓸 거면 — 두 개

**Git** — https://git-scm.com/downloads
Windows는 설치 중 옵션을 그대로 두면 됩니다. **Git Bash가 같이 깔리는데, 이 프로젝트는 Git Bash를 기준으로 합니다** (3번 항목 참고).

**Flutter SDK 3.27 이상** — https://docs.flutter.dev/get-started/install
설치 후 확인:

```bash
flutter --version     # 3.27 이상이면 OK
flutter doctor        # 빨간 X 중 Android 관련은 웹으로만 돌릴 거면 무시해도 됩니다
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

### 모드 C는 — 추가 설치 없음

**Flutter와 인터넷만 있으면 됩니다.** Node.js·Java도, Firebase 계정 로그인도 필요 없습니다. 서버는 이미 만들어져 있고 접속 정보가 저장소에 커밋돼 있어서, `flutter pub get` 만 끝났으면 바로 붙습니다.

### 📱 Android 기기로 띄운다면 — 모드와 무관하게 추가로 필요

**웹(Chrome)으로 띄우면 이 항목은 필요 없습니다.** 실기기나 AVD로 띄울 때만 해당합니다.

- **JDK 17 이상** — Android 빌드가 Java 17을 타깃합니다. 모드 B의 "Java 11"만 설치하면 **에뮬레이터는 뜨는데 `flutter run` 이 Gradle에서 실패합니다.**
- **Android SDK** — `flutter doctor` 의 *Android toolchain* 항목

> 모드 C(dev 서버)도 예외가 아닙니다. "추가 설치 없음"은 **웹으로 띄울 때** 이야기입니다.
> 설치 위치·환경 변수 설정은 [README의 *Android 기기로 띄우기*](../README.md#-android-기기로-띄우기-실기기--avd) 를 보세요.

---

## 2. 프로젝트 받기 (처음 한 번만)

```bash
git clone https://github.com/Jiwonang/KeepCon.git
cd KeepCon
flutter pub get
```

`flutter pub get`은 라이브러리를 받는 명령입니다. 여기서 에러가 나면 Flutter 설치가 덜 된 것이니 `flutter doctor`부터 보세요.

---

## 3. 터미널은 편한 걸 쓰세요

cmd · PowerShell · Git Bash 중 **아무거나 써도 됩니다.** 확장자만 다른 같은 스크립트를 준비해뒀습니다.

| 쓰는 셸 | 실행할 파일 |
|---------|------------|
| cmd · PowerShell | `tool\emulators.cmd` |
| Git Bash · macOS · Linux | `tool/emulators.sh` |

하는 일은 완전히 같습니다. 4-B에 셸별 명령이 나란히 적혀 있으니 자기 것만 골라 쓰면 됩니다.

<details>
<summary>왜 파일이 두 개인지 (안 궁금하면 넘어가세요)</summary>

cmd·PowerShell에서 `bash tool/emulators.sh`를 치면 Git Bash가 아니라 **WSL**이 실행되어 이렇게 실패합니다:

```text
WSL (10 - Relay) ERROR: execvpe(/bin/bash) failed: No such file or directory
```

`bash`라는 이름이 PATH에서 `C:\Windows\System32\bash.exe`(WSL 런처)로 잡히고, Git Bash가 있는 `C:\Program Files\Git\bin`은 PATH에 없기 때문입니다. cmd냐 PowerShell이냐는 상관없이 똑같이 실패합니다.

"Git Bash를 쓰세요"라고 안내만 할 수도 있었지만, **쓰는 셸에서 그냥 되는 편이** 낫다고 봐서 `.cmd` 버전을 함께 뒀습니다.

</details>

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

**프로젝트 폴더(KeepCon)에서** 자기 셸에 맞는 줄을 실행하세요.

```bat
:: cmd
tool\emulators.cmd
```

```powershell
# PowerShell
.\tool\emulators.cmd
```

```bash
# Git Bash / macOS / Linux
bash tool/emulators.sh
```

아래 화면이 나오면 성공입니다. **이 터미널은 그대로 두세요** (닫으면 서버가 꺼집니다):

```text
✔  All emulators ready! It is now safe to connect your app.
   View Emulator UI at http://127.0.0.1:4000/
```

#### 터미널 B — 앱

**새 터미널을 열고**, 역시 프로젝트 폴더에서:

```bash
flutter run -d chrome
```

이 명령은 어느 셸에서든 똑같습니다. **플래그가 없는 게 맞습니다** — 기본이 터미널 A의 에뮬레이터입니다. (`--dart-define=USE_FIREBASE_EMULATOR=true` 를 붙여도 같습니다. 기본값이 나중에 바뀌어도 에뮬레이터를 고정하고 싶을 때 쓰세요.)

로그인 화면이 뜨면 아래 계정으로 들어가세요:

| 역할 | 이메일 | 비밀번호 |
|------|--------|----------|
| 방장 | `owner@keepcon.test` | `test1234` |
| 파티원 | `member@keepcon.test` | `test1234` |

두 계정은 **저장소에 미리 넣어둔 것**이라 팀원 모두가 똑같이 씁니다. 회원가입할 필요 없습니다. 기프티콘과 그룹('우리 가족')도 이미 들어 있습니다.

> 이 비밀번호는 테스트 전용입니다. 가짜 서버라 유출 위험은 없지만, **실제 계정에는 절대 쓰지 마세요.**

### 4-C. 팀 개발 서버 (터미널 1개)

팀원과 **같은 그룹에 들어가서** 공유 기능을 테스트할 때 씁니다. 서버를 띄울 필요가 없어 터미널 하나면 됩니다.

```bash
flutter run -d chrome --dart-define=USE_FIREBASE=true
```

로그인 화면이 뜨면 **회원가입부터 하세요.** 4-B의 공용 계정(`owner@keepcon.test` 등)은 에뮬레이터 전용이라 여기서는 안 됩니다. 이메일은 아무거나 써도 되지만, 팀원끼리 누가 누군지 알아볼 수 있게 정하면 편합니다.

**팀원과 같이 테스트하는 순서:**

1. 둘 다 위 명령으로 앱을 띄우고 각자 회원가입
2. 한 명이 공유 탭에서 **그룹 생성** → 초대코드를 팀원에게 전달
3. 다른 한 명이 그 코드로 **그룹 참여**
4. 한 명이 기프티콘을 그룹에 공유 → **상대 화면에 뜨는지 확인**
5. 상대가 사용 처리 → **원래 주인에게 알림·사용이력이 반영되는지 확인**

> ⚠️ **그룹 삭제·공유 취소 같은 파괴적 테스트는 여기서 하지 마세요.** 데이터가 팀 공유라 남이 쓰던 것도 함께 사라집니다. 그런 건 4-B(에뮬레이터)에서 하세요.
>
> 🧹 데이터가 지저분해지면 밀어버릴 수 있습니다 — `bash tool/reset_dev.sh` (cmd·PowerShell은 `tool\reset_dev.cmd`). Firestore 데이터만 지우고 **계정은 남으므로** 다시 회원가입할 필요는 없습니다.

---

## 5. 잘 됐는지 확인하는 법

**앱을 띄운 터미널의 로그**를 보면 어디에 붙었는지 알 수 있습니다:

| 로그 | 붙은 곳 |
|------|---------|
| (Firebase 관련 줄 없음) | 데모 모드(4-A) — 팀원과 공유 안 됨 |
| `KeepCon: Firebase 에뮬레이터 연결됨 (localhost — auth:9099, firestore:8080)` | 에뮬레이터(4-B) — 내 PC에만 있음 |
| `KeepCon: Firebase 연결됨 (dev — keepcon-dev)` | 팀 개발 서버(4-C) ✅ |
| `KeepCon: Firebase 연결됨 (prod — keepcon-ab660)` | **실서비스** — 의도한 게 아니면 즉시 끄세요 |

**"왜 팀원이 만든 그룹이 안 보이지?"** 싶을 때 여기부터 확인하세요. 플래그를 빠뜨리면 데모 모드로 뜨는데, 화면이 멀쩡히 나오고 로그인도 돼 있어서 알아채기 어렵습니다.

**http://localhost:4000** 을 브라우저로 열면 저장된 계정과 데이터를 눈으로 볼 수 있습니다. 앱에서 뭔가 만들면 여기에 바로 나타납니다.

### 끄는 법

두 터미널에서 각각 `Ctrl + C`. 순서는 상관없습니다.

---

## 6. 알아둘 것

**에뮬레이터에서 만든 데이터는 내 PC에 남습니다.** `Ctrl+C`로 끄면 `.emulator-local/`에 저장되고, 다음에 켜면 거기서 이어서 시작합니다. **내가 회원가입한 계정으로 계속 작업할 수 있습니다.** 이 폴더는 `.gitignore`에 있어 커밋되지 않으니 남의 저장소로 흘러가지 않습니다.

- 맨 처음 실행할 때만 커밋된 `emulator-seed/`(공용 계정)에서 시작합니다. 그 뒤로는 내 데이터입니다.
- **처음 상태로 되돌리려면** `bash tool/emulators.sh --fresh` (cmd는 `tool\emulators.cmd --fresh`). 파괴적 테스트로 데이터가 엉켰을 때 쓰세요.
- ⚠️ **반드시 `Ctrl+C`로 끄세요.** 터미널 창을 그냥 닫으면 저장 신호가 가지 않아 그 세션에서 만든 것이 사라집니다.

**`--dart-define`은 앱을 재시작해야 바뀝니다.** 실행 중에 `r`(핫 리로드)을 눌러도 백엔드는 안 바뀝니다. 모드를 바꾸려면 `Ctrl+C`로 끄고 다시 실행하세요.

**Android 실기기로 띄우려면** 기기를 USB로 연결하고 *개발자 옵션 › USB 디버깅*을 켠 뒤, `-d chrome`만 빼고 실행하면 됩니다. 별도 설정은 없습니다(dev·실서비스 모두 Android가 구성돼 있습니다):

```bash
flutter devices                                 # 기기가 목록에 보이는지 먼저 확인
flutter run --dart-define=USE_FIREBASE=true     # dev 서버에 붙어 실기기로 시연
```

**실기기 + 로컬 에뮬레이터 조합은 지원하지 않습니다.** `10.0.2.2` 자동 전환은 Android 스튜디오 에뮬레이터에만 해당하고, USB 실기기에는 그 주소가 없습니다. 사설 IP로 우회하려면 에뮬레이터 LAN 바인딩 · PC 방화벽 · cleartext HTTP 허용까지 전부 손봐야 하니, **실기기는 위처럼 dev 서버를 쓰세요.**

**iOS는 구성하지 않습니다.** 빌드·서명·실행이 전부 macOS + Xcode를 요구하는데 팀에 macOS가 없어, 검증할 수 없는 코드만 쌓이던 `ios/`를 2026-08-18에 걷어냈습니다. 실기기 시연은 Android로 합니다. 되살리는 절차는 [README](../README.md#연결된-firebase-프로젝트---둘-다-구성-완료)에 있습니다.

---

## 7. 막혔을 때

| 증상 | 원인과 해결 |
|------|------------|
| `bash: command not found` 또는 `WSL ... execvpe(/bin/bash) failed` | cmd/PowerShell에서 `.sh`를 실행한 것. 같은 폴더의 **`.cmd` 버전**을 쓰세요 (`tool\emulators.cmd`). 3번 항목 참고. |
| `Port 8080 is not open` / `Could not start Emulator UI, port taken` | 에뮬레이터가 이미 떠 있거나 다른 프로그램이 그 포트를 씀. 기존 터미널에서 `Ctrl+C`로 끄고 다시 시도하세요. 그래도 안 되면 PC를 재시작하는 게 빠릅니다. |
| 에뮬레이터가 뜨다 마는데 Java 얘기가 나옴 | Java 미설치. 1번 항목 참고. |
| 로그인 화면에서 계정이 안 먹음 | 시드가 안 올라온 것. 터미널 A 로그에 `Importing accounts from ...` 이 있는지 보세요. 없다면 **프로젝트 폴더가 아닌 곳**에서 실행했을 가능성이 큽니다. |
| 앱이 로그인 화면 없이 바로 목록으로 감 | `--dart-define=USE_DEMO=true` 로 뜬 것. 플래그를 빼면 에뮬레이터로 갑니다. |
| **"에뮬레이터가 떠 있지 않습니다"** 안내 화면이 뜸 | 터미널 A를 안 띄운 것. 화면에 적힌 명령을 그대로 실행하고 앱을 다시 실행하세요. |
| `flutter pub get` 에서 에러 | `flutter doctor` 로 Flutter 설치 상태부터 확인. 버전이 3.27 미만이면 업그레이드하세요. |

---

## 8. 다음 단계

앱이 떴다면 이제 작업을 시작할 수 있습니다. **코드를 고치기 전에** 아래를 읽어주세요:

- [README — 협업 규약](../README.md#-협업-규약-페이지별-담당--필독) — 브랜치·커밋·PR 규칙, 공유 계약(SSOT) 규칙
- [README — 프로젝트 구조](../README.md#-프로젝트-구조) — 어느 폴더가 무엇인지

특히 **작업 브랜치는 항상 최신 `develop`에서 따고**, `main`·`develop`에 직접 push하지 않는다는 두 가지는 먼저 알고 시작하는 게 좋습니다.
