/// main 페이지 — 날짜 파생 계산이 공유하는 **단일 시각**.
///
/// 만료 임박 판정·D-day 표시는 전부 "지금이 며칠인가"에 달려 있는데, 이 값을 읽는 곳이
/// 여럿이면 두 가지가 동시에 깨진다:
///
/// 1. **일관성** — 소비자마다 [DateTime.now]를 따로 읽으면 서로 다른 "오늘"로 판정할 수
///    있다. 실제로 그랬다: 배너 목록(`expiringSoonGifticonsProvider`)은 원천 목록이
///    바뀔 때만 재계산되고 표시 목록(`visibleGifticonsProvider`)은 필터가 바뀔 때도
///    재계산되는데, 각자 시계를 읽어서 **자정을 넘긴 뒤 필터를 켜면** 배너는 어제 기준
///    "1개 곧 만료"인데 목록은 오늘 기준으로 그 항목을 걸러내 0개가 됐다. 술어를
///    [isExpiringSoonGifticon] 하나로 합쳐도 시계가 갈리면 답은 그대로 갈린다.
/// 2. **신선도** — 값을 캐시하는 provider가 시각을 한 번만 읽으면 날짜가 바뀌어도
///    영원히 어제를 본다. 앱을 켜 둔 채 자정을 넘기면 D-day가 하루 밀린 채 굳는다.
///
/// 그래서 시각을 한 곳에서 읽고, **다음 로컬 자정에 스스로 무효화**한다. 소비자는
/// `ref.watch(nowProvider)`만 하면 일관성과 신선도를 함께 얻는다.
///
/// 테스트는 이 provider를 override해 시각을 고정한다 — 그러지 않으면 `DateTime.now()`에
/// 의존하는 테스트가 자정을 넘기는 순간 전부 하루씩 밀려 깨진다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 날짜 파생 계산이 공유하는 현재 시각.
///
/// 다음 **로컬** 자정에 [Ref.invalidateSelf]로 스스로 무효화한다. 로컬 기준인 이유는
/// 만료 판정(`shared/util/expiry_policy.dart`)이 로컬 달력 날짜로 세기 때문이다 —
/// UTC 자정에 갱신하면 한국(UTC+9)에서는 오전 9시에 날짜가 바뀌는 꼴이 된다.
final nowProvider = Provider<DateTime>((ref) {
  final DateTime now = DateTime.now();

  // day + 1은 Dart가 월/연 경계를 알아서 넘겨준다(예: 12월 31일 + 1 → 1월 1일).
  final DateTime nextMidnight = DateTime(now.year, now.month, now.day + 1);
  final Timer timer = Timer(
    nextMidnight.difference(now),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);

  return now;
});
