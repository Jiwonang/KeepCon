// ShareRepository 초대코드 재발급(regenerateInviteToken) 테스트 (계약 대상).
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

import 'join_via_approval.dart';

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
    final Group updated = await repo.regenerateInviteToken(groupId: g.id);
    final DateTime after = DateTime.now();

    expect(updated.inviteToken, isNot(g.inviteToken));
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
    expect((await repo.getGroupById(g.id))!.inviteToken, updated.inviteToken);
    expect((await repo.getGroupById(g.id))!.inviteExpiresAt,
        updated.inviteExpiresAt);
  });

  test('비방장은 재발급 불가(StateError)', () async {
    // g_friends에서 나는 멤버(방장 아님).
    final Group friends = (await repo.getGroupById('g_friends'))!;
    expect(friends.isOwnedBy(me), isFalse);
    await expectLater(
      repo.regenerateInviteToken(groupId: 'g_friends'),
      throwsStateError,
    );
    // 코드는 유지된다.
    expect((await repo.getGroupById('g_friends'))!.inviteToken,
        friends.inviteToken);
  });

  test('없는 그룹은 StateError', () async {
    await expectLater(
      repo.regenerateInviteToken(groupId: 'no_such_group'),
      throwsStateError,
    );
  });

  test('재발급 후 새 코드로 그룹에 참여할 수 있다', () async {
    final Group g = await repo.createGroup(name: '코드교체', emoji: '🎫');
    final String oldCode = g.inviteToken;
    final Group updated = await repo.regenerateInviteToken(groupId: g.id);
    final String newCode = updated.inviteToken;
    expect(newCode, isNot(oldCode));

    // 다른 사용자로 전환해 새 코드로 요청 → 방장 승인 → 실제 합류.
    await signUpAs(auth, email: 'newbie@keepcon.app', displayName: '뉴비');
    final Group joined = await joinViaApproval(
      repo,
      auth,
      inviteToken: newCode,
      owner: OwnerCredentials(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      ),
      requesterEmail: 'newbie@keepcon.app',
      requesterPassword: 'pw123456',
    );
    expect(joined.id, g.id);
    expect((await repo.getGroupById(g.id))!.inviteToken, newCode);

    // 옛 코드는 더 이상 이 그룹을 가리키지 않는다 — 이제 계약대로 거부된다
    // (옛 `joinGroup`은 없는 토큰에 가짜 그룹을 만들어 성공한 것처럼 보였다).
    await expectLater(repo.requestToJoin(oldCode), throwsStateError);
  });
}
