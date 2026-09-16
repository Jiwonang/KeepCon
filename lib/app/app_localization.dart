/// 앱 셸의 로케일 설정 — 한 벌(SSOT).
///
/// `MaterialApp`이 둘이다(`main.dart`의 `KeepConApp`·`emulator_unavailable_page.dart`의
/// `EmulatorUnavailableApp`). 한쪽만 고치면 다른 화면에서 같은 증상(영어 날짜 피커 —
/// #147)이 남으므로 두 곳이 이 한 벌을 소비한다. 다국어를 붙이는 날도 여기 한 곳만
/// 바꾼다.
///
/// `locale`은 **`ko`로 고정**한다. 앱 문구가 전부 한국어라 기기 언어를 따르게 두면
/// "한국어 UI + 영어 피커"의 불일치가 남는다 — 기기 언어를 따르는 것은 화면 문구가
/// 로케일을 타게 된 뒤에야 의미가 있다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 앱이 고정하는 로케일.
const Locale appLocale = Locale('ko');

/// 지원 로케일. `locale`을 고정하므로 해석 결과는 항상 `ko`다 — `WidgetsApp`은
/// 고정 locale을 `[locale]` 하나로 해석해 첫 완전 일치에서 끝나므로, 여기 다른
/// 항목을 넣어도 절대 선택되지 않는다(폴백이 아니라 죽은 값). 다국어를 붙일 때
/// [appLocale] 고정을 풀면서 함께 늘린다.
const List<Locale> appSupportedLocales = <Locale>[Locale('ko')];

/// Material·Cupertino·Widgets 세 계층의 내장 문구 번역(날짜 피커의 "취소/확인",
/// 툴팁 등). 앱 자체 문구는 여기 없다 — 소스에 한국어로 적혀 있다.
///
/// ⚠️ Cupertino 위젯을 안 쓴다고 `GlobalCupertinoLocalizations`를 빼지 말 것.
/// 웹에서는 `defaultTargetPlatform`이 **방문자 브라우저의 OS**를 따라 iOS·macOS가
/// 되고, 그때 `TextField`의 기본 컨텍스트 메뉴(`AdaptiveTextSelectionToolbar`)가
/// `CupertinoLocalizations.of(context)`를 요구해 없으면 던진다 — 복사/붙여넣기
/// 메뉴가 아이폰 브라우저 방문자에게 통째로 깨진다(`ko` 고정이라 MaterialApp이
/// 덧붙이는 `DefaultCupertinoLocalizations`는 `en`에만 걸려 폴백도 없다).
///
/// 비용(릴리스 빌드 실측, 에이전트 리뷰): APK +2.0 MB(+1.9%, ABI당 ~670 KB) ·
/// 웹 main.dart.js gzip +113 KB(+11%). 델리게이트 load는 동기·캐시라 부팅 공백은
/// 없지만, 최초 해석 때 97개 로케일의 날짜 심볼을 한 번에 초기화하고 번역은
/// 로케일 `switch`라 트리셰이킹이 못 지운다 — `supportedLocales`를 줄여도
/// 바이너리는 안 준다. 유일한 레버는 ko 전용 `MaterialLocalizations` 직접 구현인데
/// 위 웹 Cupertino 요구까지 떠안아야 해서 하지 않는다.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    GlobalMaterialLocalizations.delegates;
