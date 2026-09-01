/// 자격증명 **조회 문서가 손상됐을 때**의 fail-closed 가드.
///
/// 공유 계약 스위트(`share_repository_contract_suite.dart`)에 올리지 않는 이유: in-memory
/// 구현에는 조회 문서라는 개념 자체가 없다. 이것은 두 구현이 합의해야 할 *계약*이 아니라
/// firebase 고유의 **자료구조**이고, 계약 스위트에 억지로 올리면 한쪽에서 공허해진다.
///
/// 왜 필요한가 — 두 절 모두 코드가 스스로 fail-closed라고 선언해 놓고 검증이 없었다.
/// 뮤테이션으로 확인: `groupId.isEmpty`를 지워도, 만료 검사의 `||`를 `&&`로 뒤집어도
/// 전체 스위트가 통과했다. 특히 후자는 만료 필드가 없는 문서를 **영구히 유효한 초대
/// 자격증명**으로 만드는 방향이라, 24시간 정책을 코드로 강제하려던 가드가 통째로 뚫린다.
///
/// ⚠️ 이 모양의 문서가 오늘 실서비스에 있다고 확인한 것은 아니다 — 두 컬렉션의 쓰기
/// 규칙이 `expiresAt is timestamp`를 요구하고 컬렉션 자체가 그 규칙과 함께 생겼다.
/// 그래도 고정하는 이유는 **규칙을 안 거치는 경로**(관리자 콘솔·마이그레이션 스크립트·
/// 레거시 문서)가 있고, 클라이언트 가드만 두면 규칙을 안 거치는 요청에 무력하다는 것이
/// 이 저장소가 PR #89에서 이미 데인 형태이기 때문이다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/repositories/impl/firebase/firebase_share_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late FirebaseShareRepository repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    repo = FirebaseShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      firestore: db,
    );
    // 요청의 행위자는 정의상 비멤버다.
    await auth.signUp(
      email: 'guard@keepcon.test',
      password: 'keepcon',
      displayName: '손님',
    );
  });

  tearDown(() {
    gifticons.dispose();
    auth.dispose();
  });

  Future<void> seedToken(String token, Map<String, dynamic> doc) => db
      .collection(FirebaseShareRepository.inviteTokensCollection)
      .doc(token)
      .set(doc);

  test('만료 필드가 없는 조회 문서는 만료로 닫는다(fail-closed)', () async {
    // 레거시 문서를 만료로 읽는 기존 규약과 같은 방향이다. 반대로 열면 그 문서가
    // **영구 초대 링크**가 되어, 만료를 코드로 강제한 의미가 사라진다.
    await seedToken('legacy-token', <String, dynamic>{'groupId': 'g_legacy'});

    await expectLater(
      repo.requestToJoin('legacy-token'),
      throwsA(isA<InviteExpiredException>()),
    );
  });

  test('만료 필드의 타입이 다르면 만료로 닫는다', () async {
    // 손상은 결측만이 아니다 — 문자열로 저장된 값도 같은 방향으로 닫혀야 한다.
    await seedToken('typo-token', <String, dynamic>{
      'groupId': 'g_legacy',
      'expiresAt': '2099-01-01T00:00:00Z',
    });

    await expectLater(
      repo.requestToJoin('typo-token'),
      throwsA(isA<InviteExpiredException>()),
    );
  });

  test('groupId가 빈 문자열이면 만료가 아니라 평범한 StateError다', () async {
    // "없는 자격증명"과 "만료"를 뭉뚱그리면 안 된다 — 화면이 만료라고 안내하면 존재한
    // 적 없는 그룹의 재발급을 기다리게 만든다. 그리고 이 절을 지우면 빈 `groupId`가
    // 참여 요청 문서에 그대로 굳는다.
    await seedToken('empty-gid', <String, dynamic>{
      'groupId': '',
      'expiresAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
    });

    await expectLater(
      repo.requestToJoin('empty-gid'),
      throwsA(allOf(isA<StateError>(), isNot(isA<InviteExpiredException>()))),
    );
  });
}
