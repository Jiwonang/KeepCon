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
