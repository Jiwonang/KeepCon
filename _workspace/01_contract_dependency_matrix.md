# KeepCon 공유 계약 의존성 매트릭스 (v1)

> 단일 진실 원천(SSOT). 페이지 개발자와 QA는 이 문서를 경계면 검증의 기준으로 삼는다.
> 이번 검증 슬라이스 범위: **scan(생산) → main(소비)**. auth는 인터페이스+mock으로 대체.
> 계약 위치: `lib/shared/`. 이 문서와 소스가 어긋나면 소스가 아니라 **양쪽을 함께** 갱신한다.

작성일: 2026-07-06 · 최종 갱신: 2026-07-30 · 계약 버전: v2.4 (날짜 포맷 유틸 승격)

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
| **scan** (생산자) | `authRepositoryProvider`→`AuthRepository.currentUser` (소유자 식별), `gifticonRepositoryProvider`, `Gifticon`, `GifticonStatus.available`, `AppRoutes.scan` | `GifticonRepository.addGifticon(Gifticon)` |
| **main** (소비자) | `gifticonRepositoryProvider`→`watchGifticons(ownerId)`, `Gifticon`(+`price`), `SortOption`, `FilterOption`, `GifticonStatus`, `AppRoutes.main`, `Theme.of(context)`(AppTheme) | 총금액 통계 = `price` 합산, (상태 변경 시) `GifticonRepository.updateStatus(id, status)` |
| **share** (그룹/공유) | `shareRepositoryProvider`→`ShareRepository`(그룹 CRUD·멤버·초대·공유/취소·`markUsed`·이력·알림), `Group`/`GroupMember`/`SharedGifticon`/`UsageLog`/`GroupNotification`, `ShareStatus`/`MemberRole`/`GroupNotificationType`, `authRepositoryProvider`→`currentUser`(행위자 식별), `gifticonRepositoryProvider`→`watchGifticons(uid)`(공유 후보 = `Gifticon`), `AppRoutes.share` | `SharedGifticon`/`UsageLog`/`GroupNotification`(share repo에 씀), **`GifticonRepository.updateStatus(gifticonId, GifticonStatus.used)`**(원본 사용 동기화, `markUsed` 경유) |
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

## 후속 확장 예정(이번 슬라이스 범위 밖)

- ✅ **승격 완료(v2):** `Group`, `GroupMember`, `SharedGifticon`, `UsageLog`, `ShareStatus`, `GroupNotification`/`GroupNotificationType`, `MemberRole`, `InviteExpiry`, `ShareRepository`(+`InMemoryShareRepository`, `shareRepositoryProvider`). → `lib/shared/models/group.dart`·`share.dart`, `lib/shared/repositories/share_repository.dart`. 상세 `02_share_contract_promotion.md`.
  - 그룹 관리 행위(생성/삭제/나가기/소유권이전/초대정책)와 `GroupRepository`로 따로 나눌 필요 없이 **하나의 `ShareRepository`**로 통합했다(그룹과 공유가 강결합 도메인).
- ✅ **리팩터 완료(share-page-dev, v2.2):** `lib/features/share/data/`(로컬 `share_models.dart`·`share_store.dart`·`korean_particle.dart`) **제거 완료** → 페이지가 `lib/shared` 계약을 소비. share 테스트는 `ShareStore` 대상에서 **`InMemoryShareRepository` 대상**으로 전환됨(`test/features/share/share_repository_*_test.dart`), korean_particle 테스트는 `test/shared/util/`로 이동. 매핑은 `02_share_contract_promotion.md` D절.
- ✅ **승격 완료(v2.4):** 날짜 라벨 포맷 — 3곳(main `formatDate` / share `formatExpiryLabel` 계열 / scan 인라인)에 분산됐던 `YYYY.MM.DD` 조립을 `lib/shared/util/date_format.dart`의 `formatYmdDot`으로 통합. 표기 규칙 합의 결과는 **점 구분자 통일**(다수 표기, scan만 `-`였음)이고, D-day 라벨(`formatDDay`)·상대 시각(`formatRelativeKo`)은 입력·의미가 달라 **승격 대상이 아님**(각 페이지 로컬 유지).
- **다음 승격 후보:** 현재 알려진 후보 없음. 새로 발견하면 규칙 ③(**실제 두 번째 소비자가 생겼을 때**)을 확인한 뒤 여기에 후보로 기록하고, 직접 `lib/shared`를 고치지 말고 `contract-architect`에게 요청한다(`CODEOWNERS` 리뷰 강제).
- **미착수:** 기기 푸시 알림용 `NotificationService`/범용 `NotificationType`(그룹 알림은 `ShareRepository`가 충족), auth/share **세부** 라우트(그룹 상세·초대 등 페이지 내부 내비게이션 — 현재 `AppRoutes.share` 탭 라우트만 존재).
