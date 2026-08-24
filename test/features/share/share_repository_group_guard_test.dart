// ShareRepository 그룹 삭제/나가기/소유권 이전 권한 가드 테스트 (계약 대상).
//
// 02 문서 B-1 동작 계약 보존(위반 시 StateError):
// - deleteGroup: 방장 본인만 삭제 가능.
// - leaveGroup: 멤버만 나갈 수 있고, 방장은 다른 멤버가 있으면 불가(이전 선행).
//   단독 방장은 나가기로 그룹을 정리할 수 있다.
// - transferOwnershipAndLeave: 방장만, 신임 방장은 나를 제외한 기존 멤버여야 한다.
//
// 프로토타입과 차이: leaveGroup/transfer 후에도 남은 멤버가 있으면 그룹은 전역적으로
// 유지된다(getGroupById로는 조회됨). '내 그룹'에서 빠졌는지는 getGroups(userId)로 본다.

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

  Future<bool> inMyGroups(String id) async {
    final List<Group> mine = await repo.getGroups(me);
    return mine.any((Group g) => g.id == id);
  }

  group('ShareRepository.deleteGroup 가드', () {
    test('방장 본인은 삭제 성공, 방장이 아니면 StateError', () async {
      // 내가 만든 그룹 → 나는 방장. 삭제 성공.
      final Group mine = await repo.createGroup(name: '내 그룹', emoji: '🏠');
      await repo.deleteGroup(mine.id);
      expect(await repo.getGroupById(mine.id), isNull);

      // 초대로 참여한 그룹 → 방장은 u_host, 나는 멤버. 삭제 불가.
      final Group joined = await joinHostGroup(repo, auth, '가족');
      expect(joined.isOwnedBy(me), isFalse);
      await expectLater(repo.deleteGroup(joined.id), throwsStateError);
      expect(await repo.getGroupById(joined.id), isNotNull);
    });
  });

  group('ShareRepository.leaveGroup 가드', () {
    test('일반 멤버는 나가기 성공(내 그룹에서 빠짐)', () async {
      final Group joined = await joinHostGroup(repo, auth, '동아리');
      await expectLater(
          repo.deleteGroup(joined.id), throwsStateError); // 멤버는 삭제 불가
      await repo.leaveGroup(joined.id);
      expect(await inMyGroups(joined.id), isFalse);
    });

    test('단독 방장은 나가기로 그룹 정리 가능', () async {
      final Group solo = await repo.createGroup(name: '혼자 그룹', emoji: '🎁');
      expect(solo.memberCount, 1);
      await repo.leaveGroup(solo.id);
      expect(await repo.getGroupById(solo.id), isNull);
    });

    test('방장이 다른 멤버와 함께면 나가기 불가 → 이전 후 성공 (g_family)', () async {
      const String gid = 'g_family';
      final Group fam = (await repo.getGroupById(gid))!;
      expect(fam.isOwnedBy(me), isTrue);
      expect(fam.memberCount, greaterThan(1));

      // 1) 다른 멤버가 있으므로 바로 나가기 불가.
      await expectLater(repo.leaveGroup(gid), throwsStateError);
      expect((await repo.getGroupById(gid))!.isOwnedBy(me), isTrue);

      // 2) 신임 방장이 멤버가 아니면 이전 불가.
      await expectLater(
        repo.transferOwnershipAndLeave(groupId: gid, newOwnerUserId: 'u_ghost'),
        throwsStateError,
      );
      // 3) 나 자신을 신임 방장으로 지정해도 불가.
      await expectLater(
        repo.transferOwnershipAndLeave(groupId: gid, newOwnerUserId: me),
        throwsStateError,
      );
      expect((await repo.getGroupById(gid))!.isOwnedBy(me), isTrue); // 아직 나

      // 4) 유효한 멤버(u_mom)에게 이전 → 성공. 방장 교체 + 나는 멤버에서 제거, 그룹 유지.
      final Group after = await repo.transferOwnershipAndLeave(
        groupId: gid,
        newOwnerUserId: 'u_mom',
      );
      expect(after.isOwnedBy('u_mom'), isTrue);
      expect(after.isMember(me), isFalse);
      // 내 멤버십이 사라졌으므로 '내 그룹'에서는 빠지지만, 그룹 자체는 전역 유지.
      expect(await inMyGroups(gid), isFalse);
      expect(await repo.getGroupById(gid), isNotNull);
    });
  });

  group('ShareRepository.transferOwnershipAndLeave 가드', () {
    test('방장이 아니면 이전 불가', () async {
      final Group joined = await joinHostGroup(repo, auth, '모임');
      expect(joined.isOwnedBy(me), isFalse);
      await expectLater(
        repo.transferOwnershipAndLeave(groupId: joined.id, newOwnerUserId: me),
        throwsStateError,
      );
      expect(await repo.getGroupById(joined.id), isNotNull);
    });
  });
}
