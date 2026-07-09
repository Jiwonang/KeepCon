// ShareStore 초대 권한(방장 한정) 가드 테스트.
//
// - canInvite: 방장은 항상 가능, 일반 멤버는 inviteOwnerOnly가 꺼졌을 때만 가능.
// - setInviteOwnerOnly: 방장만 정책을 바꿀 수 있다.
//
// 재정렬 안전성: 정책을 바꾸는 케이스는 각자 createGroup/joinGroup으로 새 그룹을
// 만들어 서로 겹치지 않게 하고, 시드 그룹은 읽기(assert)만 한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/data/share_models.dart';
import 'package:keepcon/features/share/data/share_store.dart';

void main() {
  final ShareStore store = ShareStore.instance;

  group('ShareStore.canInvite', () {
    test('방장은 정책과 무관하게 초대 가능', () {
      // 내가 만든 그룹 → 나는 방장.
      final Group mine = store.createGroup(name: '내 그룹', emoji: '🏠');
      expect(store.canInvite(mine.id), isTrue);
      // 방장 한정으로 켜도 방장(나)은 여전히 가능.
      expect(store.setInviteOwnerOnly(mine.id, true), isTrue);
      expect(store.canInvite(mine.id), isTrue);
    });

    test('일반 멤버는 방장 한정이 꺼졌을 때만 초대 가능', () {
      // 시드 친구 모임: 홍길동 방장, 나는 멤버, inviteOwnerOnly=true → 초대 불가.
      final Group friends = store.groupById('g_friends')!;
      expect(friends.owner.id, isNot(ShareStore.myId));
      expect(friends.inviteOwnerOnly, isTrue);
      expect(store.canInvite('g_friends'), isFalse);

      // 참여 그룹(기본 정책 off)에서 나는 멤버 → 초대 가능.
      final Group joined = store.joinGroup('111111');
      expect(joined.inviteOwnerOnly, isFalse);
      expect(store.canInvite(joined.id), isTrue);
    });

    test('비멤버/없는 그룹은 초대 불가', () {
      expect(store.canInvite('no_such_group'), isFalse);
    });
  });

  group('ShareStore.setInviteOwnerOnly', () {
    test('방장만 정책 변경 가능, 일반 멤버는 거부', () {
      // 내가 방장인 그룹 → 정책 변경 성공, 값 반영.
      final Group mine = store.createGroup(name: '정책 그룹', emoji: '💼');
      expect(mine.inviteOwnerOnly, isFalse);
      expect(store.setInviteOwnerOnly(mine.id, true), isTrue);
      expect(store.groupById(mine.id)!.inviteOwnerOnly, isTrue);

      // 참여 그룹에서 나는 멤버(방장 아님) → 정책 변경 거부, 값 유지.
      final Group joined = store.joinGroup('222222');
      final bool before = joined.inviteOwnerOnly;
      expect(store.setInviteOwnerOnly(joined.id, true), isFalse);
      expect(store.groupById(joined.id)!.inviteOwnerOnly, before);
    });
  });
}
