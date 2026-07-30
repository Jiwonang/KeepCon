/// 금액 입력 천 단위 콤마 포매터 단위 테스트.
///
/// 검증 포인트:
/// 1. 순수 그룹핑 함수([formatThousands])의 콤마 위치
/// 2. [ThousandsSeparatorInputFormatter]의 입력 중 동작(선행 0·커서 위치)
/// 3. 계약 경계 — 콤마가 붙은 문자열이 `GifticonFormState.parsedPrice`에서
///    다시 int로 파싱되는지(포매터가 계약을 깨지 않음)
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/util/price_input_formatter.dart';

/// 사용자가 [text]를 입력하고 커서가 맨 뒤에 있는 상태를 만든다.
TextEditingValue _typed(String text) {
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}

void main() {
  group('formatThousands', () {
    test('3자리 이하는 콤마를 넣지 않는다', () {
      expect(formatThousands(''), '');
      expect(formatThousands('0'), '0');
      expect(formatThousands('45'), '45');
      expect(formatThousands('500'), '500');
    });

    test('천 단위마다 콤마를 넣는다', () {
      expect(formatThousands('4500'), '4,500');
      expect(formatThousands('45000'), '45,000');
      expect(formatThousands('450000'), '450,000');
      expect(formatThousands('1234567'), '1,234,567');
      expect(formatThousands('1000000000'), '1,000,000,000');
    });

    test('숫자 이외의 문자는 무시한다', () {
      expect(formatThousands('4,500'), '4,500');
      expect(formatThousands(' 4500원 '), '4,500');
    });
  });

  group('ThousandsSeparatorInputFormatter', () {
    const ThousandsSeparatorInputFormatter formatter =
        ThousandsSeparatorInputFormatter();

    test('입력 중 천 단위 콤마를 자동으로 붙인다', () {
      final TextEditingValue result = formatter.formatEditUpdate(
        _typed('450'),
        _typed('4500'),
      );

      expect(result.text, '4,500');

      // 커서는 문자열 끝(숫자 4개 뒤)에 있어야 한다.
      expect(result.selection.baseOffset, '4,500'.length);
    });

    test('이미 콤마가 있는 값에 이어서 입력해도 콤마가 재정렬된다', () {
      // 화면에는 "4,500"이 있고 사용자가 뒤에 0을 붙여 "4,5000"이 된 상태.
      final TextEditingValue result = formatter.formatEditUpdate(
        _typed('4,500'),
        _typed('4,5000'),
      );

      expect(result.text, '45,000');
    });

    test('무료/사은품 금액 0은 유지한다(계약상 유효한 값)', () {
      final TextEditingValue result = formatter.formatEditUpdate(
        _typed(''),
        _typed('0'),
      );

      expect(result.text, '0');
    });

    test('의미 없는 선행 0은 제거한다', () {
      expect(
        formatter.formatEditUpdate(_typed('0'), _typed('05')).text,
        '5',
      );

      expect(
        formatter.formatEditUpdate(_typed('00'), _typed('007')).text,
        '7',
      );

      // 전부 0이면 한 자리는 남긴다.
      expect(
        formatter.formatEditUpdate(_typed('0'), _typed('00')).text,
        '0',
      );
    });

    test('모두 지우면 빈 값이 된다', () {
      final TextEditingValue result = formatter.formatEditUpdate(
        _typed('4,500'),
        _typed(''),
      );

      expect(result.text, '');
      expect(result.selection.baseOffset, 0);
    });

    test('중간을 수정해도 커서가 문자열 끝으로 튀지 않는다', () {
      // "1,234,567"에서 앞쪽 '1' 바로 뒤(offset 1)에 '9'를 넣어 "19,234,567".
      const TextEditingValue newValue = TextEditingValue(
        text: '19,234,567',
        selection: TextSelection.collapsed(offset: 2),
      );

      final TextEditingValue result = formatter.formatEditUpdate(
        _typed('1,234,567'),
        newValue,
      );

      expect(result.text, '19,234,567');

      // 커서 앞 숫자는 '1','9' 두 개 → 포맷 후에도 두 번째 숫자 뒤.
      expect(result.selection.baseOffset, 2);
    });

    test('숫자가 아닌 문자를 붙여 넣으면 제거된다', () {
      final TextEditingValue result = formatter.formatEditUpdate(
        _typed(''),
        _typed('4,500원'),
      );

      expect(result.text, '4,500');
    });
  });

  group('계약 경계 — 콤마 포함 문자열도 parsedPrice가 int로 변환한다', () {
    test('포매터 결과를 폼 상태에 넣어도 price 파싱이 깨지지 않는다', () {
      const ThousandsSeparatorInputFormatter formatter =
          ThousandsSeparatorInputFormatter();

      final String formatted = formatter
          .formatEditUpdate(
            _typed('123456'),
            _typed('1234567'),
          )
          .text;

      expect(formatted, '1,234,567');

      final GifticonFormState state = GifticonFormState(price: formatted);

      // 계약(Gifticon.price: int)으로 넘어가는 값은 콤마가 제거된 정수다.
      expect(state.parsedPrice, 1234567);

      // 필수 필드가 채워진 상태라면 금액 때문에 검증이 실패하지 않는다.
      final GifticonFormState valid = GifticonFormState(
        brand: '스타벅스',
        productName: '아메리카노 T',
        price: formatted,
        expiryDate: DateTime(2026, 12, 31),
      );

      expect(valid.validate(), isNull);
    });

    test('금액 0도 검증을 통과한다', () {
      final GifticonFormState state = GifticonFormState(
        brand: '스타벅스',
        productName: '사은품 쿠폰',
        price: '0',
        expiryDate: DateTime(2026, 12, 31),
      );

      expect(state.parsedPrice, 0);
      expect(state.validate(), isNull);
    });
  });
}
