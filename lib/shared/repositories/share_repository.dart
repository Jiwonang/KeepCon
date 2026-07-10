/// KeepCon 공유 계약 — ShareRepository 인터페이스.
///
/// share 페이지의 그룹/공유 도메인 데이터 계층 계약. 프로토타입의 `ShareStore`
/// (`lib/features/share/data/share_store.dart`) 동작을 정본 인터페이스로 승격한 것이다.
///
/// ## 설계 규약 (GifticonRepository 스타일 준수)
/// - **행위자(actor) = 현재 로그인 사용자.** 변경 메서드(create/leave/delete/share/markUsed 등)는
///   `AuthRepository.currentUser`가 행위자다. 구현체가 세션에서 행위자를 해석한다
///   (이 인터페이스는 행위자 id를 파라미터로 받지 않는다 — 조회 메서드만 [userId]를 받는다).
/// - **가드 위반은 [StateError].** 권한/상태/전이 위반은 [StateError]를 던진다
///   (GifticonRepository.updateStatus가 불허 전이에 [StateError]를 던지는 것과 동일 규약).
///   프로토타입 `ShareStore`는 `bool`을 반환했지만, 데이터 계약에서는 예외로 통일한다.
/// - **UI 게이팅은 모델 predicate로.** 버튼 노출 여부는 예외 try/catch가 아니라
///   [Group.isOwnedBy]/[Group.canInvite]/[SharedGifticon.isLockedFor] 등 순수 predicate로
///   판정한다(구현의 [StateError]는 방어선(defense-in-depth)이다).
/// - **정렬/필터 없음.** Repository는 소유자/그룹별 원천 목록/스트림만 제공한다
///   (정렬/필터/포맷은 소비자 책임 — GifticonRepository와 동일).
///
/// ## 경계면(다른 페이지와의 연결)
/// - **share ↔ auth:** 행위자와 멤버 식별은 [User.id] 기반. 구현체는 `AuthRepository`를 주입받는다.
/// - **share ↔ main:** [markUsed] 시 원본 [Gifticon]을 `GifticonStatus.used`로 동기화한다.
///   구현체는 기존 `GifticonRepository.updateStatus`를 **소비**한다(계약 무변경).
library;

import '../models/gifticon.dart';
import '../models/group.dart';
import '../models/share.dart';

/// 그룹/공유 데이터 계약.
///
/// 페이지는 이 abstract 인터페이스에만 의존한다. 구현체(mock/실제 백엔드)는 교체 가능.
abstract class ShareRepository {
  // ── 그룹 조회 ───────────────────────────────────────────────────────
  /// [userId]가 멤버로 속한 그룹 목록을 반응형으로 관찰한다.
  ///
  /// 멤버십이 사라지면(나가기/소유권 이전) 해당 그룹은 이 스트림에서 빠진다.
  Stream<List<Group>> watchGroups(String userId);

  /// [userId]가 멤버로 속한 그룹 목록을 1회성으로 조회한다.
  Future<List<Group>> getGroups(String userId);

  /// id로 그룹 단건 조회. 없으면 `null`.
  Future<Group?> getGroupById(String groupId);

  // ── 그룹 관리 (행위자 = currentUser) ─────────────────────────────────
  /// 새 그룹을 생성한다. 행위자가 방장([MemberRole.owner])이 된다.
  ///
  /// 세션에 현재 사용자가 없으면 [StateError].
  Future<Group> createGroup({required String name, required String emoji});

  /// 초대코드로 그룹에 참여한다. 행위자가 멤버([MemberRole.member])로 합류한다.
  Future<Group> joinGroup(String inviteCode);

  /// 그룹에서 나간다.
  ///
  /// 가드: 행위자가 멤버여야 한다. 방장이면서 다른 멤버가 남아 있으면
  /// [transferOwnershipAndLeave]가 선행되어야 하므로 나갈 수 없다([StateError]).
  /// 단독 멤버(방장 포함)일 때 나가면 그룹이 정리된다.
  Future<void> leaveGroup(String groupId);

  /// 그룹을 삭제한다.
  ///
  /// 가드: 방장 본인만 삭제할 수 있다. 위반 시 [StateError].
  Future<void> deleteGroup(String groupId);

  /// 소유권을 [newOwnerUserId]에게 넘기고 행위자는 그룹에서 빠진다.
  ///
  /// 가드: 행위자가 방장이어야 하고, [newOwnerUserId]는 행위자를 제외한 기존 멤버여야 한다.
  /// 위반 시 [StateError]. 성공 시 갱신된(새 방장 반영·행위자 제거) 그룹을 반환한다.
  Future<Group> transferOwnershipAndLeave({
    required String groupId,
    required String newOwnerUserId,
  });

  /// 초대 권한 정책(방장 한정 여부)을 설정한다.
  ///
  /// 가드: 방장 본인만 정책을 바꿀 수 있다. 위반 시 [StateError].
  /// 성공 시 갱신된 그룹을 반환한다.
  Future<Group> setInviteOwnerOnly({
    required String groupId,
    required bool ownerOnly,
  });

  // ── 공유 기프티콘 ────────────────────────────────────────────────────
  /// 특정 그룹의 공유 기프티콘 목록을 반응형으로 관찰한다.
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId);

  /// 특정 그룹의 공유 기프티콘 목록을 1회성으로 조회한다.
  Future<List<SharedGifticon>> getSharedGifticons(String groupId);

  /// 원본 [Gifticon]을 그룹에 공유한다. 행위자가 공유자가 된다.
  ///
  /// [SharedGifticon.gifticonId]에 [gifticon]의 id를, 표시 필드를 스냅샷으로 담고,
  /// [ShareStatus.available] 상태로 등록한다. 그룹에 '등록' 알림을 남긴다.
  ///
  /// 공유 자체는 원본 [Gifticon]의 상태를 바꾸지 않는다(원본은 사용되기 전까지 available).
  ///
  /// **불변식: 한 기프티콘은 최대 1회만 공유될 수 있다.** 같은 [Gifticon.id]가 행위자가 속한
  /// 어느 그룹에든 이미 공유돼 있으면 [StateError]를 던진다(이중 사용·[UsageLog] 다중 발생 방지).
  /// [cancelShare]로 회수하면 다시 공유할 수 있고, 사용 완료([markUsed])된 기프티콘은 재공유되지 않는다.
  ///
  /// 그룹 없음/비멤버여도 [StateError].
  Future<SharedGifticon> shareGifticon({
    required String groupId,
    required Gifticon gifticon,
  });

  /// 찜(사용 예정) 토글 — 행위자가 찜/찜 해제한다.
  ///
  /// 다른 멤버가 이미 찜한 항목은 덮어쓸 수 없다([StateError]). 항목 없음도 [StateError].
  /// 성공 시 갱신된 항목을 반환한다.
  Future<SharedGifticon> toggleReservation(String sharedGifticonId);

  /// 사용 완료 처리 — [ShareStatus.available] → [ShareStatus.used]로 전이한다.
  ///
  /// 가드: 항목이 [ShareStatus.available]이어야 한다(사용중/사용완료면 [StateError]).
  /// 부수효과: 잠금/찜 해제, 사용 이력([UsageLog]) 추가, 그룹 '사용 완료' 알림 추가,
  /// 그리고 **원본 [Gifticon]을 `GifticonStatus.used`로 동기화**(GifticonRepository.updateStatus).
  /// 원본이 조회되지 않거나(데모 시드) 이미 사용/만료면 동기화는 건너뛴다.
  /// 성공 시 갱신된 항목을 반환한다.
  Future<SharedGifticon> markUsed(String sharedGifticonId);

  /// 공유 취소(회수) — 공유자 본인이, 사용 가능한 항목만 회수한다.
  ///
  /// 가드: 행위자가 공유자([SharedGifticon.sharedByUserId])여야 하고, 항목이
  /// [ShareStatus.available]이어야 한다. 위반/항목 없음이면 [StateError].
  Future<void> cancelShare(String sharedGifticonId);

  // ── 사용 이력 / 알림 ─────────────────────────────────────────────────
  /// [userId]가 속한 그룹들의 사용 이력을 반응형으로 관찰한다(최신순).
  Stream<List<UsageLog>> watchUsageLogs(String userId);

  /// [userId]가 속한 그룹들의 사용 이력을 1회성으로 조회한다(최신순).
  Future<List<UsageLog>> getUsageLogs(String userId);

  /// [userId]가 속한 그룹들의 알림을 반응형으로 관찰한다(최신순).
  Stream<List<GroupNotification>> watchNotifications(String userId);

  /// [userId]가 속한 그룹들의 알림을 1회성으로 조회한다(최신순).
  Future<List<GroupNotification>> getNotifications(String userId);
}
