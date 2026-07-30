/// 유효기간 빠른 선택(+30일/+90일/+1년) 계산 검증.
///
/// 이 값은 계약 필수 필드인 `Gifticon.expiryDate`로 그대로 들어간다.
/// 계산이 틀리면 메인 페이지의 만료임박순 정렬·만료 판정이 함께 틀어지므로
/// 달력 경계(월말/연말/윤년)와 자정 정규화를 명시적으로 고정한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/util/expiry_quick_pick.dart';

void main() {
  group('ExpiryQuickPick.resolve', () {
    test('+30일 / +90일 / +1년 기본 계산', () {
      final DateTime base = DateTime(2026, 7, 30);

      expect(
        ExpiryQuickPick.after30Days.resolve(base),
        DateTime(2026, 8, 29),
      );

      expect(
        ExpiryQuickPick.after90Days.resolve(base),
        DateTime(2026, 10, 28),
      );

      expect(
        ExpiryQuickPick.afterOneYear.resolve(base),
        DateTime(2027, 7, 30),
      );
    });

    test('월말/연말을 넘어가는 경우도 달력 기준으로 이월된다', () {
      // 12월 말 → 이듬해로 넘어간다.
      expect(
        ExpiryQuickPick.after30Days.resolve(DateTime(2026, 12, 20)),
        DateTime(2027, 1, 19),
      );

      // 1월 31일 + 30일 → 3월 2일 (2026년 2월은 28일)
      expect(
        ExpiryQuickPick.after30Days.resolve(DateTime(2026, 1, 31)),
        DateTime(2026, 3, 2),
      );
    });

    test('윤년 2월 29일 + 1년은 2월 28일로 클램프된다(이월 금지)', () {
      // 2025-02-29는 존재하지 않는다. DateTime 정규화(3/1 이월)를 그대로 쓰면
      // 실제 유효기간보다 늦은 만료일이 저장되므로,
      // 만료일은 안전한 짧은 쪽(그 달의 마지막 날)으로 클램프한다.
      expect(
        ExpiryQuickPick.afterOneYear.resolve(DateTime(2024, 2, 29)),
        DateTime(2025, 2, 28),
      );
    });

    test('윤년 2월 29일을 지나는 +90일 계산', () {
      // 2024-01-01 + 90일 → 2024-03-31 (2024년 2월은 29일)
      expect(
        ExpiryQuickPick.after90Days.resolve(DateTime(2024, 1, 1)),
        DateTime(2024, 3, 31),
      );
    });

    test('기준일의 시각은 버리고 자정으로 정규화한다', () {
      // DateTime.now()처럼 시·분·초가 있는 값이 들어와도
      // DatePicker 결과(자정)와 형태가 같아야 한다.
      final DateTime noisyBase = DateTime(2026, 7, 30, 23, 59, 59, 999, 999);

      final DateTime resolved = ExpiryQuickPick.after30Days.resolve(noisyBase);

      expect(resolved, DateTime(2026, 8, 29));
      expect(resolved.hour, 0);
      expect(resolved.minute, 0);
      expect(resolved.second, 0);
      expect(resolved.millisecond, 0);
      expect(resolved.microsecond, 0);
    });

    test('모든 옵션은 기준일보다 미래이며 라벨을 가진다', () {
      final DateTime base = DateTime(2026, 7, 30);

      for (final ExpiryQuickPick pick in ExpiryQuickPick.values) {
        expect(
          pick.resolve(base).isAfter(base),
          isTrue,
          reason: '${pick.name}은 기준일보다 미래여야 한다',
        );

        expect(pick.label, isNotEmpty);
      }
    });
  });
}
