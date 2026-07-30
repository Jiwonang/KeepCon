# QA 리포트 (2026-07-06, 검증 범위: SSOT provider 단일화 회귀 검증 + scan↔main 경계면 전수)

## 요약
- 통과: 9 / 실패: 0 / 미검증(미구현): 2 (share, auth 실구현 — 계약 슬라이스상 mock 대체)
- 최종 판정: **통과 (잔여 이슈 없음)**. 이전 치명 결함(중복 provider 선언 → 인스턴스 분리) **수정 확인**. 수정 과정에서 신규 회귀 **0**.

## 회귀 항목 상태 (이전 지적 → 현재)

### [치명→수정됨] Repository provider 중복 선언 (인스턴스 분리)
- 이전 문제: scan/main이 `authRepositoryProvider`/`gifticonRepositoryProvider`를 각각 중복 선언 → 서로 다른 InMemory 인스턴스 참조 → scan 추가분이 main에 미반영.
- 현재 상태: **해소됨.**
  - SSOT provider 신설 확인: `lib/shared/providers/repositories.dart:69`(auth), `:84`(gifticon) — 선언은 **이 파일 한 곳에만** 존재. `lib/features/` 하위 잔존 선언 0건(grep `...Provider =`).
  - 소비부 3곳 모두 SSOT import:
    - `lib/features/main/main_page.dart:16`
    - `lib/features/scan/state/gifticon_form_state.dart:17`
    - `lib/features/main/state/gifticon_list_providers.dart:20`

### [치명→수정됨] 삭제 파일 dead import
- 이전 문제: `scan_providers.dart`, `main/state/repository_providers.dart` 삭제 예정.
- 현재 상태: **파일 존재 안 함**(파일 트리 확인). 두 파일명에 대한 잔존 import 0건(grep `scan_providers|repository_providers`). dead import 없음.

## 통과 항목 (경계면별 교차 비교)

### [핵심] scan(생산) ↔ main(소비) 인스턴스 공유 — 데이터 흐름 연결 확인
- 생산부 `gifticon_form_state.dart:209`: `_ref.read(gifticonRepositoryProvider).addGifticon(draft)`
- 소비부 `gifticon_list_providers.dart:39-40`: `ref.watch(gifticonRepositoryProvider)` → `repo.watchGifticons(user.id)`
- **동일 심볼·동일 SSOT 파일**(`shared/providers/repositories.dart`)을 양쪽이 참조. 단일 `ProviderScope` 내에서 같은 인스턴스 공유.
- ownerId 규약 일치: scan은 `ownerId: currentUser.id`(`:196`)로 채우고, main은 `watchGifticons(user.id)`로 조회. InMemory 구현(`in_memory_gifticon_repository.dart:75-77`)이 `g.ownerId == ownerId`로 필터하고, `addGifticon`이 broadcast 스트림에 `_emit()`(`:35`) → main의 `watchGifticons`(`:40-43`)가 재방출. **scan 추가 → main 반영 경로 실연결 확인.**

### 세션(auth) 소비 정합성
- scan: `authRepositoryProvider).currentUser`(`gifticon_form_state.dart:178`) — 동기 getter, 계약 `currentUser`(`auth_repository.dart:18`) 일치.
- main: `authRepositoryProvider` → `auth.watchCurrentUser()`(`gifticon_list_providers.dart:26-27`) — 계약 `watchCurrentUser()`(`auth_repository.dart:24`) 일치. 양쪽 동일 SSOT provider 참조.

### Repository 시그니처 대조 (계약 ↔ 호출부)
- `addGifticon(Gifticon) → Future<Gifticon>`: 계약 `gifticon_repository.dart:25` ↔ 호출 `:209`. 일치.
- `watchGifticons(String ownerId) → Stream<List<Gifticon>>`: 계약 `:31` ↔ 호출 `:40`. 일치.
- `watchCurrentUser() → Stream<User?>`: 계약 `auth_repository.dart:24` ↔ 호출 `:27`. 일치.
- `updateStatus(String, GifticonStatus)`: 계약 `:43`, InMemory 구현 `:58` 전이 검증 포함. (현재 호출자 없음 — share 미구현이므로 정상, 死메서드 아님.)

### 중복 모델 정의 0
- `class Gifticon`은 `lib/shared/models/gifticon.dart:86`, `class User`는 `lib/shared/models/user.dart:14` — **shared 밖 재정의 없음**(grep 전수). Group/GroupMember/SharedGifticon/UsageLog는 미도입(share 미구현).

### 매직 스트링 0 (계약 enum 사용)
- 상태/정렬/필터 문자열 리터럴 grep(`"available"`,`"used"`,`"latest"` 등): `lib/features` 내 0건.
- main 필터/정렬은 계약 enum만 사용: `SortOption.*`(`gifticon_sorter.dart:13-19`), `GifticonStatus`/`FilterOption`(`gifticon_filter.dart:33,54`), `SortOption.expiryAsc` 기본값(`gifticon_list_providers.dart:45`).
- scan 신규 status: `GifticonStatus.available`(`gifticon_form_state.dart:203`) — 계약 규칙(신규=available) 준수.

### 상태 전이 정합성
- 계약 허용 전이(`gifticon.dart:39-43`): available→{used,expired}, used/expired는 종결. InMemory `updateStatus`가 `GifticonStatusTransition.isAllowed`로 강제(`in_memory_gifticon_repository.dart:64`). scan은 available만 생성. **무단 전이·죽은 상태 없음.**

### 라우트 상수 사용
- 하드코딩 경로 0건. `AppRoutes.scan`(`scan_page.dart:21`), 내비게이션 `pushNamed(AppRoutes.scan)`(`main_page.dart:38`) — 계약 `routes.dart:13,16`과 일치.

### 정적 분석
- `flutter analyze`: **No issues found** (경고 0).

## 미검증 (미구현 — 계약 슬라이스 범위 밖)
- share 페이지(그룹/공유/사용동기화/알림): 미구현. updateStatus 소비, ShareStatus/NotificationType enum, 그룹 모델은 후속 확장에서 재검증.
- auth 실구현(실제 AuthRepository): 현재 `InMemoryAuthRepository` mock. 조립부 override 규칙(`repositories.dart:25-49`)은 문서화되어 있음. main.dart 조립부는 이번 슬라이스 범위 밖.

---

# feat/scan-camera 검증 (2026-07-30, 인라인 QA — 서브에이전트 529 장애로 리더 직접 수행)

## 검증 대상
카메라 실시간 바코드 스캔(mobile_scanner ^7.4.0) + 수동 입력 보완 4항목 (미커밋 working tree)

## 경계면별 판정

| # | 경계면 | 판정 | 근거 |
|---|--------|------|------|
| 1 | scan → 계약(lib/shared) | **통과** | `git diff develop -- lib/shared` 빈 출력(무수정). submit() 경로 무변경 — status=available, kDefaultCategory 보정, ownerId, addGifticon 시그니처 기존 검증 유지. SSOT guard ✓ |
| 2 | scan → main (imagePath=null) | **통과** | 카메라 경로는 barcode만 프리필. 필수 필드는 validate()가 저장 전 강제. main gifticon_card.dart:126 — imagePath null/empty → 카테고리색 placeholder 분기 확인 |
| 3 | 카메라 흐름 상태 안전성 | **통과** | camera 분기가 try 내부·startWith 이후에 위치(scan_page.dart:250), _busy 가드 공유, 취소(null) 시 return→finally reset(). 스캐너 화면은 Riverpod 미접촉·_handled 중복 pop 가드·dispose에서 컨트롤러 해제 |
| 4 | 저장 후 계속 등록 | **통과** | _submitAndContinue: submit 성공 후 startWith(현재 source)로 세션 갱신·폼 초기화. in-flight 중 이탈 시 세션 가드가 stale 결과 차단(기존 메커니즘). ScanSubmitInProgress 비활성화 재사용 |
| 5 | 콤마 포매터 ↔ parsedPrice | **통과** | digitsOnly→ThousandsSeparator 순서, parsedPrice가 콤마 제거(기존 코드+신규 테스트로 고정) |
| 6 | 스캐너 반환 계약 | **통과** | push<String> → String? → prefillFromRecognition(barcode:) 명명 파라미터 정합 |

## 기계 검증
- SSOT guard: 위반 없음 ✓
- dart format --set-exit-if-changed: 0 changed ✓
- flutter analyze: No issues found ✓
- flutter test: 109 passed ✓

## 발견 이슈
- blocker/major: 없음
- minor(비차단, 기록만): ①mobile_scanner 카메라 UX(프리뷰·플래시·권한 프롬프트)는 실기기 검증 필요 ②ios pod install 미실행(Windows 환경) ③main gifticon_card가 로컬 파일 경로에 Image.network 사용 — 기존 이슈(이번 변경과 무관, errorBuilder로 placeholder 폴백되어 안전)
