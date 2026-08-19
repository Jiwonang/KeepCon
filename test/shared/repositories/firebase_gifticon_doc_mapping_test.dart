/// Firestore 문서 → [Gifticon] **매핑의 손상 내성** 테스트.
///
/// share 쪽과 같은 사고 구조다 — `FirebaseGifticonRepository.watchGifticons`가 목록 전체를
/// 이 매퍼로 매핑하므로, 문서 하나가 [Error]를 던지면 **사용자의 기프티콘 목록이 통째로
/// 사라진다.** 이쪽이 더 아픈 이유는 대상이 남의 공유분이 아니라 본인의 핵심 데이터라는
/// 점이다.
///
/// 함께 고정하는 것: `price`의 문자열 폴백이 **실제로 도달하는가**. 예전 코드는
/// `(data['price'] as num?)?.toInt() ?? int.tryParse(...)`라 문자열이 오면 캐스팅이 먼저
/// 던져 폴백에 닿지 못했다 — 방어 코드처럼 보이지만 죽은 가지였다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/repositories/impl/firebase/firebase_gifticon_repository.dart';

void main() {
  const Map<String, dynamic> garbage = <String, dynamic>{
    'ownerId': 42,
    'brand': 3.14,
    'productName': <String, dynamic>{'nested': 'map'},
    'price': double.nan,
    'barcode': <int>[1, 2],
    'category': true,
    'expiryDate': 'not-a-timestamp',
    'registeredAt': 7,
    'status': 99,
    'imagePath': 0,
  };

  test('타입이 전부 어긋난 문서도 예외 없이 매핑된다', () {
    final Gifticon g =
        FirebaseGifticonRepository.gifticonFromData('gx-1', garbage);

    expect(g.id, 'gx-1');
    expect(g.ownerId, '');
    expect(g.brand, '');
    expect(g.productName, '');
    expect(g.price, 0);
    expect(g.barcode, isNull);
    expect(g.imagePath, isNull);
    expect(g.expiryDate, DateTime.fromMillisecondsSinceEpoch(0));
    // 알 수 없는 status는 기존 규약대로 available로 폴백한다.
    expect(g.status, GifticonStatus.available);
  });

  test('빈 문서도 던지지 않는다', () {
    expect(
      () => FirebaseGifticonRepository.gifticonFromData(
          'gx-1', const <String, dynamic>{}),
      returnsNormally,
    );
  });

  test('price의 문자열 폴백이 실제로 동작한다(예전엔 캐스팅이 먼저 던져 죽은 가지였다)', () {
    Gifticon withPrice(Object? price) =>
        FirebaseGifticonRepository.gifticonFromData(
            'gx-1', <String, dynamic>{'price': price});

    expect(withPrice(3000).price, 3000); // int
    expect(withPrice(3000.7).price, 3000); // double → truncate
    expect(withPrice('4500').price, 4500); // 문자열 파싱 — 여기가 닿지 않았다
    expect(withPrice('사천오백').price, 0); // 파싱 실패 → 0
    expect(withPrice(double.nan).price, 0); // toInt()가 던지는 값 → 0
    expect(withPrice(null).price, 0);
  });

  test('정상 문서는 그대로 매핑된다(방어가 값을 뭉개지 않는다)', () {
    final Gifticon g = FirebaseGifticonRepository.gifticonFromData(
      'gx-9',
      <String, dynamic>{
        'ownerId': 'user-1',
        'brand': '메가커피',
        'productName': '아이스 아메리카노',
        'price': 3000,
        'barcode': '1234',
        'category': '카페',
        'status': GifticonStatus.used.name,
        'imagePath': '/tmp/x.png',
      },
    );

    expect(g.ownerId, 'user-1');
    expect(g.brand, '메가커피');
    expect(g.productName, '아이스 아메리카노');
    expect(g.price, 3000);
    expect(g.barcode, '1234');
    expect(g.category, '카페');
    expect(g.status, GifticonStatus.used);
    expect(g.imagePath, '/tmp/x.png');
  });
}
