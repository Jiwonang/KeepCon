// 초대코드 생성·형태 판정 (계약 대상 — `lib/shared/util/invite_code.dart`).
//
// 검증 대상:
// - newInviteCode: 항상 6자리 문자열이고, **선행 0을 보존**한다.
// - 10^6 전체를 쓴다(모듈로 바이어스 없이 경계값이 그대로 나온다).
// - isWellFormedInviteCode: 코드와 링크 토큰을 모양으로 가른다.
//
// 선행 0이 왜 테스트할 가치가 있나: `int`로 다루면 `012345`가 `12345`가 되어 **다른
// 코드**가 되고, 공간도 10^6에서 9·10^5로 조용히 줄어든다. 화면에서 읽은 값과 저장된
// 값이 어긋나는 종류의 결함이라 눈으로는 잘 안 보인다.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/util/invite_code.dart';
import 'package:keepcon/shared/util/invite_token.dart';

/// `nextInt`가 정해진 값을 순서대로 돌려주는 시험용 난수원.
///
/// 경계값(0, 999999)을 실제로 뽑아 보려면 난수를 고정할 수밖에 없다 —
/// [Random.secure]로는 그 두 값을 기다릴 수 없다.
class _ScriptedRandom implements Random {
  _ScriptedRandom(this._values);

  final List<int> _values;
  int _i = 0;

  @override
  int nextInt(int max) {
    expect(max, inviteCodeSpace,
        reason: '생성기는 10^6 전체를 요구해야 한다(공간을 좁히면 엔트로피가 준다)');
    return _values[_i++ % _values.length];
  }

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

void main() {
  group('newInviteCode', () {
    test('항상 6자리 숫자 문자열이다', () {
      for (int i = 0; i < 200; i++) {
        final String code = newInviteCode();
        expect(code.length, inviteCodeLength);
        expect(isWellFormedInviteCode(code), isTrue, reason: '생성값: $code');
      }
    });

    test('선행 0을 보존한다 — 0은 "000000"이지 "0"이 아니다', () {
      final String code = newInviteCode(random: _ScriptedRandom(<int>[0]));
      expect(code, '000000');
      expect(code.length, inviteCodeLength);
    });

    test('선행 0이 하나만 필요한 경우도 채운다', () {
      final String code = newInviteCode(random: _ScriptedRandom(<int>[12345]));
      expect(code, '012345');
    });

    test('공간의 최댓값도 그대로 나온다', () {
      final String code =
          newInviteCode(random: _ScriptedRandom(<int>[inviteCodeSpace - 1]));
      expect(code, '999999');
    });

    test('두 번 부르면 (거의 항상) 다른 값이다 — 상수가 아니다', () {
      // 10^6 공간에서 20개가 전부 같을 확률은 없다고 봐도 된다.
      final Set<String> seen = <String>{
        for (int i = 0; i < 20; i++) newInviteCode(),
      };
      expect(seen.length, greaterThan(1));
    });
  });

  group('isWellFormedInviteCode', () {
    test('6자리 숫자만 통과한다', () {
      // ⚠️ 예시 값으로 `482913`을 쓰지 않는다 — 그건 이 저장소의 **시드 링크 토큰**이다
      //    (v3.0 이전 토큰은 6자리였다). 두 공간이 겹친다는 사실이 여기서 흐려지면,
      //    "코드와 토큰은 모양으로 구분된다"는 잘못된 전제가 다시 자란다.
      expect(isWellFormedInviteCode('000000'), isTrue);
      expect(isWellFormedInviteCode('305177'), isTrue);
      expect(isWellFormedInviteCode('999999'), isTrue);
    });

    test('자릿수가 다르면 거부한다', () {
      expect(isWellFormedInviteCode('12345'), isFalse);
      expect(isWellFormedInviteCode('1234567'), isFalse);
      expect(isWellFormedInviteCode(''), isFalse);
    });

    test('숫자가 아닌 문자가 섞이면 거부한다', () {
      expect(isWellFormedInviteCode('12a456'), isFalse);
      expect(isWellFormedInviteCode('12-456'), isFalse);
      expect(isWellFormedInviteCode(' 12345'), isFalse);
      // 전각 숫자는 `int.parse`가 받아 주는 구현도 있어 따로 못박는다.
      expect(isWellFormedInviteCode('１２３４５６'), isFalse);
    });

    test('지금 발급되는 링크 토큰은 통과하지 않는다(128비트 · base64url 22자)', () {
      for (int i = 0; i < 200; i++) {
        expect(isWellFormedInviteCode(newInviteToken()), isFalse);
      }
    });

    test('⚠️ 레거시 6자리 링크 토큰은 통과한다 — 모양만으로는 구분되지 않는다', () {
      // v3.0(128비트) 이전 토큰은 6자리 숫자였고 그 값들이 아직 살아 있다(시드 포함).
      // 즉 이 판정자는 "코드일 **수도** 있다"만 말한다. 자격증명 해석이 이 값 하나로
      // 컬렉션을 **배타적으로** 고르면 그 링크들이 통째로 '없는 코드'가 된다 —
      // 실제로 그렇게 짰다가 리뷰에서 잡혔다. 해석부는 코드를 먼저 보되 빗나가면
      // 토큰도 봐야 한다(`ShareRepository.requestToJoin` 구현 참조).
      expect(isWellFormedInviteCode('482913'), isTrue,
          reason: '이 값은 이 저장소의 시드 **링크 토큰**이다');
    });
  });
}
