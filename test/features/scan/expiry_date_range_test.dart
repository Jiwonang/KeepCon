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

    test('상한은 어느 해든 그 해의 마지막 날이다 — 월·일 생략 금지', () {
      // 상한이 `DateTime(2035)`(=2035-01-01)이던 시절에는 그 해 364일이 잘렸다.
      // "2035년까지"로 읽히는 표기가 실제로는 "2035년 첫날까지"였던 것이다.
      //
      // ⚠️ **연도를 박아 검사하지 않는다.** `DateTime(2035, 7, 1)`이 범위 안인지로
      // 고정하면 상한을 `DateTime(2040)`으로 옮겼을 때 **그대로 통과한다** — 같은
      // 결함이 재발했는데 CI는 초록이다. 지켜야 하는 규칙은 "2035년 연말"이 아니라
      // **"어느 해로 옮기든 12/31"** 이므로 그것을 직접 본다.
      expect(expirySelectableTo.month, 12);
      expect(expirySelectableTo.day, 31);
    });

    test('하한은 어느 해든 그 해의 첫날이다 — 상한과 반대편이다', () {
      // 상한의 "월·일 생략 금지"를 이쪽에 적용해 `DateTime(2020, 12, 31)`로
      // 고치면 2020년의 364일이 조용히 잘린다 — OCR이 낸 2020-03-15를 클램프가
      // 연말로 밀어 올려 피커가 엉뚱한 날에서 열린다.
      //
      // 그런데 기존 단언만으로는 **아무것도 죽지 않는다**(뮤테이션 확인: scan
      // 149건 전부 초록). `from < to`는 그때도 참이고 하한 관련 단언은 2016년만
      // 본다. 상한만 지키면 "왜 얘는 생략하지" 하는 다음 사람이 CI 초록을 믿는다.
      expect(expirySelectableFrom.month, 1);
      expect(expirySelectableFrom.day, 1);
    });
  });
}
