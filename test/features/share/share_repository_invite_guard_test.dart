// ShareRepository 초대 권한(방장 한정) 가드 테스트 (계약 대상).
//
// 02 문서 B-1 동작 계약 보존:
// - 초대 가능 여부는 모델 predicate Group.canInvite(userId)로 판정
//   (방장은 항상 가능, 일반 멤버는 inviteOwnerOnly가 꺼졌을 때만 가능).
// - setInviteOwnerOnly: 방장 본인만 정책 변경 가능(위반 시 StateError).
//
// 행위자 = InMemoryAuthRepository.defaultUser(id 'user-1').
// 시드 g_friends: 홍길동(u_gil) 방장, 나 멤버, inviteOwnerOnly=true.

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

  group('Group.canInvite (모델 predicate)', () {
    test('방장은 정책과 무관하게 초대 가능', () async {
      final Group mine = await repo.createGroup(name: '내 그룹', emoji: '🏠');
      expect(mine.canInvite(me), isTrue);
      // 방장 한정으로 켜도 방장(나)은 여전히 가능.
      final Group updated =
          await repo.setInviteOwnerOnly(groupId: mine.id, ownerOnly: true);
      expect(updated.canInvite(me), isTrue);
    });

    test('일반 멤버는 방장 한정이 꺼졌을 때만 초대 가능', () async {
      // 시드 친구 모임: 홍길동 방장, 나는 멤버, inviteOwnerOnly=true → 초대 불가.
      final Group friends = (await repo.getGroupById('g_friends'))!;
      expect(friends.isOwnedBy(me), isFalse);
      expect(friends.inviteOwnerOnly, isTrue);
      expect(friends.canInvite(me), isFalse);

      // 참여 그룹(기본 정책 off)에서 나는 멤버 → 초대 가능.
      final Group joined = await repo.joinGroup('111111');
      expect(joined.inviteOwnerOnly, isFalse);
      expect(joined.canInvite(me), isTrue);
    });

    test('비멤버는 초대 불가', () async {
      final Group friends = (await repo.getGroupById('g_friends'))!;
      expect(friends.canInvite('u_stranger'), isFalse);
    });
  });

  group('ShareRepository.setInviteOwnerOnly 가드', () {
    test('방장만 정책 변경 가능, 일반 멤버는 StateError', () async {
      // 내가 방장인 그룹 → 정책 변경 성공, 값 반영.
      final Group mine = await repo.createGroup(name: '정책 그룹', emoji: '💼');
      expect(mine.inviteOwnerOnly, isFalse);
      await repo.setInviteOwnerOnly(groupId: mine.id, ownerOnly: true);
      expect((await repo.getGroupById(mine.id))!.inviteOwnerOnly, isTrue);

      // 참여 그룹에서 나는 멤버(방장 아님) → 정책 변경 거부, 값 유지.
      final Group joined = await repo.joinGroup('222222');
      final bool before = joined.inviteOwnerOnly;
      await expectLater(
        repo.setInviteOwnerOnly(groupId: joined.id, ownerOnly: true),
        throwsStateError,
      );
      expect((await repo.getGroupById(joined.id))!.inviteOwnerOnly, before);
    });

    test('없는 그룹은 StateError', () async {
      await expectLater(
        repo.setInviteOwnerOnly(groupId: 'no_such_group', ownerOnly: true),
        throwsStateError,
      );
    });
  });
}
