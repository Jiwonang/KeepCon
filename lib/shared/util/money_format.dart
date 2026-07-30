/// KeepCon 공유 유틸 — 금액 표시 포맷(천 단위 그룹핑).
///
/// 동일한 자릿수 그룹핑 알고리즘이 두 페이지에 복사돼 있었기에
/// CLAUDE.md 승격 워크플로 규칙 ③(**실제 두 번째 소비자가 생겼을 때 승격**)에 따라
/// 정본으로 승격한 것이다:
///
/// - main 목록/통계 표시 — `formatWon(int)` (lib/features/main/widgets/format.dart)
/// - scan 금액 입력 포매터 — `formatThousands(String)`
///   (lib/features/scan/util/price_input_formatter.dart)
///
/// 두 소비자의 요구가 달라(한쪽은 부호 있는 `int`, 다른 쪽은 "숫자만 문자열")
/// **코어는 하나([groupThousands])로 두고 소비자별 진입점을 얇게** 얹었다.
/// 승격은 순수 리팩터이며 두 소비자의 기존 동작을 바꾸지 않는다.
///
/// 동작 불변의 증거:
/// - scan: 기존 test/features/scan/price_input_formatter_test.dart **무수정 통과**
/// - main: 기존 테스트가 없었으므로, 삭제된 구현과의 문자 단위 비교 +
///   신설 정본 테스트(test/shared/util/money_format_test.dart)로 확인
///
/// 모델/Repository 계약과 달리 도메인 결합이 없는 **순수 표시 유틸**이므로
/// `lib/shared/util/`에 둔다(`korean_particle.dart`·`invite_link.dart`와 동일한 성격).
/// 계약값(`Gifticon.price: int`)을 바꾸지 않으며, 표시 문자열만 만든다.
///
/// (승격 이력·다음 후보는 계약 매트릭스의 "다음 승격 후보" 절에서 관리한다)
library;

/// 숫자 이외의 문자.
///
/// 키 입력마다 재컴파일하지 않도록 최상위에 둔다(입력 포매터가 매 타이핑마다 호출).
final RegExp _nonDigits = RegExp(r'[^0-9]');

/// [input]에서 숫자('0'~'9')만 남긴다. 예: `' 4,500원 '` → `'4500'`.
///
/// 사용자 입력·OCR 결과처럼 콤마·공백·단위가 섞일 수 있는 문자열을
/// [groupThousands]에 넘기기 전에 정제하는 용도다.
String digitsOnly(String input) => input.replaceAll(_nonDigits, '');

/// **코어** — 문자열에 뒤에서부터 3자리마다 콤마를 넣는다.
///
/// 부호·단위·소수점을 해석하지 않는 순수 그룹핑이다. [digits]가
/// **숫자만으로 이루어져 있다는 전제**는 호출자의 책임이며, 공개 진입점
/// [formatThousands]·[formatWon]이 각자의 방식으로 그것을 보장한다.
///
/// 예:
///
/// ```
/// ''        → ''
/// '0'       → '0'
/// '4500'    → '4,500'
/// '1234567' → '1,234,567'
/// ```
String groupThousands(String digits) {
  // 전제조건을 debug 빌드에서 검출한다.
  //
  // 이 함수는 정제를 하지 않으므로 비숫자가 섞인 입력('4,500', '-45' 등)은
  // 조용히 잘못된 결과('4,,500')를 만든다 — 그런 입력은 진입점
  // [formatThousands]를 쓰거나 [digitsOnly]로 먼저 정제해야 한다.
  // (release에서는 컴파일 아웃되어 핫패스 비용 없음)
  assert(
    !_nonDigits.hasMatch(digits),
    'groupThousands는 숫자만으로 이루어진 문자열을 받는다. '
    '정제가 필요하면 formatThousands 또는 digitsOnly를 사용할 것.',
  );

  // 3자리 이하는 콤마가 없다 — 아래 루프와 결과는 같고, 입력 포매터의
  // 매 키 입력 경로에서 StringBuffer 할당을 피하는 빠른 경로다.
  if (digits.length <= 3) {
    return digits;
  }

  final StringBuffer buffer = StringBuffer();

  // 뒤에서부터 3자리마다 콤마를 넣는다.
  //
  // 앞쪽 그룹의 길이는 전체 길이의 나머지로 결정된다.
  // 예: '1234567' → 앞 그룹 '1' + '234' + '567'
  for (int i = 0; i < digits.length; i++) {
    // 남은 자리 수가 3의 배수가 되는 경계마다 콤마를 넣는다(맨 앞은 제외).
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }

    buffer.write(digits[i]);
  }

  return buffer.toString();
}

/// 관용(lenient) 진입점 — 임의의 문자열을 천 단위 콤마 형태로.
///
/// [input]의 비숫자를 먼저 제거하므로 이미 포맷된 값에도 **멱등**하게 동작한다
/// (`'4,500'` → `'4,500'`). 금액 입력 포매터·컨트롤러 동기화처럼
/// "화면 문자열"을 다루는 소비자용이다.
///
/// 예:
///
/// ```
/// ''         → ''
/// '4,500'    → '4,500'
/// ' 4500원 ' → '4,500'
/// ```
String formatThousands(String input) => groupThousands(digitsOnly(input));

/// 정수 금액(원)을 천 단위 콤마 문자열로. 예: `58500` → `'58,500'`.
///
/// 음수는 부호를 보존한다(`-1200` → `'-1,200'`). 계약 필드
/// `Gifticon.price`는 음수가 아니지만, 합계·차액 계산 등에서 음수가 들어와도
/// `-` 위치가 어긋나지 않도록 절댓값을 그룹핑한 뒤 부호를 앞에 붙인다.
///
/// 값이 `int`이므로 [digitsOnly] 정제를 거치지 않고 코어를 직접 호출한다.
///
/// **지원 범위**: 통상적인 금액 범위(수십억 원 단위까지)에서 올바르다.
/// 다음 극단값은 지원하지 않으며 debug 빌드에서 코어의 assert가 검출한다:
/// - VM의 `int64 최솟값`(abs()가 음수로 남는 유일한 값)
/// - web(dart2js)에서 1e21 이상(toString()이 지수 표기를 반환)
String formatWon(int won) {
  final String grouped = groupThousands(won.abs().toString());
  return won < 0 ? '-$grouped' : grouped;
}
