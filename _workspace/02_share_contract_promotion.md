# 공유(share) 도메인 계약 승격 (Promotion) — v2

> 목적: 프로토타입(`lib/features/share/data/`)에 갇힌 그룹/공유 도메인 모델·스토어를
> `lib/shared/`의 정본(SSOT)으로 승격한다. 이 문서는 **무엇을 무엇으로 바꿨는지**의 기준서다.
>
> 작성일: 2026-07-10 · 상태: **구현 완료** (`lib/shared/` 실제 파일 생성됨) · 계약 버전: v2
>
> ⚠️ **이 문서는 2026-07-10 승격 시점의 스냅샷이다 — 아래 인터페이스 선언은 그때의 계약이고,
> 지금의 계약이 아니다.** 현재 계약의 정본은 `lib/shared/`의 실제 코드이며, 그 이후 변경 이력은
> `_workspace/01_contract_dependency_matrix.md`의 버전 표를 따른다. 이 문서를 현재 계약으로 읽지 마라.
>
> **규모부터 말하면**: 아래 `ShareRepository` 선언은 현재 계약과 대조했을 때 **문서에만 있는 것 1개**
> (`joinGroup`), **현재에만 있는 것 12개**(`requestToJoin`·`approveJoinRequest`·`rejectJoinRequest`·
> `cancelJoinRequest`·`get`/`watchMyJoinRequests`·`get`/`watchPendingJoinRequests`·`removeMember`·
> `regenerateInviteToken`·`markNotificationsRead`·`watchNotificationsReadAt`)다. 즉 **승인제 API 전체가
> 이 문서에 없다.** 아래 목록은 그중 눈에 띄는 몇 개일 뿐이다:
> - `ShareRepository.joinGroup`은 **v3.8에서 삭제됐다.** 참여는 `requestToJoin` → 방장 `approveJoinRequest`
>   승인제로 바뀌었다 — 링크 소지만으로 멤버가 되지 않는다.
> - `InviteExpiry` enum(`oneHour`/`oneDay`/`sevenDays`/`never`)은 **v2.8에서 삭제됐다.** 만료는
>   `Group.inviteValidity` 상수로 **24시간 고정**이다. 특히 `never`(무제한)는 유출된 링크가 영구
>   참여 경로가 되어 **위험해서 지운 값**이다 — 되살리지 마라.
> - `inviteCode`는 `inviteToken`으로 개명됐고(v2.9), 6자리에서 **128비트**로 올라갔다(v3.0).
> - `Group.inviteHost`·`Group.inviteUrl`은 **v3.1에서 제거됐다.** 링크는 `inviteOriginProvider` +
>   `inviteUrlFrom(origin:, inviteToken:)`으로 조립한다.
>
> ⚠️ 제약: 이 승격은 `lib/shared/`만 생성한다. `lib/features/share/`의 기존 코드(로컬 모델·스토어·
> 페이지·테스트)는 **건드리지 않았다.** 그 리팩터(로컬 모델 제거 → 계약 소비)는 후속 단계에서
> share-page-dev가 수행한다. 그때까지 프로토타입과 계약이 잠시 병존한다(의도된 상태).

---

## A. 승격 대상 결정

### A-1. 모델/enum 승격 매핑

| 프로토타입 (로컬) | 정본 (계약) | 위치 | 핵심 변경 |
|------|------|------|------|
| `MemberRole` | `MemberRole` | `lib/shared/models/group.dart` | 그대로(owner/member) |
| `InviteExpiry` | `InviteExpiry` | `group.dart` | 그대로(oneHour/oneDay/sevenDays/never + label) |
| `GroupMember` | `GroupMember` | `group.dart` | `id`→**`userId`**([User.id] 참조), `name`→`displayName`, `emoji`→`avatarEmoji`. 방장/멤버/초대 predicate를 [Group]으로 이동 |
| `Group` | `Group` | `group.dart` | **불변 값 객체화**(final 필드 + copyWith). `isMember`/`isOwnedBy`/`canInvite`/`memberById` 순수 predicate 추가(스토어 로직 흡수) |
| `ShareStatus` | `ShareStatus` | `lib/shared/models/share.dart` | 그대로(available/inUse/used + label) + **`ShareStatusTransition` 전이 SSOT 신설** |
| `SharedGifticon` | `SharedGifticon` | `share.dart` | **`gifticonId` 신설**(원본 [Gifticon.id] 참조). `sharedByName`→`sharedByUserId`, `lockedByName`→`lockedByUserId`, `reservedByName`→`reservedByUserId`(모두 [User.id]). `product`→`productName`. `expiryLabel`(String)→`expiryDate`(DateTime). `barcode` 하드코딩 기본값 제거→nullable |
| `UsageLog` | `UsageLog` | `share.dart` | `who`(이름)→`userId`([User.id]). `groupName`(String)→`groupId`([Group.id]). `what`(합친 문자열)→`brand`+`productName`. `when`(라벨)→`usedAt`(DateTime). `id`·`sharedGifticonId` 신설 |
| `GroupNotificationType` | `GroupNotificationType` | `share.dart` | 그대로(registered/expiringSoon/used + label) |
| `GroupNotification` | `GroupNotification` | `share.dart` | `groupId` 신설(소속 그룹 귀속). `when`(라벨)→`createdAt`(DateTime). `id` 신설 |
| `MyGifticon` | **폐기** | — | 계약에 만들지 않음. 공유 후보 목록은 `GifticonRepository.watchGifticons(currentUser.id)`를 필터해 [Gifticon]으로 직접 소비 |
| `ShareStore` (인메모리 상태+가드) | `ShareRepository` + `InMemoryShareRepository` | `lib/shared/repositories/` | 아래 A-2 |

### A-2. 개선 근거 (프로토타입 정리·제거)

- **이름 문자열 → `User.id` 참조.** 프로토타입은 `sharedByName == myName` 같은 **이름 문자열 비교**로
  권한을 판정했다(동명이인·개명에 취약). 계약은 `sharedByUserId == currentUser.id`로 대체한다.
- **`GroupMember.id` 하드코딩('me') → 세션 기반.** `AuthRepository.currentUser.id`가 행위자 식별의
  단일 기준. `InMemoryShareRepository`가 `AuthRepository`를 주입받아 해석한다.
- **`MyGifticon` 폐기.** 원본 [Gifticon]을 그대로 소비한다. 공유 시 `shareGifticon(gifticon: ...)`에
  원본 [Gifticon]을 넘기면 표시 필드를 스냅샷으로 담고 `gifticonId`로 원본을 연결한다.
- **`SharedGifticon`이 원본 [Gifticon.id] 참조(`gifticonId`).** 사용 완료 시 이 참조로 원본을
  `GifticonStatus.used`로 동기화한다(share ↔ main 경계의 핵심).
- **표시 라벨 문자열 → 실제 타입.** `expiryLabel`/`when`을 `DateTime`으로 승격. 상대 시각("방금",
  "2일 전") 포맷은 소비자(UI) 책임(정렬/필터를 소비자가 갖는 기존 규약과 일관).
- **가드 반환값 통일: `bool` → `StateError`.** 프로토타입 스토어는 UI-facing이라 가드 위반에 `bool`을
  반환했다. 데이터 계약에서는 `GifticonRepository.updateStatus`와 동일하게 **위반 시 [StateError]**.
  UI 게이팅(버튼 노출)은 예외가 아니라 모델 predicate로 판정한다(방어선 이중화).

### A-3. `SharedGifticon` 표시 필드를 스냅샷으로 두는 이유

다른 그룹 멤버는 공유자의 **개인** 기프티콘 목록을 조회할 수 없다(`watchGifticons(ownerId)`는
소유자별 경계). 따라서 브랜드/상품명/만료일/바코드를 공유 시점에 **스냅샷**으로 담고, 원본과의
연결은 `gifticonId`로만 유지한다. 이는 흔한 denormalized read-model 패턴이며, 원본 상태 동기화는
`gifticonId`를 통해 공유자 앱에서 수행된다.

---

## B. `ShareRepository` 인터페이스 (최종 시그니처)

위치: `lib/shared/repositories/share_repository.dart` (abstract) ·
구현: `lib/shared/repositories/impl/in_memory_share_repository.dart`

```dart
abstract class ShareRepository {
  // 그룹 조회
  Stream<List<Group>> watchGroups(String userId);
  Future<List<Group>> getGroups(String userId);
  Future<Group?> getGroupById(String groupId);

  // 그룹 관리 (행위자 = AuthRepository.currentUser)
  Future<Group> createGroup({required String name, required String emoji});
  Future<Group> joinGroup(String inviteCode);
  Future<void> leaveGroup(String groupId);
  Future<void> deleteGroup(String groupId);
  Future<Group> transferOwnershipAndLeave({required String groupId, required String newOwnerUserId});
  Future<Group> setInviteOwnerOnly({required String groupId, required bool ownerOnly});

  // 공유 기프티콘
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId);
  Future<List<SharedGifticon>> getSharedGifticons(String groupId);
  Future<SharedGifticon> shareGifticon({required String groupId, required Gifticon gifticon});
  Future<SharedGifticon> toggleReservation(String sharedGifticonId);
  Future<SharedGifticon> markUsed(String sharedGifticonId);
  Future<void> cancelShare(String sharedGifticonId);

  // 사용 이력 / 알림
  Stream<List<UsageLog>> watchUsageLogs(String userId);
  Future<List<UsageLog>> getUsageLogs(String userId);
  Stream<List<GroupNotification>> watchNotifications(String userId);
  Future<List<GroupNotification>> getNotifications(String userId);
}
```

### B-1. 가드 규약 (구현이 강제 — [StateError]) — 프로토타입 스토어 동작 보존

| 메서드 | 가드 | 프로토타입 대응(보존) |
|------|------|------|
| `createGroup`/`joinGroup` | 세션에 현재 사용자 없으면 [StateError] | 행위자=me |
| `leaveGroup` | 멤버여야 함. 방장+다른 멤버 있으면 불가(이전 선행) | `ShareStore.leaveGroup` |
| `deleteGroup` | 방장 본인만 | `ShareStore.deleteGroup` |
| `transferOwnershipAndLeave` | 방장만, 신임 방장은 나 아닌 기존 멤버 | `ShareStore.transferOwnershipAndLeave` |
| `setInviteOwnerOnly` | 방장 본인만 | `ShareStore.setInviteOwnerOnly` |
| `toggleReservation` | 다른 멤버가 이미 찜하면 불가 | `ShareStore.toggleReservation` |
| `markUsed` | `available`에서만(사용중/완료 불가) | `ShareStore.markUsed` |
| `cancelShare` | 공유자 본인 + `available`만 | `ShareStore.cancelShare` |

> `test/features/share/*`의 가드 계약(cancel/group_guard/invite_guard)에 인코딩된 **동작**이
> 위 표로 그대로 보존된다. (기존 테스트는 로컬 스토어를 대상으로 계속 통과 — 승격이 깨지 않음.)

### B-2. UI 게이팅용 순수 predicate (모델 소비)

버튼 노출/비활성은 예외 try/catch가 아니라 이미 watch 중인 모델에서 판정한다:
- `Group.isOwnedBy(userId)` · `Group.canInvite(userId)` · `Group.isMember(userId)` · `Group.memberById(userId)`
- `SharedGifticon.isLockedFor(userId)` · `SharedGifticon.isReservedByOther(userId)` · `SharedGifticon.isUsed`

---

## C. 의존성 / 경계면

### C-1. share ↔ auth (행위자·멤버 식별)
- `InMemoryShareRepository`가 `AuthRepository`를 주입받아 `currentUser`로 행위자를 해석한다.
- 멤버는 `GroupMember.userId == currentUser.id`로 식별. `myId='me'` 하드코딩 제거.
- `shareRepositoryProvider`가 `authRepositoryProvider`를 `watch`하므로 조립부에서 auth를
  override하면 자동으로 같은 세션을 공유한다.

### C-2. share ↔ main (사용 동기화 — 원본 상태 전이)
- `markUsed`가 원본 [Gifticon]을 `available → used`로 동기화한다.
- **기존 계약 `GifticonRepository.updateStatus(id, GifticonStatus.used)`를 소비**한다(계약 무변경).
- `GifticonStatus`에 'shared' 상태를 **추가하지 않는다**(기존 전이표·main 스위치 보호). 공유 사실은
  share 도메인에서만 추적하고, 원본 상태는 **실제 사용될 때만** 전이한다.
- 안전장치: 원본이 조회되지 않거나(시드의 가짜 `gifticonId`) 이미 used/expired여서 전이가 불허되면
  동기화를 조용히 건너뛴다(사용 완료 자체는 유효).
- `shareGifticon`/`cancelShare`는 원본 상태를 바꾸지 않는다(공유/회수는 available 유지).

### C-3. provider 배선 (SSOT)
- `shareRepositoryProvider` = `lib/shared/providers/repositories.dart`의 **유일 정본**.
  `authRepositoryProvider` + `gifticonRepositoryProvider`를 `watch`해 **같은 인스턴스**를 주입받는다.
- 인스턴스가 갈라지면 공유 사용 동기화가 main에 반영되지 않으므로, share 페이지는 provider를
  재선언하지 말고 import 해서 소비한다.

---

## D. share-page-dev 리팩터 매핑 (무엇을 무엇으로 교체하나)

| 기존 (features/share) | 교체 후 (계약 소비) |
|------|------|
| `import '.../data/share_models.dart'` | `import 'package:keepcon/shared/models/group.dart';` + `.../models/share.dart` |
| `ShareStore.instance` (싱글턴) | `ref.watch(shareRepositoryProvider)` |
| `ListenableBuilder`(ChangeNotifier) | `ref.watch` + `StreamProvider`/`ref.watch(...watchGroups(uid))` 등 |
| `ShareStore.myId`/`myName`/`myEmoji` | `ref.watch(authRepositoryProvider).currentUser` |
| `store.groups` | `watchGroups(currentUser.id)` |
| `store.sharedOf(gid)` | `watchSharedGifticons(gid)` |
| `store.usageLogs` / `store.notifications` | `watchUsageLogs(uid)` / `watchNotifications(uid)` |
| `store.myGifticons` (`MyGifticon`) | `gifticonRepository.watchGifticons(uid)` 필터([Gifticon]) |
| `store.createGroup(...)` 등 (bool 반환) | `await shareRepository.createGroup(...)` (StateError 가드) |
| `store.isOwner(gid)` | `group.isOwnedBy(uid)` (모델 predicate) |
| `store.canInvite(gid)` | `group.canInvite(uid)` |
| `store.isLockedForMe(item)` | `item.isLockedFor(uid)` |
| `SharedGifticon.expiryLabel` | `SharedGifticon.expiryDate` (UI에서 포맷) |
| `korean_particle.dart` (features/share) | **승격 완료** → `lib/shared/util/korean_particle.dart` (`josa()`/`KoreanJosa.eulReul` 등). 어느 페이지든 import 소비 |

**주의(동작 차이):** 가드 위반이 `false` 반환이 아니라 [StateError]로 바뀐다. UI는 (1) 모델 predicate로
버튼을 미리 게이팅하고, (2) 방어적으로 호출부에서 [StateError]를 catch해 스낵바로 안내하는 이중 처리를
권장한다.

---

## E. 남은 breaking 지점

**계약 레벨 breaking: 없음.** 기존 계약(`Gifticon`/`User`/`GifticonRepository`/`AuthRepository`/
`GifticonStatus`) 시그니처는 **한 줄도 바꾸지 않았다.** 이번 승격은 순수 **추가**다(신규 모델 2파일 +
신규 repository 2파일 + 신규 provider 1개).

**후속 단계의 예정된 변경(share-page-dev 담당, 이번 범위 밖):**
- `lib/features/share/data/share_models.dart`·`share_store.dart` **제거** 후 계약 소비로 교체.
- 그때 `test/features/share/*`가 계약(`InMemoryShareRepository`) 대상 테스트로 재작성될 수 있다
  (동작 계약은 B-1 표로 보존되므로 로직 변경은 아님).
- ✅ `korean_particle.dart` **승격 완료** → `lib/shared/util/korean_particle.dart`(share-page-dev,
  코드·테스트 완료, features 3곳이 소비 중). `in_memory_share_repository.dart`의 로컬 `_eulReul`
  헬퍼도 공유 `KoreanJosa.eulReul`로 대체(중복 제거).

**미포함(의도적 범위 축소):**
- 기기 푸시 알림용 `NotificationService`/범용 `NotificationType`은 만들지 않았다. 그룹 알림은
  `ShareRepository.watch/getNotifications` + `GroupNotification`/`GroupNotificationType`로 충족.
  (매트릭스 "후속 확장 예정"에서 이 항목은 별도 슬라이스로 남긴다.)
