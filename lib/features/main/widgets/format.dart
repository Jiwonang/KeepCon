/// main 페이지 — 표시용 포맷 헬퍼(UI 전용).
///
/// 값 규약(계약 enum/필드)과 무관한 순수 표시 문자열만 만든다.
library;

/// 정수 금액(원)을 천단위 콤마 문자열로. 예: 58500 → "58,500".
String formatWon(int won) {
  final String digits = won.abs().toString();
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) sb.write(',');
    sb.write(digits[i]);
  }
  return won < 0 ? '-$sb' : sb.toString();
}

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
