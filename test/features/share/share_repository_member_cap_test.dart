// ShareRepository 그룹 인원제한(member cap) 가드 테스트 (계약 대상, P2).
//
// 계약:
// - Group.maxMembers(기본 Group.defaultMaxMembers, 최소 1) — 방장 포함 인원 상한.
// - Group.isFull / remainingSlots — 참여 가능 여부 판정의 단일 진입점(모델 predicate).
// - createGroup(maxMembers): 방장이 상한을 정한다.
// - joinGroup: Group.isFull이면 StateError로 참여 거부(이미 멤버면 no-op이 우선).
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

  GroupMember owner(String id) => GroupMember(
        userId: id,
        displayName: id,
        avatarEmoji: '🙂',
        role: MemberRole.owner,
      );

  group('Group 인원제한 (모델)', () {
    test('maxMembers 기본값과 isFull/remainingSlots', () {
      final Group g = Group(
        id: 'g',
        name: 'g',
        emoji: '🎁',
        inviteCode: '000000',
        members: <GroupMember>[owner('user-1')],
      );
      expect(g.maxMembers, Group.defaultMaxMembers);
      expect(g.isFull, isFalse);
      expect(g.remainingSlots, Group.defaultMaxMembers - 1);
    });

    test('멤버 수 == maxMembers면 isFull, remainingSlots 0', () {
      final Group g = Group(
        id: 'g',
        name: 'g',
        emoji: '🎁',
        inviteCode: '000000',
        maxMembers: 1,
        members: <GroupMember>[owner('user-1')],
      );
      expect(g.isFull, isTrue);
      expect(g.remainingSlots, 0);
    });

    test('maxMembers < 1은 생성자 불변식 위반(AssertionError)', () {
      expect(
        () => Group(
          id: 'g',
          name: 'g',
          emoji: '🎁',
          inviteCode: '000000',
          maxMembers: 0,
          members: <GroupMember>[owner('user-1')],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('createGroup(maxMembers)', () {
    test('지정한 상한이 반영되고, 미지정 시 기본값', () async {
      final Group capped =
          await repo.createGroup(name: '소규모', emoji: '🏠', maxMembers: 4);
      expect(capped.maxMembers, 4);

      final Group def = await repo.createGroup(name: '기본', emoji: '👥');
      expect(def.maxMembers, Group.defaultMaxMembers);
    });
  });

  group('joinGroup 정원 가드', () {
    test('정원이 찬 그룹에 새 사용자가 참여하면 StateError', () async {
      // user-1이 정원 1(방장뿐이라 즉시 만석)인 그룹을 만든다.
      final Group full =
          await repo.createGroup(name: '만석', emoji: '⛔', maxMembers: 1);
      expect(full.isFull, isTrue);

      // 다른 사용자로 전환해 같은 코드로 참여 시도 → 정원 초과로 거부.
      await auth.signUp(
        email: 'other@keepcon.app',
        password: 'pw123456',
        displayName: '다른이',
      );
      await expectLater(
        repo.joinGroup(full.inviteCode),
        throwsStateError,
      );
    });

    test('여유가 있으면 새 사용자가 정상 참여', () async {
      final Group g =
          await repo.createGroup(name: '여유', emoji: '✅', maxMembers: 2);
      final String code = g.inviteCode;

      await auth.signUp(
        email: 'friend@keepcon.app',
        password: 'pw123456',
        displayName: '친구',
      );
      final Group joined = await repo.joinGroup(code);
      expect(joined.id, g.id);
      expect(joined.memberCount, 2);
      expect(joined.isFull, isTrue); // 2/2로 이제 만석.
    });
  });
}
