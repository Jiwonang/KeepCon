# KeepCon 공유 계약 의존성 매트릭스 (v1)

> 단일 진실 원천(SSOT). 페이지 개발자와 QA는 이 문서를 경계면 검증의 기준으로 삼는다.
> 이번 검증 슬라이스 범위: **scan(생산) → main(소비)**. auth는 인터페이스+mock으로 대체.
> 계약 위치: `lib/shared/`. 이 문서와 소스가 어긋나면 소스가 아니라 **양쪽을 함께** 갱신한다.

작성일: 2026-07-06 · 최종 갱신: 2026-07-30 · 계약 버전: v2.5 (내 그룹 목록 provider 승격)

---

## 계약 요약

| 계약 | 종류 | 위치 | v |
|------|------|------|---|
| `User` | model | `lib/shared/models/user.dart` | 1 |
| `Gifticon` | model | `lib/shared/models/gifticon.dart` | 1 |
| `GifticonStatus` (available/used/expired) | enum | `lib/shared/models/gifticon.dart` | 1 |
| `SortOption` (expiryAsc/registeredDesc/brandAsc) | enum | `lib/shared/models/gifticon.dart` | 1 |
| `FilterOption` (status/category) | enum | `lib/shared/models/gifticon.dart` | 1 |
| `GifticonStatusTransition.isAllowed(from, to)` | 전이 규칙 | `lib/shared/models/gifticon.dart` | 1 |
| `AuthRepository` | interface | `lib/shared/repositories/auth_repository.dart` | 1 |
| `AuthRepository.currentUser` → `User?` (getter) | method | 〃 | 1 |
| `AuthRepository.watchCurrentUser()` → `Stream<User?>` | method | 〃 | 1 |
| `GifticonRepository` | interface | `lib/shared/repositories/gifticon_repository.dart` | 1 |
| `GifticonRepository.addGifticon(Gifticon)` → `Future<Gifticon>` | method | 〃 | 1 |
| `GifticonRepository.watchGifticons(String ownerId)` → `Stream<List<Gifticon>>` | method | 〃 | 1 |
| `GifticonRepository.getGifticons(String ownerId)` → `Future<List<Gifticon>>` | method | 〃 | 1 |
| `GifticonRepository.getGifticonById(String id)` → `Future<Gifticon?>` | method | 〃 | 1 |
| `GifticonRepository.updateStatus(String id, GifticonStatus status)` → `Future<Gifticon>` | method | 〃 | 1 |
| `InMemoryAuthRepository` | mock impl | `lib/shared/repositories/impl/in_memory_auth_repository.dart` | 1 |
| `InMemoryGifticonRepository` | mock impl | `lib/shared/repositories/impl/in_memory_gifticon_repository.dart` | 1 |
| `authRepositoryProvider` (`Provider<AuthRepository>`) — **SSOT** | provider | `lib/shared/providers/repositories.dart` | 1 |
| `gifticonRepositoryProvider` (`Provider<GifticonRepository>`) — **SSOT** | provider | `lib/shared/providers/repositories.dart` | 1 |
| `FirebaseAuthRepository` (`AuthRepository` 구현) | firebase impl | `lib/shared/repositories/impl/firebase/firebase_auth_repository.dart` | 1 |
| `FirebaseGifticonRepository` (`GifticonRepository` 구현) | firebase impl | `lib/shared/repositories/impl/firebase/firebase_gifticon_repository.dart` | 1 |
| `initFirebaseAndBuildOverrides()` → `Future<List<Override>>`, `firebaseProviderOverrides()` → `List<Override>` | bootstrap | `lib/shared/firebase/firebase_bootstrap.dart` | 1 |
| `DefaultFirebaseOptions.currentPlatform` (플레이스홀더 스텁) | firebase config | `lib/firebase_options.dart` | 1 |
| `AppRoutes.main` = `'/main'`, `AppRoutes.scan` = `'/scan'`, `AppRoutes.share` = `'/share'` | route | `lib/shared/routes.dart` | 1 |
| **공유 디자인 테마 = SSOT** (`AppColorsLight`/`AppColorsDark`/`AppColorsCommon`) | design tokens | `lib/shared/theme/app_colors.dart` | 1.3 |
| `AppTheme.light` / `AppTheme.dark` → `ThemeData` (Material3) | theme factory | `lib/shared/theme/app_theme.dart` | 1.3 |
| `themeModeProvider` (`NotifierProvider<ThemeModeController, ThemeMode>`, 기본 `ThemeMode.light`) — **SSOT** | provider | `lib/shared/providers/theme_mode_provider.dart` | 1.3 |
| `ThemeModeController.set(ThemeMode)` / `.setDark(bool)` / `.toggle()` | method | 〃 | 1.3 |
| `Gifticon.price` (`int`, KRW, **required·non-nullable**) | model field | `lib/shared/models/gifticon.dart` | 1.3 |
| `Group` / `GroupMember` | model | `lib/shared/models/group.dart` | 2 |
| `MemberRole` (owner/member) | enum | `lib/shared/models/group.dart` | 2 |
| `InviteExpiry` (oneHour/oneDay/sevenDays/never) | enum | `lib/shared/models/group.dart` | 2 |
| `Group.isOwnedBy/isMember/canInvite/memberById(userId)` | predicate | 〃 | 2 |
| `SharedGifticon` (원본 `Gifticon.id`를 `gifticonId`로 참조) | model | `lib/shared/models/share.dart` | 2 |
| `UsageLog` / `GroupNotification` | model | `lib/shared/models/share.dart` | 2 |
| `ShareStatus` (available/inUse/used) | enum | `lib/shared/models/share.dart` | 2 |
| `ShareStatusTransition.isAllowed(from, to)` | 전이 규칙 | `lib/shared/models/share.dart` | 2 |
| `GroupNotificationType` (registered/expiringSoon/used) | enum | `lib/shared/models/share.dart` | 2 |
| `ShareRepository` | interface | `lib/shared/repositories/share_repository.dart` | 2 |
| `ShareRepository.watchGroups(String userId)` → `Stream<List<Group>>` | method | 〃 | 2 |
| `ShareRepository.getGroups(userId)` / `getGroupById(groupId)` | method | 〃 | 2 |
| `ShareRepository.createGroup({name, emoji})` / `joinGroup(inviteCode)` → `Future<Group>` | method | 〃 | 2 |
| `ShareRepository.leaveGroup(groupId)` / `deleteGroup(groupId)` → `Future<void>` | method | 〃 | 2 |
| `ShareRepository.transferOwnershipAndLeave({groupId, newOwnerUserId})` → `Future<Group>` | method | 〃 | 2 |
| `ShareRepository.setInviteOwnerOnly({groupId, ownerOnly})` → `Future<Group>` | method | 〃 | 2 |
| `ShareRepository.watchSharedGifticons(groupId)` / `getSharedGifticons(groupId)` | method | 〃 | 2 |
| `ShareRepository.shareGifticon({groupId, Gifticon gifticon})` → `Future<SharedGifticon>` | method | 〃 | 2 |
| `ShareRepository.toggleReservation(id)` / `markUsed(id)` → `Future<SharedGifticon>` | method | 〃 | 2 |
| `ShareRepository.cancelShare(id)` → `Future<void>` | method | 〃 | 2 |
| `ShareRepository.watch/getUsageLogs(userId)` / `watch/getNotifications(userId)` | method | 〃 | 2 |
| `InMemoryShareRepository` (AuthRepository·GifticonRepository 주입) | mock impl | `lib/shared/repositories/impl/in_memory_share_repository.dart` | 2 |
| `shareRepositoryProvider` (`Provider<ShareRepository>`) — **SSOT** | provider | `lib/shared/providers/repositories.dart` | 2 |
| `josa(word, withBatchim, withoutBatchim)` / `KoreanJosa` 확장(`eulReul`/`iGa`/`eunNeun`/`waGwa`) | util | `lib/shared/util/korean_particle.dart` | 2 |
| `groupThousands(digits)` (코어) / `digitsOnly(input)` / `formatThousands(input)` (scan 진입점) / `formatWon(won)` (main 진입점) | util | `lib/shared/util/money_format.dart` | 2.3 |
| `formatYmdDot(DateTime)` → `'YYYY.MM.DD'` (코어 — main·share·scan 공통 날짜 표기) | util | `lib/shared/util/date_format.dart` | 2.4 |
| `myGroupsProvider` (`AutoDisposeProvider<AsyncValue<List<Group>>>`) — **SSOT**. 세션→`watchGroups` 체인 정본. scan·share **공용 구독 1개** | provider | `lib/shared/providers/my_groups_provider.dart` | 2.5 |

### `Gifticon` 필드 계약

| 필드 | 타입 | nullable | 생산자(scan) 책임 | 소비자(main) 용도 |
|------|------|:---:|------|------|
| `id` | `String` | no | 생성 or Repo 발급 | 식별 |
| `ownerId` | `String` | no | 현재 로그인 `User.id`로 채움 | 소유자별 조회 키 |
| `brand` | `String` | no | 반드시 채움(미상 시 입력 강제) | 브랜드명순 정렬·표시 |
| `productName` | `String` | no | 반드시 채움 | 표시 |
| `price` | `int` | **no** | 반드시 채움(미상 시 입력 강제, 무료/사은품=0) | 카드 가격 표시 + 홈 총금액 통계 합산 |
| `barcode` | `String?` | **yes** | 인식/입력 실패 시 null 허용 | (미사용) |
| `category` | `String` | no | 반드시 채움(미분류 시 "기타") | 카테고리 필터 |
| `expiryDate` | `DateTime` | no | 반드시 채움(인식 실패 시 입력 강제) | 만료임박순 정렬·만료 판정 |
| `registeredAt` | `DateTime` | no | 생성 시 채움 or Repo 발급 | 최신 등록순 정렬 |
| `status` | `GifticonStatus` | no | 항상 `available`로 시작 | 상태 필터 |
| `imagePath` | `String?` | **yes** | 수동 입력은 이미지 없이 가능 → null 허용 | 썸네일(있으면) |

---

## 페이지별 소비/생산

| 페이지 | 소비 (읽음) | 생산 (씀) |
|--------|------|------|
| **auth** (mock) | `User` | `AuthRepository.currentUser`, `watchCurrentUser()` (→ `InMemoryAuthRepository` 제공) |
| **scan** (생산자) | `authRepositoryProvider`→`AuthRepository.currentUser` (소유자 식별), `gifticonRepositoryProvider`, `Gifticon`, `GifticonStatus.available`, `AppRoutes.scan`, `shareRepositoryProvider`→`shareGifticon(...)`, **`myGroupsProvider`**(저장할 그룹 선택지 — 세션→`watchGroups(uid)` 체인 정본; scan 파생에서 `valueOrNull ?? []` 폴딩), `Group`(id·name·emoji) | `GifticonRepository.addGifticon(Gifticon)`, (그룹 선택 시) `ShareRepository.shareGifticon({groupId, gifticon: saved})` |
| **main** (소비자) | `gifticonRepositoryProvider`→`watchGifticons(ownerId)`, `Gifticon`(+`price`), `SortOption`, `FilterOption`, `GifticonStatus`, `AppRoutes.main`, `Theme.of(context)`(AppTheme) | 총금액 통계 = `price` 합산, (상태 변경 시) `GifticonRepository.updateStatus(id, status)` |
| **share** (그룹/공유) | `shareRepositoryProvider`→`ShareRepository`(그룹 CRUD·멤버·초대·공유/취소·`markUsed`·이력·알림), **`myGroupsProvider`**(내 그룹 목록 — `AsyncValue` 그대로 전파), `Group`/`GroupMember`/`SharedGifticon`/`UsageLog`/`GroupNotification`, `ShareStatus`/`MemberRole`/`GroupNotificationType`, `authRepositoryProvider`→`currentUser`(행위자 식별), `gifticonRepositoryProvider`→`watchGifticons(uid)`(공유 후보 = `Gifticon`), `AppRoutes.share` | `SharedGifticon`/`UsageLog`/`GroupNotification`(share repo에 씀), **`GifticonRepository.updateStatus(gifticonId, GifticonStatus.used)`**(원본 사용 동기화, `markUsed` 경유) |
| **auth/설정('마이')** | `themeModeProvider`(watch) | `ThemeModeController.setDark(bool)`/`.set(mode)` (다크 토글) |
| **앱 조립부(main.dart)** | `themeModeProvider`(watch), `AppTheme.light`/`AppTheme.dark` | `MaterialApp.theme`/`darkTheme`/`themeMode` 배선 |

---

## 크로스페이지 주의점 (경계면 버그 방어선)

1. **scan이 반드시 채워야 하는 `Gifticon` 필수 필드**
   `id`(또는 Repo 발급 위임), `ownerId`, `brand`, `productName`, `category`, `expiryDate`, `registeredAt`, `status`.
   - 이 중 하나라도 비면 main의 정렬/필터가 깨진다. `barcode`·`imagePath`만 null 허용.
   - `category` 미분류 시 **빈 문자열 금지** — "기타" 같은 기본값을 넣는다(카테고리 필터가 빈 값을 항목으로 오인하지 않게).

2. **소유자 일관성**
   scan은 `authRepository.currentUser!.id`를 `ownerId`에 넣고, main은 같은 `ownerId`로 `watchGifticons`를 구독해야 목록이 이어진다. mock의 `InMemoryAuthRepository.defaultUser.id == 'user-1'`이 양쪽 공유 기준값.

3. **정렬/필터는 소비자(main)가 수행**
   Repository는 정렬/필터하지 않은 원천 목록만 준다. main은 `SortOption`/`FilterOption` enum에 따라 자기 상태 계층에서 적용한다. scan/Repo에 정렬 파라미터를 요구하지 말 것(계약에 없음).

4. **허용 상태 전이 (SSOT)** — `GifticonStatusTransition.isAllowed`로만 검증
   - `available → used` (사용 완료 / 공유 사용 동기화)
   - `available → expired` (만료 경과)
   - 그 외(되돌리기, `used↔expired`)는 **불허**. `InMemoryGifticonRepository.updateStatus`는 위반 시 `StateError`를 던진다. main이 사용완료 처리 시 이 규칙을 어기면 예외 발생 → QA 체크 포인트.

5. **매직 스트링 금지**
   route는 `AppRoutes.main`/`AppRoutes.scan` 상수만 사용. 상태/정렬/필터는 문자열이 아니라 enum으로만 비교.

6. **모델/함수 중복 정의 금지**
   페이지 내부에 `Gifticon`/`User`/status enum을 재정의하지 말 것. 반드시 `lib/shared/`의 단일 정의를 import.

8. **공유 테마 = SSOT (`lib/shared/theme`)**
   - 색·라운드·타이포·인풋·칩·내비 톤은 `AppTheme.light`/`AppTheme.dark`에 담겨 있다.
     페이지는 **색을 하드코딩하지 말고** `Theme.of(context)`(colorScheme/textTheme/컴포넌트 테마)를 소비한다.
     원색 토큰이 직접 필요할 때만 `AppColorsLight`/`AppColorsDark`/`AppColorsCommon` 참조.
   - 페이지 내부에 별도 `ThemeData`/색 상수를 재정의하지 말 것(테마 교체 시 갈라짐).
   - **기본 = 라이트(`ThemeMode.light`)**, 다크는 설정('마이')에서 `themeModeProvider`로 토글.

9. **`themeModeProvider` = SSOT (`lib/shared/providers/theme_mode_provider.dart`)**
   - `ThemeMode`는 오직 이 provider가 소유한다. 설정 페이지·앱 조립부만 소비.
   - 앱 조립부: `ref.watch(themeModeProvider)` → `MaterialApp.themeMode`.
   - 설정 토글: `ref.read(themeModeProvider.notifier).setDark(bool)` / `.set(ThemeMode)`.
   - 영구 저장은 후속(현재 in-memory, 재시작 시 라이트로 리셋). `shared_preferences`는 TODO.

10. **`Gifticon.price` = required·non-nullable (`int`, KRW)**
   - scan은 세 경로(카메라/갤러리/수동) 모두에서 반드시 채운다(미상 시 입력 강제, 무료/사은품=0).
   - main 총금액 통계 = 원천 목록의 `price` 합산(소비자 계산). 카드 가격 표시도 이 필드.
   - `price` 누락/빈 값 금지. required이므로 생성 시 반드시 인자 전달(생략 시 컴파일 에러).

11. **share 경계면 (v2 승격) — 공유 사용 동기화·행위자 식별**
   - **행위자(actor) = `AuthRepository.currentUser`.** `ShareRepository`의 변경 메서드는
     현재 사용자를 행위자로 본다. 멤버 식별은 `GroupMember.userId == currentUser.id`
     (프로토타입의 이름 문자열/`'me'` 하드코딩 비교를 대체). share는 auth 세션과 반드시 일치해야 한다.
   - **`markUsed` = 유일한 원본 상태 전이 지점.** 공유 항목이 사용 완료되면
     `GifticonRepository.updateStatus(sharedGifticon.gifticonId, GifticonStatus.used)`로 원본을
     `available → used`로 전이한다 → main 목록/필터에 반영. **기존 `GifticonRepository` 계약을 소비**할 뿐
     시그니처를 바꾸지 않는다. `GifticonStatus`에 'shared' 상태를 추가하지 않는다(전이표·main 스위치 보호).
   - **`shareGifticon`/`cancelShare`는 원본 상태 불변.** 공유/회수는 원본을 available로 유지한다.
   - **인스턴스 공유 필수.** `shareRepositoryProvider`는 `authRepositoryProvider`·
     `gifticonRepositoryProvider`를 `watch`해 **같은 인스턴스**를 주입받는다. 갈라지면 사용 동기화가
     main에 반영되지 않는다(#7과 동일 원인).
   - **가드 위반 = `StateError`(예외).** `ShareRepository`는 GifticonRepository와 동일 규약으로
     권한/상태 위반에 `StateError`를 던진다(프로토타입 스토어의 `bool` 반환과 다름). UI 버튼 게이팅은
     예외가 아니라 모델 predicate(`Group.isOwnedBy/canInvite`, `SharedGifticon.isLockedFor`)로 판정.
   - **`ShareStatus` ≠ `GifticonStatus`.** 전자는 그룹 내 사용 흐름(available/inUse/used), 후자는
     원본 보관 상태(available/used/expired). 혼용 금지. 전이 검증은 각 `*Transition.isAllowed` 사용.
   - **표시 필드는 스냅샷.** `SharedGifticon`의 brand/productName/expiryDate/barcode는 공유 시점
     원본 스냅샷(다른 멤버는 공유자 개인 목록 조회 불가). 원본 연결은 `gifticonId`.

7. **Repository provider = SSOT (경계면 결함 원인 #1)**
   - `authRepositoryProvider`·`gifticonRepositoryProvider`는 **오직**
     `lib/shared/providers/repositories.dart`에만 존재한다. 페이지(`lib/features/*`)는
     이 provider를 **재선언하지 말고 import 해서 소비**한다.
   - 페이지마다 provider를 중복 선언하면 페이지별로 **다른 Repository 인스턴스**를 참조하게 되어
     scan이 추가한 기프티콘이 main에 반영되지 않는다(통합 QA 실검출 결함). provider는 모델·인터페이스와
     동급의 공유 관심사이므로 계약 레벨에서 하나로 둔다.
   - **override 조립 규칙(main.dart):** `ProviderScope(overrides: [...])`에서
     ① `authRepositoryProvider`를 auth 페이지 제공 실구현으로 override 하고,
     ② `gifticonRepositoryProvider`는 **scan·main·share가 같은 단일 인스턴스를 공유**하도록
     조립부에서 하나의 인스턴스를 만들어 `overrideWithValue(...)`로 주입한다. 인스턴스가 갈라지면
     동일 결함이 재발한다. (기본값도 SSOT라 단일 인스턴스지만, 실구현 교체 시 인스턴스 분기를 막기 위해
     조립부에서 명시적으로 하나만 생성한다.)
   - import 심볼: `package:keepcon/shared/providers/repositories.dart`의
     `authRepositoryProvider`, `gifticonRepositoryProvider` (또는 상대경로
     `../../../shared/providers/repositories.dart`).

12. **scan → share: 저장 시 선택 그룹으로 `shareGifticon` 소비 (계약 무변경)**
   - 스캔/추가 화면의 '저장할 그룹 선택'은 정본 `myGroupsProvider`(#13, v2.5 —
     내부적으로 `watchGroups(uid)` 체인)를 scan 파생 `scanTargetGroupsProvider`로
     폴딩(`valueOrNull ?? []`)해 타일을 만들고(첫 타일 = '내 지갑' = 대상 없음), 저장 시
     `GifticonRepository.addGifticon` **성공 후** 대상 그룹이 있으면
     `ShareRepository.shareGifticon(groupId:, gifticon: saved)`를 호출한다.
   - **`Gifticon`에 `groupId`를 추가하지 않는다.** 그룹 소속은 share 도메인의
     `SharedGifticon`으로만 표현되므로, scan은 기존 share 규약(등록 알림 · "한 기프티콘은
     1회만 공유" 불변식 · `markUsed` 시 원본 `GifticonStatus.used` 동기화)에 그대로 합류한다.
     신규 저장 직후 공유이므로 정상 흐름에서 이중 공유 `StateError`는 발생하지 않는다.
   - **부분 실패 정책:** 공유는 저장 성공 뒤의 부수 단계다. 공유가 실패해도(선택한 그룹이
     사라짐/비멤버 등 `StateError`) 저장을 되돌리지 않고 제출은 성공으로 유지하며, UI가
     "저장됨 + 그룹 공유됨" / "저장됨(그룹 공유 실패)"를 문구로 구분해 안내한다.
     내부 `StateError.message`(영문·raw id)는 사용자에게 노출하지 않는다 —
     share 페이지 규약과 동일하게 한국어 중립 문구 + debug 로그.
   - 공유 성공 안내 문구의 그룹명은 **원격 재조회 없이** scan의 선택 목록
     provider(`scanTargetGroupsProvider` — `watchGroups` 파생)에서 동기 캡처한다
     (`getGroupById` 미소비 — shareGifticon 구현이 이미 그룹 문서를 읽으므로
     이중 read 방지. 목록에 없으면 문구만 "그룹에 공유됨"으로 일반화).
     즉 main 목록에는 항상 반영되고, 그룹 공유만 누락될 수 있다.
   - 선택 식별자는 index가 아니라 **groupId**(`String?`, null = 내 지갑)다.

13. **`myGroupsProvider` = SSOT (`lib/shared/providers/my_groups_provider.dart`, v2.5)**
   - "현재 사용자의 그룹 목록"은 **오직 이 provider**가 소유한다. 페이지는
     `watchCurrentUser()` → `watchGroups(uid)` 체인을 **다시 조립하지 않고** 이것을 `watch` 한다.
   - **왜 정본인가 = 구독 중복 방어.** provider 인스턴스가 다르면 Riverpod은 스트림을 각각
     열기 때문에, 같은 사용자에 대해 `watchGroups`가 두 번 구독됐다(승격 전 scan+share).
     in-memory에서는 조용히 넘어가지만 Firestore에서는 `arrayContains` 리스너 2개 =
     **문서 읽기·과금 2배**(초기 스냅샷 + 이후 모든 변경분). 같은 인스턴스를 watch 하면
     Riverpod이 구독을 1개로 합친다 — 인스턴스 분기 결함(#7)의 provider 버전이다.
   - **노출 형태 = `AsyncValue<List<Group>>`.** 로딩/에러 구분은 정본이 보존하고, 정보를
     잃는 방향의 변환(빈 목록 폴딩)은 페이지 파생/소비 지점에서 한다:
     share는 `groupByIdProvider`만 `AsyncValue` 구분 소비(whenData)하고 목록/요약 소비
     지점들은 `valueOrNull ?? []` 폴딩 / scan = `scanTargetGroupsProvider`에서
     `valueOrNull ?? const <Group>[]`.
   - **상태 규약:** 알려진 user가 있으면(확정 방출 또는 세션 일시 순단 중 **이전 값 보존**)
     그 user의 그룹 스트림을 그대로 반환 — 세션 순단으로 이미 로드된 목록이 사라지지 않는다.
     알려진 user 없이 세션 로딩 중 → `AsyncLoading` 전파(빈 목록으로 접지 않음),
     세션 `data(null)`(미로그인 확정) → `AsyncData(<Group>[])` + **`watchGroups` 미구독**,
     그 외 에러 → `AsyncError` 전파.
   - **⚠️ 접을 때는 `.value`가 아니라 `valueOrNull`.** `.value`는 이전 값이 없는
     `AsyncError`에서 **rethrow** 하므로, 첫 방출이 에러면 폴백(`?? []`)에 도달하지 못하고
     소비 provider가 throw 한다. 정본·파생·소비 지점 어느 층에서도 이 함정을 쓰지 않는다.
     v2.5 후속 정리에서 **lib 전수**(share 전 소비 지점 + main의 세션·목록·통계 폴딩,
     mypage·scan은 기존 준수)를 `valueOrNull`로 통일 완료 — 새 폴딩 코드는 이 규약을 따를 것.
   - **수명 = `autoDispose`.** scan은 일회성 플로우라 이탈 시 리스너가 남으면 안 되고,
     share의 파생은 keepAlive라 한 번 만들어지면 정본 수명을 **붙잡는다**(승격 전 keepAlive
     체인과 동일한 수명 — share 동작 불변). 결과적으로 구독 수는 **0 또는 1**이며 승격 전
     최댓값(2)보다 항상 적거나 같다. keepAlive provider가 autoDispose 정본을 `watch` 하는
     조합은 허용된다(Riverpod 2.6 확인, 테스트로 고정).
     ✅ **share 화면 에러 표시/재시도 완료(main 목록·scan 타일은 후속).** 폴딩(`valueOrNull`)은
     그대로 두고, 화면이 **원천 provider의 `hasError`를 함께 관찰**해 인라인 배너
     (`lib/features/share/widgets/share_error_banner.dart`)를 얹는다. 재시도는 **사용자 액션
     전용**이며(자동 재시도 금지 — 장애 중 retry storm) 구현은 원천 `ref.invalidate`다
     (`retryNotifications`/`retryUsageLogs`/`retrySharedGifticons`/`retryShareCandidates`).
     재시도 스코프 규약: **에러인 원천 인스턴스만** invalidate한다(멀쩡한 스트림 재구독 =
     불필요 재읽기·과금 — 그룹별 공유 family는 실패 인스턴스만 골라 되살린다. 테스트가
     "멀쩡한 그룹 비재구독"을 고정). 빈 안내는 에러뿐 아니라 **값 없는 로딩에도 게이트**한다
     (콜드 스타트에 "없어요"로 위장 금지 — 전면 화면은 스피너, 섹션은 억제).
     알림 화면은 **성공 데이터 방출 뒤에만** `markNotificationsRead`를 호출한다(읽음 가드 —
     에러 중 진입 시 읽음 처리가 일어나 못 본 알림이 유실되던 문제 해소. 이전 값을 보존한
     에러 상태도 "봤다"로 치지 않는다 — 보존 목록은 최신이 아닐 수 있어, 지금 readAt을 찍으면
     에러 중 도착 못 한 새 알림이 유실된다. 실패 시 가드 복원은 StateError뿐 아니라 저장소
     구현별 예외 전체에 적용).
     ⚠️ **남은 한계(내 그룹 목록 한정):** 이 provider가 에러로 끝나면 `AsyncError`가
     정본의 **private 체인**(`_currentUserProvider`/`_groupsByUserProvider`)에 캐시되고,
     페이지에서 `invalidate(myGroupsProvider)`를 해도 그 dependency는 재구독되지 않는다
     (실측 확인 — Riverpod의 invalidate는 dependency로 전파되지 않는다). 그래서 **에러의 원인이
     그룹 목록인 배너는 표시만 하고 재시도 버튼을 두지 않는다**(동작하지 않는 버튼 방지 —
     `ShareErrorBanner`가 onRetry=null이면 복구 안내 접미를 스스로 붙인다):
     share 메인 '내 그룹'·사용 이력 배너는 항상, 공유 상세·공유 시트 배너는
     `myGroupListUnavailableProvider`가 true일 때. 판정은 **"값도 없는 에러"로 한정**한다
     (`hasError && !hasValue`) — 이전 값을 보존한 순단 에러까지 포함하면 멀쩡히 렌더되는
     목록 위에 해소 불가능한 배너가 앱 재시작 전까지 영구 표시되고, 함께 발생한 재시도
     가능한 공유 스트림 에러의 버튼까지 부당하게 사라진다(재시도 훅 승격 후 순단 표시 재검토).
     원인이 share 소유 스트림이면 같은 배너가 재시도 버튼을 갖는다(원인별 분기).
     해소하려면 정본에 재시도 훅(예: private 체인을 되살리는 `refreshMyGroups(Ref)` 또는
     `myGroupsRetryProvider`)이 필요하다 — `lib/shared`는 `CODEOWNERS` 대상이라 페이지 담당이
     직접 고치지 않고 `contract-architect`에게 요청한다(아래 후속 목록 참조).
   - **아직 정본이 아닌 것:** 세션 스트림(`watchCurrentUser()`) 자체. 앱 조립부·main·mypage·
     share가 각각 구독하고 정본 내부에도 하나 있다(총 5곳). 소비자가 많아 별도 승격 후보로 남긴다.
     ⚠️ 정산 기록: share 정상상태의 동시 세션 구독이 승격 전 1개(shareCurrentUserProvider 공용)
     → 승격 후 2개(그것 + 정본 내부)로 늘었다(비과금 auth 리스너라 실비용 미미). 또한
     `memberNamesProvider`가 두 세션 소스를 혼합하므로 계정 전환 프레임에서 두 값이 한 프레임
     어긋날 수 있다 — 세션 정본화 슬라이스에서 정본 내부 구독을 세션 정본 소비로 바꿔 해소할 것.

---

## 데이터 소스 = 인터페이스 뒤에서 교체 가능 (in-memory ↔ Firebase)

**핵심:** 페이지들은 `AuthRepository`/`GifticonRepository` **abstract 인터페이스에만** 의존한다.
따라서 백엔드(데이터 소스)는 인터페이스 뒤에서 교체 가능하다 — 페이지 코드는 한 줄도 바뀌지 않는다.
이것이 계약(SSOT)의 가치다.

| 데이터 소스 | 구현체 | 위치 | 활성화 방법 |
|------|------|------|------|
| **in-memory (기본)** | `InMemoryAuthRepository`, `InMemoryGifticonRepository` | `lib/shared/repositories/impl/` | 기본값. override 불필요. 데모/개발/테스트용 |
| **Firebase (선택)** | `FirebaseAuthRepository`(firebase_auth), `FirebaseGifticonRepository`(cloud_firestore) | `lib/shared/repositories/impl/firebase/` | 부트스트랩으로 provider override |

- **기본 실행은 in-memory 유지.** Firebase는 강제로 초기화되지 않는다 —
  `firebase_bootstrap.dart`의 전환 함수를 **명시적으로 호출**해야만 켜진다.
  사용자가 `flutterfire configure`를 아직 안 했어도 앱은 정상 실행되고 컴파일도 안 깨진다.
- `abstract class AuthRepository`/`GifticonRepository`는 **절대 변경하지 않았다.**
  Firebase 구현은 **새 구현체 추가**일 뿐, 계약 시그니처는 그대로다(breaking change 없음).

### Firebase 문서 매핑 규약 (`FirebaseGifticonRepository`)
- 컬렉션 `'gifticons'`, 문서 id = `Gifticon.id`.
- `GifticonStatus` enum은 `.name` **문자열**로 저장·역매핑(매직 스트링 방지 — enum 이름에 고정).
- `DateTime`(`expiryDate`/`registeredAt`)은 Firestore `Timestamp`로 저장·역매핑.
- `watchGifticons(ownerId)` = `where('ownerId', isEqualTo: ownerId).snapshots()` (정렬/필터 없음 — 소비자 책임).
- `updateStatus`는 트랜잭션 안에서 현재 상태를 읽어 `GifticonStatusTransition.isAllowed`로 검증,
  위반 시 `StateError`(계약 준수). in-memory 구현과 동일한 전이 규칙.
- `FirebaseAuthRepository`: `currentUser`=`FirebaseAuth.instance.currentUser` 매핑,
  `watchCurrentUser()`=`authStateChanges()` 매핑. `User.displayName` **빈 문자열 금지** 규칙 준수
  (firebase displayName 없으면 이메일 로컬파트 → uid 앞부분 순으로 채움).

### 사용자가 Firebase를 켜는 절차
1. **Firebase 콘솔에서 프로젝트 생성** — https://console.firebase.google.com
2. **FlutterFire CLI 구성** —
   `dart pub global activate flutterfire_cli` 실행 후, 프로젝트 루트에서 `flutterfire configure`.
   → `lib/firebase_options.dart`가 실제 값으로 **자동 생성·덮어쓰기**된다
   (현재는 `UnimplementedError`를 던지는 플레이스홀더 스텁이며, 손으로 채우지 않는다).
3. **Auth/Firestore 활성화** — 콘솔에서 Authentication과 Cloud Firestore를 켠다.
4. **부트스트랩으로 provider override 활성화** — 앱 조립부(`main.dart`)에서
   `await initFirebaseAndBuildOverrides()`가 반환한 override를 `ProviderScope(overrides: ...)`에 주입.
   (in-memory로 되돌리려면 override를 비우면 된다.)

> 참고: `lib/main.dart`는 이 스캐폴딩에서 수정하지 않았다. 앱 조립부(하단 탭 셸 배선 포함)는
> 오케스트레이터가 담당하며, 그 배선에서 `firebase_bootstrap.dart`를 호출해 전환한다.

---

## 변경 이력

| 버전 | 날짜 | 변경 | 영향 페이지 |
|------|------|------|------|
| v1 | 2026-07-06 | scan→main 슬라이스 초기 계약 확정 | scan, main (auth mock) |
| v1.1 | 2026-07-06 | **경계면 결함 수정**: Repository provider를 계약 SSOT로 신설(`lib/shared/providers/repositories.dart`). scan/main이 각각 `authRepositoryProvider`/`gifticonRepositoryProvider`를 중복 선언해 서로 다른 InMemory 인스턴스를 참조 → scan 추가분이 main에 미반영되던 결함의 근본 원인 제거. 페이지는 공유 provider를 import 하고 자기 중복 선언을 삭제해야 함(scan/main 개발자 후속 처리). 크로스페이지 주의점 #7(override 조립 규칙) 추가. | scan, main, share(향후) |
| v1.2 | 2026-07-06 | **Firebase 데이터 계층 스캐폴딩 (non-breaking)**: `pubspec.yaml`에 firebase_core/firebase_auth/cloud_firestore 추가. `AuthRepository`/`GifticonRepository` 인터페이스는 **무수정** — Firebase 구현체(`FirebaseAuthRepository`, `FirebaseGifticonRepository`)를 `impl/firebase/`에 신규 추가하고, 전환 부트스트랩(`firebase_bootstrap.dart`)과 플레이스홀더 `firebase_options.dart` 스텁을 제공. 기본 실행은 in-memory 유지(Firebase 강제 초기화 없음). `AppRoutes.share` 추가(하단 탭 셸 공유 탭). "데이터 소스 = 인터페이스 뒤 교체 가능" 절 신설. 페이지 코드 변경 불필요(계약 시그니처 불변). | (없음 — non-breaking. share 라우트만 하단 탭 셸/share 페이지가 소비) |
| v1.3 | 2026-07-07 | **공유 디자인 시스템(SSOT) + 가격 필드 확정.** (1) 라이트(기본·화이트)/다크 색 토큰을 `lib/shared/theme/app_colors.dart`에, `AppTheme.light`/`AppTheme.dark`(Material3)를 `lib/shared/theme/app_theme.dart`에 신설 — 페이지가 `Theme.of(context)`만 소비해도 KeepCon 틀 디자인이 나오게 함. (2) `themeModeProvider`(NotifierProvider, 기본 `ThemeMode.light`)를 `lib/shared/providers/theme_mode_provider.dart`에 신설(설정 토글·앱 조립부 소비). (3) **`Gifticon.price`(`int`, KRW, required·non-nullable) 추가** — 생성자/copyWith/==/hashCode/toString 반영. Repository 인터페이스(`AuthRepository`/`GifticonRepository`)는 **무수정**. **⚠️ Breaking(모델 생성부):** `price` required로 인해 계약 외부의 `Gifticon(...)` 생성 지점(`lib/main.dart` 시드 5건, `lib/features/scan/state/gifticon_form_state.dart:194` draft)이 컴파일 에러 → 각 담당(assembly, scan-page-dev)이 `price` 인자를 채워야 함(의도된 것). 계약 소유 파일(`firebase_gifticon_repository.dart` 매핑)은 contract-architect가 함께 갱신 완료. | main(price 통계·표시, 테마), auth/설정(테마 토글), scan(price 입력), 앱 조립부(테마 배선). scan/main/앱조립부 = **생성부 갱신 필요** |
| v2 | 2026-07-10 | **공유(share) 도메인 계약 승격 (non-breaking, 순수 추가).** 프로토타입(`lib/features/share/data/`)의 로컬 모델·스토어를 `lib/shared/` 정본으로 승격. (1) 모델 신설: `lib/shared/models/group.dart`(`Group`/`GroupMember`/`MemberRole`/`InviteExpiry`), `lib/shared/models/share.dart`(`SharedGifticon`/`UsageLog`/`GroupNotification`/`ShareStatus`+전이 SSOT/`GroupNotificationType`). (2) `ShareRepository` abstract + `InMemoryShareRepository`(스토어 가드 로직 이관, AuthRepository·GifticonRepository 주입) 신설. (3) `shareRepositoryProvider`(SSOT) 추가 — auth·gifticon provider를 watch해 동일 인스턴스 공유. **개선점:** 이름 문자열→`User.id` 참조, `GroupMember.id` 하드코딩→세션 기반, `MyGifticon` 폐기(원본 `Gifticon` 소비), `SharedGifticon.gifticonId`로 원본 참조, 라벨 String→DateTime, 가드 `bool`→`StateError`. **기존 계약(`Gifticon`/`User`/`GifticonRepository`/`AuthRepository`/`GifticonStatus`) 무수정 — breaking 없음.** 상세: `_workspace/02_share_contract_promotion.md`. 후속 리팩터(로컬 모델 제거→계약 소비)는 share-page-dev 담당. | share(신규 소비/생산), main(공유 `markUsed`의 원본 used 동기화를 `watchGifticons`로 수신) |
| v2.1 | 2026-07-10 | **`korean_particle` 유틸 승격 (non-breaking, 순수 추가).** 프로토타입 `lib/features/share/data/korean_particle.dart`를 범용 유틸 `lib/shared/util/korean_particle.dart`로 승격(`josa()` + `KoreanJosa` 확장 `eulReul`/`iGa`/`eunNeun`/`waGwa`). 도메인 결합 없는 순수 언어 유틸이라 모델/Repository와 달리 `util/`에 둔다. 승격·테스트는 share-page-dev가 완료, features 3곳이 소비 중. 계약 요약 표에 항목 반영(문서 드리프트 정정). `in_memory_share_repository.dart`의 로컬 `_eulReul` 헬퍼는 공유 `KoreanJosa.eulReul`로 대체(중복 제거). | (없음 — non-breaking. 알림 문구 조립 시 어느 페이지든 소비 가능) |
| v2.2 | 2026-07-10 | **공유 페이지 계약 소비 전환 완료 + 계약 방어 강화(회귀/리뷰 반영).** (1) share-page-dev가 `lib/features/share/data/`(로컬 모델·스토어·util) **제거 완료**, 페이지가 `lib/shared` 계약을 직접 소비. share 테스트가 `InMemoryShareRepository` 대상으로 전환(`test/features/share/share_repository_*_test.dart`). (2) [회귀] `InMemoryShareRepository.shareGifticon`에 **"한 기프티콘은 최대 1회만 공유" 불변식** 복원(중복 공유 → `StateError`, 이중 사용·`UsageLog` 다중 방지). (3) [CodeRabbit] `Group` 생성자에 **owner 불변식**(멤버≥1, 방장 정확히 1명) assert 추가 + **`members`를 `List.unmodifiable`로 방어 복사**, `owner` getter의 조용한 `orElse: members.first` 제거(불변식 위반 시 `StateError`). 기존 계약 시그니처 무수정 — breaking 없음. | share(제거·소비 전환), 계약 방어(모든 `Group`/공유 소비자) |
| v2.3 | 2026-07-30 | **금액 포맷 유틸 승격 (non-breaking, 순수 리팩터).** 동일한 천 단위 그룹핑 알고리즘이 main(`formatWon`, `lib/features/main/widgets/format.dart`)과 scan(`formatThousands`, `lib/features/scan/util/price_input_formatter.dart`)에 복사돼 있어 승격 규칙 ③(실제 두 번째 소비자)을 충족 → `lib/shared/util/money_format.dart` 정본 신설. **코어 하나 + 소비자별 얇은 진입점** 구조: `groupThousands(String digits)`(순수 그룹핑, digits-only 전제 debug assert, 3자리 이하 빠른 경로) / `digitsOnly(String)`(비숫자 제거) / `formatThousands(String)`= `groupThousands(digitsOnly(x))`(scan — 관용·멱등) / `formatWon(int)`(main — 절댓값 그룹핑 후 부호 앞 결합). 소비자는 정본을 **직접 import**한다(main_page·gifticon_card는 `show formatWon`; scan 입력 포매터는 코어·`digitsOnly` 소비, `gifticon_form`용 `formatThousands` 재export는 기존 테스트가 경로를 고정하는 scan 쪽에만 유지). 신규 테스트 `test/shared/util/money_format_test.dart`, **기존 `test/features/scan/price_input_formatter_test.dart` 무수정 통과**(동작 불변의 증거). | (없음 — non-breaking, 시그니처·동작 불변. main·scan은 이미 정본 소비로 전환됨) |
| v2.4 | 2026-07-30 | **날짜 포맷 유틸 승격 (non-breaking 계약 + scan 표시 통일 1건).** 같은 `YYYY.MM.DD` 조립이 세 페이지에 분산돼 있어(승격 규칙 ③의 두 번째·세 번째 소비자 확인) `lib/shared/util/date_format.dart` 정본 신설 — **코어 `formatYmdDot(DateTime)` → `'YYYY.MM.DD'` 하나만** 승격했다(월·일 두 자리 패딩, 연도는 패딩하지 않고 네 자리 전제를 debug assert로 가드, 시·분·초 무시). 소비자 고유 표현은 각 페이지에 남긴다: share의 `~` 접두(`formatExpiryLabel`)·`HH:mm` 조합(`formatInviteExpiry`)·상대 시각(`formatRelativeKo`), main의 `formatDDay`. 소비 전환 — main: 로컬 `formatDate` **삭제**, 호출부(`main_page.dart`·`gifticon_card.dart`)가 정본을 `show formatYmdDot`으로 **직접 import**(재export shim 없음, v2.3 리뷰에서 확정된 방식) / share: `share_format.dart`가 코어에 위임(공개 함수명·출력 문자열 불변, 페이지 호출부 무수정) / scan: `gifticon_form.dart` 인라인 `padLeft` 조립 제거 후 정본 소비. **⚠️ 의도된 표시 변경 1건:** scan 날짜 선택 버튼 라벨이 `YYYY-MM-DD` → `YYYY.MM.DD`. 같은 유효기간이 등록 화면과 목록/공유 화면에서 다르게 보이던 불일치를 **다수 표기(`.`)로 통일**한 것이며, 계약 값(`Gifticon.expiryDate: DateTime`)·시그니처는 불변이다. 신규 테스트 `test/shared/util/date_format_test.dart`. **삭제 구현과의 문자 단위 코드 비교 + 신설 share_format 출력 고정 테스트(`test/features/share/share_format_test.dart`)로 확인**(기존 main·share 테스트는 이 경로를 지나지 않아 증거가 아님 — share 라벨 출력은 이번에 처음 테스트로 고정됨), scan 위젯 테스트(`test/features/scan/gifticon_form_input_test.dart`)는 구분자 단언만 `.`로 갱신. | scan(**표시 문자열 변경** — QA 시각 확인 대상), main·share(동작 불변, 정본 위임) |
| v2.5 | 2026-07-30 | **"내 그룹 목록" provider 승격 (non-breaking, 중복 구독 제거).** scan(`_scanCurrentUserProvider`/`_scanGroupsByUserProvider`)과 share(`_groupsByUserProvider`+`myGroupsProvider`)가 세션→`watchGroups(uid)` 체인을 각자 조립해 **같은 사용자에 대해 `watchGroups`를 두 번 구독**하던 문제(integration-qa 검출, 규칙 ③ 충족) → `lib/shared/providers/my_groups_provider.dart` 정본 신설. 정본은 `AsyncValue<List<Group>>`를 노출해 **로딩/에러 구분을 보존**하고(share 기존 규약과 동일: 세션 로딩→`AsyncLoading` 전파, `data(null)`→`AsyncData([])`), 정보를 잃는 폴딩은 페이지 파생에 남긴다(scan `scanTargetGroupsProvider` = `valueOrNull ?? []`). 세션·그룹 스트림 provider는 정본 파일 **내부(private)** 로 감춘다. **수명 = `autoDispose`**(scan 일회성 플로우 보호 + share 상시 탭이 보는 동안 유지 → 구독은 0 또는 1로 수렴, 승격 전 최댓값 2보다 항상 적거나 같다). 소비 전환 — scan: 중복 체인 2개 **삭제**, `scanTargetGroupsProvider`가 정본 소비(공개 이름·폴딩 동작 불변) / share: `_groupsByUserProvider`+로컬 `myGroupsProvider` **삭제**, 정본을 **직접 import**(재export shim 없음 — v2.3/v2.4에서 확정된 방식; `share_page.dart`·`usage_log_page.dart`는 import 1줄만 추가, `ref.watch(myGroupsProvider)` 호출부는 무수정). `.value`의 AsyncError rethrow 함정은 정본·파생 모두 `valueOrNull`로 회피(주석에 명시). 신규 테스트 `test/shared/providers/my_groups_provider_test.dart` — 계측 `ShareRepository`(구독 카운터)로 **"두 소비자 동시 watch → `watchGroups` 호출·구독 각 1회"**, "scan만 해제 시 재구독 없이 유지 / 마지막 소비자 해제 시 구독 0", "미로그인 시 미구독 + `AsyncData([])`", "로딩 전파 + scan은 빈 목록", "에러 전파 시 rethrow 없음"을 고정. 크로스페이지 주의점 #13 신설. | scan·share(동작 불변, 정본 소비 — 호출 표현·공개 provider 이름 불변) |

## 후속 확장 예정(이번 슬라이스 범위 밖)

- ✅ **승격 완료(v2):** `Group`, `GroupMember`, `SharedGifticon`, `UsageLog`, `ShareStatus`, `GroupNotification`/`GroupNotificationType`, `MemberRole`, `InviteExpiry`, `ShareRepository`(+`InMemoryShareRepository`, `shareRepositoryProvider`). → `lib/shared/models/group.dart`·`share.dart`, `lib/shared/repositories/share_repository.dart`. 상세 `02_share_contract_promotion.md`.
  - 그룹 관리 행위(생성/삭제/나가기/소유권이전/초대정책)와 `GroupRepository`로 따로 나눌 필요 없이 **하나의 `ShareRepository`**로 통합했다(그룹과 공유가 강결합 도메인).
- ✅ **리팩터 완료(share-page-dev, v2.2):** `lib/features/share/data/`(로컬 `share_models.dart`·`share_store.dart`·`korean_particle.dart`) **제거 완료** → 페이지가 `lib/shared` 계약을 소비. share 테스트는 `ShareStore` 대상에서 **`InMemoryShareRepository` 대상**으로 전환됨(`test/features/share/share_repository_*_test.dart`), korean_particle 테스트는 `test/shared/util/`로 이동. 매핑은 `02_share_contract_promotion.md` D절.
- ✅ **승격 완료(v2.4):** 날짜 라벨 포맷 — 3곳(main `formatDate` / share `formatExpiryLabel` 계열 / scan 인라인)에 분산됐던 `YYYY.MM.DD` 조립을 `lib/shared/util/date_format.dart`의 `formatYmdDot`으로 통합. 표기 규칙 합의 결과는 **점 구분자 통일**(다수 표기, scan만 `-`였음)이고, D-day 라벨(`formatDDay`)·상대 시각(`formatRelativeKo`)은 입력·의미가 달라 **승격 대상이 아님**(각 페이지 로컬 유지).
- ✅ **승격 완료(v2.5):** "현재 사용자의 그룹 목록 스트림" provider — scan/share에 중복 조립돼 `watchGroups`를 두 번 구독했던 체인을 `lib/shared/providers/my_groups_provider.dart`의 `myGroupsProvider`(**SSOT**, `autoDispose`, `AsyncValue` 노출)로 통합. 페이지 파생 형태는 계획대로 로컬 유지(share = `AsyncValue` 전파, scan = 빈 목록 폴딩). 구독 단일화는 테스트로 고정(`test/shared/providers/my_groups_provider_test.dart`). 상세는 크로스페이지 주의점 #13.
- **다음 승격 후보(경량):** `AsyncValue<List<T>>` 폴딩 확장(예: `orEmpty` — `valueOrNull ?? const []`) — 같은 관용구가 lib 16곳에 반복되고, 단일 폴딩 지점이 없으면 `.value` 변형이 재유입될 수 있다(v2.5 후속 정리에서 main 홈 1곳 재유입 실증). 표준 관용구 대비 프로젝트 고유 어휘 도입이라 순이득은 중간 — 채택 여부는 `contract-architect` 판단.
- **다음 승격 후보:** **세션 스트림(`AuthRepository.watchCurrentUser()`) provider** — 현재 5곳이 각자 구독한다: 앱 조립부(`lib/app/auth_gate.dart`), main(`currentUserProvider`, `lib/features/main/state/gifticon_list_providers.dart`), mypage(`lib/features/mypage/mypage_page.dart`), share(`shareCurrentUserProvider`, `lib/features/share/state/share_providers.dart`), 그리고 `my_groups_provider.dart` 내부. 규칙 ③은 이미 충족(소비자 다수)이지만 그룹 목록보다 소비자가 많고 셸(조립부) 수명과 얽혀 있어 별도 슬라이스로 다룬다 — 승격 시 `lib/shared/providers/`에 세션 정본을 두고 `my_groups_provider.dart`가 그것을 소비하도록 바꾼다. Firestore 과금 영향은 그룹 목록보다 작다(인증 상태 리스너는 문서 읽기가 아니다) — 이득은 **인스턴스/타이밍 일관성**이다. 페이지 담당은 직접 `lib/shared`를 고치지 말고 `contract-architect`에게 요청할 것(`CODEOWNERS` 리뷰 강제).
- **계약 요청(share → contract-architect, #13 후속):** `myGroupsProvider`의 **수동 재시도 훅**.
  share 화면들은 이제 원천 `hasError`를 관찰해 배너+재시도를 제공하지만(알림·사용 이력·그룹별
  공유 스트림·공유 후보), **내 그룹 목록만 재시도 경로가 없다** — 에러가 정본 파일 안의 private
  provider에 캐시되고 `invalidate(myGroupsProvider)`는 dependency로 전파되지 않기 때문이다.
  정본 쪽에 재시도 진입점(private 체인을 invalidate하는 공개 함수/provider)이 생기면 share 메인
  '내 그룹' 배너에 재시도 버튼을 붙일 수 있다. 시그니처·형태는 계약 소유자 판단.
  - ⚠️ **두 계층을 모두 되살려야 한다 — `_groupsByUserProvider`(그룹 스트림)만으로는 절반만
    해소된다.** 정본은 세션도 자기 파일 안의 별도 `_currentUserProvider`로 구독한다(같은
    `watchCurrentUser()`의 두 번째 구독 — 아래 "세션 스트림 승격 후보"가 기록한 그 중복).
    인증 스트림이 실패하면 **캐시된 에러가 둘**(share의 `shareCurrentUserProvider` + 정본 내부)
    생기고, share의 `_retrySessionIfFailed`는 앞의 것만 되살릴 수 있다. 따라서 훅은
    `_currentUserProvider`도 함께 무효화해야 한다.
  - 대안: **세션 스트림 승격과 묶어서** 처리한다. 정본이 세션 정본을 소비하도록 바뀌면
    중복 구독이 사라지고, share가 세션 정본 하나만 invalidate해도 그룹 목록까지 회복되므로
    이 요청의 절반이 자동으로 해소된다(그 경우 남는 것은 `_groupsByUserProvider` 계층뿐).
- **가드 보강 후보(계약 소유자 판단 필요):** `tool/check_ssot.sh`의 `SSOT_PROVIDERS` 목록에 **`myGroupsProvider`가 아직 없다** — 지금은 페이지가 같은 이름의 provider를 다시 선언해도 CI가 잡지 못한다(정본이 없던 시절과 같은 재발 경로). 이번 변경 범위(계약+소비 전환)와 분리해 CI 가드 PR로 다루기를 권한다.
- **미착수:** 기기 푸시 알림용 `NotificationService`/범용 `NotificationType`(그룹 알림은 `ShareRepository`가 충족), auth/share **세부** 라우트(그룹 상세·초대 등 페이지 내부 내비게이션 — 현재 `AppRoutes.share` 탭 라우트만 존재).
