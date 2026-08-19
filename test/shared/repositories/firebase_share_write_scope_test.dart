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
    expect(bodies.keys, contains('joinGroup'));
    expect(bodies.keys, contains('leaveGroup'));
    expect(bodies.keys, contains('deleteGroup'));
    expect(bodies['joinGroup'], contains('_groupToDoc('));
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
}
