/// share 페이지 — 표시용 포맷 헬퍼(UI 전용).
///
/// 계약 모델은 만료일/시각을 [DateTime]으로 담고(라벨 문자열 폐기), 상대 시각·유효기간
/// 라벨 포맷은 소비자(UI) 책임이라는 규약을 따른다. 값 규약(enum/필드)과 무관한 순수
/// 표시 문자열만 만든다.
///
/// `YYYY.MM.DD` 날짜 조립 자체는 main·scan과 겹쳐
/// `lib/shared/util/date_format.dart`의 [formatYmdDot] 정본으로 승격했다
/// (CLAUDE.md 승격 규칙 ③). 이 파일은 그 코어를 소비하고, `~` 접두·`HH:mm` 조합·
/// 상대 시각처럼 **share 화면 고유의 표현만** 유지한다.
///
/// 함수명·출력 문자열은 불변이다 — 단 하나의 예외: 도메인 밖 연도(4자리 아님)는
/// 정본의 debug assert가 검출한다(승격 전에는 조용히 이상한 라벨을 렌더했다.
/// release 빌드는 assert가 컴파일 아웃되어 차이 없음).
/// 출력 문자열은 test/features/share/share_format_test.dart가 고정한다.
library;

import '../../../shared/util/date_format.dart' show formatYmdDot;

/// 시·분을 두 자리로 채우는 로컬 헬퍼([formatInviteExpiry]의 `HH:mm` 전용).
String _two(int v) => v.toString().padLeft(2, '0');

/// 유효기간을 "~YYYY.MM.DD"로. 예: DateTime(2026,9,30) → "~2026.09.30".
String formatExpiryLabel(DateTime d) => '~${formatYmdDot(d)}';

/// 초대 **링크** 만료 시각을 "YYYY.MM.DD HH:mm"로. 예: "2026.07.29 15:30".
///
/// 6자리 초대코드는 5분짜리라 이 포맷을 쓰지 않는다 — 그쪽은 `M:SS` 카운트다운이다.
/// 초대 유효기간이 24시간이라 날짜만으로는 언제 끊기는지 알 수 없으므로 시각까지 표시한다.
String formatInviteExpiry(DateTime d) =>
    '${formatYmdDot(d)} ${_two(d.hour)}:${_two(d.minute)}';

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
