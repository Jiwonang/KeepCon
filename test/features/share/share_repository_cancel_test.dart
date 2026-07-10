// ShareRepository.cancelShare 권한/상태 가드 테스트 (계약 InMemoryShareRepository 대상).
//
// 02 문서 B-1 동작 계약(공유 취소 권한·상태)을 보존한다:
// - 공유자 본인만 회수 가능(sharedByUserId == currentUser.id)
// - 사용 가능(available) 상태만 회수 가능(사용중/사용완료 불가)
// 프로토타입 스토어는 bool을 반환했지만, 계약은 가드 위반 시 StateError를 던진다.
//
// 행위자는 AuthRepository.currentUser(= InMemoryAuthRepository.defaultUser, id 'user-1').
// 시드: s_1(엄마 공유·available), s_2(내 공유·inUse), s_3(누나 공유·used) — 모두 g_family.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/share.dart';
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

  Gifticon freshGifticon(String id) => Gifticon(
        id: id,
        ownerId: me,
        brand: '메가커피',
        productName: '아이스 아메리카노',
        price: 3000,
        category: '카페',
        expiryDate: DateTime(2027, 1, 1),
        registeredAt: DateTime(2026, 1, 1),
      );

  Future<bool> presentInFamily(String id) async {
    final List<SharedGifticon> list = await repo.getSharedGifticons('g_family');
    return list.any((SharedGifticon s) => s.id == id);
  }

  group('ShareRepository.cancelShare 가드', () {
    test('공유자가 아니면 회수 불가(StateError, 목록 유지)', () async {
      final List<SharedGifticon> list =
          await repo.getSharedGifticons('g_family');
      final SharedGifticon s1 =
          list.firstWhere((SharedGifticon s) => s.id == 's_1');
      expect(s1.sharedByUserId, isNot(me));

      await expectLater(repo.cancelShare('s_1'), throwsStateError);
      expect(await presentInFamily('s_1'), isTrue);
    });

    test('사용중(inUse)이면 공유자 본인이어도 회수 불가', () async {
      final List<SharedGifticon> list =
          await repo.getSharedGifticons('g_family');
      final SharedGifticon s2 =
          list.firstWhere((SharedGifticon s) => s.id == 's_2');
      expect(s2.sharedByUserId, me);
      expect(s2.status, ShareStatus.inUse);

      await expectLater(repo.cancelShare('s_2'), throwsStateError);
      expect(await presentInFamily('s_2'), isTrue);
    });

    test('사용완료(used) 항목은 회수 불가(available만 가능)', () async {
      // 내 기프티콘을 새로 공유 → available 항목 생성 후 used로 전이시켜 회수 시도.
      final SharedGifticon shared = await repo.shareGifticon(
        groupId: 'g_family',
        gifticon: freshGifticon('gx-used'),
      );
      final SharedGifticon used = await repo.markUsed(shared.id);
      expect(used.status, ShareStatus.used);

      await expectLater(repo.cancelShare(shared.id), throwsStateError);
      expect(await presentInFamily(shared.id), isTrue); // 여전히 목록에 남아 있다
    });

    test('공유자 본인의 사용가능 항목은 회수 성공(제거), 재회수는 StateError', () async {
      final SharedGifticon shared = await repo.shareGifticon(
        groupId: 'g_family',
        gifticon: freshGifticon('gx-ok'),
      );
      expect(shared.sharedByUserId, me);
      expect(shared.status, ShareStatus.available);

      await repo.cancelShare(shared.id); // 성공(예외 없음)
      expect(await presentInFamily(shared.id), isFalse);

      // 이미 제거된 항목을 다시 회수하면 '항목 없음' → StateError(중복 회수 방지).
      await expectLater(repo.cancelShare(shared.id), throwsStateError);
    });
  });
}
