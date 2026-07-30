// ShareRepository 초대코드 재발급(regenerateInviteCode) 테스트 (계약 대상).
//
// 계약:
// - 방장 본인만 재발급 가능(위반/그룹 없음이면 StateError).
// - 새 코드를 발급해 기존 코드/링크를 무효화하고, 만료(inviteExpiresAt)를 초기화(null)한다.
//
// 행위자 기본 = InMemoryAuthRepository.defaultUser(id 'user-1').

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

  test('방장 재발급 — 코드 변경 + 만료 초기화(null)', () async {
    final Group g = await repo.createGroup(name: '재발급', emoji: '🔄');
    await repo.setInviteExpiry(groupId: g.id, expiry: InviteExpiry.oneDay);
    expect((await repo.getGroupById(g.id))!.inviteExpiresAt, isNotNull);

    final Group updated = await repo.regenerateInviteCode(groupId: g.id);
    expect(updated.inviteCode, isNot(g.inviteCode));
    expect(updated.inviteExpiresAt, isNull);
    expect((await repo.getGroupById(g.id))!.inviteCode, updated.inviteCode);
  });

  test('비방장은 재발급 불가(StateError)', () async {
    // g_friends에서 나는 멤버(방장 아님).
    final Group friends = (await repo.getGroupById('g_friends'))!;
    expect(friends.isOwnedBy(me), isFalse);
    await expectLater(
      repo.regenerateInviteCode(groupId: 'g_friends'),
      throwsStateError,
    );
    // 코드는 유지된다.
    expect(
        (await repo.getGroupById('g_friends'))!.inviteCode, friends.inviteCode);
  });

  test('없는 그룹은 StateError', () async {
    await expectLater(
      repo.regenerateInviteCode(groupId: 'no_such_group'),
      throwsStateError,
    );
  });

  test('재발급 후 새 코드로 참여 가능, 옛 코드는 그 그룹에 연결되지 않음', () async {
    final Group g = await repo.createGroup(name: '코드교체', emoji: '🎫');
    final String oldCode = g.inviteCode;
    final Group updated = await repo.regenerateInviteCode(groupId: g.id);
    final String newCode = updated.inviteCode;

    // 다른 사용자로 전환.
    await auth.signUp(
      email: 'newbie@keepcon.app',
      password: 'pw123456',
      displayName: '뉴비',
    );

    // 새 코드로는 실제 그룹에 합류.
    final Group joined = await repo.joinGroup(newCode);
    expect(joined.id, g.id);

    // 옛 코드는 더 이상 그 그룹을 가리키지 않는다(in-memory 스텁은 미발견 코드를
    // 데모용 가짜 그룹으로 처리하므로, 실제 그룹 id와 다름을 확인).
    final Group viaOld = await repo.joinGroup(oldCode);
    expect(viaOld.id, isNot(g.id));
  });
}
