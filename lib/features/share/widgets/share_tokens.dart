/// share 페이지 — 공유 색 토큰 접근 헬퍼.
///
/// `ColorScheme`에 직접 매핑되지 않는 정본 토큰(예: darkSurface = 배너/아바타
/// 강조면)을 **밝기에 맞는 공유 팔레트**에서 가져온다. 색을 하드코딩하지 않고
/// 반드시 [AppColorsLight]/[AppColorsDark] 정본을 소비하기 위한 얇은 어댑터.
/// (main 페이지의 `MainThemeTokens`와 동일 패턴 — 색 정의가 아니라 정본 소비 어댑터.)
library;

import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';

extension ShareThemeTokens on BuildContext {
  /// 현재 밝기에 맞는 darkSurface(어두운 강조면) 토큰.
  Color get darkSurface => Theme.of(this).brightness == Brightness.dark
      ? AppColorsDark.darkSurface
      : AppColorsLight.darkSurface;

  /// darkSurface 위 전경색(공통 화이트).
  Color get onDarkSurface => AppColorsCommon.onDark;
}
