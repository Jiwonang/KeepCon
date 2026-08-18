---
name: keepcon-orchestrator
description: "KeepCon(흩어진 기프티콘을 한 곳에서 관리·보관·공유하는 Flutter 앱) 개발 에이전트 팀을 조율하는 오케스트레이터. 로그인/설정·메인·스캔·공유 페이지 개발, 공유 계약 설계, 페이지 간 통합 정합성 검증을 하나의 팀으로 실행한다. 트리거 — KeepCon 개발/기능 구현/페이지 작업/기프티콘·그룹·공유·스캔 기능 요청 시. 후속 작업 — 특정 페이지만 다시, 기능 수정·보완·업데이트, 재실행, 이전 결과 개선, 연동 오류 수정, 통합 검증 요청 시에도 반드시 이 스킬을 사용."
---

# KeepCon Orchestrator — 기프티콘 관리·공유 앱 개발 팀 조율

KeepCon의 개발 에이전트 팀을 조율하여 Flutter 앱을 구현하는 통합 스킬. 4개 페이지(로그인/설정·메인·스캔·공유)를 담당별로 병렬 개발하되, **공유 계약 설계자**가 페이지 간 의존성의 기준을 확정하고 **통합 QA**가 경계면을 교차 검증하여, 담당 분리에서 오는 연동 버그(중복 구현·잘못된 함수명·값 불일치)를 원천 차단한다.

## 실행 모드: 에이전트 팀

페이지 간 실시간 의존성 협의(SendMessage)가 이 프로젝트의 핵심이므로 **에이전트 팀**을 사용한다. 계약 설계자가 파이프라인 시작점, 4개 페이지 개발자가 팬아웃, 통합 QA가 점진적 검증자(producer-reviewer)로 한 팀 안에서 협업한다. 순서는 작업 의존성(`depends_on`)으로 강제한다.

## 에이전트 구성

| 팀원 | 에이전트 타입 | 역할 | 스킬 | 출력 |
|------|-------------|------|------|------|
| contract-architect | contract-architect (커스텀) | 공유 계약 SSOT 설계·유지 | contract-design | `lib/shared/**`, `_workspace/01_contract_dependency_matrix.md` |
| auth-settings-dev | auth-settings-dev (커스텀) | 로그인/회원가입/비번찾기/설정 | flutter-page-dev | `lib/features/auth/**` |
| main-page-dev | main-page-dev (커스텀) | 기프티콘 목록/정렬/필터 | flutter-page-dev | `lib/features/main/**` |
| scan-page-dev | scan-page-dev (커스텀) | 카메라/갤러리/수동 추가 | flutter-page-dev | `lib/features/scan/**` |
| share-page-dev | share-page-dev (커스텀) | 그룹/초대/공유/사용동기화/알림 | flutter-page-dev | `lib/features/share/**` |
| integration-qa | integration-qa (커스텀) | 경계면 교차 검증 (점진적) | integration-coherence-check | `_workspace/qa_report.md` |

> 모든 팀원은 `model: "opus"`로 스폰한다.

## 워크플로우

### Phase 0: 컨텍스트 확인 (후속 작업 지원)

1. `_workspace/`와 `lib/shared/`, `lib/features/` 존재 여부 확인.
2. 실행 모드 결정:
   - **미존재** → 초기 실행. Phase 1로.
   - **존재 + 부분 수정 요청**(예: "공유 페이지 초대 기능만 다시") → 부분 재실행. 계약 설계자 + 해당 페이지 개발자 + QA만 팀에 구성하고, 지목된 산출물만 수정.
   - **존재 + 새 요구/새 기능** → 증분 실행. 기존 계약·코드를 존중하며 확장. 큰 방향 전환이면 기존 `_workspace/`를 `_workspace_{YYYYMMDD_HHMMSS}/`로 이동 후 진행.
3. 부분/증분 재실행 시: 이전 산출물 경로와 사용자 피드백을 각 팀원 프롬프트에 포함해 기존 결과를 읽고 반영하도록 지시.

### Phase 1: 준비

1. **프로젝트 전역 표준 확인.** 코드 작성 전 반드시 확정해야 페이지마다 제각각이 되는 것을 막는다. 아직 안 정해졌으면 사용자에게 한 번에 확인한다:
   - 상태관리 라이브러리 (예: Riverpod / Provider / Bloc)
   - 카메라·이미지·OCR 패키지 (스캔 페이지용)
   - Flutter 프로젝트 초기화 여부(`pubspec.yaml` 존재) — 없으면 스캐폴딩 필요
   확정된 표준은 `_workspace/00_project_standards.md`에 기록하고 전 팀원 프롬프트에 포함한다.
2. `_workspace/` 생성 (초기 실행 시). 새 실행이면 기존 것을 타임스탬프 디렉토리로 이동 후 재생성.
3. 페이지 기능 명세(사용자 요청의 페이지 트리)를 `_workspace/00_spec.md`에 저장.

### Phase 2: 팀 구성

1. 팀 생성:

   ```text
   TeamCreate(
     team_name: "keepcon-team",
     members: [
       { name: "contract-architect", agent_type: "contract-architect", model: "opus",
         prompt: "KeepCon 공유 계약을 lib/shared/에 확정하라. contract-design 스킬을 따르고, _workspace/00_spec.md와 00_project_standards.md를 읽어라. v1 계약(모델·Repository 인터페이스·enum·라우트)을 최우선으로 빠르게 확정하고 의존성 매트릭스를 작성한 뒤 전 페이지 개발자에게 브로드캐스트하라." },
       { name: "auth-settings-dev", agent_type: "auth-settings-dev", model: "opus",
         prompt: "로그인/설정 페이지를 lib/features/auth/에 구현하라. flutter-page-dev 스킬을 따르고, contract-architect의 계약 확정을 기다린 뒤 AuthRepository를 구현하고 currentUser 접근점을 다른 페이지에 공유하라." },
       { name: "main-page-dev", agent_type: "main-page-dev", model: "opus",
         prompt: "메인 페이지(목록/정렬/필터)를 lib/features/main/에 구현하라. flutter-page-dev 스킬을 따르고, 계약의 Gifticon·SortOption·FilterOption·GifticonRepository를 소비하라. scan/share가 만든 데이터가 목록에 반영되는지 그들과 협의하라." },
       { name: "scan-page-dev", agent_type: "scan-page-dev", model: "opus",
         prompt: "스캔/추가 페이지(카메라·갤러리·수동)를 lib/features/scan/에 구현하라. flutter-page-dev 스킬을 따르고, GifticonRepository로 신규 Gifticon을 생성하되 main의 정렬/필터가 쓰는 필드를 빠짐없이 채워라." },
       { name: "share-page-dev", agent_type: "share-page-dev", model: "opus",
         prompt: "공유 페이지(그룹·초대·공유·사용동기화·알림·취소)를 lib/features/share/에 구현하라. flutter-page-dev 스킬을 따르고, 사용 시 GifticonRepository로 원본 status를 전이시켜 main에 반영되게 하라." },
       { name: "integration-qa", agent_type: "integration-qa", model: "opus",
         prompt: "integration-coherence-check 스킬로 경계면을 교차 검증하라. 각 페이지가 완성될 때마다 점진적으로 검증하고, 발견 즉시 양쪽 개발자에게 수정 요청하라. _workspace/qa_report.md에 기록하라." }
     ]
   )
   ```

2. 작업 등록 (`depends_on`으로 순서 강제):

   ```text
   TaskCreate(tasks: [
     { title: "공유 계약 v1 확정", assignee: "contract-architect" },
     { title: "auth 페이지 구현", assignee: "auth-settings-dev", depends_on: ["공유 계약 v1 확정"] },
     { title: "main 페이지 구현", assignee: "main-page-dev", depends_on: ["공유 계약 v1 확정"] },
     { title: "scan 페이지 구현", assignee: "scan-page-dev", depends_on: ["공유 계약 v1 확정"] },
     { title: "share 페이지 구현", assignee: "share-page-dev", depends_on: ["공유 계약 v1 확정"] },
     { title: "auth 경계면 검증", assignee: "integration-qa", depends_on: ["auth 페이지 구현"] },
     { title: "main 경계면 검증", assignee: "integration-qa", depends_on: ["main 페이지 구현"] },
     { title: "scan 경계면 검증", assignee: "integration-qa", depends_on: ["scan 페이지 구현"] },
     { title: "share 경계면 검증", assignee: "integration-qa", depends_on: ["share 페이지 구현"] },
     { title: "전체 통합 검증", assignee: "integration-qa", depends_on: ["auth 경계면 검증","main 경계면 검증","scan 경계면 검증","share 경계면 검증"] }
   ])
   ```

### Phase 3: 계약 확정 → 병렬 페이지 개발 → 점진적 검증

**실행 방식:** 팀원 자체 조율.

1. **계약 우선.** contract-architect가 v1 계약을 확정하고 의존성 매트릭스를 전원에게 브로드캐스트할 때까지 페이지 개발자는 계약 의존 코드를 시작하지 않는다(그동안 UI 스캐폴딩만).
2. **팬아웃 병렬 개발.** 계약 확정 후 4개 페이지 개발자가 병렬로 진행하며, 경계면은 SendMessage로 협의한다:
   - scan ↔ main: Gifticon 필수 필드/기본값 규칙
   - share ↔ main: 사용 동기화 status ↔ 필터 기준
   - auth → main/scan/share: currentUser 접근점
   - 계약에 없는 것이 필요하면 누구든 contract-architect에게 요청 → 계약 증분 확장 후 재브로드캐스트.
3. **점진적 QA.** integration-qa는 각 페이지가 완성되는 즉시 그 경계면을 교차 검증하고, 발견 즉시 양쪽 개발자에게 수정 요청. 계약이 변경되면 의존 페이지를 재검증.

**리더 모니터링:** 팀원 유휴 알림 수신, 막힌 팀원에게 SendMessage 지시 또는 작업 재할당, TaskGet으로 진행률 확인. 계약 변경이 여러 페이지에 파급되면 리더가 재검증 순서를 조정.

### Phase 4: 전체 통합 검증 및 마감

1. 모든 페이지 완료 대기(TaskGet).
2. integration-qa의 "전체 통합 검증" 실행 — 전 경계면 최종 교차 검증 + `flutter analyze`.
3. `_workspace/qa_report.md`의 잔여 실패 항목을 해당 개발자에게 수정 지시 → 재검증(최대 2회 루프).
4. 최종 결과 요약: 구현된 페이지, 통과/잔여 이슈, 실행 방법을 사용자에게 보고.

### Phase 5: 정리

1. 팀원 종료(SendMessage), 팀 정리(TeamDelete).
2. `_workspace/` 보존(감사 추적용).
3. 사용자에게 피드백 요청(Phase 7 진화): "페이지 분담·계약·워크플로우에 바꾸고 싶은 점이 있나요?"

## 데이터 흐름

```text
[리더] → TeamCreate → contract-architect ──(계약 브로드캐스트)──▶ 4 페이지 개발자
                              │                                    │  ↕ SendMessage
                       lib/shared/**                         lib/features/*/**
                   01_contract_dependency_matrix.md               │
                              └──────── integration-qa ◀───────────┘
                                        (점진적 교차 검증)
                                              ↓
                                        qa_report.md
                                              ↓
                                        [리더: 마감 보고]
```

## 에러 핸들링

| 상황 | 전략 |
|------|------|
| 계약 설계자 지연 → 페이지 전원 대기 | 리더가 계약 v1 범위를 최소로 좁히도록 지시(핵심 모델·인터페이스 먼저), 나머지는 증분 |
| 두 페이지가 상충 계약 요청 | 계약 설계자가 병기 후 통합안 제시, 삭제 금지, 합의 도출 |
| 잘못된 함수명/중복 구현 발견 | QA가 양쪽 개발자에게 파일:라인 + 수정법 통지, 최우선 수정 |
| 팀원 1명 실패/중지 | 리더 감지 → 상태 확인 → 재시작 또는 작업 재할당 |
| QA 재검증 루프 3회 초과 | 잔여 이슈를 리포트에 명시하고 진행, 사용자에게 보고 |
| 프로젝트 표준 미확정 | Phase 1에서 사용자 확인 없이 코드 시작 금지 |

## 테스트 시나리오

### 정상 흐름
1. 사용자가 KeepCon 개발/특정 기능을 요청.
2. Phase 1에서 전역 표준(상태관리·패키지) 확정, `_workspace/` 준비.
3. Phase 2에서 6인 팀 + 의존성 있는 10개 작업 등록.
4. contract-architect가 계약 v1 확정·브로드캐스트 → 4개 페이지 병렬 개발(SendMessage 협의) → QA 점진 검증.
5. Phase 4에서 전체 통합 검증, 잔여 이슈 수정.
6. 예상 결과: `lib/shared/**` + `lib/features/{auth,main,scan,share}/**` 구현, `qa_report.md`에 통과 기록.

### 에러 흐름
1. scan이 `Gifticon.expiryDate`를 안 채워 main 만료임박 정렬에서 누락.
2. integration-qa가 scan 경계면 검증에서 교차 비교로 발견.
3. scan-page-dev와 main-page-dev **모두**에게 파일:라인 + 기본값 규칙 수정법 통지.
4. contract-architect가 필요 시 nullable 여부/기본값을 매트릭스에 명시.
5. 수정 후 재검증 → 통과. 리포트에 이력 남김.
