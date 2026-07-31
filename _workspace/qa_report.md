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
| 4 | 저장 후 계속 등록 | **통과** | _submitAndContinue: submit 성공 후 startWith(ScanSource.manual)로 세션을 의도적으로 manual 고정 갱신·폼 초기화(이전 source 유지 금지 — camera/gallery 출처 위장 방지, /code-review 반영). in-flight 중 이탈 시 세션 가드가 stale 결과 차단. ScanSubmitInProgress 비활성화 재사용 |
| 5 | 콤마 포매터 ↔ parsedPrice | **통과** | digitsOnly 제거, ThousandsSeparatorInputFormatter 단독 사용(비숫자 제거 자체 수행 — 중복 방지, /code-review 반영), parsedPrice가 콤마 제거(기존 코드+신규 테스트로 고정) |
| 6 | 스캐너 반환 계약 | **통과** | push<String> → String? → prefillFromRecognition(barcode:) 명명 파라미터 정합 |

## 기계 검증
- SSOT guard: 위반 없음 ✓
- dart format --set-exit-if-changed: 0 changed ✓
- flutter analyze: No issues found ✓
- flutter test: 109 passed ✓

## 발견 이슈
- blocker/major: 없음
- minor(비차단, 기록만): ①mobile_scanner 카메라 UX(프리뷰·플래시·권한 프롬프트)는 실기기 검증 필요 ②ios pod install 미실행(Windows 환경) ③main gifticon_card가 로컬 파일 경로에 Image.network 사용 — 기존 이슈(이번 변경과 무관, errorBuilder로 placeholder 폴백되어 안전)

---

# feat/scan-group-select 검증 (2026-07-30, integration-qa)

## 검증 대상
`git diff develop` + 미커밋 신규 파일 — scan 저장 대상 그룹 실연동.
신설 `lib/features/scan/state/scan_target_group_state.dart`(`scanTargetGroupsProvider`), `test/features/scan/scan_target_group_test.dart`.
수정 `scan_page.dart`(`_GroupSelector` 실연동·`_targetGroupId` 소유), `state/gifticon_form_state.dart`(`targetGroupId`·submit의 저장 후 `shareGifticon`·`ScanSubmitSuccess` 확장), `widgets/gifticon_form.dart`(`_shareNote`·계속 등록 그룹 유지), 매트릭스 주의점 12.
설계 전제(리더 확정) 준수 확인: 계약 무변경(`git diff develop -- lib/shared` 빈 출력), `Gifticon`에 `groupId` 없음, 저장 성공 후 `shareGifticon` 소비, 부분 실패는 `Success(shareError)`.

## 요약
- 경계면 통과 6 / 실패 0 / 미검증 0
- 기계 검증 4종 전부 green. blocker·major 없음, minor 4건(전부 비차단).

## 경계면별 판정
| # | 경계면 | 판정 | 교차 비교 근거 (생산자 ↔ 소비자) |
|---|--------|------|--------------------------------|
| 1 | scan → share 계약 (`shareGifticon`) | **통과** | 시그니처: 계약 `share_repository.dart:145-148` `shareGifticon({required String groupId, required Gifticon gifticon}) → Future<SharedGifticon>` ↔ 호출부 `gifticon_form_state.dart:759-762` 명명 인자 일치. **행위자 규약 준수** — actor를 파라미터로 넘기지 않음(계약 `share_repository.dart:9` "이 인터페이스는 행위자 id를 파라미터로 받지 않는다"), 구현이 `_requireUser()`로 세션 해석(`in_memory_share_repository.dart:401`). **1회 공유 불변식 충돌 없음(양쪽 구현 확인)** — draft `id: ''`(`gifticon_form_state.dart:694`)이지만 `InMemoryGifticonRepository.addGifticon`이 `gifticon-${++_seq}` 발급(`in_memory_gifticon_repository.dart:31`), `FirebaseGifticonRepository`가 `ref.id` 발급(`firebase_gifticon_repository.dart:42-43`) → `saved.id`는 항상 유일·비어있지 않음 → `_isAlreadyShared(saved.id, me.id)` 항상 false(`in_memory_share_repository.dart:410`). 어느 한쪽이라도 `id: ''`를 유지했다면 두 번째 저장부터 불변식 오검출 + Firestore `_locks.doc('')` 예외가 났을 지점 — 통과 확인. `getGroupById`도 계약 메서드(`share_repository.dart:43`, 없으면 null) 그대로 소비. SSOT provider 경유(`_ref.read(shareRepositoryProvider)`, `gifticon_form_state.dart:673`) — 구현체 직접 인스턴스화 없음 |
| 2 | scan → share → main 데이터 흐름 | **통과** | 공유는 원본 상태 무변경 — `in_memory_share_repository.dart:413-436`에 `updateStatus` 호출 없음 → 원본 `available` 유지 → main `watchGifticons`/상태 필터에 정상 표시. 테스트가 `saved.status == available` + `getGifticons(myId)` 포함을 고정(`scan_target_group_test.dart:113-131`). **markUsed 동기화도 이 신규 흐름에서 성립(오히려 강화)** — `SharedGifticon.gifticonId = saved.id`(`:416`) → `markUsed` → `_syncOriginalUsed(item.gifticonId)`(`:500`) → `getGifticonById`가 **실재하는** 원본을 찾음 → `GifticonStatusTransition.isAllowed(available, used)` true → `updateStatus(id, used)`(`:529-538`). 데모 시드 공유는 원본이 없어 동기화를 건너뛰지만(계약 doc `share_repository.dart:161`), scan이 만든 항목은 같은 repo 인스턴스에 실제로 존재하므로 반드시 동기화된다 |
| 3 | provider 인스턴스 정합 | **통과** | `scanTargetGroupsProvider`가 `ref.watch(shareRepositoryProvider)`(`scan_target_group_state.dart:36`) — share 페이지 `share_providers.dart:41`과 **동일 SSOT provider**. 조립부 확인: `lib/main.dart` `_inMemoryOverrides()`는 `gifticonRepositoryProvider`만 override(`:140`)하고 `shareRepositoryProvider`는 auth·gifticon을 `watch`하므로 override된 인스턴스를 자동 주입(`repositories.dart`); `firebaseProviderOverrides()`는 auth 1개·gifticon 1개를 만들어 같은 쌍을 `FirebaseShareRepository`에 주입하고 3개를 함께 override(`firebase_bootstrap.dart:181-193`). **v1.1 인스턴스 분기 결함 재발 없음.** SSOT guard도 위반 0 |
| 4 | 세션 가드 상호작용 | **통과** | 리더가 서술한 설계와 코드 일치 — `shareGifticon` await는 `gifticon_form_state.dart:759`(가드 **앞**), 세션 가드는 `:793`(`!mounted` 또는 `session != _session`), 상태 쓰기는 `:802`(가드 **뒤**). `shareRepository`를 await **전에** 캡처(`:672-673`)해 컨테이너 폐기 후 `_ref.read` 예외를 회피 — 의도적이고 정확. 이탈 레이스: reset()이 세션을 올려도 공유는 진행(데이터가 사용자 의도와 일치) → 가드가 null 반환 → `_submitWithFeedback`이 스낵바·pop·폼 초기화를 모두 생략(`gifticon_form.dart:523`) → 데이터/UI 양쪽 정합. 컨테이너 폐기 중 레이스도 내부 try/catch가 흡수 후 `!mounted`로 폐기 → 크래시 경로 없음 |
| 5 | 선택 상태 수명 | **통과**(문서 보강 권고 — minor 2) | `_targetGroupId`는 `_ScanPageState` 소유(`scan_page.dart:91`), `_openForm`의 `finally`가 부르는 `controller.reset()`(`:489`)은 **폼 세션의** targetGroupId만 비우고 페이지 선택은 유지 → 다음 `_openForm`이 `startWith(source, targetGroupId: _targetGroupId)`로 재공급(`:235`). 코드·주석(`:87-91`, `:233-234`)과 테스트("reset은 대상 그룹까지 비운다")가 폼측/페이지측을 각각 고정 — 의도 정합. 계속 등록은 await **전에** targetGroupId를 캡처한 뒤 `startWith(manual, targetGroupId:)`로 물려줌(stale 회피) — doc과 일치. 탈퇴 그룹 선택 잔존은 공유 실패로 흡수(`scan_page.dart:769-771` + 부분 실패 정책)되어 저장은 성공 |
| 6 | 매트릭스 정합 | **통과**(1건 누락 — minor 3) | 주의점 12의 항목들(watchGroups로 타일 구성·첫 타일=내 지갑 / addGifticon 성공 후 shareGifticon / Gifticon에 groupId 미추가 / 부분 실패 정책 / 식별자=groupId)이 구현과 항목별 일치. 페이지별 소비·생산 표의 scan 행도 갱신됨. 누락: scan이 실제로 소비하는 `ShareRepository.getGroupById`가 소비 목록·주의점 12에 없음 |

## 기계 검증
- `bash tool/check_ssot.sh`: 위반 없음 ✓
- `dart format --set-exit-if-changed .`: 0 changed ✓
- `flutter analyze`: No issues found! ✓
- `flutter test`: **150 passed** ✓ (feat/scan-camera 시점 109 → 신규 테스트 포함 증가, 회귀 0)

## 회귀 확인 (이전 리포트 지적 항목)
| 이전 지적 | 현재 | 근거 |
|---|---|---|
| [치명] Repository provider 중복 선언 → 인스턴스 분기 | **유지 수정됨** | scan 신규 provider도 SSOT를 watch. `lib/features`에 provider 재선언 0(SSOT guard ✓) |
| [치명] 삭제 파일 dead import | **유지 수정됨** | analyze 0 issues |
| feat/scan-camera 경계면 1~6 | **유지 통과** | submit 경로의 status=available·kDefaultCategory·ownerId·addGifticon 시그니처 무변경, 세션 가드 패턴 유지 |

## 발견 이슈 (심각도순 — 전부 비차단)

### [minor 1] 내부 `StateError.message`가 사용자 문구로 노출 — share 페이지 규약과 불일치
- 위치: `lib/features/scan/state/gifticon_form_state.dart:775` → `lib/features/scan/widgets/gifticon_form.dart` `_shareNote`
- 문제: `shareError = e is StateError ? e.message : '$e'`가 저장소 내부 영문 메시지를 그대로 담고, 스낵바가 그대로 출력한다 → `저장됨: 스타벅스 아메리카노 T (그룹 공유 실패: Group not found: g_family)`. 원문은 `in_memory_share_repository.dart:74/404/411`의 영문 + **raw groupId 노출**이다. 테스트 `scan_target_group_test.dart:214`가 `contains('g_gone')`으로 이 누출을 오히려 고정하고 있다. 계약은 `StateError`를 표시용이 아니라 가드/이중 방어로 규정하며(`share_repository.dart:13-15`), share 페이지는 전부 `on StateError`로 받아 **자체 한국어 중립 문구**를 쓴다(`member_invite_page.dart:138-144` "그룹이 없거나 재발급 권한이 없어요.", `group_detail_page.dart:285-288` "멤버를 내보낼 수 없어요. 다시 확인해 주세요.") — scan만 규약에서 이탈.
- 수정: scan에서 `on StateError` → 한국어 중립 문구로 매핑(예: '그룹을 찾을 수 없거나 공유 권한이 없어 그룹 공유만 실패했어요')하고, 원문은 `kDebugMode` 가드 하에 `debugPrint`로만 남긴다. 테스트 단언도 내부 id 대신 사용자 문구로 교체. 구조화된 에러 타입 도입은 계약 변경이므로 **페이지측 매핑을 우선**한다.
- 통지: scan-page-dev (규약 출처 확인용으로 share-page-dev 참조)

### [minor 2] `watchGroups` 로딩 순간 선택 표시가 사라짐 (데이터는 정상, 표시만 stale)
- 위치: `lib/features/scan/state/scan_target_group_state.dart:41-49` + `lib/features/scan/scan_page.dart:833`
- 문제: `scanTargetGroupsProvider`가 로딩·미로그인·빈 목록을 모두 빈 목록으로 접는다. 실 백엔드(Firebase `watchGroups`) 지연이나 세션 재방출로 일시 로딩이 생기면 그룹 타일이 사라지고, `data.groupId == selectedGroupId`가 `'내 지갑'`(null)에도 걸리지 않아 **어떤 타일도 선택으로 보이지 않는다**. 그런데 `_targetGroupId`는 살아 있어 그 순간 저장하면 실제로는 해당 그룹에 공유된다 → 화면이 실제 저장 대상을 과소 표기. `scan_page.dart:769-771` 주석은 이 상황을 "탈퇴로 사라진 경우"로만 서술해 로딩 케이스를 덮지 못한다.
- 수정: ①`_targetGroupId != null`인데 목록에 없으면 마지막으로 알던 그룹명으로 placeholder 선택 타일을 유지, 또는 ②`myGroupsProvider`처럼 로딩을 전파해 로딩 중에는 선택을 지우지 않기. 최소 조치로 주석에 로딩 케이스를 명기.
- 통지: scan-page-dev

### [minor 3] 매트릭스 문서 드리프트 — `getGroupById` 소비 누락
- 위치: `_workspace/01_contract_dependency_matrix.md` 페이지별 소비 표 scan 행 + 주의점 12
- 문제: scan이 안내 문구용으로 `ShareRepository.getGroupById(groupId)`를 실제 소비하는데(`gifticon_form_state.dart:768`) 문서에 없다. 또한 이번 변경에 대한 변경 이력 행이 없다(계약 무변경이므로 판단은 소유자 몫).
- 수정: scan 소비 목록에 `getGroupById(groupId)`(공유 성공 그룹명 조회, 실패 시 문구만 일반화) 추가. 이력 행 추가 여부는 contract-architect 판정.
- 통지: contract-architect (문서는 계약 소유자 영역 — `CODEOWNERS`)

### [minor 4] 승격 후보 발견 — "사용자별 그룹 스트림" provider 실질 중복 (규칙 ③ 충족)
- 위치: `lib/features/scan/state/scan_target_group_state.dart:29-37` ↔ `lib/features/share/state/share_providers.dart:26-42`
- 판정: `scanTargetGroupsProvider` 자체는 **중복이 아니다** — `myGroupsProvider`는 `AsyncValue`로 로딩을 전파하고 scan 쪽은 빈 목록으로 접는 등 **소비 형태가 달라** 정당한 별도 파생 provider다(SSOT 규약은 모델·enum·인터페이스·SSOT provider 재정의를 금지하며 페이지 파생 상태는 허용 — SSOT guard도 통과). 다만 그 **하위 두 provider는 본문이 사실상 동일**하다: `_scanCurrentUserProvider` ≡ `shareCurrentUserProvider`(`authRepositoryProvider.watchCurrentUser()`), `_scanGroupsByUserProvider` ≡ `_groupsByUserProvider`(`StreamProvider.family` → `watchGroups(userId)`). 즉 같은 조각의 **두 번째 실사용 소비자가 생겼다** → 승격 규칙 ③(투기적 아님, 실제 2번째 소비자) 충족.
- 부수 영향: 동일 사용자에 대해 `watchGroups` 스트림을 **두 번 구독**한다. in-memory에서는 무해하지만 Firebase에서는 `array-contains` 리스너가 두 개 붙는다(`firebase_share_repository.dart:89`) — 중복 읽기/과금.
- 조치: 페이지가 직접 `lib/shared`를 고치지 말고(`CODEOWNERS` 리뷰 강제) `contract-architect`에게 `lib/shared/providers/`로의 승격을 요청한다. 승격 시 계약 정본은 `AsyncValue`를 보존하는 형태로 두고, 로딩을 접는 정책은 scan 로컬 파생에 남기는 것이 두 소비자를 모두 만족시킨다. 매트릭스 "다음 승격 후보"에도 기록 필요(현재 "후보 없음"으로 적혀 있어 드리프트).
- 통지: contract-architect (주), scan-page-dev·share-page-dev (소비 전환 대상)

## 남은 리스크
- 실기기 검증 미수행(Windows 환경): 그룹 타일 4개 이상일 때의 `Wrap` 줄바꿈 레이아웃, 실제 Firebase `watchGroups` 지연 하에서의 minor 2 체감도.
- `FirebaseShareRepository.shareGifticon`의 1회 공유 불변식은 `_locks/{gifticonId}` 문서로 원자 강제됨을 **코드로만** 확인(에뮬레이터 실행 검증 미수행). in-memory 경로는 테스트로 고정됨.

---

# feat/share-error-ui 검증 (2026-07-31, integration-qa)

## 검증 대상
`git diff develop` + 미커밋 신규 파일. 신설 `lib/features/share/widgets/share_error_banner.dart`,
`test/features/share/share_error_ui_test.dart`; 수정 `share_providers.dart`(에러 감지 파생 3 + 재시도 진입점 4),
알림/사용이력/공유상세/그룹상세/share 메인/공유 시트, 매트릭스 #13.

설계 전제(리더 확정): 자동 재시도 금지 · 에러 감지는 원천 `hasError` · 폴딩(`valueOrNull`) 규약 무변경 ·
`lib/shared` 무수정 · 알림 읽음은 AsyncData 방출 후 1회.

## 요약
- 통과 6 / 실패 0 / 관찰·개선 7 (**차단 이슈 없음**)
- 기계 검증 4종 전부 green. 설계 전제 6개 모두 코드로 확인됨.
- 발견된 불일치는 전부 **보수적 방향**(에러를 과소 표시)이며, 엉뚱한 스트림의 에러가 다른 화면에
  뜨는 **오배선(cross-wiring)은 0건**이다. 실질 이슈는 "동작하지 않는 재시도 버튼" 2건과
  "다른 섹션의 false-empty 잔존" 1건.

## 기계 검증

| 항목 | 결과 |
|------|------|
| `bash tool/check_ssot.sh` | exit 0 (통과) |
| `dart format --set-exit-if-changed .` | exit 0 — `No issues found!` |
| `flutter analyze` | exit 0 — 이슈 0 |
| `flutter test` | exit 0 — QA 시점 165개 → **최종(리뷰 반영 후) 178개 전부 통과** |

## 경계면별 판정

| # | 경계면 | 생산자 (왼쪽) | 소비자 (오른쪽) | 판정 |
|---|--------|--------------|----------------|------|
| 1 | share → 계약 무수정 | `lib/shared/**` | 브랜치 diff | 통과 — `git diff develop -- lib/shared` 빈 출력, SSOT guard exit 0 |
| 1b | `markNotificationsRead` 시그니처·의미 | `share_repository.dart:190-193` | `group_notifications_page.dart:70` | 시그니처 일치 / dartdoc 문구 드리프트 ([minor 3]) |
| 2 | 알림 읽음 가드 4경로 | `notificationsProvider` | `_markReadWhenVisible` | (a)(b)(c)(d) 전부 성립, listen 누수 없음 / 미로그인 경로 1건 ([minor 1]) |
| 3 | 재시도 진입점 4개 | `retry*` | 원천 provider | 4/4 정확한 원천 지정 / family 과잉 invalidate ([minor 2]) |
| 4 | `myGroups` 재시도 불가 실측 | `my_groups_provider.dart:79/87/110` | `share_page.dart:81-89` | 프로브 결론 **정확**(Riverpod semantics상 옳음) / 계약 요청에 세션 계층 누락 ([minor 5]) |
| 5 | 배너 소비 정합(오배선) | 각 화면 표시 데이터 원천 | 각 화면 `hasError` 원천 | 오배선 0건 / 재시도 불가 케이스 2건 (`medium 1`, `minor 4`) + false-empty 1건 (`medium 2`) |
| 6 | scan/main 영향 0 | 브랜치 diff 범위 | — | 통과 — 변경은 `lib/features/share/**` + 매트릭스뿐 |

### #2 읽음 가드 4경로 추적 (코드 근거)
- **(a) 첫 프레임 데이터 존재** — `initState`의 `addPostFrameCallback` → `ref.read(notificationsProvider)`가
  `AsyncData` → 즉시 mark. `mounted` 가드 있음. 테스트 "정상 진입(데이터 방출)"이 고정.
- **(b) 늦은 도착** — `build`의 `ref.listen`이 이후 첫 `AsyncData`를 받아 mark. 테스트 "회복되어 목록이 보이면"이 고정.
- **(c) 에러→회복** — (b)와 동일 경로. 에러 진입 시 `readAt`이 `null`로 유지됨을 테스트가 단언(알림 보존).
- **(d) 이전 값 안은 AsyncLoading/AsyncError 제외** — `value is! AsyncData<...>`(`:63`)로 성립.
  Riverpod에서 `copyWithPrevious`된 로딩/에러는 각각 `AsyncLoading`/`AsyncError` 타입을 유지하므로
  타입 검사만으로 정확히 배제된다. **단 직접 테스트 없음**([minor 6]).
- **누수** — `ref.listen`을 `ConsumerState.build`에서 호출하는 것은 정규 용법이라 element와 함께 자동 해제된다.
  `_markRead()`는 `await` **이전에** `ref.read`를 끝내므로 dispose 후 ref 접근이 없다. 화면 재진입 시
  새 State가 `_markedRead=false`로 시작해 재호출되는데, 연산이 멱등이라 정상.

### #4 Riverpod semantics 교차 확인
`ref.invalidate(P)`는 **P와 P의 dependents**를 무효화하며 **dependencies로는 전파되지 않는다**.
`myGroupsProvider`(`:110`)는 같은 파일의 private `_currentUserProvider`(`:79`)·`_groupsByUserProvider`(`:87`)를
`watch`하므로, `invalidate(myGroupsProvider)`는 본문만 재실행하고 **여전히 캐시된 `AsyncError`를 다시 읽는다**.
→ 프로브 결론 정확, `onRetry: null` 판단 타당.
보강 근거: autoDispose에 기대는 우회(무효화 순간 마지막 리스너가 떨어져 private family가 자멸하기를 기대)도
**신뢰 불가**다 — 재빌드가 같은 tick 안에서 다시 `watch`하므로 autoDispose 스윕과의 순서가 Riverpod 내부
구현에 의존한다. 정본 훅이 유일한 해법이라는 매트릭스 결론이 맞다.
매트릭스 "계약 요청" 항목은 대상 provider·원인·구체적 형태 2안(`refreshMyGroups(Ref)` / `myGroupsRetryProvider`)을
명시해 **후속 실행 가능 수준**이다. 다만 [minor 5]의 세션 계층 누락을 보완할 것.

## 발견 이슈 (심각도순 — 전부 비차단)

> **처리 결과(리더 반영, 같은 브랜치에서 해소 — 아래 원문은 발견 시점 기록으로 보존):**
>
> | 이슈 | 상태 | 근거 위치 |
> |------|------|-----------|
> | `medium 1` | ✅ 해소 | `shared_gifticon_detail_page.dart` — `myGroupListUnavailableProvider` 분기로 `onRetry` null 강등 |
> | `medium 2` | ✅ 해소 | `share_page.dart` — 공유 빈 안내를 `!groupsUnavailable`(+로딩)로 게이트 |
> | `minor 1` | ✅ 해소 | `group_notifications_page.dart` — 실패 시 `_markedRead` 복원(비-StateError 포함) + 복원 직후 재평가 |
> | `minor 2` | ✅ 해소 | `share_providers.dart` — `retrySharedGifticons(ref, groupId:)` 스코프 재시도(그룹 상세가 `group.id` 전달), 인자 없는 경로도 실패 인스턴스만 invalidate |
> | `minor 3` | ✅ 해소 | `share_repository.dart` dartdoc 정정(계약 소유자 수행 — CODEOWNERS 리뷰 대상) |
> | `minor 4` | ✅ 해소 | `share_sheets.dart` — `medium 1`과 동일 분기 |
> | `minor 5` | ✅ 해소 | 매트릭스 #13 계약 요청에 `_currentUserProvider` 계층 + 세션 승격 연계 명시 |
> | `minor 6` | ✅ 해소 | `share_error_ui_test.dart` — 이력/시트 재시도·`groupsFail` false-empty·스코프 재시도·순단 보존·로딩 게이트 회귀 추가 |
> | `minor 7` | ✅ 해소 | `usage_log_page.dart` — 그룹 축 `onRetry: null` 배너 추가 |

### [medium 1] 공유 상세: `myGroups` 에러일 때 동작하지 않는 재시도 버튼
- 위치: `lib/features/share/pages/shared_gifticon_detail_page.dart:37,47`
- 문제: 배너 조건은 `sharedItemLookupHasErrorProvider`(= `myGroups.hasError || sharedGifticonsHaveError`)인데
  재시도는 `retrySharedGifticons(ref)` 하나뿐이다. 에러 출처가 **`myGroups` 쪽이면** 이 재시도는
  `sharedGifticonsProvider`만 invalidate하므로 아무 효과가 없다. 더구나 `myGroups`가 에러면
  `sharedGifticonsHaveErrorProvider`는 그룹 목록이 빈 목록으로 접혀 `false`를 반환하므로
  (`share_providers.dart:215-222`), **이 경로에서 배너의 유일한 원인이 곧 재시도 불가능한 원인**이다.
  사용자는 눌러도 배너가 사라지지 않는 버튼을 반복해서 누르게 된다.
- 규약 위반: `share_error_banner.dart:16-18`이 스스로 "재시도 경로가 실제로 없는 원천에서는 버튼을 숨긴다"고
  규정했는데, 이 화면이 그 규칙을 지키지 못한다(`share_page.dart:87`의 '내 그룹' 배너는 지킴 — 비대칭).
- 수정: 재시도 가능 여부를 원인별로 갈라 넘긴다.
  `onRetry: ref.watch(myGroupsProvider).hasError ? null : () => retrySharedGifticons(ref)`
  (버튼이 사라질 때의 문구는 share 메인 '내 그룹' 배너와 같은 톤으로 "앱을 다시 열어 주세요" 안내 권장.)
- 통지: share-page-dev

### [medium 2] share 메인: `myGroups` 에러 시 '공유 기프티콘' 섹션에 false-empty 잔존
- 위치: `lib/features/share/share_page.dart:56,116,123-124`
- 문제: `sharedGifticonsHaveErrorProvider`가 배너 중복을 피하려 `myGroups` 에러를 **의도적으로 제외**한다
  (설계 의도 자체는 타당). 그런데 `myGroups`가 에러면 (1) `allSharedProvider`가 빈 목록으로 접히고
  (2) `sharedHaveError`는 그룹 순회가 0회라 `false`가 된다 → `:123-124`가 **"공유된 기프티콘이 없어요."**를
  띄운다. 이번 변경이 없애려던 바로 그 "실패를 없음으로 위장" 현상이, 자기 배너 바로 아래 섹션에 남는다.
  (사용 이력 섹션은 독립 스트림이라 영향 없음.)
- 수정: 공유 섹션의 빈 안내를 그룹 에러에도 게이트한다 —
  `if (shared.isEmpty && !sharedHaveError && !groupsHaveError)`.
  그룹 에러 시에는 아무것도 띄우지 않거나(위 배너가 이미 설명) 중립 placeholder를 쓴다.
  `group_detail_page`는 그룹이 인자로 확정돼 들어오므로 이 문제가 없다(그쪽 배선이 모범).
- 통지: share-page-dev

### [minor 1] 알림 읽음 1회 가드가 '미로그인 AsyncData(빈 목록)'에 소모됨
- 위치: `lib/features/share/pages/group_notifications_page.dart:63-65, 68-73`
- 문제: 세션이 `data(null)`이면 `notificationsProvider`가 `const AsyncData(<GroupNotification>[])`를 돌려주는데
  (`share_providers.dart:124-125`) 이것도 `AsyncData`라 가드를 통과한다 → `_markedRead = true`로 확정되고
  `markNotificationsRead()`는 `StateError`로 조용히 삼켜진다(`:71-73`). 이후 **진짜 세션이 도착해 목록을 보여도
  읽음 처리가 영영 일어나지 않아 뱃지가 남는다.** 실서버 `authStateChanges()`가 복원 전 `null`을 먼저 방출하는
  패턴에서 재현 가능하나, 이 화면은 로그인 상태의 share 탭에서만 진입하므로 실사용 노출은 낮다.
- 수정: 실패 시 가드를 되돌린다 —
  `on StateError { _markedRead = false; }` (또는 `_markReadWhenVisible`에서 미로그인일 때 아예 mark 시도를 건너뛰기).
  전자가 최소 변경.
- 통지: share-page-dev

### [minor 2] `retrySharedGifticons`가 family 전 인스턴스를 invalidate — 그룹 상세에서 과잉 재구독
- 위치: `lib/features/share/state/share_providers.dart:270-273` ↔ `lib/features/share/pages/group_detail_page.dart:169-171`
- 문제: 그룹 상세의 배너는 **그 그룹만**(`sharedGifticonsProvider(group.id)`) 관찰하는데, 재시도는 인자 없는
  `ref.invalidate(sharedGifticonsProvider)`라 **내 모든 그룹의 스트림을 재구독**한다. 정확성 문제는 없으나
  Firestore에서는 실패하지 않은 그룹들까지 리스너가 재시작돼 불필요한 문서 읽기·과금이 발생한다
  (그룹 N개면 1건 실패에 N건 재구독). share 메인·공유 시트는 전 그룹을 합쳐 보므로 전체 무효화가 맞다.
- 수정: 선택 인자를 추가해 호출부가 범위를 정하게 한다 —
  `void retrySharedGifticons(WidgetRef ref, {String? groupId})` → `groupId != null`이면
  `ref.invalidate(sharedGifticonsProvider(groupId))`, 아니면 기존 전체 무효화. 그룹 상세만
  `retrySharedGifticons(ref, groupId: group.id)`로 바꾼다.
- 통지: share-page-dev

### [minor 3] 계약 dartdoc 드리프트 — "알림 화면 진입 시 호출"
- 위치: `lib/shared/repositories/share_repository.dart:192`
- 판정: **계약 충돌 아님(문구 드리프트).** 규범적 계약((1) 세션 없으면 `StateError` (2) 마지막 읽음 시각을 현재로 갱신)은
  양쪽 모두 그대로다. 바뀐 것은 *호출 시점*뿐이고, "진입 시 호출해 안읽음을 해소한다"는 **호출자 가이드 문장**이다.
  `markNotificationsRead`의 소비자는 `group_notifications_page.dart:70` **단 하나**임을 전수 확인했으므로
  다른 페이지에 파급이 없고, 변경 방향도 엄격히 안전한 쪽(못 본 알림 유실 방지)이다. 코드 수정 불필요.
- 수정: 계약 dartdoc을 실제 규약에 맞게 정정 요청 — 예: "알림 화면이 **목록을 실제로 표시한 뒤** 호출해 안읽음을
  해소한다(로딩·에러 중 호출하면 못 본 알림이 읽음 처리돼 유실된다)." 매트릭스 #13에는 이미 반영돼 있어
  **드리프트는 계약 파일 쪽에만 남아 있다.** `lib/shared`는 `CODEOWNERS` 대상이므로 페이지 담당이 직접 고치지 않는다.
- 통지: contract-architect (주), share-page-dev

### [minor 4] 공유 시트도 [medium 1]과 같은 계열 — `myGroups` 에러 시 무효 재시도
- 위치: `lib/features/share/widgets/share_sheets.dart:288-294`
  (`shareCandidatesHaveErrorProvider` ← `sharedItemLookupHasErrorProvider` ← `myGroups.hasError`)
- 문제: `retryShareCandidates`는 `_gifticonsByUserProvider` + `sharedGifticonsProvider`만 되살리므로 `myGroups`
  에러는 해소 못 한다. 다만 시트는 닫고 다시 열 수 있고 저장소 `StateError` 가드가 최후 방어선이라 체감 영향은
  [medium 1]보다 작다.
- 수정: [medium 1]과 동일 패턴(`myGroups.hasError`면 `onRetry: null`) 적용. 정본 재시도 훅이 생기면 두 곳 모두 자연 해소.
- 통지: share-page-dev

### [minor 5] 매트릭스 계약 요청이 '세션 계층'을 포함하지 않음 — 훅만으로는 절반만 해소
- 위치: `_workspace/01_contract_dependency_matrix.md` 신규 "계약 요청(share → contract-architect, #13 후속)"
  ↔ `lib/features/share/state/share_providers.dart:250-254` ↔ `lib/shared/providers/my_groups_provider.dart:79`
- 문제: `_retrySessionIfFailed`는 share의 `shareCurrentUserProvider`만 invalidate한다. 그러나 `myGroupsProvider`는
  **정본 파일 내부의 별도 `_currentUserProvider`**를 쓴다(같은 `watchCurrentUser()`의 두 번째 구독 — 매트릭스가
  "아직 정본이 아닌 것"으로 이미 기록한 그 중복). 즉 인증 스트림이 실패하면 **캐시된 에러가 두 개** 생기고,
  share의 재시도 버튼을 전부 눌러도 그룹 목록 쪽 절반은 살아나지 않는다. 요청서가 `watchGroups` 계층만 언급하면
  훅을 받아도 이 경로가 남는다.
- 수정: 계약 요청에 "훅이 `_groupsByUserProvider`뿐 아니라 `_currentUserProvider`도 되살려야 한다"를 명시하거나,
  이미 후보로 올라 있는 **세션 스트림 승격**과 묶어 처리하도록 의존 관계를 적는다.
- 통지: contract-architect (주), share-page-dev

### [minor 6] 신규 테스트의 커버리지 공백
- 위치: `test/features/share/share_error_ui_test.dart`
- 문제: 재시도 4개 중 **2개만 실증**된다 — `retryNotifications`(구독 1→2)·`retrySharedGifticons`(증가)는 O,
  `retryUsageLogs`·`retryShareCandidates`는 미검증. 또한 가드 경로 (d)(이전 값을 안은 `AsyncLoading`/`AsyncError` 배제)와
  share 메인 섹션별 배너·그룹 상세 그룹별 배너가 테스트로 고정돼 있지 않다. 특히 [medium 2]는 테스트가 있었다면
  잡혔을 케이스다(`myGroups` 에러 시 share 메인 렌더링).
- 수정: `_FlakyShareRepository`에 `usageLogsFail`/`groupsFail` 토글과 `usageLogSubscriptions` 카운터를 추가해
  (1) 사용 이력 배너+재시도 재구독 (2) 공유 시트 배너+재시도 (3) `groupsFail=true`일 때 share 메인이
  "공유된 기프티콘이 없어요"를 띄우지 않는지(= [medium 2] 회귀 고정)를 추가한다.
- 통지: share-page-dev

### [minor 7] 사용 이력 화면: `myGroups` 에러가 표시되지 않음(그룹 필터가 조용히 사라짐)
- 위치: `lib/features/share/pages/usage_log_page.dart:42-43`
- 문제: 이 화면은 `usageLogsProvider`(배너 O)와 별개로 `myGroupsProvider`를 빈 목록 폴딩으로 소비해 그룹 필터를 만든다.
  그룹 목록이 실패하면 **필터 UI만 조용히 사라지고** 사용자는 이유를 모른다. 주 데이터(이력)의 false-empty는 아니라
  영향은 작다.
- 수정: 그룹 필터 영역에 `onRetry: null` 배너를 얹거나(정본 훅 도착 시 버튼 부여), 최소한 주석으로 알려진 한계를 남긴다.
- 통지: share-page-dev

## 통과 항목 (교차 비교 근거)
- **재시도 진입점 ↔ 원천 매핑 4/4 정확**: `retryNotifications` → `_notificationsByUserProvider` + `_notifReadAtByUserProvider`
  (= `notificationsProvider`/`notificationsReadAtProvider`의 실제 원천) · `retryUsageLogs` → `_usageLogsByUserProvider` ·
  `retrySharedGifticons` → `sharedGifticonsProvider` · `retryShareCandidates` → `_gifticonsByUserProvider` + `sharedGifticonsProvider`
  (= `unsharedGifticonsProvider`의 두 원천). 폴딩된 파생을 재시도 지점으로 삼은 곳이 **한 곳도 없다**.
- **재구독 실증**: share의 파생은 모두 keepAlive라 invalidate 즉시 리스너가 살아 있는 채로 재빌드된다.
  테스트가 `notificationSubscriptions` 1→2, `sharedSubscriptions` 증가로 실제 재구독을 고정한다
  (인자 없는 family invalidate가 전 인스턴스에 적용됨도 이로써 실증).
- **자동 재시도 부재 실증**: 에러 후 `pump(1s)`에도 구독 수가 1로 유지됨을 단언 — retry storm 방어가 회귀로 고정됨.
- **에러 감지 원천 정합**: 5개 화면 모두 자기가 표시하는 데이터의 원천을 관찰한다. 특히
  `sharedItemLookupHasErrorProvider`는 `sharedItemByIdProvider`가 순회하는 **두 원천을 정확히** 합쳤다(누락·과잉 없음).
  **다른 스트림의 에러가 엉뚱한 화면에 뜨는 오배선은 0건.**
- **폴딩 규약 무변경**: 모든 소비 지점이 `valueOrNull ?? const []`를 유지하고 `.value` 재유입이 없다(analyze·수동 확인).
- **테마 SSOT 준수**: `share_error_banner.dart`는 색을 `colorScheme.error` 계열, 반경을 `AppRadii.tile`에서만 가져온다(하드코딩 0).
- **내부 에러 메시지 비노출**: 5개 배너 문구 전부 한국어 중립 문구이며 `StateError.message`·raw id 노출 없음.
- **scan/main 영향 0**: 변경 파일이 `lib/features/share/**` + 매트릭스로 한정됨을 `git diff develop --name-only`로 확인.

## 남은 리스크
- `myGroups` 에러 경로는 이번 브랜치에서 **표시만 되고 회복 불가**다. 정본 재시도 훅([minor 5] 포함)이 도착하기
  전까지 사용자의 유일한 복구 수단은 앱 재시작이며, 배너 문구도 그렇게 안내한다(의도된 상태).
- 실기기·실서버(Firestore) 검증 미수행(Windows 환경). 특히 [minor 2]의 과잉 재구독 비용과, 실제
  `authStateChanges()` 초기 `null` 방출로 인한 [minor 1] 재현성은 코드 추론 기반이다.

---

# refactor/shared-session-retry 검증 (2026-07-31, integration-qa)

## 검증 대상
`git diff develop`(c2765e9 분기, 전부 미커밋) + 신규 파일.
신설 `lib/shared/providers/session_provider.dart`, `test/shared/providers/session_and_retry_test.dart`;
수정 `my_groups_provider.dart`(내부 `_currentUserProvider` 삭제 + 재시도 훅), `share_providers.dart`
(별칭 전환 + 재시도 재배선), share 화면 4개, `share_error_banner.dart`, `share_error_ui_test.dart`,
`tool/check_ssot.sh`, 매트릭스 v2.6.

## 요약

> ⚠️ 이 절부터 아래는 **QA 검증 시점의 스냅샷 기록**이다 — 발견 이슈 4건은 같은
> 브랜치에서 전부 해소됐다("발견 이슈" 절 상단의 처리 결과 표가 최종 상태이며,
> 테스트 수도 리뷰 라운드 반영 후 **193**이 최종이다).

- 통과 8 / 이슈 4 (medium 1 · minor 3) / 미검증 0 — **차단 이슈 없음**
- 기계 검증 4종 전부 green (테스트 189 — QA 시점, 최종은 193).
- 이번 슬라이스의 핵심 주장(세션 구독 단일화 · 훅 스코프 · 별칭 무해성 · 수명 체인)은 **전부 코드/실측으로 확인됨.**
- 유일한 실질 이슈 `medium 1`은 이번 변경이 만든 것이 아니라 **이번 변경이 드러낸** 기존 비대칭이다
  (세션 정본화로 그룹 축과 알림/이력 축이 **같은 스트림 인스턴스**를 보게 되면서, 같은 순단에
  두 축이 정반대로 반응하는 것이 비로소 관측 가능해졌다).

## 기계 검증

| 항목 | 결과 |
|------|------|
| `bash tool/check_ssot.sh` | exit 0 — `위반 없음 ✓` |
| `dart format --set-exit-if-changed --output=none lib test` | exit 0 |
| `flutter analyze` | exit 0 — `No issues found!` |
| `flutter test` | exit 0 — QA 시점 189개 → **최종(리뷰 라운드 반영 후) 193개 전부 통과** |

## 경계면별 판정

| # | 경계면 | 생산자 (왼쪽) | 소비자 (오른쪽) | 판정 |
|---|--------|--------------|----------------|------|
| 1 | 세션 단일화 실증 | `session_provider.dart:95-98` | `watchCurrentUser()` 구독 전수(grep) | **통과** — lib 내 직접 구독 4곳: 정본 1 + 잔여 3(`auth_gate.dart:20`, `gifticon_list_providers.dart:27`, `mypage_page.dart:39`). share 경로 자체 구독 **0** |
| 2 | 훅 스코프(에러 계층만) | `MyGroupsRetry.retry()` (`my_groups_provider.dart:193-205`) | 배너 콜백 | **통과** — `hasError` 가드 2중, family는 현재 user 인스턴스만 |
| 2b | 분담 규약(겹쳐 부르지 않음) | `_retrySessionIfFailed` (`share_providers.dart:321`) | `retry*` 5개 호출 그래프 | **통과** — 커버 공백 0 / 이중 커버 0 (아래 표) |
| 3 | 별칭 함정 | `shareCurrentUserProvider` (`share_providers.dart:52`) | 소비처 전수 | **통과** — `invalidate(별칭)` 잔존 **0건**, StreamProvider 전용 API(`.future`/`.stream`/`.notifier`) 사용 **0건**, 테스트 override **0건** |
| 4 | 읽음 가드 회귀 | `notificationsProvider` (`share_providers.dart:139-149`) | `_markReadWhenVisible` (`group_notifications_page.dart:60-71`) | **통과** — 미로그인 `data(null)`→`AsyncData([])`→가드 통과→저장소 `StateError`→`_markedRead` 복원 경로 유지. 단 `medium 1`의 부수효과 있음 |
| 5 | autoDispose 수명 체인 | `sessionUserProvider`(autoDispose) | 별칭(keepAlive) / 훅(keepAlive) | **통과**(실측) — 훅의 `ref.read`는 붙잡지 않음(PROBE A=0), 별칭은 붙잡음(PROBE B=1, 의도) |
| 6 | SSOT/재선언 | `tool/check_ssot.sh:33` | `lib/features` | **통과** — 신규 2개 이름 실제 검출 확인(임시 프로브). 패턴 한계는 `minor 3` |
| 7 | 매트릭스 ↔ 코드 | 매트릭스 v2.6 | 실제 코드 | **대체로 일치** — 배너 4곳 배선·잔여 3곳·테스트 수(8/189)·별칭 판정 모두 확인. 수치 1건 불일치(`minor 1`) |
| 8 | main·scan 영향 | 브랜치 diff | — | **통과** — `lib/features/main`·`scan` 무수정, 계약 변경은 순수 추가 + 내부 대체 |

### #2b 재시도 호출 그래프 (세션 축 커버 교차 확인)

| 진입점 | 세션 축 | 그룹 축 | 하위 스트림 | 세션 중복? |
|--------|---------|---------|-------------|-----------|
| `retryMyGroups` (계약) | 직접(에러 시) | 현재 user 인스턴스 | — | — |
| `retryNotifications:348` | `_retrySessionIfFailed` | 없음(불필요) | 알림 + readAt | 없음 |
| `retryUsageLogs:366` | `_retrySessionIfFailed` | 없음(불필요) | 이력 | 없음 |
| `retrySharedGifticons:382` | `_retrySessionIfFailed` | 없음(불필요) | 그룹별 공유 | 없음 |
| `retrySharedItemLookup:399` | **`retryMyGroups` 경유** | 커버 | 실패 인스턴스 | 없음(`_retrySessionIfFailed` 미호출 — 규약대로) |
| `retryShareCandidates:412` | **`retryMyGroups` 경유** | 커버 | 내 기프티콘 + 실패 인스턴스 | 없음(동일) |

**커버 공백 0:** 사용자가 볼 수 있는 배너 9곳(share 메인 3 · 사용이력 2 · 알림 1 · 그룹상세 1 · 공유상세 1 · 시트 1)이
전부 `onRetry`를 갖고, 각 경로가 자기 에러 원인이 될 수 있는 모든 축을 덮는다. `onRetry: null` 사이트는 lib에 **0건**
(배너 dartdoc의 "휴면 규약" 서술이 정확하며, 위젯 단위 테스트가 그 분기를 직접 고정한다).

### #5 수명 체인 실측 (임시 프로브 — 검증 후 삭제)
- **PROBE A** — 세션을 watch하던 마지막 리스너를 닫은 뒤 `activeListens = 0`.
  keepAlive인 `myGroupsRetryProvider`가 `ref.read(sessionUserProvider)`로 정본을 만져도
  **수명을 붙잡지 않는다**(`read`는 일시 구독 후 해제). 훅이 세션 리스너를 누수시키지 않음이 확인됨.
- **PROBE B** — 별칭을 watch하던 리스너를 닫은 뒤에도 `activeListens = 1`.
  keepAlive 별칭이 autoDispose 정본을 **영구히 붙잡는다**. 이는 `my_groups_provider` 때와 **동일한 규약**이고
  승격 전(share 자체 StreamProvider도 keepAlive)과 체감 수명이 같으므로 **의도된 동작**이다.
  다만 dartdoc 문구는 부정확하다(`minor 2`).

## 발견 이슈 (심각도순 — 전부 비차단)

> **처리 결과(리더 반영, 같은 브랜치에서 해소 — 아래 원문은 발견 시점 기록으로 보존):**
>
> | 이슈 | 상태 | 근거 위치 |
> |------|------|-----------|
> | `medium 1` | ✅ 해소 | 폴딩을 계약 정본 함수 `foldSessionUser`(`session_provider.dart`)로 승격·통일 — 정본 `myGroupsProvider`와 share 파생 3곳이 같은 한 구현을 소비(순단 회귀 테스트 3건 + 양성 대조 단언으로 고정, 리뷰 라운드에서 에러-우선 분기·재시도 중 배너 유지까지 보강) |
> | `minor 1` | ✅ 해소 | 매트릭스 소비처 수치 12곳 정정 + 리뷰 라운드에서 라인 좌표를 **심볼 기반** 체크리스트로 교체(좌표 부패 재발 방지) |
> | `minor 2` | ✅ 해소 | `shareCurrentUserProvider` dartdoc 수명 서술을 실측(컨테이너 수명 유지)에 맞게 정정 |
> | `minor 3` | ✅ 해소 | `check_ssot.sh` 3검사 보강(언더스코어 접두·계약 클래스·계약 함수) + 리뷰 라운드에서 수식어/`dynamic`/제네릭/타입 생략 선언까지 확장(프로브 실증), 이름 기반 가드의 한계는 주석·매트릭스에 정직 기록 |

### [medium 1] 세션 순단 시 share 파생 3곳이 계약 정본과 **정반대로** 동작한다 (`.when` vs `valueOrNull`)
- 위치: `lib/features/share/state/share_providers.dart:123`(`usageLogsProvider`),
  `:141`(`notificationsProvider`), `:190`(`shareableGifticonsProvider`)
- 문제: 세 provider는 세션 `AsyncValue`를 **`.when(...)`** 으로 분기한다. `AsyncValue.when`은
  `skipError`가 기본 `false`라, **이전 값을 보존한 순단 에러**(`copyWithPrevious`)에서도 `error` 분기를 타
  하위 스트림의 멀쩡한 데이터를 통째로 버린다. 반면 계약 정본 `myGroupsProvider`는 같은 상황을
  `valueOrNull` 기반으로 접어(`my_groups_provider.dart:113-139`) **보존된 user로 하위 스트림을 계속 반환**한다.
  정본 dartdoc(`session_provider.dart:34-37`, `my_groups_provider.dart:36-40`)이 명시한
  "접을 때는 `valueOrNull`" 규약과 어긋나는 잔여 지점이다.
- 실측(임시 프로브, 세션 스트림에 순단 에러 주입):

  ```text
  BEFORE groups=1 notifs=1
  AFTER  groups: hasValue=true  len=1     hasError=false   <- 목록 유지, 배너 없음
  AFTER  notifs: hasValue=false len=null  hasError=true    <- 목록 소멸, 배너 표시
  ```

  같은 한 번의 세션 순단에 **'내 그룹'은 아무 일도 없고, 알림·사용이력·공유후보는 비워지며 배너가 뜬다.**
- 영향: ① share 메인에서 그룹 카드는 멀쩡한데 사용 이력만 사라지는 비대칭 화면.
  ② 알림 화면에서 **사용자가 읽고 있던 목록이 사라진다**(읽음 가드 자체는 보수적 방향이라 안전 —
  `AsyncData`가 아니므로 `readAt`을 찍지 않고, 회복되면 `ref.listen`이 다시 처리한다. 알림 유실 없음).
  ③ `shareCandidatesHaveErrorProvider`가 `shareableGifticonsProvider.hasError`를 포함하므로
  시트 배너도 세션 순단만으로 뜬다.
- **회귀 아님:** 승격 전 `shareCurrentUserProvider`도 StreamProvider라 `AsyncValue` 의미가 같았고
  `.when` 거동도 동일했다. 다만 정본화로 두 축이 **같은 스트림 인스턴스**를 보게 되면서
  "같은 순단, 정반대 반응"이 비로소 한 화면에서 동시에 관측 가능해졌다.
- 수정: 세 provider를 `myGroupsProvider`(`:113-139`)와 **같은 폴딩 형태**로 맞춘다. 예(알림):

  ```dart
  final session = ref.watch(shareCurrentUserProvider);
  final user = session.valueOrNull;
  if (user != null) return ref.watch(_notificationsByUserProvider(user.id));
  if (session.isLoading) return const AsyncLoading<List<GroupNotification>>();
  if (session.hasError) {
    return AsyncError<List<GroupNotification>>(
        session.error!, session.stackTrace ?? StackTrace.current);
  }
  return const AsyncData<List<GroupNotification>>(<GroupNotification>[]);
  ```

  **미로그인 확정(`data(null)`) → `AsyncData([])` 경로는 반드시 보존**해야 읽음 가드의
  `StateError` 복원 분기(`group_notifications_page.dart:78-84`)가 그대로 성립한다.
  회귀 테스트는 "세션 순단 시 알림 목록이 유지되고 배너가 뜨지 않는다"로 고정 권장.
- 통지: share-page-dev(구현), contract-architect(정본 폴딩 규약을 파생에도 적용할지 판정)

### [minor 1] 매트릭스의 별칭 소비처 수치가 실제와 다르다 (후속 슬라이스의 체크리스트 숫자)
- 위치: `_workspace/01_contract_dependency_matrix.md` #13 — "소비처(이 파일의 파생 + **화면 5곳, 총 10곳**)",
  v2.6 변경 이력 "소비처 10곳 무수정", 후속 목록 "소비처 10곳 직수입 치환"
- 실제(grep 전수): **화면 4곳**(`group_detail_page.dart:67`, `member_invite_page.dart:187`,
  `shared_gifticon_detail_page.dart:78`, `share_page.dart:70`) + `share_providers.dart` 내부 8곳
  (`watch` 파생 5: `:123 :141 :160 :190 :428` / `read` 3: `:350 :368 :414`) = **총 12곳**.
- 문제: 별칭 제거가 후속 슬라이스의 실행 항목인데, 그 체크리스트 숫자가 틀리면 `retry*` 함수 안의
  `read` 3곳이 누락된 채 "완료" 판정될 수 있다.
- 수정: "화면 4곳 + 파일 내부 8곳(`watch` 5 / `read` 3) = 12곳"으로 정정.
- 통지: contract-architect

### [minor 2] 별칭 수명 서술이 실제보다 좁다
- 위치: `lib/features/share/state/share_providers.dart:46-47`
  — "별칭은 keepAlive라 **share 탭이 살아 있는 동안** autoDispose 정본의 수명을 붙잡는다"
- 문제: PROBE B 실측 결과 별칭이 **한 번이라도 빌드되면** 마지막 리스너가 떨어진 뒤에도 정본 구독이
  유지된다(`activeListens`가 1로 잔존). 즉 실제 수명은 "share 탭이 살아 있는 동안"이 아니라
  **ProviderContainer 수명 내내**다(로그아웃 후에도 유지). 동작 자체는 승격 전과 같아 문제없지만,
  서술이 좁아 후속에 "탭을 닫으면 풀린다"는 잘못된 전제를 만든다.
- 수정: "share 탭을 한 번 연 뒤로는 컨테이너 수명 동안"으로 정정.
  (`session_provider.dart:44-48`의 서술은 정확하다 — 이 한 줄만 어긋난다.)
- 통지: share-page-dev

### [minor 3] SSOT guard 패턴이 잡지 못하는 재선언 형태
- 위치: `tool/check_ssot.sh:33-39`
- 실측(임시 프로브 파일로 확인) — 신규 2개 이름은 정상 검출되나 다음은 **통과해 버린다**:

  | 형태 | 검출 |
  |------|------|
  | `final sessionUserProvider = ...` | 검출됨 |
  | `final _sessionUserProvider = ...` (언더스코어 접두) | **미검출** |
  | `void retryMyGroups(WidgetRef ref) {}` (훅 함수 재정의) | **미검출** |
  | `class MyGroupsRetry {}` (훅 클래스 재정의) | **미검출** |

- 문제: 언더스코어 접두는 **이번에 삭제된 `_currentUserProvider`와 정확히 같은 형태**이자
  scan의 `_scanCurrentUserProvider`가 그랬던 실제 재발 경로인데, 가드가 못 잡는다.
  훅은 이번 v2.6에서 계약 API가 됐으나 `SHARED_TYPES`·`SSOT_PROVIDERS` 어디에도 없다.
- 수정: ① provider 정규식의 이름 앞에 `_?`를 허용, ② `SHARED_TYPES`에 `MyGroupsRetry` 추가,
  ③ 훅 함수용 3번째 검사 추가.
  ※ 이름 기반 가드의 근본 한계(다른 이름의 의미상 중복 — main `currentUserProvider` 등)는
  이 가드로 막을 수 없다. 잔여 3곳 전환이 끝날 때까지는 매트릭스 잔여 표가 유일한 방어선이다.
- 통지: contract-architect

## 회귀 확인 (직전 리포트 `feat/share-error-ui` 지적 항목)

| 이전 이슈 | 현재 상태 | 근거 |
|-----------|----------|------|
| `medium 1` 공유 상세 무력한 재시도 버튼 | **더 강하게 해소** — null 강등 대신 `retrySharedItemLookup`(그룹+공유 두 축) | `shared_gifticon_detail_page.dart:56`, 신규 테스트가 `groupSubscriptions` 증가 단언 |
| `medium 2` 공유 섹션 false-empty | 유지 | `share_page.dart:138-141` — `!groupsUnavailable && !sharedPending` 게이트 존속 |
| `minor 1` 읽음 가드 복원 | 유지 | `group_notifications_page.dart:84-94` — `_markedRead=false` + 복원 직후 재평가 |
| `minor 2` 스코프 재시도 | 유지·확장 | `retrySharedGifticons(ref, groupId:)`(`group_detail_page.dart:175`) + `_retryFailedSharedInstances` |
| `minor 4` 시트 무력한 버튼 | **더 강하게 해소** — `retryShareCandidates`가 그룹 축까지 커버 | `share_sheets.dart:304`, 테스트 단언 |
| `minor 5` 계약 요청에 세션 계층 누락 | **구조적으로 해소** — 세션 정본화로 중복 캐시 에러 소스 자체가 제거 | `my_groups_provider.dart:85,115` |
| `minor 7` 사용이력 그룹 축 배너 | **버튼까지 부활** | `usage_log_page.dart:98` — `retryMyGroups(ref)` |

**신규 회귀 없음.** 이전에 `onRetry: null`로 강등됐던 4곳이 전부 실제 재시도로 승격됐고,
그때 함께 도입된 false-empty 게이트·읽음 가드·스코프 재시도는 모두 그대로 남아 있다.

## 통과 항목 (교차 비교 근거)
- **세션 구독 수** — 정본 1 + 잔여 3(main·mypage·조립부). share는 0(별칭 pass-through).
  매트릭스 잔여 표와 grep 결과가 정확히 일치.
- **훅 스코프** — `retry()`가 `session.hasError` / `_groupsByUserProvider(user.id).hasError`를
  각각 확인한 뒤에만 invalidate. family 전체 무효화 없음. 세션에 알려진 user가 없으면 그룹 계층 미접촉.
- **별칭 안전성** — 무력한 `invalidate(별칭)` 0건, StreamProvider 전용 API 소비 0건.
  타입 변경(`StreamProvider<User?>` → `Provider<AsyncValue<User?>>`)으로 깨지는 소비처 없음
  (전 소비처가 `valueOrNull`/`when`만 사용).
- **읽음 가드** — 미로그인 `data(null)` → `AsyncData([])` → 가드 통과 → `StateError` → 복원 경로가
  정본 `AsyncValue` 규약(`AsyncData(null)` = 미로그인 확정)과 정합.
- **테스트 커버리지** — 신규 `session_and_retry_test.dart` 8개(구독 1회 / autoDispose 수명 /
  훅 4경우 / `invalidate(myGroupsProvider)` 무력함 실증 / 회복 / `WidgetRef` 진입점),
  `share_error_ui_test.dart`에 재시도 부활 4 + 스코프 회귀 1 + 배너 휴면 규약 1.
  기존 `my_groups_provider_test.dart` 무수정 통과 = 동작 불변의 증거.

## 남은 리스크 (발견 당시 기록 — `medium 1`은 이후 해소됨, 상단 처리 결과 표 참조)
- **`medium 1` 미해소 시(→ 해소됨):** 세션이 불안정한 실환경(모바일 네트워크 전환 등)에서 share 탭의 세 섹션이
  근거 없이 깜빡이며 비워진다. 데이터 유실은 없고 재시도 경로도 있으나, 이번 슬라이스가 내세운
  "인스턴스/타이밍 일관성"이라는 이득을 화면 층에서 스스로 깎는다.
- **잔여 3곳(main·mypage·조립부) 전환 전까지** 세션 구독은 여전히 4개다. 계정 전환 프레임에서
  main과 share가 한 프레임 어긋날 수 있다(share↔그룹 목록 간 어긋남은 이번에 해소됨).
- **별칭 제거 슬라이스**는 `minor 1`의 정정된 12곳을 기준으로 진행해야 한다.
