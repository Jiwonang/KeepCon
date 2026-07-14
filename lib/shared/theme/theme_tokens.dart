/// KeepCon 공유 계약 — 시각 토큰(타이포·라운드·데코) + darkSurface 어댑터 (SSOT).
///
/// 색은 [AppColorsLight]/[AppColorsDark]·`Theme.of(context).colorScheme`가 정본이지만,
/// **타이포 형태·라운드 스케일·카드 데코·darkSurface 접근**은 `ColorScheme`에 직접
/// 매핑되지 않아 페이지마다 같은 리터럴을 하드코딩하기 쉽다(홈·스캔·공유가 동일한
/// 헤더 26/w900, 섹션 18/w800, 카드 보더+소프트섀도를 각각 반복). 그 반복을 이 파일의
/// 단일 토큰으로 통합한다.
///
/// ## 사용 규칙
/// - 페이지 큰 헤더는 [ThemeTokensX.pageHeaderStyle], 섹션 제목은
///   [ThemeTokensX.sectionTitleStyle]을 소비한다(리터럴 재기입 금지).
/// - 리치 카드(서피스+아웃라인 보더+소프트 섀도)는 [AppDecorations.softCard]를 쓴다.
/// - 라운드는 [AppRadii] 스케일을 참조한다. 카드 래퍼(Material/InkWell)의 클립 반경과
///   내부 데코 반경이 같은 상수를 가리키게 해 어긋남을 방지한다.
/// - `darkSurface`(알림 배너·FAB·아바타 강조면)는 [ThemeTokensX.darkSurface]로 밝기에
///   맞는 정본 팔레트를 가져온다(홈·스캔·공유가 쓰던 페이지-로컬 어댑터를 통합).
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 공유 라운드 스케일. 카드·타일·완전 라운드(pill)의 반경 정본.
///
/// 카드 반경은 정본 팔레트 [AppColorsLight.radius](=18)를 **직접 참조**해 테마
/// (`cardTheme`/`inputDecorationTheme`가 소비하는 값)와 단일 정본을 공유한다 —
/// 리터럴 18을 다시 적으면 정본이 둘로 갈라진다(디자이너가 한쪽만 바꾸면 수기 클립
/// 카드와 테마 표면이 어긋남). 개별 뱃지(9·10)나 소스 아이콘 타일(15)·이모지 타일(16)
/// 처럼 한 곳에서만 쓰는 반경은 승격하지 않고 호출부에 남긴다('늦게 승격' — 실제
/// 2번째 소비자가 있는 값만 토큰화).
abstract final class AppRadii {
  /// 카드·배너 컨테이너 반경. 정본 [AppColorsLight.radius](=18)를 그대로 참조.
  /// 홈 리치 카드·스캔 소스 카드·공유 그룹/공유 카드 공통.
  static const double card = AppColorsLight.radius;

  /// 브랜드 로고 타일 반경. 홈 리치 카드·공유 공유 카드의 좌측 브랜드 타일 공통.
  static const double tile = 14.0;

  /// 완전 라운드(pill) — 칩·찜 뱃지 등.
  static const double pill = 999.0;
}

/// 공유 데코 팩토리.
abstract final class AppDecorations {
  /// 리치 카드 공통 데코 — 서피스 배경 + 라운드 + 아웃라인 보더 + 소프트 섀도.
  ///
  /// 홈 리치 카드·스캔 소스 카드·공유 그룹 카드·공유 기프티콘 카드가 동일한
  /// (surface / r18 / outline@0.18 / onSurface 소프트 섀도) 구조를 반복하던 것을 통합한다.
  /// 섀도 농도만 카드별로 미세하게 달라(홈 0.05 vs 나머지 0.04) [shadowOpacity]로 받는다.
  static BoxDecoration softCard(
    ColorScheme scheme, {
    double radius = AppRadii.card,
    double borderOpacity = 0.18,
    double shadowOpacity = 0.04,
  }) {
    return BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border:
          Border.all(color: scheme.outline.withValues(alpha: borderOpacity)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: scheme.onSurface.withValues(alpha: shadowOpacity),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

/// 시각 토큰 접근 확장 — darkSurface 어댑터 + 공유 타이포.
///
/// (이전의 페이지-로컬 `MainThemeTokens`/`ShareThemeTokens`/스캔 인라인 어댑터를 통합.)
extension ThemeTokensX on BuildContext {
  /// 현재 밝기에 맞는 darkSurface(어두운 강조면) 토큰.
  Color get darkSurface => Theme.of(this).brightness == Brightness.dark
      ? AppColorsDark.darkSurface
      : AppColorsLight.darkSurface;

  /// darkSurface 위 전경색(공통 화이트).
  Color get onDarkSurface => AppColorsCommon.onDark;

  /// 페이지 큰 헤더(홈·스캔·공유 공통) — 26·w900·자간 -0.5.
  TextStyle? get pageHeaderStyle =>
      Theme.of(this).textTheme.headlineSmall?.copyWith(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          );

  /// 섹션 제목(스캔 '저장할 그룹 선택'·공유 섹션 헤더) — 18·w800.
  TextStyle? get sectionTitleStyle =>
      Theme.of(this).textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          );
}
