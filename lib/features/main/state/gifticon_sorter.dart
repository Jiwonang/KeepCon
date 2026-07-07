/// main 페이지 — 정렬 로직(순수 함수).
///
/// 계약 [SortOption] enum에 따라 원천 목록을 정렬한다. 정렬 키는 계약 [Gifticon]
/// 필드(expiryDate/registeredAt/brand)에서만 온다. 매직 스트링 정렬키 금지.
library;

import '../../../shared/models/gifticon.dart';

/// [SortOption]에 따라 [source]의 정렬본을 새 리스트로 반환한다(원본 불변).
List<Gifticon> sortGifticons(List<Gifticon> source, SortOption option) {
  final List<Gifticon> list = List<Gifticon>.of(source);
  switch (option) {
    case SortOption.expiryAsc:
      // 만료임박순 — expiryDate 오름차순(가까운 만료가 먼저).
      list.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    case SortOption.registeredDesc:
      // 최신 등록순 — registeredAt 내림차순(최근 등록이 먼저).
      list.sort((a, b) => b.registeredAt.compareTo(a.registeredAt));
    case SortOption.brandAsc:
      // 브랜드명순 — brand 사전순 오름차순(대소문자 무시).
      list.sort(
        (a, b) => a.brand.toLowerCase().compareTo(b.brand.toLowerCase()),
      );
  }
  return list;
}
