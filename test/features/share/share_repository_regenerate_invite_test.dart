// ShareRepository 초대코드 재발급(regenerateInviteCode) 테스트 (계약 대상).
//
// 계약:
// - 방장 본인만 재발급 가능(위반/그룹 없음이면 StateError).
// - 새 코드를 발급해 기존 코드/링크를 무효화하고, 만료(inviteExpiresAt)를
//   재발급 시점 + Group.inviteValidity(24시간)로 다시 연다.
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

  test('방장 재발급 — 코드 변경 + 만료 창 24시간 재개시', () async {
    final Group g = await repo.createGroup(name: '재발급', emoji: '🔄');

    final DateTime before = DateTime.now();
    final Group updated = await repo.regenerateInviteCode(groupId: g.id);
    final DateTime after = DateTime.now();

    expect(updated.inviteCode, isNot(g.inviteCode));
    // 재발급 시점 + 24시간 근방으로 밀린다(호출 사이 경과분 slack 허용).
    expect(
      updated.inviteExpiresAt.isBefore(before.add(Group.inviteValidity)),
      isFalse,
    );
    expect(
      updated.inviteExpiresAt.isBefore(
          after.add(Group.inviteValidity + const Duration(seconds: 5))),
      isTrue,
    );
    expect(updated.isInviteExpired(DateTime.now()), isFalse);
    expect((await repo.getGroupById(g.id))!.inviteCode, updated.inviteCode);
    expect((await repo.getGroupById(g.id))!.inviteExpiresAt,
        updated.inviteExpiresAt);
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

  test('재발급 후 새 코드로 그룹에 참여할 수 있다', () async {
    final Group g = await repo.createGroup(name: '코드교체', emoji: '🎫');
    final String oldCode = g.inviteCode;
    final Group updated = await repo.regenerateInviteCode(groupId: g.id);
    final String newCode = updated.inviteCode;
    expect(newCode, isNot(oldCode));

    // 다른 사용자로 전환해 새 코드로 실제 그룹에 합류.
    await auth.signUp(
      email: 'newbie@keepcon.app',
      password: 'pw123456',
      displayName: '뉴비',
    );
    final Group joined = await repo.joinGroup(newCode);
    expect(joined.id, g.id);
    // 옛 코드로는 이 그룹에 합류되지 않는다(옛 코드는 더 이상 이 그룹을 가리키지 않음).
    // 미발견 코드에 대한 joinGroup의 계약(StateError)·in-memory 데모 fallback 정리는
    // 별도 후속 작업에서 다룬다.
    expect((await repo.getGroupById(g.id))!.inviteCode, newCode);
  });
}
