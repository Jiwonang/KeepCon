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
}
