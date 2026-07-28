/// share 페이지 — 표시용 포맷 헬퍼(UI 전용).
///
/// 계약 모델은 만료일/시각을 [DateTime]으로 담고(라벨 문자열 폐기), 상대 시각·유효기간
/// 라벨 포맷은 소비자(UI) 책임이라는 규약을 따른다. 값 규약(enum/필드)과 무관한 순수
/// 표시 문자열만 만든다.
library;

String _two(int v) => v.toString().padLeft(2, '0');

/// 유효기간을 "~YYYY.MM.DD"로. 예: DateTime(2026,9,30) → "~2026.09.30".
String formatExpiryLabel(DateTime d) =>
    '~${d.year}.${_two(d.month)}.${_two(d.day)}';

/// 초대코드 만료 시각을 "YYYY.MM.DD HH:mm"로. 예: "2026.07.29 15:30".
/// 초대 만료는 시(hour) 단위 옵션(1시간)이 있어 날짜만으로는 부족하므로 시각까지 표시한다.
String formatInviteExpiry(DateTime d) =>
    '${d.year}.${_two(d.month)}.${_two(d.day)} '
    '${_two(d.hour)}:${_two(d.minute)}';

/// [when]을 기준 시각([now], 기본 현재)에 대한 상대 라벨로. 예: "방금", "3일 전".
String formatRelativeKo(DateTime when, {DateTime? now}) {
  final DateTime base = now ?? DateTime.now();
  final Duration diff = base.difference(when);
  if (diff.isNegative) return '방금';
  if (diff.inMinutes < 1) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  final int days = diff.inDays;
  if (days < 7) return '$days일 전';
  if (days < 30) return '${days ~/ 7}주 전';
  if (days < 365) return '${days ~/ 30}개월 전';
  return '${days ~/ 365}년 전';
}
