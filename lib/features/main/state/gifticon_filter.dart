/// main 페이지 — 정렬/필터 UI 상태 값 객체.
///
/// 정렬/필터는 **소비자(main)** 가 수행한다(계약 매트릭스 3항). 여기서는 어떤
/// 기준으로 거를지를 계약 enum([SortOption], [FilterOption], [GifticonStatus])만으로
/// 표현한다. 매직 스트링 상태값은 쓰지 않는다.
library;

import '../../../shared/models/gifticon.dart';
import '../../../shared/util/expiry_policy.dart';

/// [g]가 "만료 임박"인지 — **날짜 + 상태**를 함께 본 소비자 판정.
///
/// 계약의 [isExpiringSoon]은 날짜만 본다(모델에 의존하지 않는 순수 함수). "사용 완료한
/// 것은 임박에서 제외한다"는 상태 규칙은 화면마다 다를 수 있어 소비자 책임으로 남겨져
/// 있는데, main에서는 그 조합을 **배너 목록과 목록 필터 두 곳**이 쓴다.
///
/// 그래서 조합을 여기 한 번만 적는다. 두 곳에 각각 적으면 한쪽만 고쳐질 때 배너가 세는
/// 개수와 필터가 남기는 목록이 어긋난다 — 이 화면이 이미 한 번 밟은 함정이다.
bool isExpiringSoonGifticon(Gifticon g, {required DateTime now}) =>
    g.status == GifticonStatus.available &&
    isExpiringSoon(g.expiryDate, now: now);

/// 활성 필터 상태.
///
/// [FilterOption]은 "어떤 종류의 필터인지"(상태별/카테고리별)를 계약으로 정의하고,
/// 실제 선택 값은 아래 필드로 보관한다:
/// - [FilterOption.status] → [statusFilter] ([GifticonStatus] enum, null이면 미적용)
/// - [FilterOption.category] → [categoryFilter] (카테고리 문자열, null이면 미적용)
///
/// [expiringSoonOnly]는 계약 [FilterOption]에 대응 값이 **없다** — 만료 임박은 저장된
/// 상태가 아니라 `expiryDate`에서 매일 달라지는 파생 조건이라 [GifticonStatus]로도,
/// [FilterOption]으로도 표현되지 않는다. 지금 이 필터를 쓰는 소비자는 main 홈의 만료
/// 배너 하나뿐이므로, 계약을 넓히지 않고 페이지 로컬 필드로 둔다(CLAUDE.md 승격 규칙
/// ③ 늦게 승격 — 두 번째 소비자가 생기면 그때 `contract-architect`에 승격을 요청한다).
///
/// 모든 필터는 AND로 결합한다.
class GifticonFilter {
  /// 상태별 필터 값. null이면 상태 필터 미적용(전체 상태).
  final GifticonStatus? statusFilter;

  /// 카테고리별 필터 값. null이면 카테고리 필터 미적용(전체 카테고리).
  final String? categoryFilter;

  /// 만료 임박([expirySoonDays]일 이내)인 사용가능 기프티콘만 남길지 여부.
  ///
  /// 판정은 계약(`shared/util/expiry_policy.dart`)의 [isExpiringSoon]에 위임한다 —
  /// 홈 배너·통계 카드·만료 알림이 모두 같은 답을 내야 하므로 여기서 자체 기준을
  /// 갖지 않는다.
  final bool expiringSoonOnly;

  const GifticonFilter({
    this.statusFilter,
    this.categoryFilter,
    this.expiringSoonOnly = false,
  });

  /// 필터가 하나도 걸려 있지 않은 초기 상태.
  static const GifticonFilter none = GifticonFilter();

  /// 어떤 종류든 필터가 하나라도 걸려 있는지.
  ///
  /// 목록 헤더가 "전체 N개"와 "걸러진 N개"를 구분해 보여주는 데 쓴다 — 필터가 켜진 걸
  /// 모르면 사용자는 기프티콘이 사라졌다고 읽는다.
  bool get isAnyActive =>
      statusFilter != null || categoryFilter != null || expiringSoonOnly;

  /// 이 필터에서 특정 [option] 종류가 활성인지.
  bool isActive(FilterOption option) {
    switch (option) {
      case FilterOption.status:
        return statusFilter != null;
      case FilterOption.category:
        return categoryFilter != null;
    }
  }

  /// 상태 필터만 교체한 새 인스턴스. [status]에 null을 주면 해제.
  GifticonFilter withStatus(GifticonStatus? status) => GifticonFilter(
        statusFilter: status,
        categoryFilter: categoryFilter,
        expiringSoonOnly: expiringSoonOnly,
      );

  /// 카테고리 필터만 교체한 새 인스턴스. [category]에 null을 주면 해제.
  GifticonFilter withCategory(String? category) => GifticonFilter(
        statusFilter: statusFilter,
        categoryFilter: category,
        expiringSoonOnly: expiringSoonOnly,
      );

  /// 만료 임박 필터만 교체한 새 인스턴스.
  GifticonFilter withExpiringSoonOnly(bool value) => GifticonFilter(
        statusFilter: statusFilter,
        categoryFilter: categoryFilter,
        expiringSoonOnly: value,
      );

  /// 단일 [Gifticon]이 이 필터를 통과하는지. 값 비교는 [GifticonStatus] enum으로만 한다.
  ///
  /// [now]를 **호출자가 주입**하는 이유: 만료 임박 판정은 날짜 경계에 걸린다. 항목마다
  /// [DateTime.now]를 새로 읽으면 목록을 훑는 도중 자정을 넘길 때 앞부분과 뒷부분이
  /// 서로 다른 "오늘"로 판정돼 같은 D-day의 기프티콘이 갈린다. 목록 전체가 한 시각으로
  /// 판정되도록 호출자가 한 번만 읽어 넘긴다(테스트에서 고정 시각을 주입하는 통로이기도 하다).
  bool matches(Gifticon g, {required DateTime now}) {
    if (statusFilter != null && g.status != statusFilter) return false;
    if (categoryFilter != null && g.category != categoryFilter) return false;
    if (expiringSoonOnly && !isExpiringSoonGifticon(g, now: now)) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GifticonFilter &&
          runtimeType == other.runtimeType &&
          statusFilter == other.statusFilter &&
          categoryFilter == other.categoryFilter &&
          expiringSoonOnly == other.expiringSoonOnly;

  @override
  int get hashCode =>
      Object.hash(statusFilter, categoryFilter, expiringSoonOnly);
}
