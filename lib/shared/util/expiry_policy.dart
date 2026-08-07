/// KeepCon 공유 계약 — 만료 판정 정책(SSOT).
///
/// "며칠 남았는가"와 "만료 임박인가"를 **한 곳에서** 판정한다. 이 파일이 생기기 전에는
/// 같은 계산이 세 군데에 흩어져 있었고, 그중 하나는 알고리즘이 달라 **같은 기프티콘을
/// 두고 화면과 통계가 다른 답**을 냈다:
///
/// - `gifticon_stats.dart`: `expiryDate.difference(now).inDays` — 시분초가 섞여
///   절삭되므로 "내일 자정 만료"가 0일로 나온다(카드는 1일로 표시).
/// - `gifticon_card.dart` / `main_page.dart`: 날짜만 남겨 계산(정확) — 대신 임계
///   상수 `_expirySoonDays`를 사본으로 재선언.
///
/// 만료 임박 알림은 이 판정 위에 올라가므로, 알림과 화면이 어긋나지 않으려면 판정이
/// 먼저 하나여야 한다. 소비자(카드·통계·알림 스케줄러)는 이 함수만 호출한다.
///
/// ## 상태(status)와의 관계
/// 이 파일은 **날짜만** 본다(모델에 의존하지 않는 순수 함수). `GifticonStatus`와
/// 조합하는 규칙은 소비자 책임이다 — "사용 완료한 기프티콘은 만료 임박에서 제외" 같은
/// 판단은 화면마다 다르기 때문이다. 저장된 `GifticonStatus.expired`로의 전이는 별도
/// 관심사이며 현재 그 전이를 수행하는 주체가 없다 — 그래서 날짜 기준 판정이 실질적인
/// 만료 판단이다.
library;

/// 만료 임박 기준(일). 남은 일수가 이 값 **이하**면 임박으로 본다.
///
/// 홈 요약("N개가 7일 내 만료")·카드 만료일 강조·만료 임박 알림이 모두 이 값을 쓴다.
const int expirySoonDays = 7;

/// 날짜만 남긴 UTC 자정 시각으로 정규화한다.
///
/// UTC로 고정하는 이유: 로컬 [DateTime]끼리 빼면 DST 전환이 낀 구간에서 하루가
/// 23시간(또는 25시간)이 되어 [Duration.inDays]가 한 칸 어긋난다. 한국은 DST가 없지만
/// 웹 빌드는 사용자 브라우저의 타임존에서 돌아가므로 방어해 둔다. 년/월/일만 취해
/// 옮기므로 "그 지역의 그 날짜"라는 의미는 그대로 보존된다.
DateTime _dateOnlyUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// [expiryDate]까지 남은 **달력 일수**. 오늘 만료면 0, 이미 지났으면 음수.
///
/// 시분초는 무시하고 날짜 경계로만 센다 — 사용자가 "D-3"으로 읽는 값과 같다.
/// [now]는 테스트 주입용이며, 생략하면 [DateTime.now]를 쓴다.
int daysUntilExpiry(DateTime expiryDate, {DateTime? now}) {
  final DateTime today = _dateOnlyUtc(now ?? DateTime.now());
  return _dateOnlyUtc(expiryDate).difference(today).inDays;
}

/// [expiryDate]가 이미 지났는지(어제까지 만료). 오늘 만료는 `false`다.
///
/// 만료일 당일은 아직 쓸 수 있다고 본다 — 기프티콘의 "2026-08-07까지"는 그 날을
/// 포함하는 표기이기 때문이다.
bool isExpiredByDate(DateTime expiryDate, {DateTime? now}) =>
    daysUntilExpiry(expiryDate, now: now) < 0;

/// [expiryDate]가 만료 임박 구간([expirySoonDays]일 이내)인지.
///
/// **이미 만료된 것은 임박이 아니다**(하한 0). 이 하한이 없던 시절 통계의
/// `daysLeft <= 7` 조건은 음수도 통과시켜, 만료된 기프티콘을 "만료 임박"으로 셌다.
bool isExpiringSoon(DateTime expiryDate, {DateTime? now}) {
  final int days = daysUntilExpiry(expiryDate, now: now);
  return days >= 0 && days <= expirySoonDays;
}
