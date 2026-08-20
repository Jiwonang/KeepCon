// 초대 토큰 생성(newInviteToken) 단위 테스트.
//
// 이 값은 `inviteTokens/{token}` 문서의 **id**가 되고, 그 문서는 로그인한 누구나 id로
// 조회할 수 있다(목록 조회만 막혀 있다). 그래서 토큰이 좁으면 `list` 차단이 무의미해진다
// — 공간을 훑어 살아 있는 모든 그룹의 id를 긁을 수 있기 때문이다. 여기서 고정하는 것은
// 그 방어의 전제다: 충분한 길이, URL·문서 id 안전, 그리고 매번 다른 값.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/util/invite_token.dart';

void main() {
  test('URL·Firestore 문서 id로 안전한 문자만 쓴다', () {
    final RegExp safe = RegExp(r'^[A-Za-z0-9_-]+$');
    for (int i = 0; i < 200; i++) {
      final String t = newInviteToken();
      expect(safe.hasMatch(t), isTrue, reason: '안전하지 않은 문자: $t');
      // Firestore 문서 id 제약 — `.`/`..`/`__`로 시작·끝나는 이름과 `/`를 금지한다.
      expect(t.contains('/'), isFalse);
      expect(t.startsWith('__'), isFalse);
    }
  });

  test('패딩 없이 128비트를 담는 길이다', () {
    // base64url은 3바이트를 4자로 옮긴다 → 16바이트 = 22자(패딩 `=` 제거).
    expect(newInviteToken().length, 22);
  });

  test('매번 다른 값이다 — 좁은 공간이면 이 단언이 먼저 깨진다', () {
    final Set<String> seen = <String>{};
    for (int i = 0; i < 500; i++) {
      seen.add(newInviteToken());
    }
    expect(seen, hasLength(500));
  });

  test('주입한 난수원을 쓴다(테스트 전용 경로)', () {
    // 같은 시드를 준 두 생성기는 같은 값을 낸다 — 주입이 실제로 먹는지 확인한다.
    // 운영 경로는 Random.secure()이며, 예측 가능한 Random을 쓰면 열거 방어가 무너진다.
    expect(
      newInviteToken(random: Random(42)),
      newInviteToken(random: Random(42)),
    );
    expect(
      newInviteToken(random: Random(1)),
      isNot(newInviteToken(random: Random(2))),
    );
  });
}
