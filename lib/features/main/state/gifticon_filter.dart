/// main 페이지 — 정렬/필터 UI 상태 값 객체.
///
/// 정렬/필터는 **소비자(main)** 가 수행한다(계약 매트릭스 3항). 여기서는 어떤
/// 기준으로 거를지를 계약 enum([SortOption], [FilterOption], [GifticonStatus])만으로
/// 표현한다. 매직 스트링 상태값은 쓰지 않는다.
library;

import '../../../shared/models/gifticon.dart';

/// 활성 필터 상태.
///
/// [FilterOption]은 "어떤 종류의 필터인지"(상태별/카테고리별)를 계약으로 정의하고,
/// 실제 선택 값은 아래 필드로 보관한다:
/// - [FilterOption.status] → [statusFilter] ([GifticonStatus] enum, null이면 미적용)
/// - [FilterOption.category] → [categoryFilter] (카테고리 문자열, null이면 미적용)
///
/// 두 필터는 AND로 결합한다.
class GifticonFilter {
  /// 상태별 필터 값. null이면 상태 필터 미적용(전체 상태).
  final GifticonStatus? statusFilter;

  /// 카테고리별 필터 값. null이면 카테고리 필터 미적용(전체 카테고리).
  final String? categoryFilter;

  const GifticonFilter({this.statusFilter, this.categoryFilter});

  /// 필터가 하나도 걸려 있지 않은 초기 상태.
  static const GifticonFilter none = GifticonFilter();

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
      );

  /// 카테고리 필터만 교체한 새 인스턴스. [category]에 null을 주면 해제.
  GifticonFilter withCategory(String? category) => GifticonFilter(
        statusFilter: statusFilter,
        categoryFilter: category,
      );

  /// 단일 [Gifticon]이 이 필터를 통과하는지. 값 비교는 [GifticonStatus] enum으로만 한다.
  bool matches(Gifticon g) {
    if (statusFilter != null && g.status != statusFilter) return false;
    if (categoryFilter != null && g.category != categoryFilter) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GifticonFilter &&
          runtimeType == other.runtimeType &&
          statusFilter == other.statusFilter &&
          categoryFilter == other.categoryFilter;

  @override
  int get hashCode => Object.hash(statusFilter, categoryFilter);
}
