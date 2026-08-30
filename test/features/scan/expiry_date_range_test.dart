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

  group('지난 날짜 판정', () {
    final DateTime now = DateTime(2026, 8, 30, 14, 30);

    test('어제는 지났다', () {
      expect(isPastExpiry(DateTime(2026, 8, 29), now: now), isTrue);
    });

    test('오늘은 지나지 않았다 — 유효기간은 그날까지 유효하다', () {
      // 시각을 함께 비교하면 오늘 만료가 지난 것으로 잡힌다. 14:30에 열어도
      // 오늘 만료 기프티콘은 아직 쓸 수 있다.
      expect(isPastExpiry(DateTime(2026, 8, 30), now: now), isFalse);
    });

    test('같은 날이면 시각이 앞서도 지나지 않았다', () {
      // 자정(00:00)으로 들어온 값이 14:30과 비교돼 '지남'이 되면 안 된다.
      expect(isPastExpiry(DateTime(2026, 8, 30, 0, 0), now: now), isFalse);
    });

    test('내일은 지나지 않았다', () {
      expect(isPastExpiry(DateTime(2026, 8, 31), now: now), isFalse);
    });

    test('OCR이 흔히 내는 과거 연도는 지났다', () {
      expect(isPastExpiry(DateTime(2016, 2, 12), now: now), isTrue);
    });
  });
}
