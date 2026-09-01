/// 그룹 문서 매퍼의 **등급 배정**을 소스에서 직접 고정하는 테스트.
///
/// `FirebaseShareRepository`는 그룹 문서를 읽는 매퍼를 "무엇을 되쓰는가"에 따라 셋으로
/// 나눠 쓴다. 등급이 어긋나면 두 방향으로 사고가 난다:
///
/// - **너무 약하면** 관대 매퍼의 폴백이 [_groupToDoc]으로 굳는다(손상이 정상 값이 된다).
/// - **너무 강하면** 되쓰지 않는 경로까지 막혀, 손상된 그룹을 삭제하거나 나갈 수조차 없다
///   — 앱 안의 유일한 복구 경로가 사라진다. 실제로 한 번 그렇게 만들었다가 리뷰에서 잡혔다.
///
/// 그런데 이 배정은 **일반 테스트로는 보이지 않는다.** 매퍼 본체는 순수 static 함수라
/// 직접 검증하지만, 호출부는 `DocumentSnapshot`을 받는 인스턴스 메서드라 Firestore 없이
/// 실행할 수 없다. 그래서 호출부의 등급을 되돌려도 매퍼 테스트는 전부 통과한다.
///
/// 그 구멍을 소스 검사로 메운다 — 트랜잭션이 `_groupToDoc`으로 문서 전체를 되쓰면 반드시
/// 전체 되쓰기 매퍼를 쓰고, `_memberIdsPatch`로 멤버십을 되쓰면 최소 멤버십 매퍼를 쓴다.
/// 파싱이 아니라 "메서드 본문 안에 두 심볼이 함께 있는가"만 보므로 리팩터링에 둔감하다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 저장소 소스를 메서드 단위로 쪼갠다.
///
/// Dart를 파싱하지 않는다 — 이 파일의 메서드는 전부 두 칸 들여쓰기로 시작하므로, 그 경계로
/// 자르는 것으로 충분하다. 경계 규칙이 깨지면 아래 "호출부를 하나도 못 찾았다" 단언이 먼저
/// 실패해 테스트가 조용히 무력해지지 않는다.
Map<String, String> _methodBodies(String source) {
  // 2칸 들여쓰기로 시작해 파라미터 목록 `(`를 여는 줄 = 멤버 선언이고, 이름은 그 `(`
  // 바로 앞 식별자다. 탐욕적으로 잡으면 `async {`의 `async`를 이름으로 오인한다.
  final RegExp start = RegExp(
    r'^  (?:static\s+)?[A-Za-z_][^\n(]*?(\w+)\(',
    multiLine: true,
  );
  final List<RegExpMatch> heads = start.allMatches(source).toList();
  final Map<String, String> bodies = <String, String>{};
  for (int i = 0; i < heads.length; i++) {
    final int from = heads[i].start;
    final int to = i + 1 < heads.length ? heads[i + 1].start : source.length;
    // 같은 이름이 여러 번 잡히면(오버로드는 Dart에 없지만 게터/래퍼가 있을 수 있다)
    // 본문을 이어 붙여 "이 이름 아래 어디선가 쓰인다"로 본다.
    bodies[heads[i].group(1)!] =
        (bodies[heads[i].group(1)!] ?? '') + source.substring(from, to);
  }
  return bodies;
}

/// `requestToJoin`의 **코드→링크 폴백** 조회를 가리키는 앵커.
///
/// 한 곳에 모아 둔 것은 개명 시 고칠 자리를 하나로 만들기 위해서다(소스 검사는 식별자
/// 이름에 묶인다 — 그 한계는 아래 group 머리말에 적었다).
const String _fallbackAnchor = 'credDoc = await _inviteTokens';

/// [body]에서 폴백 블록이 닫히는 `}`의 위치. 앵커나 짝이 없으면 `null`.
///
/// **첫 `}`를 찾지 않고 깊이를 센다.** 블록 안에 문자열 보간(`${…}`)이나 중첩 블록이
/// 하나만 생겨도 첫 `}`는 그 자리에서 멈춰 창이 잘리고, **동작이 그대로인데** 단언이
/// 실패한다. 소스 검사 테스트의 값어치는 리팩터링에 둔감한 것이므로(이 파일 머리말)
/// 그 취약함을 남겨 둘 이유가 없다.
///
/// 여는 `{`를 거꾸로 찾지 않는 것도 같은 이유다 — 앵커 **앞**에 보간이 생기면 그
/// `${`를 블록 시작으로 오인한다. 앵커가 이미 블록 안이므로 깊이 1에서 시작해 앞으로만
/// 센다.
int? _fallbackBlockEnd(String body) {
  final int at = body.indexOf(_fallbackAnchor);
  if (at < 0) return null;
  int depth = 1;
  for (int i = at; i < body.length; i++) {
    if (body[i] == '{') {
      depth++;
    } else if (body[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// 폴백 블록에서 앵커 **이후** 블록이 닫힐 때까지의 본문. 못 찾으면 `null`.
String? _fallbackBlockTail(String body) {
  final int? end = _fallbackBlockEnd(body);
  if (end == null) return null;
  return body.substring(body.indexOf(_fallbackAnchor), end);
}

void main() {
  final File file = File(
    'lib/shared/repositories/impl/firebase/firebase_share_repository.dart',
  );

  late Map<String, String> bodies;

  setUpAll(() {
    expect(file.existsSync(), isTrue,
        reason: '경로가 바뀌었으면 이 테스트도 함께 옮겨야 한다: ${file.path}');
    bodies = _methodBodies(file.readAsStringSync());
  });

  test('메서드 경계를 실제로 찾아낸다(테스트가 조용히 무력해지지 않게)', () {
    // 아래 단언들은 "본문에 심볼이 없다"로도 통과할 수 있다. 경계 파싱이 살아 있는지를
    // 먼저 고정해, 정규식이 깨졌을 때 여기서 먼저 실패하게 한다.
    // 카나리아는 **전체 되쓰기를 실제로 하는** 메서드여야 한다 — 본문에 심볼이
    // 없어도 통과하는 단언들과 달리, 이건 파싱이 살아 있어야만 통과한다.
    // (v3.8 전에는 `joinGroup`이 이 자리였다. 그 메서드가 삭제되면서 옮겼다 —
    //  카나리아가 사라지면 이 테스트가 조용히 무력해진다.)
    expect(bodies.keys, contains('approveJoinRequest'));
    expect(bodies.keys, contains('leaveGroup'));
    expect(bodies.keys, contains('deleteGroup'));
    expect(bodies['approveJoinRequest'], contains('_groupToDoc('));
  });

  test('문서 전체를 되쓰는 트랜잭션은 전체 되쓰기 매퍼를 쓴다', () {
    final Iterable<String> fullWriters = bodies.entries
        .where((MapEntry<String, String> e) =>
            e.key != '_groupToDoc' && e.value.contains('_groupToDoc('))
        .map((MapEntry<String, String> e) => e.key);

    expect(fullWriters, isNotEmpty, reason: '_groupToDoc 호출부를 하나도 못 찾았다');

    for (final String name in fullWriters) {
      final String body = bodies[name]!;
      // createGroup은 문서를 새로 만드는 쪽이라 읽는 매퍼가 없다.
      if (!body.contains('_groupFromDoc')) continue;
      expect(
        body,
        contains('_groupFromDocForFullWrite('),
        reason: '$name은 _groupToDoc으로 문서 전체를 되쓰므로 전체 되쓰기 매퍼를 써야 한다 '
            '— 관대 매퍼를 쓰면 흡수된 폴백이 정상 값으로 굳는다',
      );
    }
  });

  test('멤버십을 파생해 되쓰는 트랜잭션은 최소 멤버십 매퍼를 쓴다', () {
    final Iterable<String> membershipWriters = bodies.entries
        .where((MapEntry<String, String> e) =>
            e.key != '_memberIdsPatch' && e.value.contains('_memberIdsPatch('))
        .map((MapEntry<String, String> e) => e.key);

    expect(membershipWriters, isNotEmpty,
        reason: '_memberIdsPatch 호출부를 하나도 못 찾았다');

    for (final String name in membershipWriters) {
      final String body = bodies[name]!;
      expect(
        body.contains('_groupFromDocForMembershipWrite(') ||
            body.contains('_groupFromDocForFullWrite('),
        isTrue,
        reason: '$name은 멤버십을 파생해 되쓰므로 최소 멤버십 매퍼를 써야 한다 '
            '— 걸러진 멤버가 그대로 되쓰이면 문서에서 영구히 사라진다',
      );
    }
  });

  test('되쓰지 않는 트랜잭션은 엄격 매퍼를 쓰지 않는다', () {
    // 너무 강한 등급도 사고다 — 손상 그룹의 삭제·설정 되돌리기가 막혀 복구 경로가 사라진다.
    for (final String name in <String>[
      'deleteGroup',
      'setInviteOwnerOnly',
      'regenerateInviteToken',
      'shareGifticon',
    ]) {
      final String body = bodies[name]!;
      expect(body.contains('_groupToDoc('), isFalse,
          reason: '$name이 문서 전체를 되쓰게 됐다면 등급을 올려야 한다');
      expect(body.contains('_memberIdsPatch('), isFalse,
          reason: '$name이 멤버십을 되쓰게 됐다면 등급을 올려야 한다');
      expect(
        body.contains('_groupFromDocForFullWrite(') ||
            body.contains('_groupFromDocForMembershipWrite('),
        isFalse,
        reason: '$name은 되쓰지 않으므로 엄격 매퍼를 쓸 이유가 없다 '
            '— 막으면 손상 문서의 앱 내 복구 경로가 사라진다',
      );
    }
  });

  group('requestToJoin — 자격증명 종류(isCode) 판정', () {
    // `isCode`는 만료 안내를 가르는 근거다(계약 참조) — 코드는 "새 코드를 요청", 링크는
    // "링크 재발급을 요청"으로 다음 행동이 다르다. 판정이 틀리면 만료된 6자리 **링크**가
    // "만료된 코드"로 안내되고, 사용자가 코드를 받아 와도 링크는 그대로다.
    //
    // ⚠️ 이 계층에만 커버리지가 없다. in-memory 구현은 `share_repository_invite_code_test`
    //    두 케이스가 양방향으로 고정하지만, `flutter test`는 in-memory만 돌리므로 여기서
    //    `isCode = false`를 지워도 전 테스트가 통과한다(뮤테이션으로 확인했다). 위 매퍼
    //    등급과 똑같이 "호출부가 Firestore 없이 실행되지 않는" 구멍이라 같은 방법으로 막는다.

    // ⚠️ 아래 단언들은 지역변수 이름 `isCode`·`codeShaped`와 폴백 조회 심볼
    //    `_inviteTokens`에 묶여 있다. 소스 검사의 원리적 한계이므로 **개명하면 여기도
    //    함께 옮긴다** — 안 옮기면 동작이 멀쩡한데 시끄럽게 실패한다(거짓 통과는 아니다).

    test('코드 조회가 빗나가면 링크 토큰으로 폴백한다', () {
      // 폴백 자체가 사라지면 레거시 6자리 링크가 통째로 '없는 코드'가 된다 — 종류 판정
      // 이전에 참여 경로가 막히는 더 큰 사고라, 아래 단언의 전제로 먼저 고정한다.
      final String body = bodies['requestToJoin'] ?? '';
      expect(body, isNotEmpty,
          reason: 'requestToJoin을 못 찾았다 — 이 테스트가 조용히 무력해졌다');
      expect(body, contains(_fallbackAnchor),
          reason: '코드→링크 폴백이 사라지면 레거시 6자리 링크 토큰이 전부 막힌다');
    });

    test('1차 조회는 코드 컬렉션을 먼저 본다', () {
      // 이 한 줄이 `isCode`의 **초기값**을 정한다. 뒤집으면 살아 있는 6자리 코드가
      // 1차·폴백 모두 `_inviteTokens`를 보게 되어 통째로 '없는 코드'가 되고, 그 전에
      // "코드를 먼저 본다"는 전제가 무너져 5분 창이 24시간 창에 흡수된다(계약 v3.12).
      // 아래 두 단언은 폴백 이후만 보므로 이 뒤집기를 못 잡는다 — 여기서 막는다.
      expect(
          bodies['requestToJoin']!,
          matches(
              RegExp(r'codeShaped\s*\?\s*_inviteCodes\s*:\s*_inviteTokens')),
          reason: '코드 우선이 뒤집히면 모든 초대코드가 없는 코드가 된다');
    });

    test('폴백을 타면 isCode를 false로 내린다', () {
      // 폴백 블록 **안에서** 내려야 한다. 밖에 있으면 22자 토큰까지 싸잡거나(무해)
      // 6자리 코드 정상 경로를 링크로 뒤집는다(유해) — 위치가 곧 의미다.
      final String? block = _fallbackBlockTail(bodies['requestToJoin']!);
      expect(block, isNotNull,
          reason: '폴백 블록을 못 찾았다 — 조회 심볼이나 구조가 바뀌었으면 이 검사도 함께 옮겨라');
      expect(block!, matches(RegExp(r'isCode\s*=\s*false')),
          reason: '폴백을 타고도 isCode가 true로 남으면, 만료된 6자리 **링크**가 '
              '"만료된 초대코드"로 안내된다 — 코드를 받아 와도 링크는 그대로다');
    });

    test('폴백으로 확정한 isCode가 던지기 전에 덮어써지지 않는다', () {
      // 위 단언들은 폴백 블록 **안**과 `throw` **한 줄**만 본다. 그 사이 구간은
      // 무방비여서, 거기에 `isCode = isWellFormedInviteCode(credential);` 한 줄만
      // 넣으면 셋 다 통과하면서 **이 PR이 고친 오분류가 그대로 되살아난다**
      // (만료된 레거시 6자리 링크 → "새 코드를 요청하세요"). 그 구간을 여기서 닫는다.
      final String body = bodies['requestToJoin']!;
      final int? blockEnd = _fallbackBlockEnd(body);
      expect(blockEnd, isNotNull,
          reason: '폴백 블록을 못 찾았다 — 조회 심볼이나 구조가 바뀌었으면 이 검사도 함께 옮겨라');
      final int throwAt = body.indexOf('InviteExpiredException(');
      expect(throwAt, greaterThan(blockEnd!),
          reason: '만료 던지기를 폴백 블록 뒤에서 못 찾았다 — 구조가 바뀌었으면 이 검사도 옮겨라');
      final String between = body.substring(blockEnd, throwAt);
      expect(between, isNot(matches(RegExp(r'isCode\s*='))),
          reason: '폴백으로 확정한 판정이 던지기 전에 덮어써진다');
      expect(between, isNot(contains('isWellFormedInviteCode')),
          reason: '모양으로 다시 매기면 6자리 링크 토큰 오분류가 되살아난다');
    });

    test('만료 예외가 그 판정을 그대로 싣는다 — 모양으로 다시 매기지 않는다', () {
      // 계약이 구현체에 부과한 의무다(`ShareRepository.requestToJoin` dartdoc).
      expect(
          bodies['requestToJoin']!,
          matches(RegExp(
              r'InviteExpiredException\(\s*credential\s*,\s*isCode:\s*isCode\s*,?\s*\)')),
          reason: '만료 예외가 폴백 판정이 아닌 다른 근거를 싣게 됐다');
    });
  });
}
