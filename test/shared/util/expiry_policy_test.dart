/// 만료 판정 정책(SSOT) 테스트.
///
/// 승격 전 구현들이 서로 다른 답을 내던 지점을 회귀로 고정한다:
/// 시분초 절삭, 만료 당일 경계, 이미 만료된 항목의 임박 오분류.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/util/expiry_policy.dart';

void main() {
  // 기준 시각을 "오늘 오후 3시"로 잡는다 — 시분초가 계산에 새는지 드러내려면
  // 자정이 아닌 시각이어야 한다.
  final DateTime now = DateTime(2026, 8, 7, 15, 30);

  group('daysUntilExpiry', () {
    test('오늘 만료면 0 — 만료일의 시각과 무관하다', () {
      // 자정 직후든 밤 11시든 "오늘"은 0이어야 한다. 승격 전 통계 구현은
      // difference().inDays로 절삭해 자정 만료를 -1, 밤 만료를 0으로 갈랐다.
      expect(daysUntilExpiry(DateTime(2026, 8, 7), now: now), 0);
      expect(daysUntilExpiry(DateTime(2026, 8, 7, 23, 59), now: now), 0);
    });

    test('내일 만료면 1 — 남은 시간이 24시간 미만이어도 하루로 센다', () {
      // now가 15:30이므로 내일 자정까지는 8시간 30분뿐이다. 시각 기반 계산은
      // 이걸 0일로 절삭하지만, 사용자가 읽는 D-day는 1이다.
      expect(daysUntilExpiry(DateTime(2026, 8, 8), now: now), 1);
    });

    test('지난 날짜는 음수', () {
      expect(daysUntilExpiry(DateTime(2026, 8, 6), now: now), -1);
      expect(daysUntilExpiry(DateTime(2026, 7, 31), now: now), -7);
    });

    test('월·연 경계를 넘어도 달력 일수로 센다', () {
      expect(daysUntilExpiry(DateTime(2026, 9, 1), now: now), 25);
      expect(
        daysUntilExpiry(DateTime(2027, 1, 1), now: DateTime(2026, 12, 25, 9)),
        7,
      );
    });

    test('윤년 2월을 건너뛰어도 정확하다', () {
      expect(
        daysUntilExpiry(DateTime(2028, 3, 1), now: DateTime(2028, 2, 28, 20)),
        2, // 2028은 윤년이라 2/29가 낀다.
      );
    });
  });

  group('isExpiredByDate', () {
    test('만료일 당일은 아직 만료가 아니다', () {
      // "2026-08-07까지"는 그 날을 포함하는 표기다.
      expect(isExpiredByDate(DateTime(2026, 8, 7), now: now), isFalse);
    });

    test('하루라도 지나면 만료', () {
      expect(isExpiredByDate(DateTime(2026, 8, 6), now: now), isTrue);
    });
  });

  group('isExpiringSoon', () {
    test('기준 일수 경계를 포함한다', () {
      expect(isExpiringSoon(DateTime(2026, 8, 14), now: now), isTrue); // D-7
      expect(isExpiringSoon(DateTime(2026, 8, 15), now: now), isFalse); // D-8
    });

    test('오늘 만료도 임박이다', () {
      expect(isExpiringSoon(DateTime(2026, 8, 7), now: now), isTrue);
    });

    test('이미 만료된 것은 임박이 아니다', () {
      // 승격 전 통계의 `daysLeft <= 7`은 음수도 통과시켜 만료된 항목을
      // "만료 임박"으로 셌다. 이 회귀를 고정한다.
      expect(isExpiringSoon(DateTime(2026, 8, 6), now: now), isFalse);
      expect(isExpiringSoon(DateTime(2026, 1, 1), now: now), isFalse);
    });

    test('경계 상수가 바뀌어도 정의와 일치한다', () {
      final DateTime boundary = now.add(const Duration(days: expirySoonDays));
      expect(isExpiringSoon(boundary, now: now), isTrue);
      expect(
        isExpiringSoon(
          now.add(const Duration(days: expirySoonDays + 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
