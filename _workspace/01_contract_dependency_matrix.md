# KeepCon 공유 계약 의존성 매트릭스 (v1)

> 단일 진실 원천(SSOT). 페이지 개발자와 QA는 이 문서를 경계면 검증의 기준으로 삼는다.
> 이번 검증 슬라이스 범위: **scan(생산) → main(소비)**. auth는 인터페이스+mock으로 대체.
> 계약 위치: `lib/shared/`. 이 문서와 소스가 어긋나면 소스가 아니라 **양쪽을 함께** 갱신한다.

작성일: 2026-07-06 · 최종 갱신: 2026-07-31 · 계약 버전: v2.7 (세션 소비 전환 완결 — 세션 구독 정본 1개)

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
| `Group.inviteValidity` = `Duration(hours: 24)` (고정 정책), `Group.inviteExpiresAt` (`DateTime`, **non-nullable**), `Group.isInviteExpired(now)` | 상수·필드·predicate | `lib/shared/models/group.dart` | 2.8 |
| `Group.isOwnedBy/isMember/canInvite/memberById(userId)` | predicate | 〃 | 2 |
| `SharedGifticon` (원본 `Gifticon.id`를 `gifticonId`로 참조) | model | `lib/shared/models/share.dart` | 2 |
| `UsageLog` / `GroupNotification` | model | `lib/shared/models/share.dart` | 2 |
| `ShareStatus` (available/inUse/used) | enum | `lib/shared/models/share.dart` | 2 |
| `ShareStatusTransition.isAllowed(from, to)` | 전이 규칙 | `lib/shared/models/share.dart` | 2 |
| `GroupNotificationType` (registered/expiringSoon/used) | enum | `lib/shared/models/share.dart` | 2 |
| `JoinRequest` (참여 요청 — groupId·userId·displayName·avatarEmoji·requestedAt·status) | model | `lib/shared/models/join_request.dart` | 2.9 |
| `JoinRequestStatus` (pending/approved/rejected) | enum | `lib/shared/models/join_request.dart` | 2.9 |
| `ShareRepository` | interface | `lib/shared/repositories/share_repository.dart` | 2 |
| `ShareRepository.watchGroups(String userId)` → `Stream<List<Group>>` | method | 〃 | 2 |
| `ShareRepository.getGroups(userId)` / `getGroupById(groupId)` | method | 〃 | 2 |
| `ShareRepository.createGroup({name, emoji, maxMembers})` → `Future<Group>` | method | 〃 | 3.8 |
| `ShareRepository.leaveGroup(groupId)` / `deleteGroup(groupId)` → `Future<void>` | method | 〃 | 2 |
| `ShareRepository.transferOwnershipAndLeave({groupId, newOwnerUserId})` → `Future<Group>` | method | 〃 | 2 |
| `ShareRepository.setInviteOwnerOnly({groupId, ownerOnly})` → `Future<Group>` | method | 〃 | 2 |
| `ShareRepository.watchSharedGifticons(groupId)` / `getSharedGifticons(groupId)` | method | 〃 | 2 |
| `ShareRepository.shareGifticon({groupId, Gifticon gifticon})` → `Future<SharedGifticon>` | method | 〃 | 2 |
| `ShareRepository.toggleReservation(id)` / `markUsed(id)` → `Future<SharedGifticon>` | method | 〃 | 2 |
| `ShareRepository.cancelShare(id)` → `Future<void>` | method | 〃 | 2 |
| `ShareRepository.watch/getUsageLogs(userId)` / `watch/getNotifications(userId)` | method | 〃 | 2 |
| `ShareRepository.requestToJoin(inviteToken)` → `Future<JoinRequest>` | method | 〃 | 2.9 |
| `ShareRepository.watch/getMyJoinRequests(userId)` → `List<JoinRequest>` (최신순) | method | 〃 | 2.9 |
| `ShareRepository.watch/getPendingJoinRequests(groupId)` → `List<JoinRequest>` (오래된 순) | method | 〃 | 2.9 |
| `ShareRepository.approveJoinRequest(id)` → `Future<Group>` / `rejectJoinRequest(id)` → `Future<JoinRequest>` | method | 〃 | 2.9 |
| `ShareRepository.cancelJoinRequest(id)` → `Future<void>` | method | 〃 | 2.9 |
| `InMemoryShareRepository` (AuthRepository·GifticonRepository 주입) | mock impl | `lib/shared/repositories/impl/in_memory_share_repository.dart` | 2 |
| `shareRepositoryProvider` (`Provider<ShareRepository>`) — **SSOT** | provider | `lib/shared/providers/repositories.dart` | 2 |
| `josa(word, withBatchim, withoutBatchim)` / `KoreanJosa` 확장(`eulReul`/`iGa`/`eunNeun`/`waGwa`) | util | `lib/shared/util/korean_particle.dart` | 2 |
| `groupThousands(digits)` (코어) / `digitsOnly(input)` / `formatThousands(input)` (scan 진입점) / `formatWon(won)` (main 진입점) | util | `lib/shared/util/money_format.dart` | 2.3 |
| `formatYmdDot(DateTime)` → `'YYYY.MM.DD'` (코어 — main·share·scan 공통 날짜 표기) | util | `lib/shared/util/date_format.dart` | 2.4 |
| `myGroupsProvider` (`AutoDisposeProvider<AsyncValue<List<Group>>>`) — **SSOT**. 세션→`watchGroups` 체인 정본. scan·share **공용 구독 1개** | provider | `lib/shared/providers/my_groups_provider.dart` | 2.5 |
| `sessionUserProvider` (`AutoDisposeStreamProvider<User?>`) — **SSOT**. `watchCurrentUser()` 세션 스트림 정본 | provider | `lib/shared/providers/session_provider.dart` | 2.6 |
| `myGroupsRetryProvider` (`Provider<MyGroupsRetry>`) + `MyGroupsRetry.retry()` — 내 그룹 체인 **수동 재시도 훅**(에러 계층만 재구독) | provider | `lib/shared/providers/my_groups_provider.dart` | 2.6 |
| `retryMyGroups(WidgetRef ref)` → `void` — 위 훅의 화면용 진입점(`ref.read(myGroupsRetryProvider).retry()`와 동일) | function | 〃 | 2.6 |
| `notificationsProvider` (`Provider<AsyncValue<List<GroupNotification>>>`) / `notificationsReadAtProvider` (`Provider<DateTime?>`) / `unreadNotificationCountProvider` (`Provider<int>`) — **SSOT**. 그룹 알림 목록·마지막 읽음 시각·안읽음 수. 벨 3곳(홈·공유 탭·마이페이지)이 같은 수를 본다 | provider | `lib/shared/providers/group_notifications_provider.dart` | 3.2 |
| `retryNotifications(WidgetRef ref)` → `void` — 알림·읽음 스트림 중 **에러인 것만** 재구독 | function | 〃 | 3.2 |
| `retrySessionIfFailed(WidgetRef ref)` → `void` — 세션 스트림이 에러일 때만 재구독(그룹 축을 건드리지 않는 경로용. `retryMyGroups`와 겹쳐 부르지 않는다) | function | `lib/shared/providers/session_provider.dart` | 3.2 |
| `NotificationBell({onPressed, tooltip})` — 안읽음 수 뱃지가 붙은 알림 벨(0이면 뱃지 없음, 10 이상은 `9+`). 목적지는 주입받는다 | widget | `lib/shared/widgets/notification_bell.dart` | 3.2 |
| `AppNotification` (sealed) + `GroupNotificationItem` / `ExpiryNotificationItem` — 알림 센터가 한 목록에 담는 항목. 저장된 그룹 알림과 **계산으로 복원한** 개인 만료 알림을 합친다 | model | `lib/shared/models/app_notification.dart` | 3.3 |
| `allNotificationsProvider` (`Provider<AsyncValue<List<AppNotification>>>`) — **SSOT**. 두 출처 병합(최신순). 두 축 중 어느 쪽이 에러여도 `AsyncError.copyWithPrevious`로 배너를 띄우며 지금 가진 목록은 유지하고, 어느 한 축이라도 첫 방출 전이면 값 없이 로딩을 전파한다(읽음 가드가 조기에 열려 알림이 유실되는 것을 막는다) | provider | `lib/shared/providers/group_notifications_provider.dart` | 3.3 |
| `rawGifticonsProvider` (`StreamProvider<List<Gifticon>>`) — **SSOT**. 필터 전 원천 기프티콘 목록. main 파생·만료 알림 예약·알림 센터 복원이 공용 | provider | `lib/shared/providers/raw_gifticons_provider.dart` | 3.3 |
| `firedExpiryNotifications(gifticons, {now, within})` → `List<ExpiryNotificationItem>` — **이미 울린** 만료 알림 복원(`planExpiryNotifications`의 여집합) / `expiryNotificationHistory`(30일) | function | `lib/shared/notifications/expiry_notification_plan.dart` | 3.3 |
| `nowProvider` (`Provider<DateTime>`) — **SSOT**. 날짜 파생 계산이 공유하는 단일 시각. 소비자가 각자 `DateTime.now()`를 읽으면 서로 다른 "오늘"로 판정한다. 값은 셸이 앱 복귀 시 무효화해 갱신(포그라운드 자정은 미해결). **만료·D-day 파생**은 이것만 본다. ⚠️ 상대 시각 포맷(사용 이력·공유 탭)과 초대 만료는 아직 실제 시계를 읽는다 — 문서가 아니라 코드가 지키는 범위를 적는다 | provider | `lib/shared/providers/now_provider.dart` | 3.3 |
| `inviteOriginProvider` (`Provider<String?>`) — **SSOT**. 초대 링크의 origin. `null`이면 **이 실행에서는 링크를 만들 수 없다**(화면이 링크 대신 초대코드를 안내한다). 조립부가 `inviteOriginFor(target)`으로 주입 | provider | `lib/shared/providers/invite_link_providers.dart` | 3.1 |
| `inviteUrlFrom({origin, inviteToken})` → `String` — `<origin>/invite/<token>` 조립(순수 함수, `parseInviteToken`과 라운드트립) / `inviteOriginFor(FirebaseTarget)` → `String?` — 백엔드별 origin 표 | function | `lib/shared/util/invite_link.dart`, `lib/shared/providers/invite_link_providers.dart` | 3.1 |

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
| **main** (소비자) | `gifticonRepositoryProvider`→`watchGifticons(ownerId)`, **`sessionUserProvider`**(v2.7 — 목록 체인·화면 모두 정본 직수입, 폴딩은 `valueOrNull`), `Gifticon`(+`price`), `SortOption`, `FilterOption`, `GifticonStatus`, `AppRoutes.main`, `Theme.of(context)`(AppTheme) | 총금액 통계 = `price` 합산, (상태 변경 시) `GifticonRepository.updateStatus(id, status)` |
| **share** (그룹/공유) | `shareRepositoryProvider`→`ShareRepository`(그룹 CRUD·멤버·초대·공유/취소·`markUsed`·이력·알림), **`myGroupsProvider`**(내 그룹 목록 — `AsyncValue` 그대로 전파), `Group`/`GroupMember`/`SharedGifticon`/`UsageLog`/`GroupNotification`, `ShareStatus`/`MemberRole`/`GroupNotificationType`, `authRepositoryProvider`→`currentUser`(행위자 식별), `gifticonRepositoryProvider`→`watchGifticons(uid)`(공유 후보 = `Gifticon`), `AppRoutes.share`, **`retryMyGroups(ref)`/`myGroupsRetryProvider`**(v2.6 — 내 그룹 배너 4곳의 `onRetry`), **`sessionUserProvider`**(v2.6 세션 정본 — 화면·파생이 **직수입**. 경과 조치였던 `shareCurrentUserProvider` 별칭은 제거 완료) | `SharedGifticon`/`UsageLog`/`GroupNotification`(share repo에 씀), **`GifticonRepository.updateStatus(gifticonId, GifticonStatus.used)`**(원본 사용 동기화, `markUsed` 경유) |
| **auth/설정('마이')** | `themeModeProvider`(watch), **`sessionUserProvider`**(v2.7 — mypage 프로필 카드가 정본 직수입) | `ThemeModeController.setDark(bool)`/`.set(mode)` (다크 토글) |
| **앱 조립부(main.dart)** | `themeModeProvider`(watch), `AppTheme.light`/`AppTheme.dark`, **`sessionUserProvider`**(v2.7 — `auth_gate`가 루트에서 상시 watch = 정본 수명 앵커) | `MaterialApp.theme`/`darkTheme`/`themeMode` 배선 |

> **세션 스트림 소비(v2.6 규약 / v2.7 전환 완결):** `watchCurrentUser()` 체인을 페이지에서 새로
> 조립하지 말고 `sessionUserProvider`(`lib/shared/providers/session_provider.dart`)를 소비한다.
> **전환 완료 = 전 소비자**(`myGroupsProvider` · share · main · mypage · 앱 조립부) —
> `watchCurrentUser()` 구독은 앱 전체에서 **정본 1개**다(테스트로 고정, #13).
> 새 코드도 정본을 직접 쓴다(페이지 별칭·재export shim 금지). `user?.id`처럼 일부만 필요하면
> `sessionUserProvider.select(...)`로 좁혀 재방출 리빌드를 줄인다(#13의 `select` 항목).

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
   - 📌 **판정(v2.6, QA [medium 1]): 정본의 세션 폴딩 규약은 파생에도 그대로 적용된다.**
     세션 `AsyncValue` 위에 얹는 파생은 **`.when`을 쓰지 않는다** — `when`은 `skipError`가 기본
     `false`라 **이전 값을 보존한 순단 에러에서도 error 분기**를 타 하위 스트림의 멀쩡한 데이터를
     통째로 버린다. 그 결과 같은 한 번의 세션 순단에 '내 그룹'(정본 폴딩)은 멀쩡한데 알림·사용
     이력·공유 후보(`.when` 파생)만 비워지는 **비대칭 화면**이 된다(실측). 아래 상태 규약과 같은
     `valueOrNull` 기반 4분기로 통일하되, **미로그인 확정(`data(null)`) → `AsyncData(<T>[])` 경로는
     반드시 보존**한다(알림 읽음 가드의 `StateError` 복원 분기가 그 형태에 의존). 적용 중:
     share `usageLogsProvider`·`notificationsProvider`·`shareableGifticonsProvider`(share-page-dev).
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
     ✅ **재시도 훅 도착(v2.6) — 내 그룹 목록도 되살릴 수 있다.** 승격 전에는 이 provider가
     에러로 끝나면 `AsyncError`가 정본의 **private 체인**에 캐시되고, 페이지의
     `invalidate(myGroupsProvider)`는 dependency로 전파되지 않아(실측 — Riverpod의 invalidate는
     dependents 방향으로만 전파) 되살릴 수 없었다. 그래서 원인이 그룹 목록인 배너는
     `onRetry: null`(+"앱을 다시 열어 주세요")로 남아 있었다. 이제 정본 파일이 재시도 진입점을
     제공한다:
     - **`retryMyGroups(WidgetRef ref)`** (= `ref.read(myGroupsRetryProvider).retry()`).
       share의 `retry*(WidgetRef)` 관용구와 동형이라 배너 콜백에 그대로 넣을 수 있다.
     - 되살리는 계층은 **세션(`sessionUserProvider`) + 그룹 스트림(`_groupsByUserProvider`의
       현재 user 인스턴스)** 둘 다이며, **에러인 계층만** 재구독한다(멀쩡한 스트림 재구독 =
       불필요한 읽기·과금·로딩 깜빡임 — 계약 정본 `retrySessionIfFailed`와 같은 스코프 원칙).
       세션에 알려진 user가 없으면 그룹 계층은 건드리지 않는다(family 인스턴스가 없다).
     - **자동 재시도 금지 규약은 그대로**다 — 훅은 사용자 액션(버튼/당김 새로고침)에서만 호출한다.
       `build`/`listen`에서 에러 감지 후 자동 호출하면 장애 중 retry storm이 된다.
     - 회귀 고정: `test/shared/providers/session_and_retry_test.dart`
       (세션만/그룹만/둘 다/정상 4경우 + 회복 + `WidgetRef` 진입점).
     ✅ **share 소비 전환 완료(share-page-dev, 같은 v2.6).** `onRetry` 강등(동작하지 않는
     버튼 방지)이 제거되고 배너 4곳이 훅에 배선됐다 — share 메인 '내 그룹'·사용 이력은
     `retryMyGroups(ref)` 직접, 공유 상세는 신설 `retrySharedItemLookup`(= `retryMyGroups`
     + 실패한 그룹별 공유 인스턴스), 공유 시트는 `retryShareCandidates`가 세션 계층 재시도를
     `retryMyGroups`로 승격. **분담 규약:** `retryMyGroups`가 세션+그룹을 함께 맡으므로, 그것을
     부르는 경로에서는 계약 정본 `retrySessionIfFailed`를 **겹쳐 부르지 않는다**(중복 invalidate
     방지). 그룹과 무관한 경로(알림·이력·그룹별 공유 스트림)만 `retrySessionIfFailed`를 쓴다.
     `myGroupListUnavailableProvider`는 남아 있지만 이제 **표시 판정 전용**이다(재시도 가능
     여부와 무관 — "값도 없는 에러"에서만 배너를 띄운다는 UX 판단은 유지: 멀쩡히 렌더되는
     목록 위에 실패를 얹지 않는다).
   - ✅ **세션 스트림 = 정본화·소비 전환 모두 완료(v2.6 정본 → v2.7 전환 완결).**
     `lib/shared/providers/session_provider.dart`의 **`sessionUserProvider`**
     (`AutoDisposeStreamProvider<User?>` — `myGroupsProvider`와 같은 수명 근거)가 정본이며,
     **`AuthRepository.watchCurrentUser()`를 구독하는 곳은 앱 전체에서 이 한 곳뿐이다.**
     승격 전 5곳(앱 조립부 `authStateProvider` / main `currentUserProvider` / mypage 인라인 /
     share `shareCurrentUserProvider` / `my_groups_provider.dart` 내부 `_currentUserProvider`)이
     전부 **선언 삭제 + 정본 직수입**으로 정리됐다(재export shim·별칭 없음 — v2.3에서 확정된 방식).
     즉 정본은 이제 "수렴 지점"이 아니라 **수렴 완료 상태**다.

     | 옛 소비자 | 위치 | 상태 |
     |------|------|------|
     | `_currentUserProvider` | `lib/shared/providers/my_groups_provider.dart` | ✅ 삭제(v2.6) |
     | `shareCurrentUserProvider` | `lib/features/share/state/share_providers.dart` | ✅ 별칭 경유 후 삭제(v2.6→v2.7) |
     | `currentUserProvider` | `lib/features/main/state/gifticon_list_providers.dart` | ✅ 삭제(v2.7) |
     | (인라인 구독) | `lib/features/mypage/mypage_page.dart` | ✅ 삭제(v2.7) |
     | `authStateProvider` | `lib/app/auth_gate.dart` | ✅ 삭제(v2.7) |

     **구독 1개는 문서가 아니라 테스트가 고정한다** — `test/features/main/main_session_consumer_test.dart`
     ("목록 체인과 화면이 동시에 세션을 봐도 `watchCurrentUser` 구독은 1회") +
     `test/shared/providers/session_and_retry_test.dart`(정본 소비자 2개 → 1회).
     앱 게이트가 루트에서 정본을 상시 `watch` 하므로, autoDispose 정본의 실효 수명은
     **앱 수명 = 구독 1개**다(게이트가 앵커).
     ⚠️ **재발 방지의 한계:** `tool/check_ssot.sh`는 **이름 기반**이라 `sessionUserProvider`
     재선언은 잡지만 *다른 이름으로 다시 조립한 세션 체인*(`final myOwnSession = ...watchCurrentUser()`)은
     못 잡는다. 새 세션 구독이 필요해 보이면 만들지 말고 정본을 소비한다(규약 ①재사용 우선).
     ✅ **경과 조치 종료 — 별칭 `shareCurrentUserProvider`는 제거됐다(체크리스트 소멸).**
     v2.6의 판정은 "이름 유지 pass-through는 경과 조치로 허용, **종착점은 별칭 제거**"였고
     그 종착점에 도달했다. 실측 **12곳**(v2.6 기록과 일치 — 화면 4 / 파생 `watch` 5 /
     함수 내부 `read` 3)을 `sessionUserProvider` 직수입으로 전수 치환하고 선언을 삭제했다.
     전수 확인은 예고대로 `grep -rn "shareCurrentUserProvider" lib test`로 했고(라인 좌표가
     아니라 심볼·grep이 정본), 잔존 참조는 **0건**(남은 문자열은 `lib/shared`의 회고 dartdoc
     3곳뿐 — 계약 소유자 정리 대상, 아래 후속). 테스트는 별칭명을 참조하지 않아 **무수정 통과**.
     ⚠️ **별칭 제거의 부작용 하나(치환 시 반드시 함께 판단):** 별칭은 `Provider`라
     `updateShouldNotify`가 `previous != next`였고 `AsyncValue`는 `==`를 구현하므로,
     **같은 값의 재방출을 흡수하는 필터**였다. 정본은 `StreamProvider`라 data→data 재방출도
     무조건 통지한다(riverpod 2.6.1 `FutureHandlerProviderElementMixin.handleUpdateShouldNotify`
     — 로딩 전이가 아니면 항상 true). Firebase는 `userChanges()`를 쓰므로 **토큰 갱신(약 1시간
     주기)·프로필 reload에서 값이 같은 세션이 재방출**된다. 그래서 share는 치환과 함께
     **`user?.id`만 읽는 6곳(화면 4 + `notificationsReadAtProvider` + `memberNamesProvider`)에
     `select((s) => s.valueOrNull?.id)`** 를 적용했다 — 별칭이 하던 필터를 되살리고(오히려 더
     좁다), 세션 `AsyncValue` 전체가 필요한 `foldSessionUser` 3곳만 provider를 통째로 watch한다.
     특히 `memberNamesProvider`는 반환 타입 `MemberNames`에 `==`가 없어 재계산이 곧 새 인스턴스
     = 소비 위젯 리빌드이므로, 필터 없이 치환했다면 재방출마다 카드·목록이 리빌드됐다.
     이 `select`는 **테스트가 고정한다**(QA [medium 2] 반영 — "구독 수는 테스트가 고정한다"를
     리빌드 축에도 적용): `test/features/share/session_select_rebuild_test.dart`가 같은 uid·
     다른 표시명 재방출로 대표 3지점(`memberNamesProvider` / `SharePage` / `GroupDetailPage`)의
     무재계산·무리빌드를 단언하고(각 테스트가 "정본엔 새 값이 도착했다"를 함께 단언해 공허한
     통과를 막는다), uid가 바뀌면 반드시 반응하는 양성 대조를 함께 잡는다. 역실험 실증:
     `select` 3곳을 제거하면 3개 테스트가 모두 실패한다.
     ⚠️ **정정(v2.7 후속, QA [medium 1]): "회귀 없음"과 "협소화 불필요"는 다르다.** 자체
     `StreamProvider`를 정본으로 바꾼 main·mypage·앱 조립부는 통지 특성이 정본과 같아 **이번
     치환이 새 회귀를 만들지 않는다** — 그러나 정본 dartdoc의 일반 권고(일부 필드만 쓰는
     소비자는 `select`로 좁힌다)는 그대로 적용된다. 실제로 main `rawGifticonsProvider`는
     `user.id`만 쓰면서 세션을 통째 watch해 **재방출마다 `watchGifticons`가 재구독**됐고
     (재계산이 끝인 share 6곳과 달리 스트림 teardown/재수립 = Firestore 쿼리 재읽기),
     트리거인 **mypage 프로필 편집**(`updateDisplayName`+`reload` → 같은 uid·다른
     `displayName` 재방출)은 삭제된 별칭의 `==` 필터로도 못 거르던 경로다 — `select`가 엄격히
     나은 자리. v2.7 후속에서 `select((s) => s.valueOrNull?.id)`로 좁히고 계측 테스트로
     고정했다(`test/features/main/main_session_consumer_test.dart`). 세션 `AsyncValue` **전체**가
     필요한 지점(게이트 `when` 3분기 · `main_page`의 `when` · mypage의 `displayName`·`email`)은
     통째 watch가 정답이며, 판정 기준은 "`Provider` 별칭이었나"가 아니라 **"이 소비자가 세션의
     무엇을 읽는가"** 다.
     ⚠️ 수명은 불변이다: 별칭이 붙잡던 autoDispose 정본의 구독을 이제 같은 파일의 keepAlive
     파생들(`usageLogsProvider` 등)이 직접 watch해 붙잡는다(share 탭 1회 진입 후 컨테이너 수명).
     ⚠️ 전환 교훈(다음 담당자용): **함수 안의 `read`가 누락되기 쉽다**(화면·파생만 훑으면 안
     보인다) — 체크리스트를 "전수(grep)"로 잡지 않으면 전환이 절반만 된 채 "완료"로 판정된다
     (QA [minor 1]).
     ⚠️ 정산 기록: share 정상상태의 동시 세션 구독은 v2.5에서 2개(share 자체 + 정본 내부)로
     늘었다가 v2.6에서 **1개(정본 하나 — share가 그것을 직접 소비)** 로 수렴했다.
     `memberNamesProvider`가 두 세션 소스를 혼합해 계정 전환 프레임에서 한 프레임 어긋날 수
     있던 위험도 이로써 사라졌다(그룹 목록과 세션이 **같은 스트림**을 본다).
     💰 세션 정본화의 이득은 **과금이 아니라 인스턴스/타이밍 일관성**이다(인증 상태 리스너는
     Firestore 문서 읽기가 아니다). 대신 "실패 시 캐시된 에러가 소스 수만큼 생겨 재시도가
     절반만 먹히는" 문제는 과금과 무관하게 실제 버그였다(QA [minor 5]).

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
| v2.6 | 2026-07-31 | **세션 스트림 정본 승격 + 내 그룹 재시도 훅 (non-breaking, 순수 추가 + 내부 대체).** (1) `lib/shared/providers/session_provider.dart` 신설 — `sessionUserProvider`(**SSOT**, `AutoDisposeStreamProvider<User?>`). 수명·노출 형태는 `myGroupsProvider`와 같은 근거(구독 0/1, keepAlive 소비자가 수명을 붙잡음, `AsyncValue`로 로딩/에러 구분 보존, `.value` 금지·`valueOrNull`). (2) `my_groups_provider.dart`의 내부 `_currentUserProvider` **삭제** → 정본 소비(공개 API·상태 규약·수명 전부 불변). 이로써 `watchCurrentUser()`의 "정본 내부 두 번째 구독"이 사라져 **QA [minor 5]**(세션 실패 시 캐시된 에러가 둘 → 재시도가 절반만 먹힘)의 원인 절반이 제거됐다. (3) **재시도 훅 신설**(정본 파일): `myGroupsRetryProvider`→`MyGroupsRetry.retry()`와 화면용 진입점 `retryMyGroups(WidgetRef)`. **에러인 계층만** 재구독한다(세션 / 그룹 family의 현재 user 인스턴스) — 멀쩡한 스트림은 건드리지 않는다(share `_retrySessionIfFailed`와 같은 스코프 원칙). 자동 재시도 금지 규약 유지(사용자 액션 전용, dartdoc 명시). provider 형태를 택한 이유는 private 원천 접근에 정본 파일의 `Ref`가 필요하고, `WidgetRef`/`Ref`/`ProviderContainer` 어디서든 같은 방법으로 호출되기 때문이다. (4) 신규 테스트 `test/shared/providers/session_and_retry_test.dart`(8) — 두 소비자 동시 watch 시 `watchCurrentUser` 구독 1회, autoDispose 수명, 훅의 4경우(둘 다 정상/그룹만/세션만/둘 다 에러) + `invalidate(myGroupsProvider)`의 무력함 실증 + 회복 + `WidgetRef` 진입점. **기존 `my_groups_provider_test.dart` 무수정 통과**(동작 불변의 증거). (5) `tool/check_ssot.sh` 보강 — `SSOT_PROVIDERS`에 `sessionUserProvider`·`myGroupsRetryProvider` 추가에 더해, QA [minor 3] 반영으로 **언더스코어 접두 재선언**(`final _sessionUserProvider =` — v2.6에서 삭제한 `_currentUserProvider`, 승격 전 `_scanCurrentUserProvider`와 같은 실제 재발 경로), **계약 클래스**(`MyGroupsRetry`, private 복제 포함), **계약 함수 재정의**(`SSOT_FUNCTIONS`=`retryMyGroups` — 반환 타입을 요구해 선언만 잡고 호출은 통과)까지 검출한다. 6개 선언 형태 프로브로 전수 실증 + 호출 형태 오탐 없음 확인 후 프로브 삭제. ※ 이름 기반 가드의 한계(다른 이름의 의미상 중복 — main `currentUserProvider` 등)는 잔여 표가 유일한 방어선이다. (7) QA [medium 1] 판정으로 **세션 폴딩 규약(`.when` 금지, `valueOrNull` 4분기)을 파생에도 적용**(#13), [minor 1] 반영으로 별칭 소비처 수치를 **12곳**(화면 4 + 파생 5 + `retry*` 내부 `read` 3)으로 정정. (6) **share 소비 전환 동반 완료(share-page-dev, 같은 v2.6):** `shareCurrentUserProvider`가 자체 `watchCurrentUser()` 구독을 버리고 정본 **pass-through 별칭**(`ref.watch(sessionUserProvider)`)이 됨(이름 유지 — 소비처 12곳 무수정, "invalidate 대상 아님"을 dartdoc에 명시), 배너 4곳이 `retryMyGroups` 기반으로 재배선(`retrySharedItemLookup` 신설, `retryShareCandidates` 승격), `_retrySessionIfFailed`는 정본 직접 invalidate로 교체 + **훅과 겹쳐 부르지 않는 분담 규약**. (8) **리뷰 라운드 반영(같은 v2.6):** 세션 폴딩 규약을 산문에서 **계약 함수 `foldSessionUser`로 기계화**(정본 `session_provider.dart` — `myGroupsProvider`와 share 파생 3곳이 같은 한 구현 소비, 동형성 드리프트 구조적 차단). 분기 순서는 **에러를 로딩보다 먼저**(invalidate=refresh가 이전 에러를 보존한 로딩을 만들므로, 로딩 우선이면 재시도 순간 배너가 사라졌다 재등장하는 왕복 깜빡임 — riverpod 소스로 실증, 구 `.when`의 `skipLoadingOnRefresh`와 동형). `MyGroupsRetry.retry()`의 검사용 `read`는 `Ref.exists` 가드(미마운트 autoDispose 인스턴스를 새로 만들어 낭비 구독을 여는 부수효과 차단). 순단(값 보존) 무배너 유지의 전제를 정본 dartdoc에 명시(두 구현 모두 세션 스트림이 에러로 **종료되지 않아** 다음 인증 이벤트에 자동 회복 — 종료형 구현 도입 시 재검토). `check_ssot.sh` 함수 가드에 `foldSessionUser` 추가 + 수식어/`dynamic`/제네릭/타입 생략 선언까지 검출(프로브 5형태 실증), 이름 기반 가드의 한계는 주석에 정직하게 기록. 테스트 **193** 통과. **⏳ 후속:** 세션 정본 소비 전환 잔여(main·mypage·앱 조립부)와 share 별칭 제거(소비처 직수입 치환)는 각 담당. 단일 세션 장애 시 그룹·이력 배너가 각각 뜨는 문구 중복의 통합(원인 단위 배너)은 UX 설계 항목으로 계류. 세션 전용 재시도 진입점(`retrySession`류)은 잔여 3곳 전환 시 두 번째 소비자가 생기는 시점에 승격 검토. | share(**전환·재시도 복구 완료**), main·mypage·앱 조립부(세션 전환 예정 — 이번 변경으로 깨지는 것 없음), scan(영향 없음) |
| v2.7 | 2026-07-31 | **세션 소비 전환 완결 (non-breaking, 계약 무변경 — 소비처 정리).** v2.6이 만든 정본 `sessionUserProvider`로 **남은 소비자 전부**가 옮겨왔다: ① 앱 조립부 `authStateProvider` **삭제** → `auth_gate`가 정본 직수입(루트에서 상시 watch = autoDispose 정본의 **수명 앵커**, 실효 수명 = 앱 수명) ② main `currentUserProvider` **삭제** + mypage 인라인 구독 **삭제** → 정본 직수입(폴딩은 기존 `valueOrNull` 유지 — 표시 동작 불변) ③ share 별칭 `shareCurrentUserProvider` **완전 제거**(12곳 직수입 + `user?.id`만 쓰는 6곳 `select` 보정 — `Provider` 별칭이 하던 `==` 필터를 `StreamProvider` 정본이 갖지 않는 특성 대응, 근거는 #13). **결과: `AuthRepository.watchCurrentUser()` 구독이 앱 전체에서 정본 1개로 수렴**(승격 전 5곳). 구독 수는 문서가 아니라 테스트가 고정한다 — 신규 `test/features/main/main_session_consumer_test.dart`("목록 체인과 화면이 동시에 세션을 봐도 구독 1회", 순단 시 목록 보존) + 기존 `session_and_retry_test.dart`. **계약 파일(`lib/shared`)은 dartdoc만 갱신**했다(전환 완료 반영 — 시그니처·동작 무변경). 테스트 **202** 통과. ⚠️ 재발 방지의 한계: `check_ssot.sh`는 이름 기반이라 *다른 이름으로 다시 조립한 세션 체인*은 못 잡는다 — 새 세션 구독이 필요해 보이면 만들지 말고 정본을 소비한다(규약 ①재사용 우선). | 전 페이지(auth_gate·main·mypage·share = 정본 직수입 완료, 동작 불변), scan(영향 없음 — 세션 미소비) |
| v2.8 | 2026-08-11 | **초대 만료 정책 고정 — 24시간 단일 정책 (breaking, 선택지 제거).** 방장이 만료 기간을 고르던 구조를 없애고 **모든 초대 링크·코드가 발급 시점부터 24시간만 유효**하도록 계약을 좁혔다. (1) `InviteExpiry` enum **삭제** → `Group.inviteValidity`(`Duration(hours: 24)`) 상수로 대체. (2) `ShareRepository.setInviteExpiry` **삭제** — 만료를 바꾸는 API 자체가 사라졌고, 만료된 초대를 되살리는 경로는 `regenerateInviteCode`(재발급 시점 + 24시간) 하나뿐이다. (3) `Group.inviteExpiresAt`가 `DateTime?` → **`DateTime`(non-nullable)** — "만료 없음(무제한)"이라는 상태를 타입에서 제거했다. 생성자에서 생략하면 `현재 + inviteValidity`로 채우므로 그룹 생성·데모 시드·테스트 픽스처는 자동으로 정책을 따른다. **⚠️ 레거시 Firestore 문서 취급:** `inviteExpiresAt` 필드가 없거나 손상된 문서는 epoch(=만료됨)으로 읽는다(fail-closed) — 그 코드들은 어차피 발급된 지 24시간이 지났으므로 정책상 만료가 맞고, 방장이 "코드 재발급"을 누르면 정상 복구된다. (4) 멤버 초대 화면에서 만료 선택 UI(`_ExpiryButton` 4칸)를 제거하고 남은 유효기간/만료 상태를 **표시만** 한다. 테스트 **284** 통과. | share(초대 화면 UI 변경·만료 API 소비 중단), 그 외 페이지 영향 없음 |
| v2.9 | 2026-08-18 | **참여 요청 계약 추가 + 초대코드 → 초대 토큰 이름 정리 (breaking: 이름 변경).** 초대 링크를 받은 사람이 **곧바로 멤버가 되지 않고** 방장 승인을 기다리는 흐름을 계약에 넣었다. (1) `JoinRequest` 모델 + `JoinRequestStatus`(pending/approved/rejected) 신설. 요청자에게 **그룹명·이모지·멤버 수를 담지 않는다** — 승인 전에는 어느 그룹인지 보여주지 않는 정책이라 화면이 쓰지 않는 값을 저장하지 않는다(`groupId`는 담는다. 구현이 그룹을 찾는 데 필요하고 `getMyJoinRequests`가 요청자에게 그대로 돌려주므로, '어느 그룹인지 감춘다'는 것은 모델이 아니라 화면이 지키는 규약이다). (2) `requestToJoin`/`watch·getMyJoinRequests`/`watch·getPendingJoinRequests`/`approveJoinRequest`/`rejectJoinRequest`/`cancelJoinRequest` 추가. **정원은 요청이 아니라 승인 시점에 본다** — 대기자가 자리를 선점하면 방장이 정작 받고 싶은 사람을 못 넣는다. 재요청은 멱등((그룹,사용자)당 요청 하나)이고, 거절은 **기록으로 남긴다** — 비멤버는 그룹 알림을 못 읽으므로 요청자가 결과를 알 유일한 경로다. 취소는 상태가 아니라 삭제. (3) 방장에게 요청 도착을 알리는 신호는 `watchPendingJoinRequests` **하나**다 — 알림 문서는 만들지 않는다. 요청의 행위자는 정의상 비멤버인데 `notifications` 생성은 멤버만 가능해(규칙), 클라이언트가 만들 수 없는 알림이 된다. 규칙에 비멤버 예외를 뚫으면 외부인이 그룹 알림 피드에 쓰는 길이 열리고 서버로 대신 쓰려면 유료 플랜이 필요하다 — 대기 목록이 같은 정보를 이미 갖고 있으므로 둘 다 치르지 않는다(자체 리뷰에서 에뮬레이터로 403 재현 후 결정). (4) `Group.inviteCode` → **`Group.inviteToken`**, `regenerateInviteCode` → `regenerateInviteToken`, `parseInviteCode` → `parseInviteToken`, `InviteDestination.inviteCode` → `inviteToken`. Firestore 필드 키도 옮기되 읽을 때 레거시 `inviteCode`를 받아 준다(기존 문서·시드 호환). **토큰 생성 방식은 아직 6자리 그대로** — 128비트로 올리는 일은 멤버 초대 화면이 그 값을 24pt로 표시하기 때문에 그 화면을 걷어내는 단계에서 함께 한다. (5) Firestore 구현은 아직 없다(`UnimplementedError`) — 비멤버는 규칙상 `groups`를 읽을 수 없어 토큰→그룹 조회 문서가 먼저 필요하고, 그 스키마가 규칙·인덱스를 함께 정한다. in-memory 구현 + 테스트 **20건**으로 계약을 고정했다. 전체 테스트 **364** 통과. | share(참여·승인 화면 신설 예정), 그 외 페이지는 `inviteToken` 이름 변경만 |

| v3.0 | 2026-08-20 | **참여 요청 Firestore 구현 + 보안 규칙 (스키마 확정, non-breaking).** 계약은 v2.9에서 확정했고 이번에는 그 계약을 Firestore에 앉혔다. (1) **`inviteTokens/{token}`** 조회 문서 신설 — 문서 id가 곧 토큰이고 담는 것은 `groupId`·`expiresAt`뿐이다. 비멤버는 규칙상 `groups`를 읽을 수 없어 토큰→그룹을 찾을 길이 없는데, 그 다리를 놓으면서 대문까지 열면 안 되므로 **`get`만 열고 `list`는 막았다**(목록을 열면 토큰을 몰라도 모든 그룹 id를 얻는다). (2) **`joinRequests/{groupId}_{userId}`** — 문서 id로 (그룹,사용자)당 하나를 저장소가 강제한다. 읽기는 요청자 본인과 그 그룹의 방장만(일반 멤버에게도 대기자 명단을 열지 않는다), 생성은 비멤버가 만료 전에만, 결정은 방장이 대기 중인 요청의 `status` 한 필드만. (3) **만료·멤버십을 규칙에서도 본다** — 클라이언트 트랜잭션 안에만 두면 규칙을 안 거치는 요청에 무력하다(PR #89에서 정확히 그 구멍이었다). 정원은 규칙에서 보지 않는다(대기자는 자리를 차지하지 않는다는 계약 그대로). (4) 그룹이 사라지면 요청·토큰 문서도 캐스케이드로 정리한다. 재발급은 **옛 토큰 문서를 먼저 지우고** 새 문서를 쓴다(둘 다 열리는 창을 만들지 않는다 — fail-closed). (5) `InMemoryShareRepository`에 만료 판정용 시계를 주입해 **초대 만료 가드에 처음으로 테스트를 붙였다**(`joinGroup`의 기존 미검증 가드 포함). 규칙 검증 33건 추가(총 67건), 전체 테스트 **437** 통과. **[에이전트 리뷰 반영]** 🔴 하나가 치명적이었다 — 없는 `inviteTokens` 문서를 지우면 `resource`가 null인데 `resource.data`를 만져 규칙 평가가 오류(=거부)로 죽었고, 레거시 그룹에는 그 문서가 아예 없으므로 **기존 그룹 전부가 삭제·탈퇴·재발급 불가**가 될 뻔했다(재발급은 그룹 토큰만 회전시킨 채 매번 같은 지점에서 죽는다). `resource == null` 예외를 두되 `joinRequests`에는 두지 않았다 — 거기서는 200/403이 문서 존재 오라클이 된다. 🟠 멤버십이 끊기는 세 경로(나가기·강퇴·소유권 이전)의 요청 정리가 Firebase에만 없었다 — in-memory 테스트가 못박아 둔 동작인데 `flutter test`는 in-memory만 돌려 green으로 지나갔다(반복 패턴 #1). 🟠 **토큰이 조회 가능한 문서 id가 되면서 6자리 90만 공간이 열거 오라클이 됐다** — `list`를 막아도 `get`으로 훑으면 모든 그룹 id를 얻는다. 엔트로피 상향을 '화면이 24pt로 표시해서' 미뤄 뒀는데 그 판단의 전제를 이 PR이 바꿨으므로 여기서 128비트(`Random.secure`, base64url 22자)로 올리고 표시 스타일도 함께 맞췄다. 그 외 요청 문서의 필드 하한·타입 검사(`hasOnly`만으로는 빠뜨린 필드가 매퍼 폴백으로 그룹 문서에 굳는다), 선행 정리 실패 시 토큰 복원, 낡은 규칙 주석 정정, 검증 케이스 8건 추가(총 67건). | share(다음 단계 UI가 이 구현을 소비), 그 외 페이지 영향 없음 |
| v3.1 | 2026-08-21 | **참여 요청 UI + 초대 링크 origin 분리 (⚠️ breaking).** `Group.inviteHost`·`Group.inviteUrl`이 **사라졌다** — 소비자는 `inviteOriginProvider`를 watch해 `inviteUrlFrom(origin:, inviteToken:)`으로 조립한다. 제거 이유: 그 호스트가 prod 하나로 박혀 있어 **에뮬레이터·dev에서 띄운 앱이 실서비스 도메인 링크를 발급**했다(받은 사람이 누르면 남의 실서비스 그룹으로 간다). 모델은 순수해서 백엔드를 알 수 없으므로 조립을 provider로 옮겼다. (1) 화면이 `joinGroup` 대신 **`requestToJoin`**을 부른다 — v2.9에서 계약을, v3.0에서 Firestore·규칙을 깔아 둔 승인제를 이제 UI가 실제로 쓴다. (2) **승인 전 요청자에게 그룹 식별 정보를 일절 노출하지 않는다**(이름·이모지·멤버 수·`groupId`) — 링크는 유출될 수 있고, `groupId`로 그룹을 되조회해 이름을 붙이면 `JoinRequest`가 표시 정보를 안 담는 계약을 **화면이 우회**하는 셈이 된다. (3) 방장 승인 목록은 `iAmOwner` 게이팅 + 로딩·에러를 빈 목록으로 접지 않는다(이 스트림이 요청 도착을 알리는 유일한 신호라 "못 불러왔다"가 "요청 없음"으로 보이면 대기자를 지나친다). (4) 호스팅이 **`build/web`**(Flutter 웹 빌드)을 서빙하도록 바꾸고 `assetlinks.json`을 `web/.well-known/`으로 옮겼다 — 링크를 열면 정적 안내 페이지가 아니라 앱이 뜬다. **[에이전트 리뷰 반영]** 🟠 매니페스트에 dev host만 추가하고 그 도메인을 배포하지 않으면 **Android 11 이하에서 prod 링크까지 미검증**이 된다(필터 안 모든 host가 검증돼야 한다 — minSdk 24). 🟠 `_PendingRow`에 key가 없어 목록이 줄면 State가 재사용돼 **남은 요청의 버튼이 영구히 잠겼다**(실측 재현 후 `ValueKey(r.id)` + 회귀 테스트). 🟠 웹에서 `Uri.base.origin`을 쓰던 근거가 이 저장소에서 거짓이었다 — 웹 빌드가 어디에도 배포되지 않아 링크가 항상 `localhost:<포트>`였다(그래서 (4)를 함께 했다). 🟠 빈 안내 문구를 바꾸면서 그 문구를 감시하던 **회귀 가드 2건이 죽었다**(뮤테이션으로 증명 — 게이트를 통째로 지워도 28/28 통과). 그 외 요청자 카드의 에러 삼킴, SSOT 가드 미등록(우회 실증 후 등록·재확인), 문서 정합. 테스트 **466**. | share(생산·소비), 그 외 페이지 영향 없음 |
| v3.2 | 2026-08-23 | **알림 provider 승격 + 홈 벨 진입점 (non-breaking, 이동 + 순수 추가).** 홈 헤더의 알림 벨이 **장식**이었다 — `IconButton`이 아니라 `Icon`이라 탭이 감지되지 않았고, 빨간 점은 provider가 아니라 하드코딩이라 안읽음이 0이어도 켜져 있었다. #55에서 공유 탭·마이페이지 벨만 실연동으로 고치면서 홈이 빠진 것이다(그 파일의 dartdoc이 "예전에는 장식이었다"고 적고 있는데, 홈은 여전히 그 '예전'이었다). (1) `notificationsProvider`·`notificationsReadAtProvider`·`unreadNotificationCountProvider`를 `lib/features/share/state/share_providers.dart` → **`lib/shared/providers/group_notifications_provider.dart`** 정본으로 승격. 벨이 세 화면으로 늘어 **세 번째 소비자**가 생긴 시점이라 규칙 ③(늦게 승격)을 충족한다. private 원천 스트림 2개도 함께 옮겼다 — 파생이 그것을 watch하므로 쪼갤 수 없다. (2) 승격이 재시도 훅을 끌고 갔다: `retryNotifications`는 옮긴 private 원천을 invalidate하므로 정본 파일로 동행했고(계약 정본 `retryMyGroups`·`retryFailedSharedGifticonStreams`와 같은 배치), 그것이 부르는 `_retrySessionIfFailed`는 **`retrySessionIfFailed`로 공개해 `session_provider.dart`(세션 정본)로 승격**했다 — 사본을 두면 세션 재시도 규칙이 두 벌이 된다. share의 나머지 재시도 3곳도 같은 정본을 부른다(동작 불변). (3) **`NotificationBell` 공유 위젯 신설**(`lib/shared/widgets/notification_bell.dart`) — 공유 탭 헤더의 뱃지 벨과 홈 벨이 각자 그려지면 임계값·`9+` 표기·색이 갈라진다. 안읽음 수는 위젯이 정본을 직접 구독하고, **목적지는 `onPressed`로 주입받는다**(알림 화면은 `lib/features/share`에 있어 여기서 import하면 계약이 페이지를 향해 거꾸로 의존한다). 공유 탭은 이 위젯으로 교체하며 `_ShareHeader`의 `unreadCount` 파라미터와 페이지의 카운트 watch가 사라졌다. 마이페이지의 **초록 점** 벨은 그대로 뒀다 — 표기가 다른 것은 기존 디자인이라 이번 범위 밖. (4) `tool/check_ssot.sh` 보강 — `SSOT_PROVIDERS`에 승격한 provider 3개, `SSOT_FUNCTIONS`에 `retryNotifications`·`retrySessionIfFailed` 추가(페이지가 같은 이름으로 재선언하면 CI `SSOT guard` 실패). (5) 신규 테스트 `test/features/main/notification_bell_test.dart`(4) — 벨 탭 → `GroupNotificationsPage` 진입, 안읽음 0이면 뱃지 자체가 없음(장식 시절의 상시 점을 잡는 회귀), 수가 그대로 보임, 두 자리는 `9+`. 전체 **470** 통과. | main(홈 벨 진입점 신설), share(같은 위젯 소비 — 화면 동작 불변), mypage(import 경로만 변경) |
| v3.3 | 2026-08-23 | **개인 만료 알림을 알림 센터에 통합 (non-breaking, 추가 + 이동).** 알림 목록이 그룹 알림만 담고 있어, 만료 임박 푸시를 받고 벨을 누른 사용자가 "알림이 없어요."를 봤다. (1) **저장이 아니라 파생을 골랐다** — 울린 사실을 남기려면 기기가 꺼져 있을 때도 쓸 서버가 필요한데(참여 요청 알림을 포기한 v2.9와 같은 제약), 발송 격자(`expiryNotifyLeadDays` × `expiryNotifyHour`)가 정책 상수라 **언제 울렸는지가 결정론적으로 계산된다**. `firedExpiryNotifications`를 `planExpiryNotifications` **바로 옆에** 두어 제목·본문 헬퍼를 공유한다 — 문구가 갈리면 푸시와 목록이 다른 말을 한다. 두 함수는 `isAfter(now)` 하나를 기준으로 정확히 여집합이라, 한 발송 시점이 양쪽에 들거나(중복) 어느 쪽에도 안 드는(유실) 일이 없다(테스트로 고정). (2) `AppNotification` sealed 신설 — `GroupNotification`에 nullable `groupId`를 뚫는 대신 타입을 나눴다. 모델 이름이 거짓이 되지 않고, 종류가 늘면 UI `switch`가 컴파일 에러를 낸다(`AppDestination`과 같은 근거 — 알림은 처리를 빠뜨려도 "그 줄만 조용히 안 보이는" 형태로 실패해 눈으로 못 잡는다). (3) **읽음 저장소를 새로 두지 않았다** — 파생 항목의 `createdAt`이 결정론적이라 기존 `notificationsReadAtProvider` 타임스탬프 하나로 두 출처가 함께 갈린다. (4) `rawGifticonsProvider` 승격 — 파생 계산이 `lib/shared`에 살아야 하는데 원천 목록 선언이 `lib/features/main`에 있었다(계약 → 페이지 역의존 금지). 앱 조립부의 알림 동기화가 이미 페이지 밖에서 이것을 쓰고 있었으므로 소비자 기준으로도 승격 시점이 지났다. 공개 이름은 불변(v2.5와 같은 판단). ⚠️ share의 `shareableGifticonsProvider`는 **합치지 않았다** — `foldSessionUser` 규약으로 세션 순단에 로딩/에러를 보존하는데 이쪽은 uid가 없으면 빈 목록을 방출한다. 합치면 세션이 잠깐 끊긴 것만으로 공유 시트에 "후보 없음"이 뜬다(share QA [medium 1]). 같은 사용자에 `watchGifticons` 구독이 둘인 상태는 남으며, 폴딩 규약 통일이 선행돼야 하는 별도 작업이다. (5) 개인 항목 탭 → **목적지 버스**(`GifticonHighlightDestination`) 재사용 — 딥링크·푸시와 같은 통로다. (6) 화면·이름 정리: `GroupNotificationsPage` → **`NotificationCenterPage`**(그룹 전용이 아니게 됐다), 타이틀·벨 tooltip을 '알림'으로 통일. (7) `check_ssot.sh`에 새 타입 3·provider 2·함수 1 등록. 신규 테스트 **14건**(복원 경계·예약과의 여집합·보관 기간·병합 정렬·안읽음 합산·에러 전파·탭 목적지), 전체 **484** 통과. **한계:** 파생 항목은 개별 삭제·읽음 표시가 불가능하고(계산식의 출력이라 지울 대상이 없다), 기프티콘을 지우면 그 지난 알림도 함께 사라진다 — 개별 관리가 필요해지면 저장 방식으로 올린다. | main(원천 목록 정본 소비 — 호출 무수정), share(알림 화면 개편), mypage(진입 라벨), 앱 조립부(import 경로) |
| v3.4 | 2026-08-23 | **알림 센터 자체 리뷰 반영 — 시계 정본화 + 부분 실패 허용 (non-breaking).** v3.3 직후 `/code-review`가 3건을 잡았고 그중 하나가 기능의 목적을 무효화하고 있었다. (1) 🔴 `allNotificationsProvider`가 **캐시되는 `Provider` 본문에서 `DateTime.now()`를 직접 읽었다.** 시간은 watch 대상이 아니라 파생 목록이 **최초 계산 시점에 얼어붙는다** — 8시에 앱을 열어 두면 9시에 울린 알림이 목록에 없다(firedAt > now라 예약 쪽으로 분류). 푸시를 받고 벨을 눌렀는데 비어 있는, v3.3이 고치려던 바로 그 증상이다. `nowProvider`를 `lib/features/main/state` → **`lib/shared/providers`로 승격**하고 `ref.watch`로 바꿨다. 승격이 필요했던 이유는 두 겹이다 — 파생 계산이 계약 계층에 사는데 시계가 페이지에 있으면 역의존이고, 시계를 따로 읽으면 그 파일이 **이미 기록해 둔 "서로 다른 오늘" 사고**(자정 넘긴 뒤 배너와 목록이 어긋남)가 홈 배너 vs 알림 센터 사이에서 재발한다. ⚠️ 값의 신선도 자체(앱을 켜 둔 채 자정을 넘김)는 그 파일이 별도 작업으로 분리해 둔 항목이라 여전히 미해결 — **⚠️ 이 문장은 틀렸다 — v3.5에서 정정.** `nowProvider`는 의존성이 없어 원천 목록이 재방출돼도 재계산되지 않으므로, 이 시점에는 스테일이 전혀 해소되지 않았다. (2) 🟠 그룹 알림 축의 에러가 `whenData`로 목록 전체에 전파돼 **순수 계산이라 실패할 수 없는 개인 만료 알림까지 지웠다** — 오프라인이면 배너만 뜨고 로컬 알림이 한 건도 안 보인다. `AsyncError.copyWithPrevious(AsyncData(merged))`로 바꿔 **배너는 유지하되 파생 항목은 값 자리에 싣는다**. 읽음 가드가 `AsyncData`만 "봤다"로 인정하므로 못 본 그룹 알림이 읽음 처리되는 일도 없다(첫 로딩은 값 없이 전파 — 파생 항목을 먼저 보여주면 가드가 열려 아직 도착 안 한 그룹 알림이 유실된다). (3) 🟠 개인 항목 탭이 `pop()`을 **한 번만** 불러, 마이페이지를 경유해 들어온 경우 그 화면이 남아 강조된 홈을 가렸다(강조는 시간이 지나면 거둬지므로 뒤로가기로 홈에 닿을 즈음엔 꺼져 있다) → `popUntil(isFirst)`. **교훈: v3.3의 테스트가 `now`를 전부 주입해 (1)을 구조적으로 못 잡았다** — 통과가 오히려 신호를 가렸다. 시계를 override로 앞당겨 목록이 재계산되는지 보는 테스트를 추가했다(옛 구현에서 실패함을 확인). 테스트 3건 추가(총 **487**), `check_ssot.sh`에 `nowProvider` 등록. | main(시계 정본 소비 — 호출 무수정), share(알림 화면), 그 외 영향 없음 |
| v3.5 | 2026-08-23 | **시계 신선도 — 복귀 시 갱신(앱 조립부 소유) + v3.4의 틀린 서술 정정.** v3.4 직후 `/code-review`가 잡았다: `DateTime.now()` → `ref.watch(nowProvider)`로 바꾼 것만으로는 **스테일이 하나도 해소되지 않는다.** `nowProvider`는 의존성 없는 비-autoDispose `Provider`라 컨테이너 수명 동안 한 번만 계산되고 저장소 어디에도 `invalidate(nowProvider)`가 없다(50ms 간격 두 번 읽기가 같은 `DateTime`을 주는 것으로 실측). 즉 v3.4가 🔴로 보고한 실패 시나리오(앱을 켜 둔 채 알림이 울리면 목록에 안 뜸)가 **그대로 남아 있었는데, 이력에는 "완화됨"으로 적혀 있었다.** 승격이 얻은 것은 홈 배너와 알림 센터가 같은 "오늘"을 보는 일관성과 테스트 주입 가능성뿐이다. (1) **갱신 주체를 앱 조립부에 뒀다** — `KeepConShell`에 `WidgetsBindingObserver`를 붙여 `AppLifecycleState.resumed`에서 `ref.invalidate(nowProvider)`. 타이머가 필요 없어 `now_provider.dart`가 기록한 실패(자정 `Timer`가 위젯 테스트에 pending timer로 남아 `MainPage` 마운트 테스트가 전부 깨짐)를 피한다. 화면 provider는 순수하게 남는다. 이것이 실제로 아픈 경로를 덮는다 — 백그라운드에 있는 사이 발송된 알림을 보러 돌아오는 경우다. (2) ⚠️ **앱을 포그라운드에 켜 둔 채** 시각을 넘기는 경우는 여전히 남는다(타이머 소유 구조 필요 — 별도 작업). 문서에 미해결로 명시했다. (3) `now_provider.dart`의 기존 문구 "지금은 원천 목록이 바뀔 때 함께 갱신된다"도 같은 이유로 사실이 아니었다 — 그 파일을 계약으로 올리며 틀린 서술까지 옮긴 셈이라 함께 정정했다. **교훈(2회 연속 같은 함정): v3.3 테스트는 `now`를 인자로 주입해, v3.4 테스트는 `nowProvider`를 override로 주입해 결함을 못 잡았다.** 주입은 "provider가 시계를 watch하는가"만 증명하고 "그 시계가 실제로 움직이는가"는 원리상 검증하지 못한다 — 그래서 이번엔 **라이프사이클 이벤트를 실제로 보내** 값이 바뀌는지 보는 테스트를 셸 계층에 뒀다(전이는 `resumed → inactive → hidden → paused`의 실제 순서를 따라야 한다. 건너뛰면 프레임워크가 assertion으로 막는다). 테스트 2건 추가(총 **489**). | 앱 조립부(셸 라이프사이클), main·share(시계가 실제로 갱신됨 — 호출 무수정) |
| v3.6 | 2026-08-23 | **에이전트 리뷰 반영 — 복원 술어 보강 + 파생 축 로딩/에러 대칭.** `keepcon-code-reviewer`가 🟠 2건을 잡았고 둘 다 재현했다. (1) 🟠 **`firedExpiryNotifications`가 등록 이전의 격자점을 "울렸다"고 만들어 냈다.** 예약은 앱이 목록을 동기화하는 시점부터 시작하므로 그때 이미 지나 있던 격자점은 **발송되지 않는다.** 그런데 복원은 과거라는 이유만으로 그것을 항목으로 낸다 — 실측: 8/23 14:00 등록·8/25 만료 → 예약 `[D-1]`, 복원 `[D-3@8/22, D-7@8/18]`. 기프티콘이 없던 날의 유령 알림 2건이고, `readAt`이 null인 신규 사용자에겐 그대로 안읽음 뱃지 숫자가 된다. **만료 임박 기프티콘 스캔이 이 앱의 주 흐름이라 만료 7일 이내에 등록하는 모든 기프티콘이 이 경로를 탄다.** `Gifticon.registeredAt` 하한을 추가했다. ⚠️ v3.3이 적은 "`isAfter(now)` 하나로 정확히 여집합"은 **틀린 주장이었다** — 여집합은 시간 술어에 대해서만 성립하고 "예약됨 ∪ 실제로 울림"과는 다르다. dartdoc을 네 술어(미해결·과거·등록 이후·보관 창)로 다시 썼다. (2) 🟡 **`status != available` 가드가 만료를 못 걸렀다** — `available → expired` 전이를 수행하는 주체가 이 앱에 없어(`expiry_policy.dart` dartdoc) 만료된 기프티콘도 available로 남는다. 실측: 만료 8/22(어제) → "내일 만료되는 기프티콘이 있어요" 포함 3건 복원. 같은 기프티콘을 홈 카드는 `isExpiredByDate`로 **"만료"**로 칠하는데 알림 센터는 "내일 만료"라고 말했다 — `expiry_policy.dart`가 만들어진 이유 그 자체다. 날짜 판정을 함께 본다. **부수 발견: 이 필터가 들어가면 `within`(30일)이 도달 불가가 된다** — 만료 전 기프티콘의 발송 시점은 최대 D-7이라 7일을 못 넘는다. 보관 창은 만료 정책이 완화될 때를 위한 방어선으로만 남으며, 그 관계를 테스트로 못박았다. (3) 🟠 **읽음 가드가 그룹 축의 첫 방출만 기다렸다.** 파생 축 원천(`rawGifticonsProvider`)의 로딩을 빈 목록으로 접어, 그룹 축이 먼저 도착하면 목록이 `AsyncData`가 되고 읽음 가드가 열린다. 그 순간 `readAt`이 벽시계로 찍히는데 뒤늦게 합류하는 파생 항목은 `createdAt`이 과거(오전 9시)라 **영구히 읽음**이 된다 — 뱃지를 살리려던 기능이 뱃지를 지운다. v3.4가 그룹 축에 대해 막아 둔 사고의 **대칭형**인데 한쪽만 막혀 있었다. 파생 축에도 "첫 방출 전에는 값 없이 로딩" 규약을 적용했다. (4) 🟠 같은 자리에서 **원천 에러가 배너 없이 삼켜지던 것**도 고쳤다 — "파생은 로컬 계산이라 네트워크와 무관"은 **계산**에만 맞는 말이고 원천(Firestore 스트림)에는 틀리다. 두 축 중 어느 쪽이 에러여도 배너를 띄운다. (5) 🟡 `check_ssot.sh`가 형제를 안 셌다 — `firedExpiryNotifications`만 넣고 `planExpiryNotifications`와 발송 격자 상수 4개가 빠져 있었다(에이전트가 실제 우회 프로브로 확인). 등록하고 `const List<int>`·`const Duration` 형태도 정규식이 잡는 것을 프로브로 확인했다(에이전트가 미확인으로 남긴 지점). (6) 🟡 **승격한 시계를 우회하는 소비처**를 닫았다 — `_RichGifticonCard`가 `DateTime.now()`를 직접 읽어, 앱을 켜 둔 채 자정을 넘기면 요약은 "만료 임박 0개"인데 카드는 빨간 어긋남이 난다. `ref.watch(nowProvider)`로 전환. 같은 결함이 있던 `GifticonGridCard`는 **사용처 0건인 죽은 코드**라 별도 작업으로 분리했다. (7) 🔵 벨 개수 서술 모순(같은 PR 안에서 "두 곳" vs "세 화면") 정정 + 마이페이지 벨을 통합하지 않은 이유와 `BadgeStyle` 방향을 기록, `qa_report.md`의 옛 경로 7건 정정, 탭 영역 44→48(Material 최소). 테스트 **+6건**(총 **514**). | main(카드 시계 정본화), share(알림 센터), 계약(복원 술어·병합 규약) |
| v3.7 | 2026-08-23 | **두 리뷰어 지적 반영 — 막다른 배너 + 여집합 1틱 + 문서 과잉 주장.** CodeRabbit(actionable 3 + nitpick 2)과 `keepcon-code-reviewer`(🟠1·🟡4)를 함께 반영했다. **두 리뷰어가 독립적으로 같은 🟠을 찾았다:** v3.6이 `rawGifticonsProvider` 에러로도 배너를 띄우게 만들었는데 그 배너의 `onRetry`인 `retryNotifications`는 세션·알림·읽음시각 셋만 되살린다 — 기프티콘 원천이 죽으면 '다시 시도'가 **아무것도 하지 않고**, 그 provider는 autoDispose가 아니라 **앱 재시작 전까지 회복 경로가 없다**(에이전트가 위젯으로 재현: 탭 전후 구독 1→1, 에러 유지). 게다가 읽음 가드가 `AsyncData`만 인정하므로 그룹 알림이 멀쩡해도 뱃지가 영영 안 꺼진다. 원천을 재시도 대상에 넣었다. (2) 🟡 **등록 하한이 예약과 1틱 어긋났다** — 예약은 `!fireAt.isAfter(current)`로 같은 시각을 버리는데 복원은 `isBefore`라 같은 시각을 남겼다. 에이전트가 **15,840조합 브루트포스**로 유령 3건(전부 `09:00:00.000` 정각 등록)·누락 0건을 실측했다. `!isAfter`로 맞췄다. 같은 자리의 "정확히 여집합" 인라인 주석도 v3.6이 술어 둘을 더하며 **의도적으로 거짓이 된 것**이라 정정했다(dartdoc은 이미 인정하고 있었는데 주석만 옛 주장이 남았다). (3) 🟡 `check_ssot.sh`가 예약 모듈의 함수·상수는 등록했는데 **공개 타입 `ScheduledExpiryNotification`만 빠졌다**(우회 프로브로 확인). 등록했다. (4) 🟡 **v3.6이 코드가 지키지 않는 절대 규칙을 계약 문서에 박았다** — "`DateTime.now()` 직접 읽기 금지"라고 적었는데 알림 센터 자신의 `formatRelativeKo`가 실제 시계를 읽어, 시계가 늙으면 "1일 전"이라 적힌 항목 옆에 정작 오늘 울린 알림이 빠지는 어긋남이 난다. 이 저장소가 반복해 경계한 "문서가 게이트인 줄 아는" 실수다. 알림 센터는 정본을 넘기도록 고치고, 문서 문구는 **코드가 지키는 범위**(만료·D-day 파생)로 좁히면서 남은 예외(상대 시각·초대 만료)를 명시했다. (5) 🟡 **v3.6의 카드 시계 전환에 회귀 테스트가 없었다** — 뮤테이션으로 되돌려도 514/514가 통과했다(일곱 고침 중 이것만 살아남았다). `nowProvider`를 고정해 D-day 뱃지를 단언하는 테스트 3건을 붙였고, 뮤테이션이 그중 2건을 죽이는 것을 확인했다. (6) CodeRabbit nitpick 2건 — `id` 주석이 실제 구성(`gifticonId`+`leadDays`)과 달랐던 것, 경계 테스트가 `expirySoonDays` 대신 발송 격자 상수 `expiryNotifyLeadDays.first`를 써야 하는 것. (7) 병합 정렬 테스트가 **실제 시계에 의존해 flaky**했다(09:00 직후 1분 창에서 단언이 뒤집힌다) — 시계를 고정했다. **에이전트가 반증해 준 것:** `AsyncLoading` 조기 반환이 미로그인·재시도·세션 순단을 막지 않음(실행 확인), `within` 도달 불가 판단이 맞음(801케이스), `GifticonGridCard` 죽은 코드 판단이 맞음, 카드 전환에 `const` 소실 없음. ⚠️ **작업 중 사고:** 에이전트의 뮤테이션 원복(`git checkout -- lib/`)이 동시에 편집 중이던 `lib/` 파일 2개를 날렸다. 에이전트가 내용을 보고서에 옮겨 두어 복원했다 — **리뷰 에이전트가 도는 동안 같은 트리를 편집하지 않는다.** 테스트 +3(총 **517**). | share(알림 센터 상대 시각), main(카드 테스트), 계약(재시도 훅·복원 술어·문서 범위) |

## 후속 확장 예정(이번 슬라이스 범위 밖)

- ✅ **승격 완료(v2):** `Group`, `GroupMember`, `SharedGifticon`, `UsageLog`, `ShareStatus`, `GroupNotification`/`GroupNotificationType`, `MemberRole`, ~~`InviteExpiry`~~(v2.8에서 삭제 — 24시간 고정 정책 `Group.inviteValidity`로 대체), `ShareRepository`(+`InMemoryShareRepository`, `shareRepositoryProvider`). → `lib/shared/models/group.dart`·`share.dart`, `lib/shared/repositories/share_repository.dart`. 상세 `02_share_contract_promotion.md`.
  - 그룹 관리 행위(생성/삭제/나가기/소유권이전/초대정책)와 `GroupRepository`로 따로 나눌 필요 없이 **하나의 `ShareRepository`**로 통합했다(그룹과 공유가 강결합 도메인).
- ✅ **리팩터 완료(share-page-dev, v2.2):** `lib/features/share/data/`(로컬 `share_models.dart`·`share_store.dart`·`korean_particle.dart`) **제거 완료** → 페이지가 `lib/shared` 계약을 소비. share 테스트는 `ShareStore` 대상에서 **`InMemoryShareRepository` 대상**으로 전환됨(`test/features/share/share_repository_*_test.dart`), korean_particle 테스트는 `test/shared/util/`로 이동. 매핑은 `02_share_contract_promotion.md` D절.
- ✅ **승격 완료(v2.4):** 날짜 라벨 포맷 — 3곳(main `formatDate` / share `formatExpiryLabel` 계열 / scan 인라인)에 분산됐던 `YYYY.MM.DD` 조립을 `lib/shared/util/date_format.dart`의 `formatYmdDot`으로 통합. 표기 규칙 합의 결과는 **점 구분자 통일**(다수 표기, scan만 `-`였음)이고, D-day 라벨(`formatDDay`)·상대 시각(`formatRelativeKo`)은 입력·의미가 달라 **승격 대상이 아님**(각 페이지 로컬 유지).
- ✅ **승격 완료(v2.5):** "현재 사용자의 그룹 목록 스트림" provider — scan/share에 중복 조립돼 `watchGroups`를 두 번 구독했던 체인을 `lib/shared/providers/my_groups_provider.dart`의 `myGroupsProvider`(**SSOT**, `autoDispose`, `AsyncValue` 노출)로 통합. 페이지 파생 형태는 계획대로 로컬 유지(share = `AsyncValue` 전파, scan = 빈 목록 폴딩). 구독 단일화는 테스트로 고정(`test/shared/providers/my_groups_provider_test.dart`). 상세는 크로스페이지 주의점 #13.
- **다음 승격 후보(경량):** `AsyncValue<List<T>>` 폴딩 확장(예: `orEmpty` — `valueOrNull ?? const []`) — 같은 관용구가 lib 16곳에 반복되고, 단일 폴딩 지점이 없으면 `.value` 변형이 재유입될 수 있다(v2.5 후속 정리에서 main 홈 1곳 재유입 실증). 표준 관용구 대비 프로젝트 고유 어휘 도입이라 순이득은 중간 — 채택 여부는 `contract-architect` 판단.
- ✅ **승격 완료(v2.6):** **세션 스트림(`AuthRepository.watchCurrentUser()`) provider** → `lib/shared/providers/session_provider.dart`의 `sessionUserProvider`(**SSOT**, `autoDispose`, `AsyncValue<User?>` 노출). 정본 신설 + `my_groups_provider.dart` 내부 전환에 이어 **share도 같은 v2.6에서 전환 완료**(당시 `shareCurrentUserProvider` = 자체 구독 없는 pass-through 별칭). ✅ **share 별칭 제거 완료(후속 슬라이스, share-page-dev):** 소비처 **12곳**(화면 4 + 파생 `watch` 5 + `retry*` 내부 `read` 3)을 직수입으로 전수 치환하고 별칭 선언을 삭제 — 경과 조치 종료, share는 **직수입 완료**다. `user?.id`만 읽는 6곳은 `select`로 좁혀 별칭의 `==` 필터 상실을 보정했다(근거·주의는 #13). ✅ **잔여 소비 전환 완료(v2.7):** main(`currentUserProvider`)·mypage 인라인 구독·앱 조립부(`authStateProvider`)까지 전부 선언 삭제 + 정본 직수입 → **`watchCurrentUser()` 구독은 앱 전체에서 정본 1개**(테스트 고정). 이 승격 항목은 이로써 종결. 상세·표는 크로스페이지 주의점 #13.
- ✅ **이행 완료(계약 요청 share → contract-architect, v2.6):** `myGroupsProvider`의 **수동 재시도 훅**.
  요청서가 지적한 대로 **두 계층을 모두** 되살리는 형태로 이행했고(그룹 스트림만으로는 절반),
  기록된 대안(**세션 스트림 승격과 묶어 처리**)을 택해 정본 내부의 두 번째 세션 구독 자체를
  없앴다. 결과 API:
  - `retryMyGroups(WidgetRef ref)` — 화면용(배너 `onRetry`에 직접 연결).
  - `myGroupsRetryProvider` → `MyGroupsRetry.retry()` — provider/테스트용 동일 동작.
  - 되살림 대상 = **에러인 계층만**(세션 `sessionUserProvider` / 그룹 `_groupsByUserProvider`의
    현재 user 인스턴스). 자동 재시도 금지 규약 유지.
  - ✅ **share 배선 완료(같은 v2.6):** `onRetry` 강등이 제거되고 배너 4곳이 훅에 연결됐다
    (`retrySharedItemLookup` 신설 / `retryShareCandidates` 승격 / 훅과 `retrySessionIfFailed`를
    겹쳐 부르지 않는 분담 규약). 상세는 #13.
- ✅ **가드 보강 완료(v2.6):** `tool/check_ssot.sh`의 `SSOT_PROVIDERS`에 `myGroupsProvider`(선행 반영)에 더해 **`sessionUserProvider`·`myGroupsRetryProvider`를 추가**했다 — 페이지가 같은 이름의 provider를 재선언하면 CI `SSOT guard`가 실패한다(임시 프로브로 두 이름·두 선언 형태 모두 실제 검출 확인 후 프로브 삭제).
- **미착수:** 기기 푸시 알림용 `NotificationService`/범용 `NotificationType`(그룹 알림은 `ShareRepository`가 충족), auth/share **세부** 라우트(그룹 상세·초대 등 페이지 내부 내비게이션 — 현재 `AppRoutes.share` 탭 라우트만 존재).
