/// KeepCon 공유 계약 — ThemeData (SSOT).
///
/// [AppTheme.light]/[AppTheme.dark]가 앱 전체 테마를 반환한다. Material3 사용.
/// **핵심 목표: 페이지가 `Theme.of(context)`만 소비해도 KeepCon 틀 디자인이 나오게 한다.**
/// 색·라운드·타이포·인풋·칩·내비 톤을 모두 테마에 담아, 페이지가 색을 하드코딩하지
/// 않도록 한다.
///
/// ## 앱 조립부 사용법 (main.dart)
/// ```dart
/// final mode = ref.watch(themeModeProvider); // ThemeMode
/// MaterialApp(
///   theme: AppTheme.light,
///   darkTheme: AppTheme.dark,
///   themeMode: mode, // 기본 ThemeMode.light
///   ...
/// );
/// ```
/// 설정('마이')에서 [themeModeProvider]를 토글하면 전 페이지가 즉시 반영된다.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// KeepCon 라이트/다크 [ThemeData] 팩토리 (SSOT).
abstract final class AppTheme {
  /// 라이트(기본·화이트) 테마.
  static ThemeData get light => _build(
        brightness: Brightness.light,
        bg: AppColorsLight.bg,
        bgSubtle: AppColorsLight.bgSubtle,
        ink: AppColorsLight.ink,
        muted: AppColorsLight.muted,
        brand: AppColorsLight.brand,
        card: AppColorsLight.card,
        radius: AppColorsLight.radius,
      );

  /// 다크 테마(설정에서 토글).
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        bg: AppColorsDark.bg,
        bgSubtle: AppColorsDark.bgSubtle,
        ink: AppColorsDark.ink,
        muted: AppColorsDark.muted,
        brand: AppColorsDark.brand,
        card: AppColorsDark.card,
        radius: AppColorsDark.radius,
      );

  /// 공통 [ThemeData] 조립. 모드별 토큰을 받아 동일 구조로 테마를 구성한다.
  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color bgSubtle,
    required Color ink,
    required Color muted,
    required Color brand,
    required Color card,
    required double radius,
  }) {
    // 명시적 ColorScheme — seed 자동 생성이 아닌 정본 토큰을 직접 배선한다.
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: brand,
      onPrimary: AppColorsCommon.onPrimary,
      secondary: brand,
      onSecondary: AppColorsCommon.onPrimary,
      error: AppColorsCommon.danger,
      onError: AppColorsCommon.onDark,
      surface: card,
      onSurface: ink,
      // 보조 표면(검색바/섹션 구분).
      surfaceContainerHighest: bgSubtle,
      onSurfaceVariant: muted,
      outline: muted,
    );

    final BorderRadius cardRadius = BorderRadius.circular(radius);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      // 소프트 섀도(정본): 은은한 그림자 톤.
      shadowColor: ink.withValues(alpha: 0.08),
      splashFactory: InkRipple.splashFactory,

      // 카드 — 라운드 18 + 소프트 섀도.
      cardTheme: CardThemeData(
        color: card,
        elevation: 1,
        shadowColor: ink.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
      ),

      // AppBar — 투명 배경 + ink 텍스트(볼드 타이틀).
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ink,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: ink),
      ),

      // 텍스트 — 볼드 타이틀 + 보조색 라벨.
      textTheme: TextTheme(
        headlineSmall:
            TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w700),
        titleLarge:
            TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
        titleMedium:
            TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: ink, fontSize: 15),
        bodyMedium: TextStyle(color: ink, fontSize: 14),
        // 보조 텍스트(라벨·날짜) = muted.
        bodySmall: TextStyle(color: muted, fontSize: 12),
        labelMedium: TextStyle(color: muted, fontSize: 12),
      ),

      // 입력(검색바 등) — 회색 pill, 무테두리.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSubtle,
        hintStyle: TextStyle(color: muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: cardRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: cardRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: cardRadius,
          borderSide: BorderSide(color: brand, width: 1.5),
        ),
      ),

      // 칩(D-day 뱃지·카테고리) — 라운드, brand 톤 선택.
      chipTheme: ChipThemeData(
        backgroundColor: bgSubtle,
        selectedColor: brand,
        secondarySelectedColor: brand,
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(
            color: AppColorsCommon.onPrimary, fontWeight: FontWeight.w600),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // FAB(+) — darkSurface 강조(정본).
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brightness == Brightness.light
            ? AppColorsLight.darkSurface
            : AppColorsDark.darkSurface,
        foregroundColor: AppColorsCommon.onDark,
        elevation: 2,
        shape: const CircleBorder(),
      ),

      // 하단 내비게이션(NavigationBar / Material3).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        elevation: 0,
        indicatorColor: brand.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? brand : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? brand : muted);
        }),
      ),

      // BottomAppBar(중앙 노치 셸을 쓸 경우) 톤.
      bottomAppBarTheme: BottomAppBarThemeData(
        color: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // 아이콘 기본 톤.
      iconTheme: IconThemeData(color: ink),

      // ElevatedButton(확인 pill 등) — brand.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: AppColorsCommon.onPrimary,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: muted.withValues(alpha: 0.20),
        thickness: 1,
      ),
    );
  }
}
