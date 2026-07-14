/// KeepCon 공유 계약 — 브랜드 색 팔레트 (SSOT).
///
/// 기프티콘 카드의 **브랜드 로고 타일** 색·전경색·짧은 라벨을 브랜드명으로 매핑한다.
/// 데이터 모델(`Gifticon.brand`)에는 색/로고 정보가 없으므로, 표시용 스타일을 여기서
/// 결정한다. 등록된 브랜드는 큐레이션 색, 미등록 브랜드는 이름 해시로 안정적으로 배정.
///
/// 색은 브랜드 아이덴티티라 라이트/다크 공통으로 쓴다(타일은 자체 배경+전경이라
/// 모드와 무관하게 대비가 유지된다).
library;

import 'package:flutter/material.dart';

/// 한 브랜드의 타일 표시 스타일.
class BrandStyle {
  const BrandStyle({
    required this.background,
    required this.foreground,
    required this.label,
  });

  /// 타일 배경색(브랜드 색).
  final Color background;

  /// 타일 위 텍스트/로고 전경색.
  final Color foreground;

  /// 타일에 표시하는 짧은 라벨(2~3자).
  final String label;
}

/// 브랜드명 → [BrandStyle] 조회. 미등록 브랜드는 해시 기반 폴백.
abstract final class BrandPalette {
  static const Color _white = Color(0xFFFFFFFF);

  /// 큐레이션된 주요 브랜드.
  static const Map<String, BrandStyle> _known = <String, BrandStyle>{
    'CU': BrandStyle(
        background: Color(0xFF5C2D91),
        foreground: Color(0xFFC6F24A),
        label: 'CU'),
    'GS25': BrandStyle(
        background: Color(0xFF0E4DA4), foreground: _white, label: 'GS'),
    '스타벅스': BrandStyle(
        background: Color(0xFF00704A), foreground: _white, label: '스벅'),
    '배스킨라빈스': BrandStyle(
        background: Color(0xFFEC4C9A), foreground: _white, label: 'BR'),
    '올리브영': BrandStyle(
        background: Color(0xFF84A80D), foreground: _white, label: '올리브'),
    '교보문고': BrandStyle(
        background: Color(0xFF2E5A3E), foreground: _white, label: '교보'),
    'BBQ': BrandStyle(
        background: Color(0xFFD32F2F), foreground: _white, label: 'BBQ'),
  };

  /// 미등록 브랜드 폴백 색 팔레트(해시로 안정 배정).
  static const List<Color> _fallback = <Color>[
    Color(0xFF4C5BD4),
    Color(0xFF1D9E75),
    Color(0xFFD8632F),
    Color(0xFF7A4AC0),
    Color(0xFF2894A8),
    Color(0xFFC0392B),
  ];

  /// [brand]에 해당하는 타일 스타일. 미등록이면 이름 해시로 색·이니셜 배정.
  static BrandStyle of(String brand) {
    final BrandStyle? hit = _known[brand.trim()];
    if (hit != null) return hit;

    final String name = brand.trim();
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.codeUnitAt(i)) & 0x7fffffff;
    }
    final Color bg = _fallback[hash % _fallback.length];
    final String label =
        name.isEmpty ? '?' : name.characters.take(2).toString().toUpperCase();
    return BrandStyle(background: bg, foreground: _white, label: label);
  }
}
