/// GifticonOcrParser 실제 기프티콘 픽스처 테스트.
///
/// 아래 두 상수는 **손으로 지어낸 텍스트가 아니라** 실제 기프티콘 이미지를
/// ML Kit(`TextRecognitionScript.korean`)에 돌려 나온 원문이다. 안드로이드
/// 기기에서 `MlKitService.scan(InputImage.fromFilePath(...))`으로 수집했다 —
/// 스캔 페이지의 카메라·갤러리 두 경로가 타는 바로 그 호출이다.
///
/// ## 지어낸 입력으로는 안 되는 이유
/// ML Kit이 돌려주는 **줄 순서는 사람이 보는 순서가 아니다.** 카카오톡 쪽
/// 원문을 보면 이미지 위에 도장처럼 찍힌 "사용완료"가 `사용` / `완료` 두 줄로
/// 쪼개진 뒤, 그 **사이에 `스타벅스`가 끼어 들어온다.** 화면을 눈으로 옮겨
/// 적었다면 절대 나오지 않을 배치다. 상단 시계도 `9:27`이 아니라 `9:274`로
/// 읽힌다(파서 `_isNoiseLine` 주석이 예로 든 그 오인식이 실제로 재현됐다).
///
/// ## 익명화
/// 저장소가 Public이므로 **값만** 바꾸고 **모양은 그대로 뒀다** — 파서가 보는
/// 것은 값이 아니라 형태(`.+의 선물$`, 8~30자리 숫자)이기 때문에 검증 범위는
/// 줄지 않는다. 바꾼 것은 두 가지뿐이다.
///   - 보낸 사람 실명 → `민서`
///   - 바코드 숫자 → 자릿수가 같은 다른 숫자(13자리 / 12자리)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/services/gifticon_ocr_parser.dart';

/// 카카오톡 선물하기 — 사용완료된 스타벅스 음료 교환권. 금액·유효기간 표기 없음.
const String _kakaoGiftOcr = '9:274\n'
    '민서의 선물\n'
    '"응원합니다!"\n'
    '선물하기\n'
    '삭제\n'
    '나도 선물하기\n'
    '사용\n'
    '스타벅스\n'
    '완료\n'
    '아이스 카페 아메리카노T\n'
    '1000 2000 3000 0\n'
    '후기 작성\n'
    '선물추억';

/// 기프티쇼 — 스타벅스 e카드 금액권. 금액·유효기간이 모두 찍혀 있다.
const String _giftishowOcr = '기프티쇼 선물이 도착했어요!\n'
    '감사합니다.\n'
    'BUCKS\n'
    'COFFEE CO.\n'
    '가드고환권 50,000원권\n'
    '스타벅스\n'
    '스타벅스 e카드 5만원 교환권\n'
    '~2026년 07월 06일까지 사용\n'
    '교환처 : 스타벅스\n'
    '1000 2000 3000\n'
    '기업용\n'
    '내 마음의 선물, 기프티쇼 qiftishOW';

void main() {
  const GifticonOcrParser parser = GifticonOcrParser();

  group('카카오톡 선물하기 원문', () {
    test('브랜드·상품명을 뽑고 없는 금액·유효기간은 비운다', () {
      final GifticonOcrResult result = parser.parse(_kakaoGiftOcr);

      expect(result.brand, '스타벅스');
      expect(result.productName, '아이스 카페 아메리카노T');

      // 이 기프티콘에는 금액도 유효기간도 찍혀 있지 않다. 없는 값을 그럴듯하게
      // 채우는 쪽이 비우는 쪽보다 나쁘다 — 사용자가 검토 없이 저장한다.
      expect(result.price, isNull);
      expect(result.expiryDate, isNull);
    });

    test('"사용완료" 도장이 브랜드를 사이에 두고 갈라져도 브랜드가 정확하다', () {
      // ML Kit은 도장 텍스트를 `사용` / `완료`로 쪼개 브랜드 앞뒤에 흩어 놓는다.
      // 두 조각이 각각 노이즈로 걸리지 않으면 `사용`이 브랜드가 되고
      // `완료`가 상품명이 된다.
      expect(_kakaoGiftOcr.contains('사용\n스타벅스\n완료'), isTrue);

      final GifticonOcrResult result = parser.parse(_kakaoGiftOcr);

      expect(result.brand, '스타벅스');
      expect(result.productName, '아이스 카페 아메리카노T');
    });

    test('상태바 시계가 9:274로 읽힌다 — 브랜드로도 상품명으로도 오지 않는다', () {
      // ⚠️ 이 픽스처에서 브랜드를 지키는 것은 노이즈 필터가 **아니라** 브랜드
      // 사전이다 — `_isNoiseLine`을 통째로 무력화해도 이 단언은 통과한다
      // (뮤테이션으로 확인). 이름이 인과를 주장하지 않도록 여기서 남기는 것은
      // "실제 OCR이 초 자리를 붙여 세 자리로 읽는다"는 **사실**뿐이다.
      //
      // 시계 노이즈 규칙 자체는 사전에 없는 브랜드로
      // gifticon_ocr_brand_product_test.dart가 세 자리까지 포함해 고정한다.
      expect(_kakaoGiftOcr.contains('9:274'), isTrue);

      final GifticonOcrResult result = parser.parse(_kakaoGiftOcr);

      expect(result.brand, isNot('9:274'));
      expect(result.productName, isNot('9:274'));
    });
  });

  group('기프티쇼 원문', () {
    test('브랜드·상품명·금액·유효기간을 모두 뽑는다', () {
      final GifticonOcrResult result = parser.parse(_giftishowOcr);

      expect(result.brand, '스타벅스');
      expect(result.productName, '스타벅스 e카드 5만원 교환권');
      expect(result.price, '50000');
      expect(result.expiryDate, DateTime(2026, 7, 6));
    });

    test('유효기간 줄이 노이즈로 걸러져도 만료일은 뽑힌다', () {
      // `~2026년 07월 06일까지 사용`은 '사용'을 담고 있어 _isNoiseLine에
      // 걸린다. 그런데도 날짜가 나오는 것은 _extractExpiryDate가 걸러진 줄이
      // 아니라 **원문 전체**를 보기 때문이다. 날짜 추출을 걸러진 줄 기준으로
      // 바꾸면 이 기프티콘의 유효기간이 통째로 사라진다.
      expect(_giftishowOcr.contains('~2026년 07월 06일까지 사용'), isTrue);

      expect(parser.parse(_giftishowOcr).expiryDate, DateTime(2026, 7, 6));
    });

    test('금액은 상품명 줄이 아니라 오인식된 다른 줄에서 나온다', () {
      // 원문에서 금액이 붙은 줄은 "카드교환권"이 `가드고환권`으로 잘못 읽힌
      // 줄이다. 상품명 줄의 "5만원"은 숫자+단위 형태가 아니라 잡히지 않는다.
      expect(_giftishowOcr.contains('가드고환권 50,000원권'), isTrue);

      expect(parser.parse(_giftishowOcr).price, '50000');
    });

    test('브랜드 사전이 BUCKS·COFFEE CO.보다 뒤에 있는 스타벅스를 고른다', () {
      // 로고가 먼저 읽혀 `BUCKS`, `COFFEE CO.`가 앞줄에 온다. 사전 매칭이
      // 없으면 이 중 하나가 브랜드가 된다.
      final GifticonOcrResult result = parser.parse(_giftishowOcr);

      expect(result.brand, '스타벅스');
      expect(result.brand, isNot('BUCKS'));
    });
  });
}
