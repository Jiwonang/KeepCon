/// KeepCon 공유 계약 — GifticonRepository 인터페이스.
///
/// scan(생산) → main(소비) 축의 데이터 계층 계약.
///
/// 정렬/필터 책임 분담 (SSOT):
/// - Repository는 **정렬/필터하지 않은** 소유자별 원천 목록/스트림만 제공한다.
/// - 정렬([SortOption])·필터([FilterOption]) 적용은 **소비자(main)** 의 상태 계층에서 수행한다.
///   이렇게 두는 이유: 정렬/필터 조합이 UI 상태이고, mock/실백엔드 교체 시 쿼리 언어 차이에
///   영향받지 않게 하기 위함.
library;

import '../models/gifticon.dart';

/// 백엔드가 **아직 끝나지 않은 공유**를 보고 [GifticonRepository.deleteGifticon]이나
/// [GifticonRepository.updateDetails]를 거부했다.
///
/// [StateError]를 상속하므로 기존 `on StateError` 소비자도 그대로 받는다(non-breaking).
/// 타입으로 따로 둔 이유는 "없음"과 다음 행동이 다르기 때문이다 — 없는 기프티콘은 상세를
/// 닫아야 하고, 공유 중인 기프티콘은 살아 있으니 그대로 두고 회수를 안내해야 한다. 화면이
/// 목록 스트림의 현재 값으로 사유를 다시 추측하면, 리스너가 늦거나 목록이 에러일 때
/// 살아 있는 것을 "이미 삭제됐다"고 말한다(`InviteExpiredException`과 같은 규약 — 판정은
/// 메시지가 아니라 타입으로).
class GifticonShareBlockedException extends StateError {
  /// [id]는 거부된 기프티콘이다. 진단용으로 [message]에 담는다.
  GifticonShareBlockedException(String id)
      : super('Gifticon has an active share: $id');
}

/// 기프티콘 데이터 계약.
///
/// 페이지는 이 abstract 인터페이스에만 의존한다.
abstract class GifticonRepository {
  /// 신규 기프티콘을 저장한다. (scan 생산 경로)
  ///
  /// [gifticon]의 필수 필드는 계약([Gifticon] 문서 참조)대로 채워져 있어야 한다.
  /// 특히 [Gifticon.ownerId]는 현재 로그인 사용자 id여야 하고,
  /// [Gifticon.status]는 [GifticonStatus.available]이어야 한다.
  ///
  /// 저장 후 확정된(예: id/registeredAt이 Repository에서 발급될 수 있는) 인스턴스를 반환한다.
  Future<Gifticon> addGifticon(Gifticon gifticon);

  /// 특정 소유자의 기프티콘 목록을 반응형으로 관찰한다. (main 소비 경로)
  ///
  /// [ownerId]에 해당하는 [Gifticon] 리스트를 방출하며, 추가/변경 시 새 리스트를 방출한다.
  /// **정렬/필터되지 않은** 원천 목록이다 — 정렬/필터는 소비자가 적용한다.
  Stream<List<Gifticon>> watchGifticons(String ownerId);

  /// 특정 소유자의 기프티콘 목록을 1회성으로 조회한다. (스트림이 필요 없는 소비 경로)
  Future<List<Gifticon>> getGifticons(String ownerId);

  /// 단건 조회. 없으면 `null`을 반환한다.
  Future<Gifticon?> getGifticonById(String id);

  /// 기프티콘 상태를 전이한다. (main의 사용완료 처리, 공유 사용 동기화 등)
  ///
  /// 전이는 [GifticonStatusTransition.isAllowed] 규칙을 따라야 하며, 위반 시 구현체는
  /// [StateError]를 던지는 것을 계약으로 한다. 성공 시 갱신된 [Gifticon]을 반환한다.
  Future<Gifticon> updateStatus(String id, GifticonStatus status);

  /// 유효기간을 [newExpiryDate]로 **연장한다**. (만료된 기프티콘을 되살리는 경로)
  ///
  /// 실제 연장은 브랜드사가 해 주는 것이고, 이 계약은 그 결과(새 만료일)를 기록한다.
  ///
  /// 가드 — 위반 시 [StateError]:
  /// - 문서가 없으면 안 된다.
  /// - [newExpiryDate]가 현재 [Gifticon.expiryDate]보다 **뒤 날짜**여야 한다
  ///   (판정은 [isLaterExpiryDate] — 달력 일 단위). 같은 날·앞당기기는 연장이 아니다.
  /// - [Gifticon.status]가 [GifticonStatus.used]면 안 된다 — 이미 쓴 기프티콘은 기간을
  ///   늘려도 쓸 수 없다.
  ///
  /// 효과: [Gifticon.expiryDate]를 옮기고, 저장된 상태가 [GifticonStatus.expired]면
  /// [GifticonStatus.available]로 되돌린다(전이 표의 유일한 예외 — [GifticonStatus] 문서 참조).
  /// 성공 시 갱신된 [Gifticon]을 반환한다.
  ///
  /// ## 행위자(누가 연장할 수 있는가)
  /// 이 인터페이스는 행위자를 받지 않는다(`updateStatus`와 같다). **연장은 등록한
  /// 본인만** 할 수 있고, 그 강제는 두 겹이다 — 화면은 자기 목록에서만 이 경로를
  /// 열고(main은 `watchGifticons(ownerId)`로 자기 것만 본다), 백엔드는
  /// `firestore.rules`의 `gifticons` 규칙이 `ownerId == uid()`인 쓰기만 허용한다.
  ///
  /// ## ⚠️ 공유 중인 기프티콘에 직접 부르지 마라
  /// [SharedGifticon.expiryDate]는 원본의 **스냅샷**이라 이 메서드로는 갱신되지 않는다.
  /// 그룹에 공유된 기프티콘의 연장은 `ShareRepository.extendSharedExpiry`로 하며, 그쪽이
  /// 스냅샷과 원본을 함께 옮긴다(같은 이유로 `updateStatus`도 공유 중에는 부르지 않는다 —
  /// 그 규약은 main 상세 화면의 사용 완료 가드에 이미 적혀 있다).
  Future<Gifticon> extendExpiry(String id, DateTime newExpiryDate);

  /// 기프티콘을 **완전히 삭제한다.** 되돌리기는 없다(숨김·휴지통이 아니다).
  ///
  /// 가드 — 문서가 없으면 [StateError]. 상태는 가리지 않는다(보유중·사용 완료·만료 모두
  /// 지울 수 있다). 무료 한도는 보유중이고 날짜상 만료되지 않은 것만 세므로, 그런
  /// 기프티콘을 지우면 한 자리가 비고 같은 바코드로 다시 등록할 수 있다.
  ///
  /// ## 행위자(누가 지울 수 있는가)
  /// [extendExpiry]와 같다 — 인터페이스는 행위자를 받지 않고, **등록한 본인만** 지울 수
  /// 있다. 화면은 자기 목록에서만 이 경로를 열고, 백엔드는 `firestore.rules`의
  /// `gifticons` 삭제 규칙이 `ownerId == uid()`만 허용한다.
  ///
  /// ## ⚠️ 그룹에 공유 중(`ShareStatus.available`)이면 부르지 마라
  /// 이 계약은 공유를 모른다(저장소가 분리돼 있다). 공유 중인 원본을 지우면 그룹에는
  /// 원본 없는 공유 항목이 남는다 — 멤버가 그것을 쓰면 원본 동기화는 best-effort라
  /// 조용히 건너뛰지만, 공유자 화면에서 그 항목을 회수·연장할 근거가 사라진다. 그래서
  /// 화면이 공유 여부를 확정한 뒤 **공유가 없거나 이미 사용 완료된 경우에만** 이 경로를
  /// 연다(main 상세 화면의 삭제 가드). 공유 중이면 먼저 `ShareRepository.cancelShare`로
  /// 회수하게 안내한다. 사용 완료된 공유 항목은 이력이라 원본을 지워도 남는다.
  ///
  /// 규칙 있는 백엔드(Firestore)는 화면 가드가 못 보는 경우 — 지금 속하지 않은 그룹의
  /// 공유, 두 기기의 공유·삭제가 겹친 경합 — 까지 규칙으로 거부하고, 구현은 그것을
  /// [GifticonShareBlockedException]([StateError]의 하위 타입)으로 알린다. 소비자는 그
  /// 타입을 먼저 받고, 나머지 [StateError]를 "없음"으로 읽는다. in-memory 구현은 공유를
  /// 모르므로 이 타입을 내지 않는다(두 저장소가 분리돼 있다).
  Future<void> deleteGifticon(String id);

  /// 기프티콘 내용([GifticonDetails])을 고친다. 성공 시 갱신된 [Gifticon]을 반환한다.
  ///
  /// 가드 — 위반 시 [StateError]: 문서가 없거나, [GifticonDetails.normalized]가 거부하는
  /// 값일 때. **상태는 가리지 않는다** — 사용 완료·만료된 기프티콘의 오타도 고칠 수 있다.
  /// 만료일·상태·소유자·등록 시각은 바꾸지 않는다(부분 갱신).
  ///
  /// 행위자는 [deleteGifticon]과 같다 — **등록한 본인만**이고, 강제는 화면과
  /// `firestore.rules`의 `gifticons` 규칙이 한다.
  ///
  /// ## ⚠️ 그룹에 공유 중(`ShareStatus.available`·`inUse`)이면 부르지 마라
  /// `SharedGifticon`은 브랜드·상품명·바코드를 **스냅샷**으로 들고 있어 원본만 고치면
  /// 그룹이 옛 정보를 본다. 사용자 결정은 스냅샷 동기화가 아니라 "회수한 뒤 수정"이다.
  /// 강제와 예외 타입은 [deleteGifticon]과 같다 — 화면이 공유 여부를 확정한 뒤 경로를
  /// 열고, Firestore는 규칙으로도 거부해 [GifticonShareBlockedException]을 낸다.
  /// in-memory 구현은 공유를 모르므로 이 타입을 내지 않는다. 사용 완료된 공유 항목은
  /// 이력이라 고쳐도 그 시점의 스냅샷을 그대로 남긴다.
  Future<Gifticon> updateDetails(String id, GifticonDetails details);
}
