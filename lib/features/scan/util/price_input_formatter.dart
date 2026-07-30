/// 금액 입력 천 단위 콤마 포매터 (scan 페이지 로컬).
///
/// 사용자가 금액을 입력하는 동안 "4500" → "4,500"처럼 천 단위 콤마를
/// 실시간으로 붙여 준다.
///
/// 상태에는 콤마가 포함된 문자열이 그대로 저장돼도 문제없다 —
/// 계약 변환 지점인 `GifticonFormState.parsedPrice`가 콤마를 제거한 뒤
/// `int`로 파싱하기 때문이다(`price.replaceAll(',', '')`).
/// 따라서 이 포매터는 **표시 편의 전용**이며 계약에 영향을 주지 않는다.
///
/// 승격 상태 (CLAUDE.md 승격 워크플로):
/// 동일한 자릿수 그룹핑 로직이 main 페이지의 `formatWon`
/// (lib/features/main/widgets/format.dart)에도 존재한다 —
/// 즉 **두 번째 소비자가 이미 있어 승격 조건(규칙 ③)을 충족**한다.
/// 다만 승격은 lib/shared 변경(CODEOWNERS 리뷰)과 main 페이지 수정을
/// 동반하므로, "페이지 1개 = PR 1개" 원칙에 따라 이 PR에서는 로컬 사본을
/// 유지하고 `contract-architect`에게 공유 승격을 **별도 작업으로 요청**한다.
/// (승격 완료 시 이 파일의 formatThousands는 공유 헬퍼 소비로 대체할 것)
library;

import 'package:flutter/services.dart';

/// 숫자 이외의 문자.
final RegExp _nonDigits = RegExp(r'[^0-9]');

/// 선행 0 (예: "007"의 "00").
///
/// 키 입력마다 재컴파일하지 않도록 [_nonDigits]처럼 최상위에 둔다.
final RegExp _leadingZeros = RegExp(r'^0+');

/// 숫자만으로 이루어진 문자열에 천 단위 콤마를 넣는다.
///
/// 순수 함수이므로 단위 테스트로 검증한다.
///
/// 예:
///
/// ```
/// ''       → ''
/// '0'      → '0'
/// '4500'   → '4,500'
/// '1234567'→ '1,234,567'
/// ```
///
/// [digits]에 숫자 이외의 문자가 섞여 있으면 먼저 제거한다
/// (호출자가 이미 정제했더라도 안전하게 동작하도록).
String formatThousands(String digits) {
  final String clean = digits.replaceAll(_nonDigits, '');

  if (clean.length <= 3) {
    return clean;
  }

  final StringBuffer buffer = StringBuffer();

  // 뒤에서부터 3자리마다 콤마를 넣는다.
  //
  // 앞쪽 그룹의 길이는 전체 길이의 나머지로 결정된다.
  // 예: '1234567' → 앞 그룹 '1' + '234' + '567'
  for (int i = 0; i < clean.length; i++) {
    // 남은 자리 수가 3의 배수가 되는 경계마다 콤마를 넣는다(맨 앞은 제외).
    if (i > 0 && (clean.length - i) % 3 == 0) {
      buffer.write(',');
    }

    buffer.write(clean[i]);
  }

  return buffer.toString();
}

/// 입력 중 천 단위 콤마를 자동으로 유지하는 [TextInputFormatter].
///
/// 동작:
///
/// 1. 새 입력값에서 숫자만 남긴다(사용자가 붙여 넣은 콤마·공백·문자 제거).
/// 2. 의미 없는 선행 0을 제거한다. 단 "0" 한 자리는 남긴다
///    (무료/사은품 기프티콘의 금액 0은 계약상 유효한 값이다).
/// 3. [formatThousands]로 콤마를 넣는다.
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
    final String rawDigits = newValue.text.replaceAll(_nonDigits, '');

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
    final String formatted = formatThousands(digits);

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
