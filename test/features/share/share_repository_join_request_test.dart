// ShareRepository 참여 요청(초대 링크 → 방장 승인) 테스트 (계약 대상).
//
// 검증 대상 계약:
// - requestToJoin: 링크 소지자는 **요청만** 할 수 있고 멤버가 되지 않는다.
//   알림 문서는 만들지 않는다 — 방장에게 도착을 알리는 신호는 대기 목록 하나다.
//   만료·이미 멤버는 StateError. 같은 사람의 재요청은 멱등(요청이 쌓이지 않는다).
//   정원은 요청 시점에 보지 않는다(대기자는 자리를 차지하지 않는다).
// - approveJoinRequest: 방장만, 대기 중인 요청만. 승인 시점에 정원을 본다.
// - rejectJoinRequest: 방장만. 거절은 기록으로 남는다(요청자가 결과를 볼 유일한 경로).
// - cancelJoinRequest: 요청자 본인만. 문서를 지운다.
//
// 행위자 전환은 InMemoryAuthRepository.signUp/signIn으로 한다
// (방장 = defaultUser 'user-1', 요청자 = 아래에서 새로 만드는 계정).

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

void main() {
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository repo;

  const String guestEmail = 'guest@keepcon.test';
  const String guestPassword = 'keepcon';

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

  /// 요청자 계정으로 전환한다(처음 호출이면 계정을 만든다).
  Future<User> asGuest() async {
    try {
      return await auth.signIn(email: guestEmail, password: guestPassword);
    } on Object {
      return auth.signUp(
        email: guestEmail,
        password: guestPassword,
        displayName: '초대받은 사람',
      );
    }
  }

  /// 두 번째 요청자 계정으로 전환한다(소유권 이전 시나리오용).
  Future<User> asGuest2() async {
    const String email = 'guest2@keepcon.test';
    try {
      return await auth.signIn(email: email, password: guestPassword);
    } on Object {
      return auth.signUp(
        email: email,
        password: guestPassword,
        displayName: '초대받은 사람2',
      );
    }
  }

  /// 방장 계정으로 돌아온다.
  Future<User> asOwner() => auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );

  /// 방장이 만든 새 그룹.
  Future<Group> createOwnedGroup({int maxMembers = 10}) =>
      repo.createGroup(name: '우리집', emoji: '🏠', maxMembers: maxMembers);

  group('requestToJoin', () {
    test('요청해도 멤버가 되지 않는다 — 대기 상태로만 남는다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();

      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      expect(req.status, JoinRequestStatus.pending);
      expect(req.isPending, isTrue);
      expect(req.groupId, g.id);
      expect(req.userId, guest.id);

      // 핵심: 아직 멤버가 아니다.
      final Group after = (await repo.getGroupById(g.id))!;
      expect(after.isMember(guest.id), isFalse);
      expect(after.memberCount, 1);
      // 그룹 목록에도 안 보인다(멤버십 기준 조회).
      expect(await repo.getGroups(guest.id), isEmpty);
    });

    test('같은 링크를 두 번 눌러도 요청은 하나다(멱등)', () async {
      final Group g = await createOwnedGroup();
      await asGuest();

      final JoinRequest first = await repo.requestToJoin(g.inviteToken);
      final JoinRequest second = await repo.requestToJoin(g.inviteToken);

      expect(second.id, first.id);
      // 방장이 보는 신호(대기 목록)에도 하나만 쌓인다 — 이게 요청 도착을 알리는
      // 유일한 경로이므로, 여기서 중복되면 방장 화면이 곧바로 어지러워진다.
      expect(await repo.getPendingJoinRequests(g.id), hasLength(1));
    });

    test('존재하지 않는 토큰으로는 요청할 수 없다', () async {
      await asGuest();
      await expectLater(
        repo.requestToJoin('없는-토큰'),
        throwsA(isA<StateError>()),
      );
    });

    // 만료된 초대에 대한 거부는 여기서 검증하지 못한다 — in-memory 구현에 시계를
    // 주입할 방법이 없어 `inviteExpiresAt`을 과거로 만든 그룹을 만들 수 없다(같은
    // 이유로 기존 `joinGroup`의 만료 가드도 미검증 상태다). 만료 판정 자체는 모델의
    // `Group.isInviteExpired`가 단일 진입점이며 `requestToJoin`이 그것을 그대로
    // 소비한다. 실제 거부는 Firestore 구현과 함께 규칙 검증에서 확인한다.

    test('이미 멤버면 요청할 수 없다', () async {
      final Group g = await createOwnedGroup();
      await expectLater(
        repo.requestToJoin(g.inviteToken), // 방장 본인
        throwsA(isA<StateError>()),
      );
    });

    test('정원이 차 있어도 요청 자체는 받는다(정원은 승인 시점에 본다)', () async {
      final Group g = await createOwnedGroup(maxMembers: 1);
      expect(g.isFull, isTrue);

      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);
      expect(req.isPending, isTrue);
    });
  });

  group('approveJoinRequest', () {
    test('방장이 승인하면 멤버가 된다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      final Group updated = await repo.approveJoinRequest(req.id);

      expect(updated.isMember(guest.id), isTrue);
      expect(updated.memberCount, 2);
      // 요청자의 표시 이름·아바타가 그대로 멤버가 된다(승인 화면과 멤버 목록 일치).
      final GroupMember added = updated.memberById(guest.id)!;
      expect(added.displayName, req.displayName);
      expect(added.avatarEmoji, req.avatarEmoji);
      expect(added.role, MemberRole.member);

      // 대기 목록에서 빠지고, 요청자에게는 승인으로 보인다.
      expect(await repo.getPendingJoinRequests(g.id), isEmpty);
      final List<JoinRequest> mine = await repo.getMyJoinRequests(guest.id);
      expect(mine.single.status, JoinRequestStatus.approved);
    });

    test('방장이 아니면 승인할 수 없다', () async {
      final Group g = await createOwnedGroup();
      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      // 요청자 본인이 자기 요청을 승인하려 해도 막힌다.
      await expectLater(
        repo.approveJoinRequest(req.id),
        throwsA(isA<StateError>()),
      );
      expect((await repo.getGroupById(g.id))!.memberCount, 1);
    });

    test('정원이 찼으면 승인이 거부되고 요청은 대기로 남는다', () async {
      final Group g = await createOwnedGroup(maxMembers: 1);
      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await expectLater(
        repo.approveJoinRequest(req.id),
        throwsA(isA<StateError>()),
      );

      // 실패한 승인이 요청 상태를 오염시키지 않는다 — 자리를 비우면 다시 승인할 수 있다.
      final List<JoinRequest> pending = await repo.getPendingJoinRequests(g.id);
      expect(pending.single.id, req.id);
      expect(pending.single.status, JoinRequestStatus.pending);
    });

    test('이미 처리된 요청은 다시 승인할 수 없다', () async {
      final Group g = await createOwnedGroup();
      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await repo.approveJoinRequest(req.id);
      await expectLater(
        repo.approveJoinRequest(req.id),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('rejectJoinRequest', () {
    test('거절은 기록으로 남아 요청자가 결과를 볼 수 있다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      final JoinRequest rejected = await repo.rejectJoinRequest(req.id);
      expect(rejected.status, JoinRequestStatus.rejected);

      // 방장의 대기 목록에서는 사라지고,
      expect(await repo.getPendingJoinRequests(g.id), isEmpty);
      // 요청자에게는 거절로 남는다(비멤버는 그룹 알림을 못 읽으므로 이게 유일한 경로).
      final List<JoinRequest> mine = await repo.getMyJoinRequests(guest.id);
      expect(mine.single.status, JoinRequestStatus.rejected);
      // 멤버는 되지 않는다.
      expect((await repo.getGroupById(g.id))!.isMember(guest.id), isFalse);
    });

    test('방장이 아니면 거절할 수 없다', () async {
      final Group g = await createOwnedGroup();
      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await expectLater(
        repo.rejectJoinRequest(req.id),
        throwsA(isA<StateError>()),
      );
    });

    test('거절당해도 다시 요청할 수 있다(오거절 복구 경로)', () async {
      final Group g = await createOwnedGroup();
      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await repo.rejectJoinRequest(req.id);

      await asGuest();
      final JoinRequest again = await repo.requestToJoin(g.inviteToken);
      expect(again.status, JoinRequestStatus.pending);
      // 요청은 여전히 (그룹, 사용자)당 하나다.
      expect(await repo.getPendingJoinRequests(g.id), hasLength(1));
    });
  });

  group('cancelJoinRequest', () {
    test('요청자는 자기 요청을 거둘 수 있다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await repo.cancelJoinRequest(req.id);

      expect(await repo.getMyJoinRequests(guest.id), isEmpty);
      expect(await repo.getPendingJoinRequests(g.id), isEmpty);
    });

    test('남의 요청은 거둘 수 없다', () async {
      final Group g = await createOwnedGroup();
      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await expectLater(
        repo.cancelJoinRequest(req.id),
        throwsA(isA<StateError>()),
      );
      expect(await repo.getPendingJoinRequests(g.id), hasLength(1));
    });
  });

  group('그룹이 사라질 때', () {
    test('그룹을 삭제하면 그 그룹의 요청도 함께 사라진다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await repo.deleteGroup(g.id);

      // 남겨 두면 승인·거절이 그룹을 못 찾아 던지고 방장도 없어서, 요청자 화면에
      // 아무도 끝낼 수 없는 '대기 중'이 영원히 남는다.
      expect(await repo.getMyJoinRequests(guest.id), isEmpty);
    });

    test('마지막 멤버가 나가 그룹이 정리돼도 요청이 남지 않는다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await repo.leaveGroup(g.id); // 방장 혼자 → 그룹 소멸

      expect(await repo.getGroupById(g.id), isNull);
      expect(await repo.getMyJoinRequests(guest.id), isEmpty);
    });
  });

  group('멤버십이 끊길 때', () {
    test('강퇴하면 승인 기록도 함께 사라진다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await repo.approveJoinRequest(req.id);
      final Group kicked =
          await repo.removeMember(groupId: g.id, userId: guest.id);

      expect(kicked.isMember(guest.id), isFalse);
      // 남겨 두면 그룹에 없는 사람에게 "승인됨"이 계속 보인다(현재 관계와 어긋난다).
      expect(await repo.getMyJoinRequests(guest.id), isEmpty);
    });

    test('스스로 나가도 승인 기록이 남지 않는다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await repo.approveJoinRequest(req.id);

      await asGuest();
      await repo.leaveGroup(g.id);

      expect(await repo.getMyJoinRequests(guest.id), isEmpty);
    });

    test('소유권을 넘기고 나가도 승인 기록이 남지 않는다', () async {
      final Group g = await createOwnedGroup();

      // 손님 둘이 요청하고 방장이 둘 다 승인한다.
      final User guest = await asGuest();
      final JoinRequest r1 = await repo.requestToJoin(g.inviteToken);
      final User guest2 = await asGuest2();
      final JoinRequest r2 = await repo.requestToJoin(g.inviteToken);
      await asOwner();
      await repo.approveJoinRequest(r1.id);
      await repo.approveJoinRequest(r2.id);

      // 방장이 손님1에게 넘기고 나간다 → 손님1이 방장.
      await repo.transferOwnershipAndLeave(
        groupId: g.id,
        newOwnerUserId: guest.id,
      );

      // 승인으로 들어온 손님1이 방장이 된 뒤, 손님2에게 넘기며 나간다.
      await asGuest();
      final Group after = await repo.transferOwnershipAndLeave(
        groupId: g.id,
        newOwnerUserId: guest2.id,
      );

      expect(after.isMember(guest.id), isFalse);
      expect(after.isOwnedBy(guest2.id), isTrue);
      // 나가기·강퇴와 같은 정리가 이 경로에도 적용돼야 한다.
      expect(await repo.getMyJoinRequests(guest.id), isEmpty);
      // 남아 있는 손님2의 기록은 그대로다.
      expect(await repo.getMyJoinRequests(guest2.id), hasLength(1));
    });

    test('강퇴당한 사람은 링크로 다시 요청할 수 있다', () async {
      final Group g = await createOwnedGroup();
      final User guest = await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);

      await asOwner();
      await repo.approveJoinRequest(req.id);
      await repo.removeMember(groupId: g.id, userId: guest.id);

      await asGuest();
      final JoinRequest again = await repo.requestToJoin(g.inviteToken);
      expect(again.status, JoinRequestStatus.pending);
      expect(await repo.getPendingJoinRequests(g.id), hasLength(1));
    });
  });

  group('스트림', () {
    test('대기 목록 스트림이 요청·승인에 반응한다', () async {
      final Group g = await createOwnedGroup();

      final List<int> counts = <int>[];
      final Stream<List<JoinRequest>> stream =
          repo.watchPendingJoinRequests(g.id);
      final sub =
          stream.listen((List<JoinRequest> rs) => counts.add(rs.length));
      await Future<void>.delayed(Duration.zero);

      await asGuest();
      final JoinRequest req = await repo.requestToJoin(g.inviteToken);
      await Future<void>.delayed(Duration.zero);

      await asOwner();
      await repo.approveJoinRequest(req.id);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(counts.first, 0); // 초기 방출
      expect(counts, contains(1)); // 요청 도착
      expect(counts.last, 0); // 승인 후 목록에서 빠짐
    });
  });
}
