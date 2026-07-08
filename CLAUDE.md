# KeepCon

흩어진 기프티콘을 한 곳에서 관리·보관하고, 그룹 공유로 가족·친구가 자유롭게 사용하도록 하는 Flutter 앱.

## 하네스: KeepCon 페이지별 개발 팀

**목표:** 4개 페이지(로그인/설정·메인·스캔·공유)를 담당별로 병렬 개발하되, 공유 계약(SSOT)과 통합 QA로 페이지 간 연동 버그(중복 구현·잘못된 함수명·값 불일치)를 원천 차단한다.

**트리거:** KeepCon 개발·기능 구현·페이지 작업·기프티콘/그룹/공유/스캔 관련 요청 시 `keepcon-orchestrator` 스킬을 사용하라. 단순 질문은 직접 응답 가능.

**핵심 규약(모든 페이지 작업의 전제):**
- 공유 모델·인터페이스·enum·라우트는 `lib/shared/`의 단일 정의만 사용한다. 페이지 내부 재정의 금지.
- Repository 메서드는 계약에 적힌 이름·파라미터 그대로 호출한다(추측 호출 금지).
- 상태/정렬/필터는 매직 스트링이 아니라 계약의 enum을 사용한다.
- 계약에 없는 것이 필요하면 만들지 말고 `contract-architect`에게 요청한다.

**협업 규칙(git 작업 시 반드시 준수):**
- **브랜치:** 기본 브랜치 `develop`(모든 작업 머지 대상), 통합 브랜치 `main`(배포 시 `develop → main` squash). 작업 브랜치는 반드시 `develop`에서 분기하고 `{type}/{설명}` 형식(예: `feat/share-group-create`). **`main`·`develop`에 직접 커밋/푸시 금지.** PR은 `develop`을 대상으로 올린다.
- **원칙:** API 1개 / 페이지 1개 = 브랜치 1개 = PR 1개.
- **커밋 메시지:** Conventional Commits(한국어) — `feat(backend): …`, `fix(frontend): …`, `refactor(…): …`, `docs(spec): …`, `ci: …`, `perf(frontend): …`.
- **PR 본문:** `.github/PULL_REQUEST_TEMPLATE.md` 형식(🚀 작업 내용 / 🤔 고민했던 내용 / 💬 리뷰 중점사항).
- **코드 리뷰(3층 중첩):** ①CI(`Format·Analyze·Test`) 게이트 ②PR마다 **CodeRabbit** 자동 리뷰 ③Claude Code로 작업 시 **코드 변경을 커밋하기 전에 `/code-review`로 자체 리뷰·수정 후 커밋**. 릴리스 전 `/security-review`.
  - CodeRabbit은 **GitHub App**이라 `.coderabbit.yaml`(리뷰 설정)만으로는 동작하지 않는다. **App이 이 저장소에 설치·접근 허용**되어야 리뷰가 붙는다(계정에 설치 후 *Only select repositories*로 골랐다면 KeepCon을 범위에 추가). 설정은 https://github.com/settings/installations.
  - **비용:** Public 저장소는 **무료**, Private는 **유료(Pro)** 또는 무료 체험. KeepCon은 Public이라 App 범위에만 추가하면 무료로 동작한다. (동작 여부=App 접근 범위, 비용=공개여부 — 두 축은 별개.)
- 병합 전 `flutter analyze` 통과 확인. 상세는 `README.md`의 "협업 규칙" 참조.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-07-06 | 초기 구성 (에이전트 6, 스킬 4) | 전체 | 페이지별 담당 분리 + 계약/통합 검증 하네스 구축 |
| 2026-07-06 | 검증 실행 (scan→main 슬라이스, 서브에이전트 모드) | contract-architect·scan·main·integration-qa | 하네스 실동작 검증. 가드레일(모델 재정의·매직스트링 방지) 정상, QA가 provider 인스턴스 분기 결함 포착·수정 후 회귀 통과 |
| 2026-07-06 | 공유 DI provider 규약 추가 | skills/contract-design, skills/flutter-page-dev | 검증에서 드러난 교훈 — 공유 Riverpod provider는 `lib/shared/providers/` 정본에 두어야 인스턴스 분기 버그 예방 |
| 2026-07-07 | 협업 규칙(브랜치·커밋·PR) 추가 | CLAUDE.md, README.md, .github/PULL_REQUEST_TEMPLATE.md | AI 팀원이 자동 준수하도록 CLAUDE.md에 명시(README만으로는 자동 적용 안 됨). develop 기본 브랜치 전환 |
| 2026-07-07 | 리뷰 정책 확정: 자동 봇 제거, 커밋 전 `/code-review` | CLAUDE.md, README.md, .github/workflows/claude-review.yml(삭제) | 자동 AI 봇은 외부 상시 접근·비밀·비용 부담 → Private 보안 위해 CI + 커밋 전 세션 내 `/code-review`로 전환 |
| 2026-07-07 | Public 전환 → 브랜치 보호 Ruleset 적용 + CodeRabbit 중첩 도입 | GitHub Ruleset(protect-main-develop), .coderabbit.yaml, README.md, CLAUDE.md | 공개 전환으로 Rulesets·CodeRabbit 무료 가능. CI+/code-review에 CodeRabbit 자동 리뷰를 3층으로 중첩 |
| 2026-07-08 | CodeRabbit 동작 전제 정정 | CLAUDE.md | PR #10에서 CodeRabbit 미동작 발견. 원인은 `.coderabbit.yaml`은 있으나 **App 저장소 접근 범위에 KeepCon 미포함**(App은 계정에 설치됨 — private passgen에서 동작 확인). 설정만으론 부족·App 설치+범위 필요, 비용은 Public=무료/Private=유료로 문구 정정 |
