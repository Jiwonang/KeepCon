/// GifticonOcrParser 브랜드·상품명 추출 테스트.
///
/// 기존 `gifticon_ocr_parser_test.dart`는 금액·날짜만 덮고 있어
/// **프리필의 핵심인 브랜드·상품명은 테스트가 0건**이었다.
/// 이 축은 조용히 틀리는 쪽이 위험하다 — 금액·날짜와 달리 그럴듯한 값이
/// 채워지면 사용자가 검토 없이 저장한다.
///
/// 여기 고정한 것은 파서가 **주석으로 의도를 명시한 규칙**들이다
/// (사전 우선 매칭 · 상단 시계/카카오톡 UI 노이즈 제거 · 보낸사람 줄 제거 ·
/// 금액/날짜/바코드/유효기간 줄 배제 · 브랜드 다음 줄부터 상품명 탐색).
/// 실제 기프티콘 OCR 원문을 픽스처로 넣는 작업은 별도이며,
/// 그때 이 규칙들이 실제 입력에서도 성립하는지 함께 확인한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/services/gifticon_ocr_parser.dart';

void main() {
  const GifticonOcrParser parser = GifticonOcrParser();

  group('브랜드 추출', () {
    test('사전에 있는 브랜드는 첫 줄이 아니어도 잡는다', () {
      final GifticonOcrResult result = parser.parse(
        '교환권\n스타벅스\n아메리카노 T',
      );

      expect(result.brand, '스타벅스');
    });

    test('사전에 없는 브랜드는 유효한 첫 줄을 쓴다', () {
      final GifticonOcrResult result = parser.parse(
        '감성커피\n아메리카노\n4,500원',
      );

      expect(result.brand, '감성커피');
      expect(result.productName, '아메리카노');
    });

    test('금액·날짜·바코드·유효기간 줄은 브랜드 후보가 아니다', () {
      final GifticonOcrResult result = parser.parse(
        '4,500원\n2026.12.31\n유효기간\n8801234567890\n감성커피',
      );

      expect(result.brand, '감성커피');
    });

    test('후보가 하나도 없으면 브랜드·상품명 모두 비운다', () {
      final GifticonOcrResult result = parser.parse('4,500원\n2026.12.31');

      expect(result.brand, isNull);
      expect(result.productName, isNull);
    });
  });

  group('노이즈 줄 제거', () {
    test('상단 상태바 시각을 브랜드로 쓰지 않는다', () {
      final GifticonOcrResult result = parser.parse(
        '9:27\n감성커피\n아메리카노',
      );

      expect(result.brand, '감성커피');
    });

    test('"○○의 선물" 보낸 사람 줄을 브랜드로 쓰지 않는다', () {
      final GifticonOcrResult result = parser.parse(
        '지훈의 선물\n감성커피\n아메리카노',
      );

      expect(result.brand, '감성커피');
    });

    test('카카오톡 선물하기 UI 문구를 브랜드·상품명으로 쓰지 않는다', () {
      final GifticonOcrResult result = parser.parse(
        '선물하기\n감성커피\n아메리카노\n사용완료',
      );

      expect(result.brand, '감성커피');
      expect(result.productName, '아메리카노');
    });
  });

  group('상품명 추출', () {
    test('브랜드 앞줄은 상품명 후보가 아니다', () {
      final GifticonOcrResult result = parser.parse(
        '카페 방문\n스타벅스\n아메리카노 T',
      );

      expect(result.productName, '아메리카노 T');
    });

    test('바코드 숫자 줄을 상품명으로 쓰지 않는다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n8801234567890\n아메리카노 T',
      );

      expect(result.productName, '아메리카노 T');
    });

    test('유효기간 라벨 줄을 상품명으로 쓰지 않는다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n유효기간\n아메리카노 T',
      );

      expect(result.productName, '아메리카노 T');
    });
  });
}
