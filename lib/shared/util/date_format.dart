/// KeepCon 공유 유틸 — 날짜 표시 포맷(`YYYY.MM.DD`).
///
/// 같은 날짜 라벨 조립이 세 페이지에 복사돼 있었기에
/// CLAUDE.md 승격 워크플로 규칙 ③(**실제 두 번째 소비자가 생겼을 때 승격**)에 따라
/// 정본으로 승격한 것이다(세 번째 소비자까지 확인된 상태):
///
/// - main 만료일 표시 — `formatDate(DateTime)` (lib/features/main/widgets/format.dart)
/// - share 유효기간/초대 만료 라벨 — `formatExpiryLabel`·`formatInviteExpiry`
///   (lib/features/share/widgets/share_format.dart)
/// - scan 날짜 선택 버튼 라벨 — 인라인 `padLeft` 조립
///   (lib/features/scan/scan_page.dart)
///
/// 승격 대상은 **코어 [formatYmdDot] 하나**다. share의 `~` 접두·`HH:mm` 조합,
/// 상대 시각(`formatRelativeKo`), main의 D-day 라벨(`formatDDay`)처럼
/// **페이지 고유의 표현**은 승격하지 않고 각 페이지에 남긴다 — 소비자가 여러 개인 것은
/// "날짜를 문자열로 찍는 방법"이고, 그 앞뒤에 무엇을 붙이는지는 화면의 문제다.
///
/// 함수명에 표기를 박아 둔(`...YmdDot`) 이유는, 나중에 다른 구분자가 필요해지면
/// 이 함수를 조용히 고치는 대신 별도 이름(`formatYmdSlash` 등)을 만들게 강제해
/// **표기 분기가 리뷰에서 눈에 보이게** 하려는 것이다.
///
/// 모델/Repository 계약과 달리 도메인 결합이 없는 **순수 표시 유틸**이므로
/// `lib/shared/util/`에 둔다(`money_format.dart`·`korean_particle.dart`와 동일한 성격).
/// 계약값(`Gifticon.expiryDate: DateTime`)을 바꾸지 않으며, 표시 문자열만 만든다.
/// 금액 포맷과는 도메인이 달라 파일을 합치지 않는다(`money_format.dart`와 형제 파일).
///
/// (승격 경위·표기 통일 이력은 `_workspace/01_contract_dependency_matrix.md` v2.4 참조)
library;

/// [v]를 두 자리로. 예: `9` → `'09'`, `30` → `'30'`.
String _two(int v) => v.toString().padLeft(2, '0');

/// **코어** — [date]의 날짜 부분을 `YYYY.MM.DD`로. 예: `DateTime(2026, 9, 30)`
/// → `'2026.09.30'`.
///
/// 시·분·초는 보지 않으며 **타임존 변환도 하지 않는다** — [date] 객체가 담고 있는
/// 연/월/일을 그대로 쓴다. UTC `DateTime`을 넘기면 UTC 기준 날짜가 나오므로,
/// 사용자 로컬 기준 날짜가 필요하면 호출 전에 `toLocal()`을 적용할 것.
/// 시각까지 필요한 화면(초대 링크 만료 등)은 이 결과에 자기 `HH:mm`을 덧붙인다.
///
/// 월·일은 두 자리로 채우고 **연도는 네 자리 표기를 전제로 채우지 않는다**.
/// 기프티콘 유효기간은 날짜 선택기·OCR 파서가 현실적인 범위로 제한하므로
/// 네 자리 밖 연도는 도메인에 존재하지 않는다. 그 전제가 깨지면(파싱 버그 등)
/// 조용히 `'12.01.02'` 같은 값을 만들지 않도록 debug 빌드의 assert가 검출한다
/// (release에서는 컴파일 아웃).
String formatYmdDot(DateTime date) {
  assert(
    date.year >= 1000 && date.year <= 9999,
    'formatYmdDot은 네 자리 연도 표기를 전제한다 — 4자리 미만은 패딩하지 않아 '
    '모호해지고, 4자리 초과는 표기 계약 밖이다. '
    '받은 연도: ${date.year} — 날짜 파싱/생성 지점을 확인할 것.',
  );

  return '${date.year}.${_two(date.month)}.${_two(date.day)}';
}
