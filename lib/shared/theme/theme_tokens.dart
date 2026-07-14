/// KeepCon 공유 계약 — 시각 토큰(타이포·라운드·데코) + darkSurface 어댑터 (SSOT).
///
/// 색은 [AppColorsLight]/[AppColorsDark]·`Theme.of(context).colorScheme`가 정본이지만,
/// **타이포 형태·라운드 스케일·카드 데코·darkSurface 접근**은 `ColorScheme`에 직접
/// 매핑되지 않아 페이지마다 같은 리터럴을 하드코딩하기 쉽다. 그 반복을 이 파일의
/// 단일 토큰으로 통합한다(페이지 코드에 raw `fontSize`/`BorderRadius.circular(n)` 금지).
///
/// ## 사용 규칙
/// - 페이지 타이포는 [ThemeTokensX]의 명명 스타일 게터를 소비한다(리터럴 재기입 금지).
/// - 라운드는 [AppRadii] 스케일을 참조한다. 카드 래퍼(Material/InkWell)의 클립 반경과
///   내부 데코 반경이 같은 상수를 가리키게 해 어긋남을 방지한다.
/// - 리치 카드(서피스+아웃라인 보더+소프트 섀도)는 [AppDecorations.softCard]를 쓴다.
/// - `darkSurface`(알림 배너·FAB·아바타 강조면)는 [ThemeTokensX.darkSurface]로 밝기에
///   맞는 정본 팔레트를 가져온다.
///
/// 값은 재디자인 목업의 실제 수치를 **그대로 보존**한다(픽셀 무변경). 페이지 고유 1회성
/// 값도 여기 상수/게터로 올려 페이지에서 raw 리터럴을 없앤다.
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 공유 라운드 스케일. 목업의 실제 반경 값을 명명 상수로 보존한다(픽셀 무변경).
abstract final class AppRadii {
  /// 완전 라운드(pill) — 칩·찜 뱃지 등.
  static const double pill = 999.0;

  /// 쿠폰 히어로·필터 칩(공유상세 히어로·사용이력 필터).
  static const double hero = 22.0;

  /// 시트/큰 패널.
  static const double sheet = 20.0;

  /// 카드·배너 컨테이너 반경(정본 18). 홈·스캔·공유 리치 카드 공통.
  static const double card = 18.0;

  /// 입력 필드·이모지 타일·배너·토글 카드.
  static const double panel = 16.0;

  /// 인증 버튼·입력 필드(로그인/회원가입/비번찾기/공유상세 버튼).
  static const double button = 15.0;

  /// 브랜드 로고 타일 / 스캔 소스 아이콘 타일.
  static const double tile = 14.0;

  /// 만료 선택 버튼·그룹 상세 하단 액션 버튼.
  static const double action = 13.0;

  /// 썸네일 플레이스홀더.
  static const double thumb = 12.0;

  /// 상태 뱃지(사용가능/잠김/사용완료).
  static const double badge = 10.0;

  /// 소형 뱃지(홈 D-day·방장 뱃지).
  static const double dot = 9.0;
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

/// 시각 토큰 접근 확장 — darkSurface 어댑터 + 공유 타이포 스케일.
///
/// 타이포 게터는 `Theme.of(this).textTheme`의 색(ink/muted)을 물려받아 크기·굵기·자간만
/// 목업 값으로 지정한다. 페이지는 이 게터를 소비하고 raw `fontSize`를 쓰지 않는다.
/// (weight만 다른 변형이 필요하면 게터 결과에 `.copyWith(fontWeight: …)` — fontSize는 유지.)
extension ThemeTokensX on BuildContext {
  /// 현재 밝기에 맞는 darkSurface(어두운 강조면) 토큰.
  Color get darkSurface => Theme.of(this).brightness == Brightness.dark
      ? AppColorsDark.darkSurface
      : AppColorsLight.darkSurface;

  /// darkSurface 위 전경색(공통 화이트).
  Color get onDarkSurface => AppColorsCommon.onDark;

  TextTheme get _tt => Theme.of(this).textTheme;

  // ── 큰 타이틀(bold display) ──

  /// 로그인 로고 타이틀 — 38·w900·자간 -1.
  TextStyle? get logoTitleStyle => _tt.headlineSmall
      ?.copyWith(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1);

  /// 비밀번호 찾기 타이틀 — 34·w900·자간 -0.5.
  TextStyle? get resetTitleStyle => _tt.headlineSmall?.copyWith(
      fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -0.5);

  /// 회원가입 타이틀 — 32·w900·자간 -0.5.
  TextStyle? get signupTitleStyle => _tt.headlineSmall?.copyWith(
      fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5);

  /// 공유 상세 상품명(히어로 하단) — 28·w900·자간 -0.5.
  TextStyle? get heroProductStyle => _tt.headlineSmall?.copyWith(
      fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5);

  /// 페이지 큰 헤더(홈·스캔·공유·마이·사용이력 탭 헤더) — 26·w900·자간 -0.5.
  TextStyle? get pageHeaderStyle => _tt.headlineSmall?.copyWith(
      fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5);

  /// 멤버 초대코드(강조) — 24·w800·자간 2.
  TextStyle? get inviteCodeStyle => _tt.titleLarge
      ?.copyWith(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2);

  /// 멤버 초대 본문 타이틀("그룹명 그룹으로 초대") — 23·w900·자간 -0.5.
  TextStyle? get inviteTitleStyle => _tt.headlineSmall?.copyWith(
      fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.5);

  // ── 카드/섹션/행 타이틀 ──

  /// 카드 대표 타이틀(그룹 상세 그룹명 등) — 20·w800.
  TextStyle? get cardTitleStyle =>
      _tt.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w800);

  /// 네비바 타이틀(그룹 상세·멤버 초대·공유 상세·그룹 알림) — 19·w800.
  TextStyle? get navTitleStyle =>
      _tt.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w800);

  /// 섹션 제목(스캔 '저장할 그룹 선택'·공유 섹션 헤더·멤버 N명) — 18·w800.
  TextStyle? get sectionTitleStyle =>
      _tt.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w800);

  /// 리스트/설정 항목 타이틀(카드 상품명·설정 행·알림 카드 제목) — 17·w800.
  TextStyle? get itemTitleStyle =>
      _tt.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w800);

  /// 리스트 행 타이틀(멤버 이름·컴팩트 행) — 16·w700.
  TextStyle? get rowTitleStyle =>
      _tt.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700);
}
