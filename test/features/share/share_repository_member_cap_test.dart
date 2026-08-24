// ShareRepository 그룹 인원제한(member cap) 가드 테스트 (계약 대상, P2).
//
// 계약:
// - Group.maxMembers(기본 Group.defaultMaxMembers, 최소 1) — 방장 포함 인원 상한.
// - Group.isFull / remainingSlots — 참여 가능 여부 판정의 단일 진입점(모델 predicate).
// - createGroup(maxMembers): 방장이 상한을 정한다.
// - approveJoinRequest: Group.isFull이면 StateError로 **승인**을 거부한다.
//   요청(requestToJoin)은 정원과 무관하게 접수된다 — 대기자가 자리를 선점하면
//   방장이 정작 받고 싶은 사람을 못 넣는다.
//
// 행위자 기본 = InMemoryAuthRepository.defaultUser(id 'user-1').

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

import 'join_via_approval.dart';

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
        inviteToken: '000000',
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
        inviteToken: '000000',
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
          inviteToken: '000000',
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

  group('정원 가드 (승인 시점)', () {
    // 정원은 **승인 시점**에 검사된다(v2.9 계약) — 대기자가 자리를 선점하면 방장이
    // 정작 받고 싶은 사람을 못 넣기 때문이다. 그래서 요청 자체는 정원과 무관하게 접수되고,
    // 거부는 방장이 승인을 누를 때 일어난다.
    test('정원이 찬 그룹은 요청은 받되 승인에서 거부한다', () async {
      // user-1이 정원 1(방장뿐이라 즉시 만석)인 그룹을 만든다.
      final Group full =
          await repo.createGroup(name: '만석', emoji: '⛔', maxMembers: 1);
      expect(full.isFull, isTrue);

      // 다른 사용자로 전환해 요청 — **요청은 성공한다**(자리를 차지하지 않는다).
      await signUpAs(auth, email: 'other@keepcon.app', displayName: '다른이');
      final JoinRequest req = await repo.requestToJoin(full.inviteToken);
      expect(req.status, JoinRequestStatus.pending);

      // 방장으로 돌아가 승인 → 정원 초과로 거부.
      await auth.signIn(
          email: InMemoryAuthRepository.defaultUser.email,
          password: InMemoryAuthRepository.defaultPassword);
      await expectLater(repo.approveJoinRequest(req.id), throwsStateError);
    });

    test('여유가 있으면 승인으로 정상 합류', () async {
      final Group g =
          await repo.createGroup(name: '여유', emoji: '✅', maxMembers: 2);

      await signUpAs(auth, email: 'friend@keepcon.app', displayName: '친구');
      final Group joined = await joinViaApproval(
        repo,
        auth,
        inviteToken: g.inviteToken,
        owner: OwnerCredentials(
          email: InMemoryAuthRepository.defaultUser.email,
          password: InMemoryAuthRepository.defaultPassword,
        ),
        requesterEmail: 'friend@keepcon.app',
        requesterPassword: 'pw123456',
      );
      expect(joined.id, g.id);
      expect(joined.memberCount, 2);
      // 이 파일의 주제는 모델 predicate다 — 승인이 `isFull`·`remainingSlots`를
      // 실제로 움직이는지까지 본다(`share_repository_join_request_test`는 요청이
      // 대기로 남는 쪽을, 여기서는 모델 값의 전이를 지킨다).
      expect(joined.isFull, isTrue); // 2/2로 이제 만석.
      expect(joined.remainingSlots, 0);
    });
  });
}
