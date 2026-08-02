/// GifticonOcrParser 금액/날짜 판정 회귀 테스트.
///
/// PR #53 CodeRabbit 지적 반영:
/// 금액 판정 규칙이 _extractPrice와 _isPriceLine에서 서로 달라
/// 날짜의 연도("2026")가 금액으로 오인되거나
/// "4500원" 줄이 브랜드/상품명 후보로 새는 문제를 방지한다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/services/gifticon_ocr_parser.dart';

void main() {
  const GifticonOcrParser parser = GifticonOcrParser();

  group('GifticonOcrParser 금액 추출', () {
    test('날짜(2026.12.31)의 연도를 금액으로 오인하지 않는다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n아메리카노 T\n2026.12.31\n4500원',
      );

      expect(result.price, '4500');
      expect(result.expiryDate, DateTime(2026, 12, 31));
    });

    test('2자리 연도 포맷(YY.MM.DD) 유효기간을 정상 파싱한다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n아메리카노 T\n26.08.01\n4500원',
      );

      expect(result.expiryDate, DateTime(2026, 8, 1));
    });

    test('콤마 없는 "4500원" 줄도 금액으로 인식해 브랜드/상품명 후보에서 제외한다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n4500원\n아메리카노 T',
      );

      expect(result.brand, '스타벅스');
      expect(result.productName, '아메리카노 T');
      expect(result.price, '4500');
    });

    test('단위 표기 없는 순수 숫자는 금액으로 추출하지 않는다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n아메리카노 T\n2026.12.31',
      );

      expect(result.price, isNull);
    });

    test('₩ 통화 기호 표기를 인식한다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n아메리카노 T\n₩4,500',
      );

      expect(result.price, '4500');
    });

    test('천 단위 콤마 표기(단위 없음)를 인식한다', () {
      final GifticonOcrResult result = parser.parse(
        '스타벅스\n아메리카노 T\n4,500\n2026-12-31',
      );

      expect(result.price, '4500');
      expect(result.expiryDate, DateTime(2026, 12, 31));
    });
  });
}
