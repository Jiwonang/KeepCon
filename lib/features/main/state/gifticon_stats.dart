/// main 페이지 — 요약 통계(홈 상단 3카드).
///
/// 통계는 **소비자(main)** 가 원천 목록에서 직접 계산한다(계약 매트릭스: 통계는 소비자 계산).
/// 계약 [Gifticon] 필드만 참조한다:
/// - 보유중  : [GifticonStatus.available] 개수
/// - 만료임박: available 이면서 [Gifticon.expiryDate]가 [expirySoonDays]일 이내
/// - 총금액  : available 기프티콘 [Gifticon.price] 합(원, KRW)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import 'gifticon_list_providers.dart';

/// 만료 임박 기준(일). 이 일수 이하로 남으면 임박으로 센다.
const int expirySoonDays = 7;

/// 홈 요약 통계 값 객체.
class GifticonStats {
  /// 보유중(사용가능) 개수.
  final int holdingCount;

  /// 만료 임박(사용가능 & 7일 이내) 개수.
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

/// 원천 목록에서 도출한 홈 요약 통계.
///
/// [rawGifticonsProvider]를 구독하므로 scan 추가/share 동기화로 목록이 바뀌면 자동 재계산된다.
final gifticonStatsProvider = Provider<GifticonStats>((ref) {
  final List<Gifticon> raw =
      ref.watch(rawGifticonsProvider).valueOrNull ?? const [];
  final DateTime now = DateTime.now();

  int holding = 0;
  int soon = 0;
  int total = 0;
  for (final Gifticon g in raw) {
    if (g.status != GifticonStatus.available) continue;
    holding += 1;
    total += g.price;
    final int daysLeft = g.expiryDate.difference(now).inDays;
    if (daysLeft <= expirySoonDays) soon += 1;
  }
  return GifticonStats(
    holdingCount: holding,
    expiringSoonCount: soon,
    totalPrice: total,
  );
});
