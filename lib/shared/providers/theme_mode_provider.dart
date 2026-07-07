/// KeepCon 공유 계약 — 앱 테마 모드 provider (단일 정본 / SSOT).
///
/// ⚠️ 이 파일이 `ThemeMode`를 소유하는 **유일한 정본**이다.
/// 설정('마이') 페이지와 앱 조립부(MaterialApp)가 모두 [themeModeProvider]를 소비한다.
/// 페이지 내부에 별도 `ThemeMode` 상태를 재선언하지 말 것(설정 토글과 화면이 갈라짐).
///
/// ---
/// ## 기본값
/// **`ThemeMode.light`** — KeepCon 기본 테마는 라이트(화이트). 다크는 설정에서 전환.
///
/// ## 앱 조립부(MaterialApp)에서의 사용법
/// 앱 조립부는 이 provider를 `watch`해서 `MaterialApp.themeMode`에 넘긴다.
/// ```dart
/// class KeepConApp extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     final ThemeMode mode = ref.watch(themeModeProvider);
///     return MaterialApp(
///       theme: AppTheme.light,
///       darkTheme: AppTheme.dark,
///       themeMode: mode,
///       ...
///     );
///   }
/// }
/// ```
///
/// ## 설정('마이')에서 토글하는 법
/// 설정 화면은 [ThemeModeController]의 메서드로 모드를 바꾼다.
/// ```dart
/// // 다크/라이트 스위치
/// ref.read(themeModeProvider.notifier).setDark(isOn);
/// // 또는 명시적 설정
/// ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
/// // system 추종을 쓰려면
/// ref.read(themeModeProvider.notifier).set(ThemeMode.system);
/// ```
///
/// ## 영구 저장 (후속)
/// 현재는 in-memory로 충분하다(앱 재시작 시 기본 라이트로 리셋).
/// TODO(후속): `shared_preferences`로 마지막 선택 모드를 저장·복원한다.
/// 그때 [ThemeModeController]의 `set`/`setDark`에서 저장, 초기화 시 로드하도록 확장한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 앱 테마 모드 상태 컨트롤러.
///
/// 기본 상태는 [ThemeMode.light]. 설정 페이지가 이 컨트롤러로 모드를 전환한다.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  /// 모드를 명시적으로 설정한다(light/dark/system).
  ///
  /// TODO(후속): shared_preferences 저장 지점.
  void set(ThemeMode mode) => state = mode;

  /// 다크 여부 불리언으로 토글한다(설정 스위치 편의 메서드).
  ///
  /// `true` → [ThemeMode.dark], `false` → [ThemeMode.light].
  void setDark(bool isDark) =>
      state = isDark ? ThemeMode.dark : ThemeMode.light;

  /// 라이트↔다크를 뒤집는다(system 상태에서 호출 시 다크로 간다).
  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

/// 앱 테마 모드 provider. **SSOT.**
///
/// 기본값 [ThemeMode.light]. 앱 조립부가 watch 하여 `MaterialApp.themeMode`에 주입하고,
/// 설정('마이')이 `themeModeProvider.notifier`로 토글한다.
final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
