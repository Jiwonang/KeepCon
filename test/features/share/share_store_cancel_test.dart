// ShareStore.cancelShare 권한/상태 가드 테스트.
//
// 공유 취소(회수)는 store 정본에서 다음을 강제한다:
// - 공유자 본인만 회수 가능(sharedByName == myName)
// - 사용중(inUse) 항목은 회수 불가
// UI 노출 조건과 별개의 방어선이므로, store 메서드를 직접 호출해 검증한다.
//
// flutter test는 테스트 파일별로 격리된 isolate에서 실행되므로, 이 파일에서
// ShareStore.instance는 시드된 신선한 싱글턴이다. 아래 테스트는 서로의 상태를
// 침범하지 않도록 대상 항목을 분리해 둔다(s_1 / s_2 / 새로 만든 항목).

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/data/share_models.dart';
import 'package:keepcon/features/share/data/share_store.dart';

void main() {
  final ShareStore store = ShareStore.instance;

  SharedGifticon byId(String id) =>
      store.allShared.firstWhere((SharedGifticon s) => s.id == id);

  group('ShareStore.cancelShare 가드', () {
    test('공유자가 아니면 회수 불가(false, 목록 유지)', () {
      // s_1: 엄마가 공유한 available 항목 → 내(나)가 회수할 수 없다.
      final SharedGifticon s1 = byId('s_1');
      expect(s1.sharedByName, isNot(ShareStore.myName));

      expect(store.cancelShare(s1), isFalse);
      expect(store.allShared.any((SharedGifticon s) => s.id == 's_1'), isTrue);
    });

    test('사용중(inUse)이면 공유자 본인이어도 회수 불가', () {
      // s_2: 내가 공유했지만 아빠가 사용중 → 사용 도중 회수 금지.
      final SharedGifticon s2 = byId('s_2');
      expect(s2.sharedByName, ShareStore.myName);
      expect(s2.status, ShareStatus.inUse);

      expect(store.cancelShare(s2), isFalse);
      expect(store.allShared.any((SharedGifticon s) => s.id == 's_2'), isTrue);
    });

    test('사용완료(used) 항목은 회수 불가(available만 가능)', () {
      // 내가 공유한 available 항목을 사용완료로 전이시킨 뒤 회수 시도 → 거부.
      final MyGifticon mine = store.myGifticons.first;
      store.shareGifticon(groupId: 'g_family', g: mine);
      final SharedGifticon shared = store.sharedOf('g_family').firstWhere(
            (SharedGifticon s) =>
                s.sharedByName == ShareStore.myName &&
                s.status == ShareStatus.available,
          );
      expect(store.markUsed(shared), isTrue); // available → used
      expect(shared.status, ShareStatus.used);

      expect(store.cancelShare(shared), isFalse);
      expect(
        store.sharedOf('g_family').any((SharedGifticon s) => s.id == shared.id),
        isTrue, // 여전히 목록에 남아 있다
      );
    });

    test('공유자 본인의 사용가능 항목은 회수 성공(true, 제거)', () {
      // 내 기프티콘을 새로 공유 → sharedByName=나, available 항목 생성 후 회수.
      final MyGifticon mine = store.myGifticons.first;
      store.shareGifticon(groupId: 'g_family', g: mine);

      final SharedGifticon shared = store.sharedOf('g_family').firstWhere(
            (SharedGifticon s) =>
                s.sharedByName == ShareStore.myName &&
                s.status == ShareStatus.available,
          );

      expect(store.cancelShare(shared), isTrue);
      expect(
        store.sharedOf('g_family').any((SharedGifticon s) => s.id == shared.id),
        isFalse,
      );

      // 이미 제거된 항목을 다시 회수하면 멱등적으로 false(중복 회수 방지).
      expect(store.cancelShare(shared), isFalse);
    });
  });
}
