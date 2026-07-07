/// KeepCon 공유 계약 — 디자인 색 토큰 (SSOT).
///
/// 정본: `_workspace/design/behance_style_tokens.md` (KeepCon 틀 이미지, 라이트).
/// **기본 테마 = 라이트(화이트)**, 다크는 설정('마이')에서 토글한다.
///
/// ## 사용 규칙 (경계면 버그 방어)
/// - 페이지는 색을 **하드코딩하지 말고** `Theme.of(context).colorScheme` 또는
///   테마 컴포넌트를 소비한다. 원색 토큰이 직접 필요할 때만 이 클래스를 참조한다.
/// - 라이트/다크 각각의 팔레트를 [AppColorsLight]/[AppColorsDark]로 분리해,
///   테마 교체만으로 전 페이지가 반영되게 한다.
/// - 색 값은 이곳에서만 정의한다. 페이지 내부 재정의 금지.
library;

import 'package:flutter/material.dart';

/// KeepCon 공통 색 상수 (모드 무관 / brand·danger 계열).
///
/// 라이트/다크에서 공통으로 참조하는 앵커 색을 모아둔다. 모드별로 달라지는 값은
/// [AppColorsLight]/[AppColorsDark]에 둔다.
abstract final class AppColorsCommon {
  /// 경고/만료 임박(빨강). **라이트/다크 공통 유지** — 정본 규약.
  static const Color danger = Color(0xFFFF3B30);

  /// primary(brand) 위 텍스트/아이콘 (라이트·다크 공통 화이트).
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// darkSurface 위 텍스트/아이콘 (공통 화이트).
  static const Color onDark = Color(0xFFFFFFFF);
}

/// 라이트(기본·화이트) 팔레트. 정본: KeepCon 틀 이미지.
abstract final class AppColorsLight {
  /// 앱 배경(순백).
  static const Color bg = Color(0xFFFFFFFF);

  /// 섹션 구분/검색바 배경(연회색).
  static const Color bgSubtle = Color(0xFFF7F7F8);

  /// 주 텍스트(타이틀·가격, 볼드 블랙).
  static const Color ink = Color(0xFF141416);

  /// 보조 텍스트(라벨·날짜, 뮤트 그레이).
  static const Color muted = Color(0xFF9A9AA0);

  /// primary(brand) — 민트그린. 정렬·시계·확인 pill·홈 아이콘·강조.
  static const Color brand = Color(0xFF1FCB8B);

  /// 다크 서피스 — 알림 배너 배경·FAB(+)·아바타 원(라이트에서도 어두운 강조면).
  static const Color darkSurface = Color(0xFF16161A);

  /// 카드 배경(화이트 + 소프트 섀도는 테마의 elevation/shadowColor로).
  static const Color card = Color(0xFFFFFFFF);

  /// 경고/만료 임박.
  static const Color danger = AppColorsCommon.danger;

  /// 카드/검색바/배너 라운드 반경(정본 18).
  static const double radius = 18.0;
}

/// 다크 팔레트(설정 토글 시). 라이트의 역상 + brand 유지.
abstract final class AppColorsDark {
  /// 앱 배경(니어 블랙).
  static const Color bg = Color(0xFF141418);

  /// 섹션 구분/검색바 배경(배경보다 살짝 밝은 면).
  static const Color bgSubtle = Color(0xFF1E1E24);

  /// 주 텍스트(오프 화이트).
  static const Color ink = Color(0xFFF5F5F7);

  /// 보조 텍스트(뮤트 — 다크에서 대비 유지 위해 라이트와 동일 톤 사용).
  static const Color muted = Color(0xFF9A9AA0);

  /// primary(brand) — 다크에서 살짝 밝은 민트그린.
  static const Color brand = Color(0xFF22D89A);

  /// 다크 서피스 — 다크 모드에선 카드보다 더 어두운 강조면(FAB/배너/아바타).
  static const Color darkSurface = Color(0xFF0E0E12);

  /// 카드 배경(다크 카드).
  static const Color card = Color(0xFF1E1E24);

  /// 경고/만료 임박(공통 유지).
  static const Color danger = AppColorsCommon.danger;

  /// 카드/검색바/배너 라운드 반경(라이트와 동일 18).
  static const double radius = 18.0;
}
