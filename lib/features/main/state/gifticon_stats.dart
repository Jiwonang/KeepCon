/// main 페이지 — 요약 통계(홈 상단 3카드).
///
/// 통계는 **소비자(main)** 가 원천 목록에서 직접 계산한다(계약 매트릭스: 통계는 소비자 계산).
/// 계약 [Gifticon] 필드만 참조한다:
/// - 보유중  : [GifticonStatus.available] 개수
/// - 만료임박: available 이면서 [isExpiringSoon] 판정을 통과한 개수
/// - 총금액  : available 기프티콘 [Gifticon.price] 합(원, KRW)
///
/// 만료 판정은 계약(`shared/util/expiry_policy.dart`)에 위임한다 — 카드·알림과 같은
/// 답을 내야 하므로 이 파일이 자체 기준을 갖지 않는다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/util/expiry_policy.dart';
import 'gifticon_filter.dart';
import 'gifticon_list_providers.dart';
import 'gifticon_sorter.dart';
import 'now_provider.dart';

/// 홈 요약 통계 값 객체.
class GifticonStats {
  /// 보유중(사용가능) 개수.
  final int holdingCount;

  /// 만료 임박(사용가능 & [expirySoonDays]일 이내) 개수. 이미 만료된 것은 빠진다.
  final int expiringSoonCount;

  /// 보유중 기프티콘의 액면가 합(원).
  final int totalPrice;

  const GifticonStats({
    required this.holdingCount,
    required this.expiringSoonCount,
    required this.totalPrice,
  });

  static const GifticonStats empty = GifticonStats(
    holdingCount: 0,
    expiringSoonCount: 0,
    totalPrice: 0,
  );
}

/// 만료 임박 기프티콘 목록 — **만료 임박순(D-day 오름차순) 정렬**.
///
/// 판정은 [isExpiringSoonGifticon] 하나만 부른다 — 목록 필터
/// ([GifticonFilter.expiringSoonOnly])와 같은 술어를 써야 "배너가 센 개수"와 "필터가
/// 남긴 목록"이 갈리지 않는다. 아래 통계도 개수를 따로 세지 않고 이 목록의 `length`를
/// 그대로 쓴다.
///
/// 조건을 여러 곳에 적으면 한쪽만 고쳐져 어긋난다 — 이 배너가 이미 한 번 밟은 함정이다:
/// 개수는 원천 기준으로 세면서 대표 브랜드는 **필터·정렬이 끝난 표시 목록**에서 뽑아,
/// 필터를 걸면 "3개 만료"인데 제목은 폴백 '기프티콘'이 뜨는 불일치가 났다.
///
/// [rawGifticonsProvider] 기준이므로 화면 필터와 무관하다 — "지금 보고 있는 목록"이
/// 아니라 "내가 가진 것 중 임박한 것"을 답해야 배너·통계가 필터에 따라 흔들리지 않는다.
///
/// 정렬을 여기서 끝내 두는 이유: 소비자(배너)가 "가장 급한 것"을 대표로 쓰는데,
/// 원천 목록의 순서는 보장이 없어 `first`가 임의의 항목이 된다.
final expiringSoonGifticonsProvider = Provider<List<Gifticon>>((ref) {
  final List<Gifticon> raw =
      ref.watch(rawGifticonsProvider).valueOrNull ?? const [];
  // 시각도 [nowProvider] 하나에서 받는다 — 술어만 통일하고 시계를 각자 읽으면
  // 자정을 넘긴 뒤 배너와 표시 목록이 서로 다른 "오늘"로 판정한다.
  final DateTime now = ref.watch(nowProvider);

  final List<Gifticon> soon = <Gifticon>[
    for (final Gifticon g in raw)
      if (isExpiringSoonGifticon(g, now: now)) g,
  ];
  return sortGifticons(soon, SortOption.expiryAsc);
});

/// 원천 목록에서 도출한 홈 요약 통계.
///
/// [rawGifticonsProvider]를 구독하므로 scan 추가/share 동기화로 목록이 바뀌면 자동 재계산된다.
/// 만료 임박 개수만은 [expiringSoonGifticonsProvider]에서 받아 온다(판정 조건 SSOT).
final gifticonStatsProvider = Provider<GifticonStats>((ref) {
  final List<Gifticon> raw =
      ref.watch(rawGifticonsProvider).valueOrNull ?? const [];
  final int soon = ref.watch(expiringSoonGifticonsProvider).length;

  int holding = 0;
  int total = 0;
  for (final Gifticon g in raw) {
    if (g.status != GifticonStatus.available) continue;
    holding += 1;
    total += g.price;
  }
  return GifticonStats(
    holdingCount: holding,
    expiringSoonCount: soon,
    totalPrice: total,
  );
});
