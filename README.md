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
- **Firebase** (`firebase_auth`, `cloud_firestore`) — 백엔드 데이터 계층 *(스캐폴딩 완료, 설정 시 활성화)*
- 기본 실행은 **in-memory mock** 저장소 — 백엔드 설정 없이 바로 실행/개발 가능

---

## 📁 프로젝트 구조

```
lib/
├── main.dart                      # 앱 조립부(ProviderScope·테마·시드)
├── firebase_options.dart          # flutterfire configure가 생성 (현재 placeholder)
├── app/
│   └── keepcon_shell.dart         # 하단 내비 셸 (홈 / + / 공유)
├── shared/                        # ⭐ 공유 계약 (SSOT) — 모든 페이지가 참조 · CODEOWNERS 보호
│   ├── models/                    # User, Gifticon, Group/GroupMember, SharedGifticon, UsageLog, GroupNotification (+ enum·상태전이)
│   ├── repositories/              # AuthRepository, GifticonRepository, ShareRepository (abstract 인터페이스)
│   │   └── impl/                  # in_memory_* (기본) · firebase/* (백엔드)
│   ├── providers/                 # repositories(DI), theme_mode_provider
│   ├── theme/                     # app_colors, app_theme (라이트/다크 ThemeData)
│   ├── util/                      # korean_particle(조사 유틸) 등 도메인 무관 범용 유틸
│   ├── firebase/                  # firebase_bootstrap (초기화·override 전환)
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

### 사전 준비
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.27 이상 (Dart 3.6+) — `Color.withValues()` 등 3.27+ API 사용
- 확인: `flutter doctor`

### 설치 & 실행
```bash
git clone https://github.com/Jiwonang/KeepCon.git
cd KeepCon
flutter pub get

# 웹으로 실행 (web 플랫폼은 이미 설정됨)
flutter run -d chrome

# 모바일로 실행하려면 플랫폼 폴더 생성 후
flutter create . --platforms=android,ios
flutter run
```

> 별도 백엔드 설정 없이 in-memory mock 데이터(시드 기프티콘)로 즉시 실행됩니다.

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

현재는 in-memory mock이 기본입니다. 실제 Firebase 백엔드로 전환하려면:

1. [Firebase 콘솔](https://console.firebase.google.com)에서 프로젝트 생성
2. FlutterFire 설정 — `lib/firebase_options.dart`가 실제 값으로 생성됩니다:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
3. 콘솔에서 **Authentication** · **Cloud Firestore** 활성화
4. 앱 조립부(`lib/main.dart`)에서 `firebase_bootstrap`의 override를 `ProviderScope`에 주입

> 인터페이스(`AuthRepository`/`GifticonRepository`)는 그대로 두고 구현만 교체하는 구조라, 페이지 코드 변경 없이 백엔드가 전환됩니다.

> ⚠️ **비밀정보 커밋 금지:** 서비스 계정 키(`*-firebase-adminsdk-*.json`), 서명 키스토어(`*.jks`·`key.properties`), `.env`·토큰은 **절대 커밋하지 않습니다**([`.gitignore`](.gitignore)로 관리 + GitHub **Secret scanning/Push protection**으로 강제). 릴리스 전 `/security-review`. — 참고로 클라이언트용 `firebase_options.dart`·`google-services.json`의 API 키는 "비밀"이 아니라 프로젝트 식별자입니다(백엔드는 Firebase 보안 규칙·App Check로 보호). 진짜 비밀은 admin SDK 키·키스토어·토큰입니다.

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
