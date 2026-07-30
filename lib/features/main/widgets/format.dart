/// main 페이지 — 표시용 포맷 헬퍼(UI 전용).
///
/// 값 규약(계약 enum/필드)과 무관한 순수 표시 문자열만 만든다.
///
/// 금액 포맷(`formatWon`)은 scan 페이지와 알고리즘이 겹쳐
/// `lib/shared/util/money_format.dart` 정본으로 승격했다(CLAUDE.md 승격 규칙 ③).
/// 재export 간접층을 두지 않는다 — 호출부(`main_page.dart`·`gifticon_card.dart`)가
/// 정본을 **직접 import**해서, 공유 심벌의 import 경로가 한 곳으로 유지된다
/// (페이지 경로로 공유 심벌이 노출되면 미래의 다른 페이지가 그리로 의존해
/// 크로스 페이지 결합이 생길 수 있다).
library;

/// 만료일을 "YYYY.MM.DD"로.
String formatDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.'
    '${d.day.toString().padLeft(2, '0')}';

/// 남은 일수를 D-day 라벨로. 오늘=D-DAY, 지남=만료.
String formatDDay(int daysLeft) {
  if (daysLeft < 0) return '만료';
  if (daysLeft == 0) return 'D-DAY';
  return 'D-$daysLeft';
}
