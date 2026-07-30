/// main 페이지 — 표시용 포맷 헬퍼(UI 전용).
///
/// 금액·만료일 포맷은 `lib/shared/util/`(money_format·date_format) 정본으로
/// 승격됐고 호출부가 정본을 직접 import한다(승격 이력은 계약 매트릭스 참조).
///
/// 남은 [formatDDay]는 main 고유 표현이므로 승격하지 않는다 —
/// 소비자가 이 페이지뿐이고, 입력이 날짜가 아니라 "남은 일수"다.
library;

/// 남은 일수를 D-day 라벨로. 오늘=D-DAY, 지남=만료.
String formatDDay(int daysLeft) {
  if (daysLeft < 0) return '만료';
  if (daysLeft == 0) return 'D-DAY';
  return 'D-$daysLeft';
}
