/// 공유 금액 포맷 정본(`lib/shared/util/money_format.dart`) 단위 테스트.
///
/// 검증 포인트:
/// 1. 코어 [groupThousands]의 콤마 위치(3자리 이하 빠른 경로 포함)
/// 2. [digitsOnly]의 정제 범위
/// 3. 소비자별 진입점 — scan의 [formatThousands](관용·멱등),
///    main의 [formatWon](부호 보존)
///
/// "두 진입점의 결과 일치" 같은 비교 테스트는 두지 않는다 —
/// 둘 다 같은 파일의 같은 코어에 위임하므로 구조적으로 항진(절대 실패 불가)이다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/util/money_format.dart';

void main() {
  group('groupThousands (코어)', () {
    test('3자리 이하는 콤마를 넣지 않는다', () {
      expect(groupThousands(''), '');
      expect(groupThousands('0'), '0');
      expect(groupThousands('7'), '7');
      expect(groupThousands('45'), '45');
      expect(groupThousands('500'), '500');
    });

    test('뒤에서부터 3자리마다 콤마를 넣는다', () {
      expect(groupThousands('4500'), '4,500');
      expect(groupThousands('45000'), '45,000');
      expect(groupThousands('450000'), '450,000');
      expect(groupThousands('1234567'), '1,234,567');
      expect(groupThousands('1000000000'), '1,000,000,000');
    });

    test('그룹 경계(3의 배수 자릿수)에서 선행 콤마가 붙지 않는다', () {
      expect(groupThousands('100'), '100');
      expect(groupThousands('100000'), '100,000');
      expect(groupThousands('100000000'), '100,000,000');
    });
  });

  group('digitsOnly', () {
    test('숫자만 남긴다', () {
      expect(digitsOnly(''), '');
      expect(digitsOnly('4500'), '4500');
      expect(digitsOnly('4,500'), '4500');
      expect(digitsOnly(' 4500원 '), '4500');
      expect(digitsOnly('12,500 KRW'), '12500');
    });

    test('숫자가 없으면 빈 문자열', () {
      expect(digitsOnly('원'), '');
      expect(digitsOnly('-'), '');
    });
  });

  group('formatThousands (scan 진입점 — 관용)', () {
    test('비숫자를 제거한 뒤 그룹핑한다', () {
      expect(formatThousands(''), '');
      expect(formatThousands('0'), '0');
      expect(formatThousands('500'), '500');
      expect(formatThousands('4500'), '4,500');
      expect(formatThousands(' 4500원 '), '4,500');
      expect(formatThousands('1234567'), '1,234,567');
    });

    test('이미 포맷된 값에도 멱등하다', () {
      expect(formatThousands('4,500'), '4,500');
      expect(formatThousands(formatThousands('1234567')), '1,234,567');
    });

    test('부호는 숫자가 아니므로 버린다(입력 포매터 전제)', () {
      // 금액 입력창은 음수를 받지 않는다 — '-'는 비숫자로 제거된다.
      expect(formatThousands('-4500'), '4,500');
    });
  });

  group('formatWon (main 진입점 — 부호 보존)', () {
    test('정수 금액을 천 단위 콤마로', () {
      expect(formatWon(0), '0');
      expect(formatWon(500), '500');
      expect(formatWon(4500), '4,500');
      expect(formatWon(58500), '58,500');
      expect(formatWon(1234567), '1,234,567');
    });

    test('음수는 부호를 앞에 붙인다', () {
      expect(formatWon(-1200), '-1,200');
      expect(formatWon(-500), '-500');
      expect(formatWon(-1234567), '-1,234,567');
    });
  });
}
