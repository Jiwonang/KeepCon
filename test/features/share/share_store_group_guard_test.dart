// ShareStore 그룹 삭제/나가기/소유권 이전 권한 가드 테스트.
//
// 정본 가드(UI 노출 조건과 별개):
// - deleteGroup: 방장 본인만 삭제 가능.
// - leaveGroup: 멤버만 나갈 수 있고, 방장은 다른 멤버가 있으면 불가(이전 선행).
//   단독 방장은 나가기로 그룹을 정리할 수 있다.
// - transferOwnershipAndLeave: 방장만, 신임 방장은 나를 제외한 기존 멤버여야 한다.
//
// 재정렬 안전성: 삭제/나가기 성공 케이스는 각 테스트가 createGroup/joinGroup으로
// **새 그룹**을 만들어 서로 겹치지 않게 하고, 시드 그룹(g_family)을 변형하는 방장
// 케이스는 한 테스트 안에서 순서대로 수행해 테스트 간 순서에 의존하지 않는다.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/data/share_models.dart';
import 'package:keepcon/features/share/data/share_store.dart';

void main() {
  final ShareStore store = ShareStore.instance;

  group('ShareStore.deleteGroup 가드', () {
    test('방장 본인은 삭제 성공, 방장이 아니면 실패', () {
      // 내가 만든 그룹 → 나는 방장. 삭제 성공.
      final Group mine = store.createGroup(name: '내 그룹', emoji: '🏠');
      expect(store.deleteGroup(mine.id), isTrue);
      expect(store.groupById(mine.id), isNull);

      // 초대로 참여한 그룹 → 방장은 u_host, 나는 멤버. 삭제 실패.
      final Group joined = store.joinGroup('111111');
      expect(joined.owner.id, isNot(ShareStore.myId));
      expect(store.deleteGroup(joined.id), isFalse);
      expect(store.groupById(joined.id), isNotNull);
    });
  });

  group('ShareStore.leaveGroup 가드', () {
    test('일반 멤버는 나가기 성공', () {
      final Group joined = store.joinGroup('222222');
      expect(store.deleteGroup(joined.id), isFalse); // (멤버는 삭제 불가 재확인)
      expect(store.leaveGroup(joined.id), isTrue);
      expect(store.groupById(joined.id), isNull);
    });

    test('단독 방장은 나가기로 그룹 정리 가능', () {
      final Group solo = store.createGroup(name: '혼자 그룹', emoji: '🎁');
      expect(solo.memberCount, 1);
      expect(store.leaveGroup(solo.id), isTrue);
      expect(store.groupById(solo.id), isNull);
    });

    test('방장이 다른 멤버와 함께면 나가기 불가 → 이전 후 성공 (g_family)', () {
      // g_family: 내가 방장, 멤버 4명(엄마·아빠·누나).
      const String gid = 'g_family';
      final Group fam = store.groupById(gid)!;
      expect(fam.owner.id, ShareStore.myId);
      expect(fam.memberCount, greaterThan(1));

      // 1) 다른 멤버가 있으므로 바로 나가기 불가.
      expect(store.leaveGroup(gid), isFalse);
      expect(store.groupById(gid), isNotNull);
      expect(store.groupById(gid)!.owner.id, ShareStore.myId);

      // 2) 신임 방장이 멤버가 아니면 이전 불가.
      expect(
        store.transferOwnershipAndLeave(groupId: gid, newOwnerId: 'u_ghost'),
        isFalse,
      );
      // 3) 나 자신을 신임 방장으로 지정해도 불가.
      expect(
        store.transferOwnershipAndLeave(
            groupId: gid, newOwnerId: ShareStore.myId),
        isFalse,
      );
      expect(store.groupById(gid)!.owner.id, ShareStore.myId); // 아직 나

      // 4) 유효한 멤버(u_mom)에게 이전 → 성공. 방장 교체 + 나는 멤버에서 제거, 그룹 유지.
      expect(
        store.transferOwnershipAndLeave(groupId: gid, newOwnerId: 'u_mom'),
        isTrue,
      );
      final Group after = store.groupById(gid)!;
      expect(after.owner.id, 'u_mom');
      expect(after.members.any((GroupMember m) => m.id == ShareStore.myId),
          isFalse);
      // 내 멤버십이 사라졌으므로 groups 뷰(내 그룹)에서는 빠진다.
      // (groupById는 내부용으로 그룹 객체를 계속 찾을 수 있다.)
      expect(store.groups.any((Group g) => g.id == gid), isFalse);
    });
  });

  group('ShareStore.transferOwnershipAndLeave 가드', () {
    test('방장이 아니면 이전 불가', () {
      // 참여한 그룹에서 나는 멤버(방장 아님) → 이전 시도 실패.
      final Group joined = store.joinGroup('333333');
      expect(joined.owner.id, isNot(ShareStore.myId));
      expect(
        store.transferOwnershipAndLeave(
            groupId: joined.id, newOwnerId: ShareStore.myId),
        isFalse,
      );
      expect(store.groupById(joined.id), isNotNull);
    });
  });
}
