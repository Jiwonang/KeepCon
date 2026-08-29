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
/// 실제 기프티콘 원문은 `gifticon_ocr_fixture_test.dart`가 덮는다. 다만 그
/// 픽스처 2건이 실제 입력으로 확인해 준 범위는 **사전 매칭 경로까지**다 —
/// 두 기프티콘 모두 브랜드가 `스타벅스`라 2단계 "유효한 첫 줄" 폴백과
/// "브랜드 다음 줄부터 상품명"이라는 순서 전제는 **실제 입력으로 미검증**이다.
/// 여기 있는 그 두 축의 테스트는 지어낸 입력에만 근거한다.
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
    test('상단 상태바 시각을 브랜드로 쓰지 않는다 — 2자리·3자리 오인식 모두', () {
      // 실제 OCR은 초 자리가 딸려 들어와 `9:274`처럼 **세 자리**로 읽기도 한다
      // (gifticon_ocr_fixture_test.dart의 카카오톡 원문이 그 사례다).
      // 정규식이 `\d{2,3}`인 이유이고, 두 자리만 테스트하면 세 자리 분기가 비어
      // `\d{2}`로 좁혀도 스캔 테스트가 전부 통과한다.
      for (final String clock in <String>['9:27', '09:27', '9:274']) {
        final GifticonOcrResult result = parser.parse(
          '$clock\n감성커피\n아메리카노',
        );

        expect(result.brand, '감성커피', reason: '시각 표기: $clock');
      }
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
