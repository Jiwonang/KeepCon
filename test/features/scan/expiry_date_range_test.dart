/// scan — 유효기간 범위·지난 날짜 판정.
///
/// 이 규칙이 지키는 것은 둘이다:
///
/// 1. **피커가 죽지 않는 것.** `showDatePicker`는 `initialDate`가
///    `firstDate`~`lastDate` 밖이면 assert로 죽는다. 폼이 들고 있는 값은 사용자가
///    고른 것이 아니라 **OCR이 프리필한 것**이라 범위 밖일 수 있다 — 파서는
///    이미지에 적힌 대로 읽으므로 2020년 이전도 낸다
///    (`gifticon_ocr_fixture_test.dart`가 `DateTime(2016, 2, 12)`로 못박고 있다).
/// 2. **지난 날짜를 알리되 막지는 않는 것.** `GifticonStatus.expired`가 계약상
///    정상 상태라 이미 만료된 것을 기록해 두는 것도 정당한 사용이다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/util/expiry_date_range.dart';

void main() {
  group('고를 수 있는 범위', () {
    test('하한이 상한보다 앞선다', () {
      // 뒤집히면 showDatePicker가 assert로 죽는다(lastDate >= firstDate).
      expect(expirySelectableFrom.isBefore(expirySelectableTo), isTrue);
    });

    test('OCR이 내는 과거 날짜는 하한 밖이다 — 클램프가 필요한 이유', () {
      // 이 단언이 깨지면(=하한이 2016보다 앞서면) 클램프가 불필요해진 것이
      // 아니라, 픽스처가 바뀐 것이다. 그때는 이 테스트가 아니라 근거를 다시 봐야 한다.
      expect(DateTime(2016, 2, 12).isBefore(expirySelectableFrom), isTrue);
    });
  });
}
