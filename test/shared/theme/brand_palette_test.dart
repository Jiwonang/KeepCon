// BrandPalette 단위 테스트.
//
// 브랜드 로고 타일의 표시 스타일 결정 로직을 검증한다. 큐레이션된 브랜드는 고정 색/라벨을,
// 미등록 브랜드는 이름 해시로 **안정적으로**(같은 이름 → 항상 같은 색) 배정해야 한다.
// 타일 대비가 깨지지 않도록 폴백 전경색은 항상 화이트다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/theme/brand_palette.dart';

void main() {
  const Color white = Color(0xFFFFFFFF);

  group('BrandPalette.of — 큐레이션 브랜드', () {
    test('등록된 브랜드는 큐레이션 색·라벨을 반환한다', () {
      final BrandStyle s = BrandPalette.of('스타벅스');

      expect(s.label, '스벅');
      expect(s.background, const Color(0xFF00704A));
      expect(s.foreground, white);
    });

    test('브랜드 고유 전경색도 유지한다(CU = 보라 배경 + 라임 전경)', () {
      final BrandStyle s = BrandPalette.of('CU');

      expect(s.background, const Color(0xFF5C2D91));
      expect(s.foreground, const Color(0xFFC6F24A));
    });

    test('앞뒤 공백은 무시하고 조회한다', () {
      final BrandStyle padded = BrandPalette.of('  GS25  ');
      final BrandStyle exact = BrandPalette.of('GS25');

      expect(padded.label, exact.label);
      expect(padded.background, exact.background);
    });
  });

  group('BrandPalette.of — 미등록 브랜드 폴백', () {
    test('같은 이름은 항상 같은 색을 배정한다(안정 해시)', () {
      final BrandStyle a = BrandPalette.of('메가커피');
      final BrandStyle b = BrandPalette.of('메가커피');

      expect(a.background, b.background);
      expect(a.label, b.label);
    });

    test('라벨은 앞 두 글자, 전경은 화이트', () {
      final BrandStyle s = BrandPalette.of('컴포즈커피');

      expect(s.label, '컴포');
      expect(s.foreground, white);
    });

    test('영문 이름의 라벨은 대문자로 변환한다', () {
      expect(BrandPalette.of('mega').label, 'ME');
    });

    test('빈 이름은 물음표 라벨로 폴백한다', () {
      final BrandStyle s = BrandPalette.of('');

      expect(s.label, '?');
      expect(s.foreground, white);
    });
  });
}
