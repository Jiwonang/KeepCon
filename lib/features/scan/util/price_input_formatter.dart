/// 금액 입력 천 단위 콤마 포매터.
///
/// 커서 복원·선행 0 처리 같은 **입력 UX 로직만 scan 로컬**이고,
/// 콤마 포맷 자체의 정본은 `lib/shared/util/money_format.dart`다(아래 승격 상태).
///
/// 사용자가 금액을 입력하는 동안 "4500" → "4,500"처럼 천 단위 콤마를
/// 실시간으로 붙여 준다.
///
/// 상태에는 콤마가 포함된 문자열이 그대로 저장돼도 문제없다 —
/// 계약 변환 지점인 `GifticonFormState.parsedPrice`가 콤마를 제거한 뒤
/// `int`로 파싱하기 때문이다(`price.replaceAll(',', '')`).
/// 따라서 이 포매터는 **표시 편의 전용**이며 계약에 영향을 주지 않는다.
///
/// 승격 상태 (CLAUDE.md 승격 워크플로): **승격 완료**.
/// 자릿수 그룹핑 로직은 main 페이지의 `formatWon`과 겹쳐 두 번째 소비자가
/// 확인됐고(규칙 ③), 공유 정본 `lib/shared/util/money_format.dart`로 승격했다.
/// 이 파일의 [formatThousands]는 이제 로컬 사본이 아니라 그 정본의 재export이며,
/// 아래 [ThousandsSeparatorInputFormatter]도 정본의 `digitsOnly`를 소비한다.
/// (입력 중 커서 위치·선행 0 처리는 scan 입력 UX 고유 로직이므로 로컬에 남긴다)
library;

import 'package:flutter/services.dart';

// 실제로 소비하는 심벌만 가져온다 — formatWon 등 나머지가
// 이 파일 스코프에 암묵적으로 들어오지 않게 한다.
import '../../../shared/util/money_format.dart' show digitsOnly, groupThousands;

/// 공유 정본의 천 단위 포맷 함수를 그대로 노출한다.
///
/// `gifticon_form.dart` 등 기존 소비자가 import 경로를 바꾸지 않고 쓰도록
/// 재export하며, 구현은 `lib/shared/util/money_format.dart` 한 곳뿐이다.
export '../../../shared/util/money_format.dart' show formatThousands;

/// 선행 0 (예: "007"의 "00").
///
/// 키 입력마다 재컴파일하지 않도록 최상위에 둔다.
final RegExp _leadingZeros = RegExp(r'^0+');

/// 입력 중 천 단위 콤마를 자동으로 유지하는 [TextInputFormatter].
///
/// 동작:
///
/// 1. 새 입력값에서 숫자만 남긴다(사용자가 붙여 넣은 콤마·공백·문자 제거).
/// 2. 의미 없는 선행 0을 제거한다. 단 "0" 한 자리는 남긴다
///    (무료/사은품 기프티콘의 금액 0은 계약상 유효한 값이다).
/// 3. 코어 [groupThousands]로 콤마를 넣는다.
///    (1단계에서 이미 숫자만 남겼으므로 관용 진입점 [formatThousands]의
///    비숫자 재정제를 거치지 않는다 — 키 입력마다의 중복 정규식 제거)
/// 4. 커서를 "원래 커서 앞에 있던 숫자 개수" 뒤로 다시 놓는다.
///    (그냥 문자열 끝으로 보내면 중간을 수정할 때 커서가 튄다)
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  const ThousandsSeparatorInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // ── 1단계: 숫자만 추출 ──
    //
    // 공유 정본의 [digitsOnly]를 쓴다(정규식 사본을 두지 않는다).
    final String rawDigits = digitsOnly(newValue.text);

    // 전부 지운 경우 — 빈 값으로 돌려준다.
    //
    // `TextEditingValue.empty`는 selection.baseOffset이 -1(선택 없음)이라
    // 커서 위치를 0으로 명시해 돌려준다.
    if (rawDigits.isEmpty) {
      return const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // ── 2단계: 선행 0 제거(단, 최소 한 자리는 남긴다) ──
    //
    // '007' → '7', '0' → '0', '00' → '0'
    String digits = rawDigits.replaceFirst(_leadingZeros, '');

    if (digits.isEmpty) {
      digits = '0';
    }

    // ── 3단계: 콤마 삽입 ──
    //
    // digits는 1단계에서 정제됐으므로 코어를 직접 호출한다
    // (formatThousands를 쓰면 digitsOnly가 한 번 더 돈다).
    final String formatted = groupThousands(digits);

    // ── 4단계: 커서 위치 복원 ──
    //
    // selection이 없는(-1) 경우는 문자열 끝으로 본다.
    final int rawOffset = newValue.selection.baseOffset < 0
        ? newValue.text.length
        : newValue.selection.baseOffset;

    final int safeOffset = rawOffset.clamp(0, newValue.text.length);

    // 커서 앞에 있던 "숫자"의 개수.
    //
    // substring/replaceAll로 중간 문자열을 만들지 않고
    // codeUnit을 직접 세어 키 입력마다의 할당을 없앤다.
    int digitsBeforeCursor = 0;

    for (int i = 0; i < safeOffset; i++) {
      if (_isDigitCodeUnit(newValue.text.codeUnitAt(i))) {
        digitsBeforeCursor++;
      }
    }

    // 선행 0을 제거한 만큼 커서 앞 숫자 개수도 줄여야 위치가 어긋나지 않는다.
    final int strippedLeadingZeros = rawDigits.length - digits.length;

    digitsBeforeCursor =
        (digitsBeforeCursor - strippedLeadingZeros).clamp(0, digits.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _offsetAfterNthDigit(formatted, digitsBeforeCursor),
      ),
      composing: TextRange.empty,
    );
  }

  /// [text]에서 [n]번째 숫자 바로 뒤의 인덱스를 구한다.
  ///
  /// [n]이 0이면 0(맨 앞), [text]의 숫자 개수보다 크면 문자열 끝을 반환한다.
  static int _offsetAfterNthDigit(String text, int n) {
    if (n <= 0) {
      return 0;
    }

    int seen = 0;

    for (int i = 0; i < text.length; i++) {
      // 콤마는 세지 않는다.
      // (한 글자 substring + 정규식 대신 codeUnit 비교 — 할당 없음)
      if (_isDigitCodeUnit(text.codeUnitAt(i))) {
        seen++;

        if (seen == n) {
          return i + 1;
        }
      }
    }

    return text.length;
  }

  /// [codeUnit]이 ASCII 숫자('0'~'9')인지.
  static bool _isDigitCodeUnit(int codeUnit) {
    return codeUnit >= 0x30 && codeUnit <= 0x39;
  }
}
