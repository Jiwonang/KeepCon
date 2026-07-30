/// 공유 날짜 포맷 정본(`lib/shared/util/date_format.dart`) 단위 테스트.
///
/// 검증 포인트:
/// 1. 코어 [formatYmdDot]의 구분자·자리 채움(월/일 두 자리, 연도는 그대로)
/// 2. 시각·타임존을 무시하고 로컬 연/월/일만 쓰는지(자정·정오 경계)
/// 3. 도메인 밖 연도에 대한 debug assert
///
/// 소비자 쪽 조립(share의 `~` 접두·`HH:mm`, main의 D-day)은 각 페이지의 표현이므로
/// 여기서 검증하지 않는다 — 이 파일은 정본이 만드는 **표기 자체**를 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/util/date_format.dart';

void main() {
  group('formatYmdDot (코어)', () {
    test('점 구분자로 YYYY.MM.DD를 만든다', () {
      expect(formatYmdDot(DateTime(2026, 9, 30)), '2026.09.30');
      expect(formatYmdDot(DateTime(2026, 12, 31)), '2026.12.31');
      expect(formatYmdDot(DateTime(2030, 11, 25)), '2030.11.25');
    });

    test('한 자리 월·일을 두 자리로 채운다', () {
      expect(formatYmdDot(DateTime(2026, 1, 1)), '2026.01.01');
      expect(formatYmdDot(DateTime(2026, 7, 9)), '2026.07.09');
      expect(formatYmdDot(DateTime(2026, 10, 5)), '2026.10.05');
    });

    test('연도는 네 자리를 그대로 쓴다(패딩·절삭 없음)', () {
      expect(formatYmdDot(DateTime(1999, 12, 31)), '1999.12.31');
      expect(formatYmdDot(DateTime(9999, 1, 1)), '9999.01.01');
    });

    test('시·분·초는 라벨에 나타나지 않는다', () {
      // 같은 날짜의 자정·정오·자정 직전이 모두 같은 문자열이어야 한다
      // (초대 만료처럼 시각을 함께 담은 DateTime도 날짜 부분만 쓴다).
      expect(formatYmdDot(DateTime(2026, 7, 29)), '2026.07.29');
      expect(formatYmdDot(DateTime(2026, 7, 29, 12, 30)), '2026.07.29');
      expect(formatYmdDot(DateTime(2026, 7, 29, 23, 59, 59)), '2026.07.29');
    });

    test('윤년 2월 29일', () {
      expect(formatYmdDot(DateTime(2028, 2, 29)), '2028.02.29');
    });

    test('생성자 정규화로 넘어온 날짜도 정규화된 값을 따른다', () {
      // DateTime(2026, 13, 1)은 2027.01.01로 정규화된다 — 포맷은 정규화 결과를
      // 그대로 보여 주며, 범위 검사를 자기 책임으로 삼지 않는다.
      expect(formatYmdDot(DateTime(2026, 13, 1)), '2027.01.01');
    });

    test('네 자리 미만 연도는 debug 빌드에서 assert로 걸린다', () {
      // 연도를 패딩하지 않는 전제를 지키는 가드다 — 조용히 '12.01.02'를
      // 만들지 않고 파싱/생성 지점의 버그로 드러낸다.
      expect(() => formatYmdDot(DateTime(12, 1, 2)),
          throwsA(isA<AssertionError>()));
    });
  });
}
