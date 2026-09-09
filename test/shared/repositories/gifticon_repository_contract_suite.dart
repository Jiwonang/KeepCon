/// 두 [GifticonRepository] 구현에 **같은 기대를 돌리는** 공유 계약 스위트.
///
/// ## 왜 구현별 테스트가 아니라 공유 스위트인가
///
/// `share_repository_contract_suite.dart`의 머리말과 같은 이유다 — 이 저장소가 반복해
/// 데인 실패 양상(반복 패턴 #1)은 "firebase에 테스트가 없다"가 아니라 **`flutter test`가
/// in-memory만 돌려서 두 구현이 갈라져도 green**이라는 것이다. 기대를 한 번 쓰고 백엔드를
/// 갈아 끼워 두 번 돌린다.
///
/// ## 지금 덮는 축
///
/// [GifticonRepository.extendExpiry] — 유효기간 연장. 가드가 셋(사용 완료 거부·뒤로만·
/// 문서 존재)이고 그중 **하나는 상태를 되돌린다**([GifticonStatus.expired] →
/// [GifticonStatus.available]). 계약 전이 표의 유일한 예외라, 한쪽 구현만 그 예외를
/// 구현하면 백엔드에 따라 만료된 기프티콘이 되살아나거나 안 되살아난다.
///
/// ## ⚠️ 이 스위트가 대체하지 못하는 것
///
/// `fake_cloud_firestore`는 서버가 아니라 자료구조다. **보안 규칙이 평가되지 않으므로**
/// "등록한 본인만 연장할 수 있다"는 규칙은 여기서 검증되지 않는다 — 그 계층의 정본은
/// `tool/verify_firestore_rules.sh`(CI `Firestore rules` 잡)다. 여기서 통과한다고
/// 남의 기프티콘을 못 고친다는 뜻이 아니다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';

/// 스위트가 백엔드에 요구하는 것 — 저장소 하나와 정리뿐이다.
///
/// 픽스처는 계약 API([GifticonRepository.addGifticon])로 심는다. 백도어를 두면 두 구현이
/// **다른 모양의 데이터** 위에서 같은 기대를 통과할 수 있다.
abstract class GifticonBackend {
  /// 자원을 거둔다. 스트림 컨트롤러가 남으면 다음 테스트가 오염된다.
  void stop();

  GifticonRepository get repo;
}

/// 두 구현이 같은 답을 내야 하는 유효기간 연장 계약.
///
/// [makeBackend]는 `setUp()`마다 새 백엔드를 만든다.
void runExpiryExtensionContract(GifticonBackend Function() makeBackend) {
  late GifticonBackend backend;

  setUp(() => backend = makeBackend());
  tearDown(() => backend.stop());

  /// 만료일 [expiry]·상태 [status]인 기프티콘을 심고 저장된 인스턴스를 돌려준다.
  Future<Gifticon> seed({
    required DateTime expiry,
    GifticonStatus status = GifticonStatus.available,
  }) {
    return backend.repo.addGifticon(Gifticon(
      id: '',
      ownerId: 'owner-1',
      brand: '스타벅스',
      productName: '아메리카노 T',
      price: 4500,
      category: '카페',
      expiryDate: expiry,
      registeredAt: DateTime(2025, 1, 1),
      status: status,
    ));
  }

  group('연장이 되는 경우', () {
    test('만료일이 뒤로 옮겨지고, 저장소에도 반영된다', () async {
      final Gifticon g = await seed(expiry: DateTime(2026, 1, 1));

      final Gifticon returned =
          await backend.repo.extendExpiry(g.id, DateTime(2026, 6, 30));

      expect(returned.expiryDate, DateTime(2026, 6, 30));
      final Gifticon? stored = await backend.repo.getGifticonById(g.id);
      expect(stored?.expiryDate, DateTime(2026, 6, 30),
          reason: '반환값만 바뀌고 저장이 안 되면 화면은 새로고침에서 옛 날짜로 돌아간다');
    });

    test('저장된 expired가 available로 되살아난다 — 전이 표의 유일한 예외', () async {
      final Gifticon g = await seed(
        expiry: DateTime(2026, 1, 1),
        status: GifticonStatus.expired,
      );

      final Gifticon returned =
          await backend.repo.extendExpiry(g.id, DateTime(2026, 6, 30));

      expect(returned.status, GifticonStatus.available);
      final Gifticon? stored = await backend.repo.getGifticonById(g.id);
      expect(stored?.status, GifticonStatus.available,
          reason: '상태가 expired로 남으면 상세 화면이 "만료 처리된 기프티콘"이라고 계속 말한다');
    });

    test('available은 available 그대로다 — 상태를 건드리지 않는다', () async {
      final Gifticon g = await seed(expiry: DateTime(2026, 1, 1));

      final Gifticon returned =
          await backend.repo.extendExpiry(g.id, DateTime(2026, 6, 30));

      expect(returned.status, GifticonStatus.available);
    });

    test('다른 필드는 그대로 남는다 — 부분 갱신', () async {
      final Gifticon g = await seed(expiry: DateTime(2026, 1, 1));

      await backend.repo.extendExpiry(g.id, DateTime(2026, 6, 30));

      final Gifticon? stored = await backend.repo.getGifticonById(g.id);
      expect(stored?.brand, g.brand);
      expect(stored?.productName, g.productName);
      expect(stored?.price, g.price);
      expect(stored?.ownerId, g.ownerId);
      expect(stored?.registeredAt, g.registeredAt);
    });
  });

  group('연장이 거부되는 경우', () {
    test('사용 완료한 기프티콘은 연장할 수 없다', () async {
      final Gifticon g = await seed(
        expiry: DateTime(2026, 1, 1),
        status: GifticonStatus.used,
      );

      await expectLater(
        backend.repo.extendExpiry(g.id, DateTime(2026, 6, 30)),
        throwsStateError,
      );
      final Gifticon? stored = await backend.repo.getGifticonById(g.id);
      expect(stored?.expiryDate, DateTime(2026, 1, 1),
          reason: '거부된 요청이 만료일만 옮겨 놓으면 안 된다');
      expect(stored?.status, GifticonStatus.used);
    });

    test('앞당기기는 연장이 아니다', () async {
      final Gifticon g = await seed(expiry: DateTime(2026, 6, 30));

      await expectLater(
        backend.repo.extendExpiry(g.id, DateTime(2026, 1, 1)),
        throwsStateError,
      );
    });

    test('같은 날짜는 시각이 뒤여도 연장이 아니다 — 판정은 달력 일 단위', () async {
      // 화면의 날짜 선택기가 자정이 아닌 시각을 얹으면 `isAfter`로는 통과한다.
      // 그러면 "연장했는데 D-day가 그대로"인 상태가 만들어진다.
      final Gifticon g = await seed(expiry: DateTime(2026, 6, 30));

      await expectLater(
        backend.repo.extendExpiry(g.id, DateTime(2026, 6, 30, 23, 59)),
        throwsStateError,
      );
    });

    test('없는 기프티콘', () async {
      await expectLater(
        backend.repo.extendExpiry('no-such-id', DateTime(2030, 1, 1)),
        throwsStateError,
      );
    });
  });
}
