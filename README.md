# KeepCon 🎁

흩어진 기프티콘을 한 곳에서 관리·보관하고, 그룹 공유로 가족·친구가 자유롭게 사용하도록 하는 Flutter 앱.

여러 앱에 흩어진 기프티콘을 한 번에 관리하고, 공유 기능으로 가족·친구끼리 함께 쓰는 것이 목표입니다.

---

## ✨ 주요 기능

| 영역 | 기능 |
|------|------|
| **홈(메인)** | 내 기프티콘 목록, 만료 임박 알림 배너, 요약 통계(보유중·만료임박·총금액), 정렬·필터, 검색 |
| **스캔·추가** | 카메라 스캔 · 갤러리 불러오기 · 직접 입력으로 기프티콘 등록 |
| **공유** *(프론트 구현 · 계약 소비)* | 그룹 관리(생성·참여·정보·소유권 이전), 멤버 초대(URL·코드·만료), 그룹 공유 기프티콘(잠김·찜·사용 동기화·회수), 사용 이력, 그룹 알림 |
| **로그인/설정** *(프론트 구현)* | 회원가입·로그인·비밀번호 찾기, 마이 페이지, 다크모드 등 설정 |

> 하단 내비게이션: **홈 / ＋(추가) / 공유**. 설정(다크모드 등)은 홈 우측 상단 톱니 아이콘 → 추후 '마이' 페이지로 확장.

---

## 🛠 기술 스택

- **Flutter** (Dart, Material 3) — 크로스플랫폼
- **Riverpod** (`flutter_riverpod`) — 상태 관리 (프로젝트 전역 표준)
- **Firebase** (`firebase_auth`, `cloud_firestore`) — 백엔드 데이터 계층 *(구현 완료. 로컬 에뮬레이터로 계정 없이 실행 가능 — [Firebase 연동](#-firebase-연동-백엔드-활성화))*
- 기본 실행은 **로컬 Firebase 에뮬레이터** — 계정·인터넷 없이 진짜 Firebase 동작으로 개발 (별도 터미널에서 에뮬레이터 기동 필요). 준비물 없이 바로 띄우려면 **in-memory mock**(`--dart-define=USE_DEMO=true`)

---

## 📁 프로젝트 구조

```text
lib/
├── main.dart                      # 앱 조립부(ProviderScope·테마·시드)
├── firebase_options.dart          # 실제 프로젝트(keepcon-ab660) 옵션 — flutterfire configure 생성물. 손으로 고치지 말 것
├── app/
│   └── keepcon_shell.dart         # 하단 내비 셸 (홈 / + / 공유)
├── shared/                        # ⭐ 공유 계약 (SSOT) — 모든 페이지가 참조 · CODEOWNERS 보호
│   ├── models/                    # User, Gifticon, Group/GroupMember, SharedGifticon, UsageLog, GroupNotification (+ enum·상태전이)
│   ├── repositories/              # AuthRepository, GifticonRepository, ShareRepository (abstract 인터페이스)
│   │   └── impl/                  # in_memory_* (USE_DEMO) · firebase/* (기본 — 에뮬레이터·dev·prod)
│   ├── providers/                 # repositories(DI), theme_mode_provider
│   ├── theme/                     # app_colors, app_theme (라이트/다크 ThemeData)
│   ├── util/                      # korean_particle(조사 유틸) 등 도메인 무관 범용 유틸
│   ├── firebase/                  # firebase_bootstrap (초기화·에뮬레이터 연결·override), demo_firebase_options(에뮬레이터 전용)
│   └── routes.dart                # named route 상수
└── features/                      # 페이지별 담당 영역 (공유 타입 재정의 금지 — SSOT guard가 차단)
    ├── auth/                      # 로그인·회원가입·비밀번호 찾기
    ├── mypage/                    # 마이 페이지(설정)
    ├── main/                      # 홈 (목록·정렬·필터·통계·카드)
    ├── scan/                      # 스캔·추가
    └── share/                     # 공유 (그룹·초대·공유 기프티콘·사용이력·알림) — lib/shared 계약 소비
```

> 공유(share) 도메인은 초기엔 페이지 내부에 하드코딩돼 있었으나 `lib/shared`로 **승격**되어 모든 페이지가 참조 가능합니다(PR #16~). 승격 이력은 [`CLAUDE.md`](CLAUDE.md) 변경 이력·`_workspace/02_share_contract_promotion.md` 참조.

---

## 🚀 시작하기

> 🔰 **처음이신가요?** 설치부터 로그인까지 순서대로 안내하는 **[로컬 실행 가이드](docs/GETTING_STARTED.md)** 를 보세요. 아래는 이미 환경이 갖춰진 분을 위한 요약입니다.

### 사전 준비
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.27 이상 (Dart 3.6+) — `Color.withValues()` 등 3.27+ API 사용
- 확인: `flutter doctor`
- *(에뮬레이터로 띄울 경우 추가)* Node.js 20+ (`npm i -g firebase-tools`), **Java 11+** — Firestore 에뮬레이터 구동용
- *(Android 기기로 띄울 경우 추가)* **JDK 17+** · Android SDK — 웹으로만 개발하면 필요 없습니다. [Android 기기로 띄우기](#-android-기기로-띄우기-실기기--avd) 참조

### 설치 (처음 한 번만)
```bash
git clone https://github.com/Jiwonang/KeepCon.git
cd KeepCon
flutter pub get
```

---

### 실행 방법

**터미널을 두 개 써야 하는 건 에뮬레이터 모드뿐입니다.** 나머지는 앱만 띄우면 됩니다.

| 모드 | 단계 |
|------|------|
| 데모 · **dev 서버** · 실서비스 | **앱 실행 한 번** → [flutter](#-flutter로-앱-실행-공통) |
| 에뮬레이터 | **① 에뮬레이터 기동**(쓰는 셸에 따라 다름 → [bash](#-bash로-실행-git-bash--macos--linux) · [cmd](#-cmd로-실행-windows)) → **② 앱 실행** |

어느 모드가 어떤 데이터를 쓰는지는 [flutter로 앱 실행](#-flutter로-앱-실행-공통)의 표를 보세요.

---

#### 🐧 bash로 실행 (Git Bash · macOS · Linux)

```bash
# 터미널 A — Firebase 에뮬레이터 (커밋된 시드 계정이 들어간 상태로 시작)
bash tool/emulators.sh

# 시드 계정을 바꿀 때만 (에뮬레이터가 떠 있는 상태에서)
bash tool/seed_emulator.sh

# 보안 규칙 검증
bash tool/verify_firestore_rules.sh
```

`All emulators ready!` 가 뜨면 **이 터미널은 그대로 두고**, 새 터미널에서 [flutter](#-flutter로-앱-실행-공통)로 앱을 띄웁니다.

---

#### 🪟 cmd로 실행 (Windows)

cmd·PowerShell에서 `bash`는 Git Bash가 아니라 **WSL**로 잡혀 실패합니다. 확장자만 다른 `.cmd` 버전을 쓰세요.

```bat
:: 터미널 A — Firebase 에뮬레이터
tool\emulators.cmd

:: 시드 계정을 바꿀 때만 (에뮬레이터가 떠 있는 상태에서)
tool\seed_emulator.cmd

:: 보안 규칙 검증
tool\verify_firestore_rules.cmd
```

PowerShell에서는 앞에 `.\`를 붙입니다 — `.\tool\emulators.cmd`

> `.sh` 를 그대로 쓰고 싶으면 Git Bash 터미널을 여세요(폴더 우클릭 → *Open Git Bash here*). 자세한 배경은 [로컬 실행 가이드 3번](docs/GETTING_STARTED.md#3-터미널은-편한-걸-쓰세요).

---

#### 💙 flutter로 앱 실행 (공통)

셸과 무관하게 동일합니다. **어떤 플래그를 붙이느냐에 따라 데이터가 어디에 저장되는지가 달라집니다.**

| 명령 | 데이터가 어디에 | 껐다 켜면 | 사전 준비 | 로그인 |
|------|----------------|-----------|-----------|--------|
| **`flutter run -d chrome`** (기본) | **내 PC**의 로컬 Firebase 에뮬레이터 | **남아 있음** (`.emulator-local/`) | **별도 터미널에서 에뮬레이터를 띄워둬야 함** | 처음엔 [공용 계정](#공용-테스트-계정-clone하면-바로-로그인), 이후 내가 만든 계정도 유지 |
| `… --dart-define=USE_FIREBASE=true` | **dev 서버** `keepcon-dev` — **팀 공유** | 남아 있음 | 없음 (인터넷 필요) | 각자 회원가입 |
| `… --dart-define=USE_FIREBASE_PROD=true` | 실서비스 `keepcon-ab660` | 남아 있음 | 없음 (인터넷 필요) | 각자 회원가입 |
| `… --dart-define=USE_DEMO=true` | **앱 메모리** (Firebase 미접속) | **사라짐** | 없음 | 이미 로그인된 상태로 시작 |

> ⚠️ **기본 실행에는 터미널이 2개 필요합니다.** 에뮬레이터는 자동으로 뜨지 않습니다 — 안 띄운 채 실행하면 앱이 **무엇을 해야 하는지 안내하는 화면**을 보여주고 멈춥니다. `Java`와 `Firebase CLI`가 필요합니다([준비물](#-1-준비물-설치)).
>
> **기본이 dev(팀 공유)가 아니라 에뮬레이터인 이유** — 기본값은 "아무것도 정하지 않았을 때 일어나는 일"이고 그건 대개 실수입니다. 그룹 삭제·공유 취소 같은 파괴적 테스트를 하려다 플래그를 깜빡하면 **남의 작업이 함께 사라집니다**(Firestore에는 롤백이 없습니다). 그래서 기본은 남의 데이터에 닿을 수 없는 쪽으로 둡니다. 팀 공유가 필요한 순간에는 **의도해서** 플래그를 붙이세요.

```bash
# 터미널 A — 에뮬레이터를 먼저 띄운다 (cmd·PowerShell은 tool\emulators.cmd)
bash tool/emulators.sh

# 터미널 B — 기본 실행. 플래그 없이 위 에뮬레이터에 붙는다
flutter run -d chrome

# dev 서버 — 팀원과 같은 그룹에 들어가는 공유 시나리오 테스트 (화면에 '공유 dev' 배지)
flutter run -d chrome --dart-define=USE_FIREBASE=true

# 실서비스 — 시연·배포 확인 전용 (화면에 '실서비스' 배지)
flutter run -d chrome --dart-define=USE_FIREBASE_PROD=true

# 데모 — 백엔드 없이 즉시 실행. 화면·UI 작업용(그룹 공유는 검증 불가)
flutter run -d chrome --dart-define=USE_DEMO=true

# 실기기(Android·iOS) — 기기를 연결하고 `-d chrome` 만 빼면 된다.
# Android는 개발자 옵션 > USB 디버깅, iOS는 Xcode에서 서명 팀 설정이 먼저 필요하다.
flutter devices                                   # 기기가 보이는지 먼저 확인
flutter run --dart-define=USE_FIREBASE=true       # dev 서버에 붙어 실기기 데모
```

> **dev·실서비스 모두 Android·iOS가 구성돼 있습니다**(패키지명·번들 id 둘 다 `com.keepcon.app`).
>
> 📱 **Android가 처음이면** JDK·SDK 준비부터 필요합니다 → [Android 기기로 띄우기](#-android-기기로-띄우기-실기기--avd).
>
> ⚠️ **iOS는 macOS + Xcode에서만 빌드됩니다.** Windows에서는 `flutter run`이 iOS 기기를 아예 보지 못합니다. macOS에서 처음 열 때 Xcode › Runner › Signing & Capabilities에서 **개인 Apple ID로 팀을 지정**해야 실기기에 설치됩니다(무료 계정도 7일짜리 프로비저닝으로 설치는 됩니다).
>
> ⚠️ **실기기 + 로컬 에뮬레이터 조합은 지원하지 않습니다.** `10.0.2.2` 자동 전환은 Android 스튜디오 에뮬레이터 전용이라 USB 실기기에서는 닿지 않고, 사설 IP로 우회하려면 에뮬레이터 LAN 바인딩(`firebase.json`의 `host`) · 방화벽 인바운드 허용 · cleartext HTTP 허용(`networkSecurityConfig`)까지 전부 손봐야 합니다. **실기기는 dev 서버(`USE_FIREBASE=true`)를 쓰세요** — 설정이 필요 없습니다.
>
> ⚠️ **팀원 그룹이 안 보인다면 플래그를 확인하세요.** 기본 실행은 **내 PC 에뮬레이터**라, 팀원이 만든 그룹은 보이지 않는 게 정상입니다(각자 PC에 격리돼 있습니다). 같은 그룹에 들어가려면 양쪽 다 `--dart-define=USE_FIREBASE=true` 로 띄워야 합니다. 어디에 붙었는지는 **화면 배지**와 아래 콘솔 출력으로 확인하세요.

**어디에 붙었는지는 콘솔에 찍힙니다** — 헤매기 전에 여기부터 보세요:

| 콘솔 출력 | 붙은 곳 |
|-----------|---------|
| (Firebase 관련 줄 없음) | 데모 모드 — **팀 공유 안 됨** |
| `KeepCon: Firebase 에뮬레이터 연결됨 …` | 내 PC 에뮬레이터 — **팀 공유 안 됨** |
| `KeepCon: Firebase 연결됨 (dev — keepcon-dev)` | dev 서버 ✅ |
| `KeepCon: Firebase 연결됨 (prod — keepcon-ab660)` | **실서비스** — 의도한 게 아니면 즉시 중단 |

> ⚠️ `--dart-define` 은 컴파일 시점에 적용됩니다. 실행 중 `r`(핫 리로드)로는 안 바뀌니, 모드를 바꾸려면 `Ctrl+C` 후 다시 실행하세요.

---

### 📱 Android 기기로 띄우기 (실기기 · AVD)

웹으로만 개발한다면 이 절은 건너뛰세요. Android로 띄울 때만 필요합니다.

#### 준비물

| 항목 | 버전 | 왜 |
|------|------|-----|
| **JDK** | **17 이상** | Android 빌드가 Java 17을 타깃합니다([`android/app/build.gradle.kts`](android/app/build.gradle.kts)의 `jvmTarget = JVM_17`). 21도 됩니다 |
| **Android SDK** | Platform 35 · Platform-Tools · Command-line Tools | `flutter doctor`의 *Android toolchain* 항목이 검사합니다 |
| **Android Emulator + 시스템 이미지** | AVD로 띄울 때만 | 실기기만 쓸 거면 설치하지 마세요(수 GB 절약) |

> ⚠️ **에뮬레이터용 `Java 11+` 와 Android 빌드용 `JDK 17+` 는 별개입니다.** 위 사전 준비의 "Java 11+"만 보고 딱 11을 설치하면 **에뮬레이터는 뜨는데 `flutter run`이 Gradle에서 실패합니다.** Android도 하실 거면 처음부터 17 이상을 설치하세요.

#### Android SDK 위치 — `%LOCALAPPDATA%` 아래는 피하세요

Windows에서 SDK를 기본 위치인 `%LOCALAPPDATA%\Android\Sdk`에 두면, 패키지 앱(MSIX)에서 실행한 도구가 그 경로를 **자기 컨테이너 안쪽으로 리디렉션**해 설치하는 일이 있습니다. 그러면 그 도구 안에서는 멀쩡히 보이는데 **일반 터미널·Android Studio에서는 같은 경로가 비어 있어서** `flutter doctor`가 이렇게 나옵니다:

```
[X] Android toolchain - develop for Android devices
    X ANDROID_HOME = C:\Users\<사용자>\AppData\Local\Android\Sdk
      but Android SDK not found at this location.
```

**AppData 바깥에 두면 이 문제가 생기지 않습니다.** Android Studio → Settings → Languages & Frameworks → Android SDK 에서 *Android SDK Location* 을 `C:\Android\Sdk` 같은 경로로 지정하고, 환경 변수를 영구 등록하세요(cmd):

```bash
setx ANDROID_HOME "C:\Android\Sdk"
```

```bash
setx ANDROID_SDK_ROOT "C:\Android\Sdk"
```

> `setx` 는 **현재 창에는 적용되지 않습니다** — 실행한 뒤 터미널을 새로 여세요.
> `setx PATH ...` 는 쓰지 마세요. PATH가 1024자에서 잘려 나갑니다(PATH 편집은 시스템 속성 GUI에서). `flutter` 는 `ANDROID_HOME` 만 있으면 `adb` 를 찾습니다.

새 창에서 `flutter doctor` 의 *Android toolchain* 이 ✓ 면 준비 끝입니다.

> *Visual Studio not installed* 는 **무시하세요.** Windows **데스크톱** 앱 빌드용이고 KeepCon은 web·android·ios만 구성돼 있습니다. 이름이 비슷할 뿐 VS Code와는 무관합니다.

#### 실기기로 띄우기

1. 폰: 설정 → 휴대전화 정보 → **빌드번호 7번 연타** → 개발자 옵션 활성화
2. 개발자 옵션 → **USB 디버깅** 켜기
3. USB 연결 → 폰에 뜨는 **"USB 디버깅을 허용하시겠습니까?"** 허용 (USB 모드는 충전이 아니라 **파일 전송(MTP)**)

```bash
flutter devices                                # 폰 모델명이 보이는지 먼저 확인
flutter run --dart-define=USE_FIREBASE=true    # 실기기는 로컬 에뮬레이터에 못 붙습니다 → dev 서버
```

| 증상 | 원인 |
|------|------|
| `flutter devices` 에 폰이 안 보임 | 충전 전용 케이블일 수 있습니다. 데이터 케이블로 바꾸고 `adb devices` 로 재확인 |
| `adb devices` 가 `unauthorized` | 폰의 허용 팝업을 놓친 것. 케이블을 뽑았다 다시 꽂으세요 |

#### AVD(가상 기기)로 띄우기

실기기와 달리 **로컬 에뮬레이터에 그대로 붙습니다** — `resolveEmulatorHost()` 가 호스트 PC를 `10.0.2.2` 로 자동 전환하기 때문입니다. 그룹 삭제·공유 취소 같은 **파괴적 테스트는 이쪽에서** 하세요.

Android Studio → Device Manager → Create Device 로 만들거나, cmd에서:

```bash
"%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" "emulator" "system-images;android-35;google_apis;x86_64"
```

```bash
"%ANDROID_HOME%\cmdline-tools\latest\bin\avdmanager.bat" create avd -n keepcon_pixel -k "system-images;android-35;google_apis;x86_64" -d pixel_7
```

```bash
flutter emulators --launch keepcon_pixel
flutter run                                    # 플래그 없음 = 로컬 에뮬레이터
```

> 터미널 A에서 `tool\emulators.cmd` 로 Firebase 에뮬레이터를 먼저 띄워 두어야 합니다 — 안 띄우면 안내 화면에서 멈춥니다.

---

## 🤝 협업 규약 (페이지별 담당 — 필독)

4개 페이지(로그인/설정·메인·스캔·공유)를 **담당자별로 나눠 병렬 개발**합니다. 페이지 간 연동 버그(중복 구현·잘못된 함수명·값 불일치)를 막기 위해 아래를 반드시 지킵니다.

- 공유 모델·인터페이스·enum·라우트·**테마**는 `lib/shared/`의 **단일 정의만** 사용합니다. 페이지 내부 재정의 금지. → CI의 **`SSOT guard`**(`tool/check_ssot.sh`)가 `lib/features`에서의 공유 타입·provider 재정의를 자동 차단합니다(문서 지침이 아니라 CI 게이트로 강제).
- Repository 메서드는 계약에 적힌 **이름·파라미터 그대로** 호출합니다(추측 호출 금지).
- 상태/정렬/필터는 매직 스트링이 아니라 **계약의 enum**을 사용합니다.
- 색상·폰트·모양은 하드코딩하지 말고 `Theme.of(context)` **테마 토큰**을 소비합니다.
- **필드 승격 워크플로** — 다른 페이지에도 필요할 필드가 새로 생기면:
  1. **재사용 우선** — 만들기 전에 `lib/shared`를 검색하고, 이미 있으면 그대로 소비합니다(로컬 유사 필드 신설 금지).
  2. **승격은 요청으로** — 없고 둘 이상 페이지가 쓸 것 같으면 직접 `lib/shared`를 고치지 말고 `contract-architect`(계약 소유자)에게 요청합니다. 계약 파일은 **[`CODEOWNERS`](.github/CODEOWNERS)로 소유자 리뷰가 강제**되어 페이지 담당의 임의 수정은 머지되지 않습니다.
  3. **늦게 승격** — "혹시 필요할까"가 아니라 실제 두 번째 소비자가 생겼을 때 승격합니다(공유는 빼기·이름변경이 전부 breaking이므로 투기적 승격 금지).

**설정도 SSOT:** `CLAUDE.md`·`.claude/agents`·`.claude/skills`는 저장소 루트에 **한 벌만** 두고 하위 폴더에 복제하지 않습니다(Claude Code가 상위 `CLAUDE.md`를 자동 상속). 규칙도 데이터처럼 한 곳에 둡니다.

> 계약의 소비/생산 관계와 크로스페이지 주의점은 [`_workspace/01_contract_dependency_matrix.md`](_workspace/01_contract_dependency_matrix.md) 참조.

### 브랜치 전략

- **기본 브랜치:** `develop` — 모든 작업 머지 대상
- **통합 브랜치:** `main` — 배포 시점에 `develop → main` squash 병합
- **작업 브랜치:** `{type}/{설명}` (예: `feat/be-me-clubs-and-application-scope`, `fix/calendar-month-nav-and-resize`)
- **API 1개 / 페이지 1개 = 브랜치 1개 = PR 1개** 원칙
- 모든 작업 브랜치는 `develop`에서 분기하고, `develop`으로 PR을 올립니다. `main`·`develop`에 직접 push하지 않습니다.

**최신화 (오래된 코드에서 작업 방지):**

- **새 작업 시작 시:** `git checkout develop && git pull --ff-only`로 develop을 최신화한 **뒤에** 분기합니다. 오래된 develop에서 브랜치를 파면 처음부터 뒤처집니다.
- **기존 브랜치 이어서 작업 시:** `git pull`을 습관적으로 치지 마세요. `git fetch`(다운로드만, 작업 파일·현재 브랜치 안 건드림)는 언제나 안전하니 자주 확인하고, develop 반영은 **커밋해 둔 깨끗한 지점에서만** `git merge origin/develop`으로 합니다. 더티(변경사항 있는) 상태에서 `git pull` 금지.
- **자동 경고:** [`.claude/settings.json`](.claude/settings.json)의 `SessionStart` 훅이 세션 시작 시 자동으로 `git fetch` 후 현재 브랜치·로컬 `develop`이 origin보다 뒤처졌으면 경고합니다(git 커밋으로 팀 공유 · Git Bash 필요). 경고가 뜨면 작업 전 최신화하세요.

### 커밋 / PR

- **커밋 메시지: Conventional Commits (한국어)**
  `feat(backend): …` · `fix(frontend): …` · `refactor(…): …` · `docs(spec): …` · `ci: …` · `perf(frontend): …`
- **PR 본문 템플릿** — [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md)가 PR 작성 시 자동 적용됩니다:
  - 🚀 작업 내용
  - 🤔 고민했던 내용
  - 💬 리뷰 중점사항
- 병합 전 `flutter analyze` 통과를 확인합니다.

> AI(Claude Code)로 작업하는 팀원도 위 규칙을 따르도록, 동일 내용을 자동 로드되는 [`CLAUDE.md`](CLAUDE.md)에도 명시해 두었습니다.

### 브랜치 보호 규칙 (저장소 소유자 설정)

문서/CLAUDE.md는 "지침"일 뿐, 직접 push를 물리적으로 막지는 않습니다. `main`·`develop` 직접 push를 차단하고 **PR + CI 통과**를 강제하려면 아래 브랜치 보호를 설정합니다.

> ✅ **적용됨:** 저장소가 **Public**이라 `protect-main-develop` Ruleset이 **활성(active)** 상태로 적용돼 있습니다 — `main`·`develop` 직접 push·삭제·강제 push 차단 + PR 필수 + `Format · Analyze · Test` 통과 필수(승인 0건, 솔로 셀프 머지 허용). 아래는 재현·수정용 참고 설정입니다.

**방법 A — GitHub UI (Rulesets)**
1. 저장소 → **Settings → Rules → Rulesets → New ruleset → New branch ruleset**
2. **Ruleset Name**: `protect-main-develop`, **Enforcement status**: `Active`
3. **Target branches → Add target → Include by pattern**: `main`, `develop` 두 개 추가
4. **Rules** 체크:
   - ✅ Restrict deletions (브랜치 삭제 금지)
   - ✅ Block force pushes (강제 push 금지)
   - ✅ Require a pull request before merging (직접 push 금지 → PR 필수. 승인 수는 솔로면 0, 팀이면 1건 이상)
   - ✅ Require status checks to pass → 검색해서 **`Format · Analyze · Test`** 추가, "Require branches to be up to date" 체크
5. **Create**

**방법 B — `gh` CLI (프로그램적 설정)**

아래 JSON을 `ruleset.json`으로 저장하고 소유자 계정으로 실행합니다:
```json
{
  "name": "protect-main-develop",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main", "refs/heads/develop"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": { "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false, "require_code_owner_review": false, "require_last_push_approval": false, "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": { "strict_required_status_checks_policy": true, "required_status_checks": [ { "context": "Format · Analyze · Test" } ] } }
  ]
}
```
```bash
gh api -X POST repos/Jiwonang/KeepCon/rulesets --input ruleset.json
```

> 설정 후에는 `main`·`develop`에 직접 push가 거부되고, PR은 CI(`Format · Analyze · Test`)가 통과해야 병합할 수 있습니다. (필요 시 승인 수는 팀 규모에 맞게 조정)

**추가 하드 백스톱 (권장 — soft 규칙을 강제로 전환):** 아래를 켜면 문서 규칙이 "지침"에서 "강제"가 됩니다.

- 룰셋 → **Require review from Code Owners** — [`CODEOWNERS`](.github/CODEOWNERS)에 지정된 계약 소유자 리뷰 없이는 `lib/shared`·하네스 설정 변경을 머지 불가(페이지 담당의 계약 임의 수정 차단).
- 룰셋 → **Require branches to be up to date before merging** — 오래된 브랜치는 최신화 전까지 머지 차단(스테일 머지 방지).
- 룰셋 → 필수 상태 체크에 **`CodeRabbit / Review`** 추가 — 자동 리뷰가 붙지 않은 PR 머지 차단.
- 룰셋 → **Do not allow bypassing the above settings**(admin 포함) — 규칙의 뿌리를 admin 우회로부터 보호.
- Settings → Code security → **Secret scanning + Push protection**(Public 무료) — 비밀정보가 포함된 push를 서버가 거부(`.gitignore`는 게이트가 아니므로 이게 진짜 백스톱).

### 코드 리뷰 정책

세 층으로 품질을 관리합니다 (층위가 서로 달라 **중첩 운영**):

- **CI 게이트 (필수·자동):** 모든 PR에서 `Format · Analyze · Test`(**SSOT guard** · dart format · flutter analyze · flutter test) 통과 — 안정성의 기반. `SSOT guard`([`tool/check_ssot.sh`](tool/check_ssot.sh))는 `lib/features`에서 공유 계약 타입·provider를 재정의/재선언하면 실패시켜 SSOT를 기계적으로 강제합니다.
- **자동 AI 리뷰 — CodeRabbit (자동):** App이 저장소에 연결돼 있으면 PR이 열리거나 갱신될 때 CodeRabbit이 협업 규칙 준수·버그를 자동 리뷰합니다. 리뷰 설정은 [`.coderabbit.yaml`](.coderabbit.yaml)에 한국어로 정의(별도 API 키·워크플로 불필요). **단, 설정 파일만으로는 동작하지 않는다** — CodeRabbit은 **GitHub App**이라 저장소에 설치·접근 허용되어야 리뷰가 붙습니다.
  - **활성화(1회, 소유자):** [github.com/settings/installations](https://github.com/settings/installations) → CodeRabbit → *Configure* → *Repository access*에 `Jiwonang/KeepCon` 추가(*All repositories*도 가능). 계정에 아직 App이 없으면 [github.com/apps/coderabbitai](https://github.com/apps/coderabbitai)에서 설치.
  - **비용:** **Public 저장소는 무료**, Private는 유료(Pro)·무료 체험. KeepCon은 Public이라 App 범위에만 추가하면 무료로 동작합니다. (동작 여부=App 접근 범위, 비용=공개여부 — 별개.)
- **커밋 전 AI 리뷰 — `/code-review` (온디맨드):** Claude Code로 작업할 때 **커밋 전** 변경 diff를 리뷰·수정한 뒤 커밋. 릴리스 전 `/security-review`로 보안 점검.

---

## 🎨 디자인 시스템

- **기본 = 라이트(화이트) 모드**, 다크모드는 설정에서 토글 (`themeModeProvider`)
- 색/타이포/모양은 `lib/shared/theme/`의 SSOT(`AppTheme.light` / `AppTheme.dark`)에 정의
- 페이지는 테마 토큰만 소비 → 테마를 바꾸면 전 페이지에 즉시 반영
- 디자인 토큰·레퍼런스: [`_workspace/design/behance_style_tokens.md`](_workspace/design/behance_style_tokens.md)

---

## 🔥 Firebase 연동 (백엔드 활성화)

백엔드는 **실행 시점에** dart-define으로 고릅니다. 인터페이스(`AuthRepository`/`GifticonRepository`/`ShareRepository`)는 그대로 두고 구현만 갈아끼우는 구조라, 어느 경로든 **페이지 코드는 한 줄도 바뀌지 않습니다.**

| 경로 | 실행 | 언제 쓰나 |
|------|------|-----------|
| in-memory 데모 | `flutter run --dart-define=USE_DEMO=true` | 화면·UI 작업. 시드 데이터로 즉시 시연 |
| Firebase 에뮬레이터 | `flutter run` (기본 — 플래그 불필요) | 혼자 하는 작업, **파괴적 테스트**, 보안 규칙 검증 |
| **dev 프로젝트** (`keepcon-dev`) | `flutter run --dart-define=USE_FIREBASE=true` | **팀 개발 기본** — 여럿이 같은 그룹에 들어가는 공유 시나리오 |
| 실서비스 (`keepcon-ab660`) | `flutter run --dart-define=USE_FIREBASE_PROD=true` | 시연·배포 확인 **전용** |

### 에뮬레이터와 dev 프로젝트는 대체재가 아닙니다

둘 다 필요하고, 쓰는 목적이 다릅니다.

**dev 프로젝트가 필요한 이유 — 에뮬레이터로는 팀원과 같은 그룹에 들어갈 수 없습니다.** 에뮬레이터는 각자 PC에 격리돼 있어서, KeepCon의 핵심인 그룹 공유(A가 공유 → B에게 보임 → B가 사용 → A에게 알림)를 **진짜 두 사람으로** 검증할 방법이 없습니다. 한 PC에서 계정 두 개로 번갈아 로그인하는 흉내만 낼 수 있습니다. 공유 백엔드가 있어야 하고, 그게 `keepcon-dev`입니다.

**에뮬레이터가 여전히 필요한 이유 — 실서버에는 롤백이 없습니다.** Firestore에는 브랜치도 되돌리기도 없어서, dev에서 "그룹 삭제"를 테스트하면 남이 쓰던 데이터도 같이 사라집니다. 그래서 **파괴적 테스트와 보안 규칙 검증은 에뮬레이터에서** 합니다(`tool/verify_firestore_rules.sh`도 에뮬레이터 전용입니다). 인터넷이 없거나 할당량을 아끼고 싶을 때도 에뮬레이터입니다.

| | 에뮬레이터 | dev 프로젝트 |
|---|---|---|
| 팀원과 같은 그룹 | ❌ 불가 | ✅ |
| 파괴적 테스트 | ✅ 자유 | ⚠️ 남의 데이터도 날아감 |
| 데이터 지속 | ✅ 내 PC에 유지(`.emulator-local/`) | ✅ 서버에 유지 |
| 리셋 | `tool/emulators.sh --fresh` | `tool/reset_dev.sh` |
| 시드 계정 | ✅ 커밋돼 있음 | ❌ 각자 회원가입 |
| 오프라인 | ✅ | ❌ |

**왜 dev와 실서비스를 나눴나.** 하나로 쓰면 시연 직전에 테스트 쓰레기를 손으로 치워야 하고, 실수로 지운 게 시연 데이터일 수 있습니다. dev는 언제든 통째로 밀어도 되니 그 부담이 사라집니다. 플래그도 `USE_FIREBASE`(dev)와 `USE_FIREBASE_PROD`(실서비스)로 분리해서, 오타 한 번에 실서비스가 열리지 않게 했습니다. 여러 플래그를 같이 넘기면 **안전한 쪽(에뮬레이터 > dev > 실서비스)이 이깁니다**.

### dev 프로젝트로 팀 개발하기

```bash
flutter run -d chrome --dart-define=USE_FIREBASE=true
```

- **시드가 없습니다.** 각자 회원가입부터 해야 합니다(에뮬레이터의 `owner@keepcon.test` 같은 공용 계정이 없습니다). 그룹 공유를 테스트하려면 한 명이 그룹을 만들고 초대코드를 팀에 공유하세요.
- **데이터가 지저분해지면 밀어버리세요.** `bash tool/reset_dev.sh` (cmd·PowerShell은 `tool\reset_dev.cmd`). Firestore 데이터만 지우고 **Auth 계정은 남기므로** 다시 회원가입할 필요는 없습니다. 실서비스 프로젝트에는 동작하지 않도록 스크립트에 하드코딩돼 있습니다.
- **파괴적 테스트는 여기서 하지 마세요.** 그룹 삭제·공유 취소처럼 남의 작업을 날릴 수 있는 건 에뮬레이터에서 확인하고 오세요.
- 앱 콘솔에 `KeepCon: Firebase 연결됨 (dev — keepcon-dev)` 가 찍힙니다. **`prod`라고 찍히면 즉시 중단하세요.**
- 요금제는 **Spark(무료)** 입니다. 할당량을 넘기면 청구서 대신 그날 요청이 멈추므로 비용 사고는 나지 않지만, 리스너 루프 버그가 있으면 팀 전체가 하루 막힙니다.

### 에뮬레이터로 실행하기

실행 명령은 **[시작하기 › 실행 방법](#실행-방법)** 에 셸별로 정리돼 있습니다(bash · cmd · flutter). 여기서는 알아둘 점만 적습니다.

- 준비물: **Java 11+** (Firestore 에뮬레이터가 Java로 동작), **Firebase CLI** (`npm i -g firebase-tools`)
- 포트: Auth `9099` · Firestore `8080` · **Emulator UI `http://localhost:4000`**
- 앱 콘솔에 `KeepCon: Firebase 에뮬레이터 연결됨 …` 이 찍히면 연결된 것입니다.
- 저장된 계정·문서는 Emulator UI에서 눈으로 확인할 수 있고, 앱에서 만든 데이터가 즉시 반영됩니다.
- **내가 만든 계정·데이터는 내 PC에 유지됩니다.** `Ctrl+C`로 끄면 `.emulator-local/`(gitignore)에 저장되고 다음 실행 때 이어서 시작합니다 — 매번 회원가입할 필요가 없습니다. 맨 처음 한 번만 커밋된 `emulator-seed/`(공용 계정)에서 시작합니다.
  - 처음 상태로 되돌리기: `bash tool/emulators.sh --fresh` (cmd는 `tool\emulators.cmd --fresh`)
  - ⚠️ **`Ctrl+C`로 끄세요.** 창을 그냥 닫으면 저장 신호가 가지 않아 그 세션 데이터가 사라집니다.
  - 커밋된 `emulator-seed/`는 이 저장에 **영향받지 않습니다** — 내보내는 곳이 개인 폴더로 분리돼 있습니다. 시드를 바꾸려면 `tool/seed_emulator.sh`를 의도적으로 실행하세요.
- Android에서는 접속 호스트가 `10.0.2.2`로 자동 전환됩니다(`resolveEmulatorHost()`). 단 **이 주소는 Android 스튜디오 에뮬레이터에서만 호스트 PC를 가리킵니다** — USB로 연결한 실기기에서는 닿지 않습니다. **실기기는 로컬 에뮬레이터 대신 dev 서버를 쓰세요**(사설 IP 우회는 LAN 바인딩·방화벽·cleartext 허용까지 필요해 권하지 않습니다).
- 프로젝트 id `demo-keepcon`의 **`demo-` 접두사**는 "에뮬레이터 전용"이라는 Firebase 규약입니다 — 실제 Google 백엔드로 나가는 요청이 차단되므로, `lib/shared/firebase/demo_firebase_options.dart`의 더미 키는 노출될 비밀이 아닙니다.
- ⚠️ Firestore가 **8080 포트**를 씁니다. 로컬 웹 서버를 띄울 때 이 포트를 피하세요.
- ⚠️ **맨손으로 `firebase emulators:start`를 치지 마세요.** [`.firebaserc`](.firebaserc)의 `default`는 `keepcon-dev`라, 프로젝트를 지정하지 않으면 에뮬레이터가 그 id로 뜹니다(로컬이라 실제 데이터가 손상되지는 않지만 시드 import가 어긋납니다). `tool/emulators.sh`·`tool\emulators.cmd`는 `--project demo-keepcon`을 명시하므로 안전합니다 — **항상 이 스크립트로 띄우세요.** 직접 치겠다면 `firebase emulators:start -P emulator`.
- ℹ️ `.firebaserc`의 `default`를 실서비스가 아니라 **`keepcon-dev`로 둔 것은 의도적입니다** — 맨손 `firebase deploy`가 실서비스로 나가지 않게 하기 위해서입니다. 실서비스에 배포할 때는 `-P prod`(또는 `--project keepcon-ab660`)를 반드시 명시하세요.

### 공용 테스트 계정 (clone하면 바로 로그인)

에뮬레이터를 띄우면([bash](#-bash로-실행-git-bash--macos--linux) · [cmd](#-cmd로-실행-windows)) [`emulator-seed/`](emulator-seed)에 커밋된 계정과 그룹이 **이미 들어 있는 상태**로 시작합니다. 각자 회원가입할 필요가 없고, 팀원 전원이 **같은 uid**를 쓰므로 방장/파티원 권한 시나리오를 그대로 공유할 수 있습니다.

| 역할 | 이메일 | 비밀번호 |
|------|--------|----------|
| 방장 | `owner@keepcon.test` | `test1234` |
| 파티원 | `member@keepcon.test` | `test1234` |

두 계정이 함께 속한 그룹과 기프티콘도 들어 있습니다 — 로그인하자마자 목록·공유 화면이 **채워진 상태**로 뜹니다.

| 그룹 | 문서 id | 초대코드 | 멤버 |
|------|---------|----------|------|
| 우리 가족 👪 | `seed-group-family` | `482913` | 방장(owner) · 파티원(member) |

| 기프티콘 | 소유자 | 상태 | 그룹 공유 |
|----------|--------|------|-----------|
| 스타벅스 아메리카노 T | 방장 | 사용 가능 (만료임박) | ✅ |
| BBQ 황금올리브 치킨 | 방장 | 사용 가능 (여유) | — |
| CU 도시락 교환권 | 방장 | **만료됨** | — |
| 배스킨라빈스 파인트 아이스크림 | 파티원 | 사용 가능 | ✅ |

만료임박·여유·만료를 섞어 둬서 D-day 뱃지와 정렬·필터를 바로 확인할 수 있습니다. 유효기간은 **시드를 만든 시점 기준 상대 날짜**라, 시간이 지나 날짜가 어긋나면 시드 재생성 스크립트를 다시 돌려 갱신하세요(아래 참고).

- 위 시드 계정은 **맨 처음 실행할 때** 들어옵니다. 그 뒤로 만든 데이터는 `Ctrl+C` 종료 시 개인 폴더 `.emulator-local/`에 저장되고 다음 실행 때 이어집니다 — **커밋된 `emulator-seed/`는 덮어쓰지 않습니다**(내보내는 곳이 분리돼 있습니다). 시드 상태로 되돌리려면 `bash tool/emulators.sh --fresh`.
- 시드 자체를 바꾸려면(계정 추가 등) 에뮬레이터가 떠 있는 상태에서 `bash tool/seed_emulator.sh`(cmd·PowerShell은 `tool\seed_emulator.cmd`)를 실행하고 `emulator-seed/`를 커밋하세요.
- ⚠️ 이 비밀번호는 공개 저장소에 그대로 적힌 **테스트 전용 값**입니다. 에뮬레이터는 실제 Google 백엔드와 연결되지 않으므로 노출 위험이 없지만, **실제 계정에는 절대 재사용하지 마세요.**

### 보안 규칙 검증

`firestore.rules`는 배포 전까지 실행되지 않는 문서일 뿐이라, 에뮬레이터에 실제로 태워서 확인합니다:

```bash
# 에뮬레이터가 떠 있는 상태에서 — bash
bash tool/verify_firestore_rules.sh
```
```bat
:: cmd·PowerShell
tool\verify_firestore_rules.cmd
```

실제 사용자 두 명을 Auth 에뮬레이터에 만들고 그 토큰으로 Firestore에 요청해, 남의 기프티콘 조회·`ownerId` 위조·비멤버의 그룹 조회가 **실제로 차단되는지** 확인합니다.

### 연결된 Firebase 프로젝트 — ✅ 둘 다 구성 완료

**추가 설정이 필요 없습니다.** 두 옵션 파일이 실제 값으로 커밋돼 있으므로 clone 후 바로 실행하면 됩니다.

| | **dev** (팀 개발) | **실서비스** (시연·배포) |
|---|---|---|
| 프로젝트 id | `keepcon-dev` ([콘솔](https://console.firebase.google.com/project/keepcon-dev/overview)) | `keepcon-ab660` ([콘솔](https://console.firebase.google.com/project/keepcon-ab660/overview)) |
| 실행 플래그 | `--dart-define=USE_FIREBASE=true` | `--dart-define=USE_FIREBASE_PROD=true` |
| 옵션 파일 | [`lib/firebase_options_dev.dart`](lib/firebase_options_dev.dart) | [`lib/firebase_options.dart`](lib/firebase_options.dart) |
| 데이터 | 팀 공유. 언제든 밀어도 됨 | 실서비스. 함부로 건드리지 말 것 |
| 리셋 | `tool/reset_dev.sh` | 없음 (의도적) |

두 프로젝트 모두 Firestore `(default)` · **Standard** 에디션 · **Native** 모드 · `asia-northeast3`(서울)이고, [`firestore.rules`](firestore.rules) · [`firestore.indexes.json`](firestore.indexes.json)이 배포돼 있습니다. 구성된 플랫폼은 **web · android · ios** 입니다(Android 패키지명·iOS 번들 id 모두 `com.keepcon.app`). 데스크톱(windows·macos·linux)은 미구성입니다.

#### `flutterfire configure`를 다시 돌려야 할 때

**언제 돌려야 하는지부터**가 중요합니다. 플랫폼을 추가할 때 말고도, **패키지명·번들 id를 바꾸는 PR이 머지되면 그때 열려 있던 브랜치는 전부 다시 돌려야 합니다.**

> ⚠️ **실제로 겪은 사고입니다.** `applicationId`를 `com.example.keepcon` → `com.keepcon.app`으로 바꾼 PR이 머지되기 27분 전에 다른 브랜치가 `configure`를 돌렸습니다(그 시점엔 옛 이름이 정상 값이라 CLI가 그 이름으로 **Firebase에 Android 앱을 새로 등록**). 이후 그 브랜치가 develop을 머지해 `build.gradle.kts`는 새 이름이 됐지만, **거기서 생성되는 `firebase_options_dev.dart`는 재생성하지 않아** 옛 앱을 가리킨 채 머지됐습니다. 소스와 생성물이 **서로 다른 파일이라 git 충돌도 나지 않습니다** — 사람이 알고 챙기지 않으면 아무도 못 봅니다. `keepcon-dev`에 남아 있는 중복 Android 앱이 그 흔적입니다.

**프로젝트가 둘이라 명령도 둘입니다.** 아래 플래그를 **매번 전부** 넘기세요. 하나라도 빠지면 조용히 잘못된 결과가 나옵니다:

| 빠뜨리면 | 생기는 일 |
|---|---|
| `--out` | CLI가 기본값 `lib/firebase_options.dart`(= **실서비스**)에 씁니다. dev 재생성 한 번으로 실서비스 옵션이 dev 값으로 덮여 씁니다. |
| `--platforms` (전체 나열) | 빠진 플랫폼이 생성물에서 **사라집니다.** |
| `--android-package-name` / `--ios-bundle-id` | CLI가 프로젝트 파일에서 패키지명을 추측합니다. 명시하면 최소한 **내가 어떤 이름으로 등록하는지 커밋에 남습니다** — 위 사고처럼 브랜치 상태에 따라 값이 조용히 달라지는 걸 리뷰에서 잡을 수 있습니다. |

돌린 뒤에는 **생성된 appId가 실제 `applicationId`/번들 id로 등록된 앱인지** 확인하세요:

```bash
firebase apps:sdkconfig ANDROID --project keepcon-dev   # package_name 이 com.keepcon.app 인지
```

```bash
# dev — 팀 개발
flutterfire configure --project=keepcon-dev --platforms=android,ios,web \
  --android-package-name=com.keepcon.app --ios-bundle-id=com.keepcon.app \
  --out=lib/firebase_options_dev.dart

# 실서비스
flutterfire configure --project=keepcon-ab660 --platforms=android,ios,web \
  --android-package-name=com.keepcon.app --ios-bundle-id=com.keepcon.app \
  --out=lib/firebase_options.dart
```

> ℹ️ **네이티브 설정 파일(`google-services.json` · `GoogleService-Info.plist`)을 쓰지 않습니다.** 그 파일들은 네이티브가 `[DEFAULT]` FirebaseApp을 먼저 만들어 **백엔드를 하나로 고정**하는데, KeepCon은 emulator·dev·prod를 실행 시 고르기 때문입니다(파일이 있으면 나머지 둘이 `[core/duplicate-app]`으로 죽습니다). 세 플랫폼 모두 web과 똑같이 **생성된 Dart 옵션만** 씁니다 — 자세한 근거는 [`android/app/build.gradle.kts`](android/app/build.gradle.kts) 주석에 있습니다.
>
> ⚠️ 그래서 **위 명령을 돌린 뒤에는 되돌릴 것이 있습니다.** CLI가 아래를 되살려 놓으므로 전부 지우고 커밋하세요:
> - `android/app/google-services.json` (`.gitignore`에 등록돼 있어 커밋되지는 않습니다)
> - `com.google.gms.google-services` 플러그인 **적용**([`android/app/build.gradle.kts`](android/app/build.gradle.kts)) — `settings.gradle.kts`의 `apply false` 선언은 적용이 아니라 무해합니다
> - **macOS에서 돌렸다면** `ios/Runner/GoogleService-Info.plist` 와 Xcode 프로젝트에 추가된 그 파일 참조 (Windows에서 돌리면 애초에 만들지 않습니다)

> ⚠️ **Firestore 에디션은 반드시 Standard입니다.** Enterprise는 MongoDB 호환 API용이라 `cloud_firestore` SDK도 `request.auth.uid` 기반 보안 규칙도 동작하지 않습니다. 콘솔에서 DB를 새로 만들 일이 있으면 Standard/Native를 고르세요.
>
> ⚠️ **리전은 변경할 수 없습니다.** `asia-northeast3`는 생성 시점에 확정됐습니다. 바꾸려면 프로젝트를 새로 만들어야 합니다.
>
> ⚠️ **두 옵션 파일의 클래스명이 `DefaultFirebaseOptions`로 같습니다.** `flutterfire configure` 생성물이라 그렇습니다. 생성물을 손으로 고치면 재생성 때 날아가므로, [`firebase_bootstrap.dart`](lib/shared/firebase/firebase_bootstrap.dart)에서 prefix import(`as dev_options` / `as prod_options`)로 구분합니다.

### 규칙을 고쳤을 때 — 배포

`firestore.rules`·`firestore.indexes.json`은 **파일을 고쳐도 배포해야 실제 프로젝트에 반영됩니다.** 그리고 프로젝트가 둘이라 **양쪽 모두**에 배포해야 합니다 — 한쪽만 하면 "dev에선 되는데 실서비스에선 막힘"이 생기고, 원인이 코드가 아니라 배포 누락이라 찾는 데 오래 걸립니다. 사람 기억에 맡기지 말고 스크립트를 쓰세요:

```bash
bash tool/deploy_rules.sh          # dev 에만 (기본)
bash tool/deploy_rules.sh prod     # 실서비스. 'prod' 를 입력해야 진행
bash tool/deploy_rules.sh all      # dev 먼저, 성공하면 prod
```
```bat
:: cmd·PowerShell
tool\deploy_rules.cmd all
```

- `all`은 **dev에 먼저** 배포하고 실패하면 prod로 넘어가지 않습니다. 규칙 오류가 실서비스보다 dev에서 먼저 드러나게 하려는 순서입니다.
- 실서비스 배포는 확인 프롬프트가 있습니다. **잘못된 규칙은 실사용자를 즉시 차단**하기 때문입니다.
- **에뮬레이터는 배포 대상이 아닙니다** — `firebase.json`을 통해 `firestore.rules`를 파일에서 직접 읽습니다. 규칙 변경을 반영하려면 에뮬레이터를 재시작하세요.
- 배포 전에 규칙이 의도대로 막는지는 `bash tool/verify_firestore_rules.sh`로 에뮬레이터에서 확인하세요.

<details>
<summary>프로젝트를 새로 만들거나 갈아끼울 때</summary>

팀에서 **한 명만** 수행하고 생성된 옵션 파일을 커밋하세요(각자 돌리면 파일이 갈라집니다):

1. `firebase projects:create <프로젝트-id> --display-name "..."`
2. `dart pub global activate flutterfire_cli` 후 — dev면 `--out`으로 파일을 나눕니다:
   ```bash
   flutterfire configure --project=<id> --platforms=web --out=lib/firebase_options_dev.dart
   ```
3. 콘솔에서 **Cloud Firestore**(Standard·Native·`asia-northeast3`) · **Authentication**(이메일/비밀번호) 활성화
   — Firestore는 콘솔에서 한 번 열어야 API가 켜지고, 그 뒤에는 CLI로도 만들 수 있습니다:
   `firebase firestore:databases:create "(default)" --location=asia-northeast3 --project <id>`
4. `firebase deploy --only firestore:rules,firestore:indexes --project <id>`
5. [`.firebaserc`](.firebaserc)에 별칭 추가, [`firebase_bootstrap.dart`](lib/shared/firebase/firebase_bootstrap.dart)의 `FirebaseTarget`에 항목 추가

</details>

> ⚠️ **비밀정보 커밋 금지:** 서비스 계정 키(`*-firebase-adminsdk-*.json`), 서명 키스토어(`*.jks`·`key.properties`), `.env`·토큰은 **절대 커밋하지 않습니다**([`.gitignore`](.gitignore)로 관리 + GitHub **Secret scanning/Push protection**으로 강제). 릴리스 전 `/security-review`. — 참고로 클라이언트용 `firebase_options.dart`·`google-services.json`의 API 키는 "비밀"이 아니라 프로젝트 식별자입니다(백엔드는 Firebase 보안 규칙·App Check로 보호). 진짜 비밀은 admin SDK 키·키스토어·토큰입니다.

---

## 🔗 초대 딥링크 (Android App Links)

초대 링크(`https://keepcon-ab660.web.app/invite/<code>`)를 휴대폰에서 누르면 **앱의 그룹 참여 시트가 바로 열립니다.** 브라우저로 새지 않게 하려면 세 곳이 맞아야 하고, 하나라도 어긋나면 **에러 없이 조용히 브라우저가 열립니다.**

| 위치 | 내용 |
|------|------|
| [`lib/shared/models/group.dart`](lib/shared/models/group.dart) | `Group.inviteHost` — 링크를 만드는 쪽 |
| [`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml) | `<data android:host=...>` — 링크를 받는 쪽 |
| [`public/.well-known/assetlinks.json`](public/.well-known/assetlinks.json) | 도메인이 이 앱을 인증하는 쪽 |

### 배포 (한 번만)

```bash
firebase deploy --only hosting --project keepcon-ab660
```

배포 후 `https://keepcon-ab660.web.app/.well-known/assetlinks.json`이 열리는지 확인하세요. 404면 App Links는 **절대** 검증되지 않습니다.

> ⚠️ `firebase.json`의 hosting `ignore`에서 기본 패턴 `**/.*`를 **일부러 뺐습니다.** 그 패턴은 `.well-known` 디렉터리째 배포에서 제외해, 설정이 전부 맞는데도 검증만 실패하는 상태를 만듭니다.

### 팀원 지문 추가 (필수)

`assetlinks.json`에는 **앱 서명 키의 SHA-256 지문**이 들어갑니다. 현재 release 빌드는 각자의 **debug 키**로 서명되므로(`build.gradle.kts` 참조) **개발자마다 지문이 다릅니다.** 등록되지 않은 지문으로 빌드하면 그 사람 기기에서만 링크가 안 열립니다.

본인 지문 확인:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

출력의 `SHA256:` 값을 `sha256_cert_fingerprints` 배열에 **추가**(교체 아님)하고 다시 배포하세요. 배열은 여러 지문을 허용합니다. 릴리스용 키스토어를 도입하면 그 지문도 함께 넣어야 합니다.

### 검증이 됐는지 확인

```bash
adb shell pm get-app-links com.keepcon.app
```

`verified`로 나와야 정상입니다. `legacy_failure`면 지문이나 배포를 다시 확인하세요. 앱을 재설치하면 검증이 다시 시도됩니다.

---

## 🧭 개발 하네스 (`.claude/`)

이 저장소에는 **페이지별 개발 팀 하네스**가 포함되어 있습니다. Claude Code에서 KeepCon 개발을 요청하면 `keepcon-orchestrator`가 계약 설계자·페이지 담당·통합 QA 에이전트를 조율합니다.

- 에이전트: `.claude/agents/` (계약 설계자 + 4페이지 담당 + 통합 QA)
- 스킬: `.claude/skills/` (오케스트레이터, 계약 설계, 페이지 개발 규약, 통합 검증)
- 트리거·규약: [`CLAUDE.md`](CLAUDE.md)
- **가드레일(규칙을 강제로):** [`tool/check_ssot.sh`](tool/check_ssot.sh)(SSOT CI 가드) · [`.github/CODEOWNERS`](.github/CODEOWNERS)(계약 소유자 리뷰) · [`.claude/settings.json`](.claude/settings.json)(SessionStart 최신화 훅) · `.gitattributes`(셸 스크립트 LF 강제)

> 하네스 설정(`CLAUDE.md`·에이전트·스킬)은 저장소 루트에 한 벌만 두고 git으로 팀 전원과 공유합니다 — 페이지 폴더에 복제하지 않습니다(상속·SSOT).

---

## 📚 참고 문서 (`_workspace/`)

- `01_contract_dependency_matrix.md` — 공유 계약·페이지별 소비/생산·크로스페이지 주의점 (SSOT 기준 문서)
- `design/behance_style_tokens.md` — 디자인 방향·토큰
- `qa_report.md` — 통합 정합성 검증 리포트
