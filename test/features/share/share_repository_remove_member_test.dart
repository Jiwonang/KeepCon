// ShareRepository 멤버 강퇴(removeMember) 가드 테스트 (계약 대상).
//
// 계약:
// - 방장 본인만 멤버를 내보낼 수 있다(위반 시 StateError).
// - 방장 자신은 강퇴 대상이 아니다(StateError) — leave/transfer를 쓴다.
// - 비멤버/없는 그룹도 StateError.
//
// 행위자 = InMemoryAuthRepository.defaultUser(id 'user-1').
// 시드 g_family: 나(user-1) 방장 + u_mom/u_dad/u_sis 멤버.
// 시드 g_friends: 홍길동(u_gil) 방장, 나(user-1)는 멤버.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

void main() {
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository repo;

  final String me = InMemoryAuthRepository.defaultUser.id; // 'user-1'

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    repo = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
  });

  tearDown(() {
    repo.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  test('방장은 다른 멤버를 내보낼 수 있다(멤버 목록에서 제거)', () async {
    final Group before = (await repo.getGroupById('g_family'))!;
    expect(before.isOwnedBy(me), isTrue);
    expect(before.isMember('u_mom'), isTrue);

    final Group updated =
        await repo.removeMember(groupId: 'g_family', userId: 'u_mom');
    expect(updated.isMember('u_mom'), isFalse);
    expect(updated.memberCount, before.memberCount - 1);
    // 방장(나)은 그대로 유지 — 불변식(방장 정확히 1명) 보존.
    expect(updated.isOwnedBy(me), isTrue);

    expect((await repo.getGroupById('g_family'))!.isMember('u_mom'), isFalse);
  });

  test('방장은 자신을 내보낼 수 없다(StateError)', () async {
    await expectLater(
      repo.removeMember(groupId: 'g_family', userId: me),
      throwsStateError,
    );
    expect((await repo.getGroupById('g_family'))!.isMember(me), isTrue);
  });

  test('비멤버는 내보낼 수 없다(StateError)', () async {
    await expectLater(
      repo.removeMember(groupId: 'g_family', userId: 'u_stranger'),
      throwsStateError,
    );
  });

  test('방장이 아니면 멤버를 내보낼 수 없다(StateError)', () async {
    // g_friends에서 나는 멤버(방장 아님) → 누구를 지목하든 권한 없음으로 거부.
    final Group friends = (await repo.getGroupById('g_friends'))!;
    expect(friends.isOwnedBy(me), isFalse);
    await expectLater(
      repo.removeMember(groupId: 'g_friends', userId: 'u_gil'),
      throwsStateError,
    );
  });

  test('없는 그룹은 StateError', () async {
    await expectLater(
      repo.removeMember(groupId: 'no_such_group', userId: 'u_mom'),
      throwsStateError,
    );
  });
}
