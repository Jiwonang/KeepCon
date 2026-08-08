/// main 페이지 — 날짜 파생 계산이 공유하는 **단일 시각**.
///
/// 만료 임박 판정·D-day 표시는 전부 "지금이 며칠인가"에 달려 있다. 이 값을 소비자마다
/// [DateTime.now]로 따로 읽으면 서로 다른 "오늘"로 판정할 수 있다. 실제로 그랬다:
/// 배너 목록(`expiringSoonGifticonsProvider`)은 원천 목록이 바뀔 때만 재계산되고
/// 표시 목록(`visibleGifticonsProvider`)은 필터가 바뀔 때도 재계산되는데, 각자 시계를
/// 읽어서 **자정을 넘긴 뒤 필터를 켜면** 배너는 어제 기준 "1개 곧 만료"인데 목록은 오늘
/// 기준으로 그 항목을 걸러내 "만료 임박 0개"가 됐다. 판정 술어를
/// [isExpiringSoonGifticon] 하나로 합쳐도 시계가 갈리면 답은 그대로 갈린다.
///
/// 그래서 시각을 한 곳에서 읽는다. 소비자는 `ref.watch(nowProvider)`만 하면 서로
/// 어긋나지 않는다.
///
/// 테스트는 이 provider를 override해 시각을 고정한다 — 그러지 않으면 `DateTime.now()`에
/// 의존하는 테스트가 자정을 넘기는 순간 전부 하루씩 밀려 깨진다.
///
/// ## 신선도는 아직 다루지 않는다(의도된 범위 제한)
///
/// 이 값은 컨테이너가 사는 동안 캐시된다. 앱을 켜 둔 채 날짜가 바뀌어도 원천 목록이
/// 다시 방출되기 전까지는 어제 기준으로 남는다 — **승격 전 `gifticonStatsProvider`도
/// 똑같이 한 번만 읽었으므로 새로 생긴 문제가 아니다.** 이 파일이 고치는 것은
/// "소비자들이 서로 다른 답을 낸다"이지 "값이 늙는다"가 아니다.
///
/// 자정에 [Ref.invalidateSelf]를 예약하는 방식은 **시도했다가 되돌렸다**: 자정까지의
/// [Timer]가 위젯 테스트에서 pending timer로 남아, [MainPage]를 마운트하는 모든 테스트가
/// "Pending timers" 로 실패한다(`test/features/share/invite_deeplink_test.dart`에서
/// 발견). 모든 테스트가 이 provider를 override하도록 강제하는 것은 전염성이 너무 크다.
///
/// 제대로 하려면 타이머를 이 provider가 아니라 **앱 진입부**가 소유해야 한다 — 예컨대
/// 셸에 라이프사이클 옵서버를 두고 resume·자정에 `ref.invalidate(nowProvider)`를
/// 부르는 식. 화면 provider는 순수하게 두고 갱신 주체를 밖에 두는 구조라, 테스트는
/// 타이머를 만나지 않는다. 별도 작업으로 분리한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 날짜 파생 계산이 공유하는 현재 시각.
///
/// 이 provider를 `watch`하는 소비자들은 항상 같은 "오늘"을 본다. 값 자체의 갱신은
/// 라이브러리 주석의 "신선도" 절 참조 — 지금은 원천 목록이 바뀔 때 함께 갱신된다.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());
