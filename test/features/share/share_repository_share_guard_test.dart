// InMemoryShareRepository.shareGifticon "한 기프티콘은 한 번만 공유" 불변식 테스트.
//
// 회귀 방지: 삭제된 ShareStore는 공유 시 원본을 후보 풀에서 제거해 한 기프티콘이
// 최대 1회만 공유되도록 강제했다. 승격된 InMemoryShareRepository는 repo 레벨 가드로
// 이 불변식을 복원한다 — 같은 gifticonId가 행위자가 속한 어느 그룹에든 이미 공유돼
// 있으면 StateError. 이 가드가 없으면 같은 기프티콘을 여러 그룹에 공유해 UsageLog가
// 다중 발생(이중 사용)할 수 있다.
//
// 시드 기준: currentUser = InMemoryAuthRepository.defaultUser('user-1')는
// g_family의 방장이자 g_friends의 멤버 → 두 그룹 모두에 공유 시도할 수 있다.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

void main() {
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository share;

  final String myId = InMemoryAuthRepository.defaultUser.id;

  Gifticon gifticon(String id) => Gifticon(
        id: id,
        ownerId: myId,
        brand: '스타벅스',
        productName: '아메리카노 T',
        price: 4500,
        category: '카페',
        expiryDate: DateTime(2026, 12, 31),
        registeredAt: DateTime(2026, 7, 1),
      );

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    share = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
  });

  tearDown(() {
    share.dispose();
    auth.dispose();
    gifticons.dispose();
  });

  group('shareGifticon 불변식 — 한 기프티콘은 한 번만 공유', () {
    test('같은 기프티콘을 두 번째 그룹에 공유하면 StateError', () async {
      final Gifticon g = gifticon('gift-A');

      // g_family(방장)에 첫 공유 → 성공.
      final SharedGifticon first =
          await share.shareGifticon(groupId: 'g_family', gifticon: g);
      expect(first.gifticonId, 'gift-A');

      // 같은 gifticonId를 g_friends(멤버)에 재공유 → 불변식 위반으로 거부.
      await expectLater(
        share.shareGifticon(groupId: 'g_friends', gifticon: g),
        throwsStateError,
      );

      // g_friends에는 공유 항목이 추가되지 않았다.
      final List<SharedGifticon> friendsShared =
          await share.getSharedGifticons('g_friends');
      expect(
        friendsShared.any((SharedGifticon s) => s.gifticonId == 'gift-A'),
        isFalse,
      );
    });

    test('같은 그룹에 재공유해도 StateError', () async {
      final Gifticon g = gifticon('gift-B');
      await share.shareGifticon(groupId: 'g_family', gifticon: g);
      await expectLater(
        share.shareGifticon(groupId: 'g_family', gifticon: g),
        throwsStateError,
      );
    });

    test('다른 기프티콘 공유는 성공', () async {
      await share.shareGifticon(
          groupId: 'g_family', gifticon: gifticon('gift-C'));
      final SharedGifticon other = await share.shareGifticon(
          groupId: 'g_friends', gifticon: gifticon('gift-D'));
      expect(other.gifticonId, 'gift-D');
    });

    test('공유취소(회수) 후 재공유는 성공', () async {
      final Gifticon g = gifticon('gift-E');
      final SharedGifticon shared =
          await share.shareGifticon(groupId: 'g_family', gifticon: g);

      // 회수(공유자 본인·available) → 후보 풀 복귀.
      await share.cancelShare(shared.id);

      // 다시 공유 가능(같은 그룹/다른 그룹 모두).
      final SharedGifticon reShared =
          await share.shareGifticon(groupId: 'g_friends', gifticon: g);
      expect(reShared.gifticonId, 'gift-E');
    });

    test('사용 완료된 기프티콘은 재공유 불가(StateError)', () async {
      final Gifticon g = gifticon('gift-F');
      final SharedGifticon shared =
          await share.shareGifticon(groupId: 'g_family', gifticon: g);

      // 사용 완료 → 항목은 used 상태로 남는다(제거되지 않음).
      await share.markUsed(shared.id);

      // 이미 공유(used)된 gifticonId라 재공유 거부 → 이중 사용/UsageLog 다중 방지.
      await expectLater(
        share.shareGifticon(groupId: 'g_friends', gifticon: g),
        throwsStateError,
      );
    });
  });
}
