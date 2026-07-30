/// share 표시 포맷 헬퍼(share_format.dart) 출력 고정 테스트.
///
/// v2.4 승격에서 [formatExpiryLabel]·[formatInviteExpiry]가 정본
/// `formatYmdDot`에 위임하도록 바뀌었다. 이 테스트는 share 고유 조합
/// (`~` 접두, `HH:mm` 두 자리 패딩)의 **정확한 출력 문자열**을 고정해,
/// 위임 지점이나 조합 로직이 조용히 변하는 것을 막는다.
///
/// (승격 전에는 이 함수들의 출력을 고정하는 테스트가 없었다 —
/// 리포지토리 계층 테스트만 존재해 표시 문자열 회귀를 잡지 못했다)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/widgets/share_format.dart';

void main() {
  group('formatExpiryLabel', () {
    test("'~' 접두 + YYYY.MM.DD (월·일 두 자리 패딩)", () {
      expect(formatExpiryLabel(DateTime(2026, 9, 30)), '~2026.09.30');
      expect(formatExpiryLabel(DateTime(2026, 1, 2)), '~2026.01.02');
    });
  });

  group('formatInviteExpiry', () {
    test('YYYY.MM.DD HH:mm — 시·분 두 자리 패딩', () {
      expect(
        formatInviteExpiry(DateTime(2026, 7, 29, 15, 30)),
        '2026.07.29 15:30',
      );
      expect(
        formatInviteExpiry(DateTime(2026, 7, 29, 9, 5)),
        '2026.07.29 09:05',
      );
      expect(
        formatInviteExpiry(DateTime(2026, 12, 1, 0, 0)),
        '2026.12.01 00:00',
      );
    });
  });
}
