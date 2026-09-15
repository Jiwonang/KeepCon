/// #147 재발 방지 가드 — `MaterialApp`을 만드는 **모든** 자리가 앱 로케일 한 벌
/// (`app_localization.dart`)을 소비하는지 `lib/`를 순회해 기계적으로 확인한다.
///
/// 손으로 쓴 소비 테스트(`app_localization_test.dart`)는 **아는 두 곳**만 못박는다.
/// 이 앱은 runApp 교체 부트스트랩이라 새 폴백 화면이 MaterialApp을 하나 더 만들
/// 수 있고(`EmulatorUnavailableApp`이 정확히 그렇게 추가됐다), 그때 로케일 배선을
/// 빼먹어도 컴파일·CI가 통과해 #147이 그 화면에서 재발한다. 이 테스트가 그 구멍을
/// 닫는다 — `tool/check_ssot.sh`가 공유 타입 재정의에 하는 것과 같은 종류의 게이트다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `MaterialApp(`·`MaterialApp<T>(`·`MaterialApp.router(` 생성식의 시작.
final RegExp _site = RegExp(r'\bMaterialApp(<[^>]*>)?(\.router)?\(');

/// 세 가지를 **모두** 본다. 델리게이트만 걸고 `locale`/`supportedLocales`를
/// 빠뜨리면 해석 결과가 `supportedLocales`의 기본값(en_US)이라 피커가 다시
/// 영어로 뜬다 — 배선이 있는데도 #147이 재발하는 모양이다(에이전트 리뷰가
/// 합성 세 번째 루트로 실측: 델리게이트만 건 루트에서 'OK'가 떴다).
const List<String> _wiredMarkers = <String>[
  'locale: appLocale',
  'supportedLocales: appSupportedLocales',
  'localizationsDelegates: appLocalizationsDelegates',
];

/// 주석 줄(`//`·`///`)을 지운 본문. doc 예시의 `MaterialApp(`과 주석에 적힌
/// 마커가 검사에 섞이지 않게 한다.
String _codeOnly(List<String> lines) =>
    lines.where((String l) => !l.trimLeft().startsWith('//')).join('\n');

/// [open]에 있는 `(`부터 짝이 맞는 `)`까지 — 생성식의 인자 블록.
///
/// 마커를 파일 전체가 아니라 **그 생성식 안에서만** 세야 한다. 파일 단위로 세면
/// 생성식 밖의 마커(다른 코드·문자열)가 배선 없는 새 MaterialApp을 가려 준다
/// (CodeRabbit, PR #182).
String _argsBlock(String code, int open) {
  int depth = 0;
  for (int i = open; i < code.length; i++) {
    final String ch = code[i];
    if (ch == '(') depth++;
    if (ch == ')') {
      depth--;
      if (depth == 0) return code.substring(open, i + 1);
    }
  }
  return code.substring(open);
}

void main() {
  test('lib/의 모든 MaterialApp 생성식이 로케일 한 벌을 소비한다', () {
    final List<String> violations = <String>[];
    int sites = 0;

    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final String code = _codeOnly(entity.readAsLinesSync());
      for (final RegExpMatch m in _site.allMatches(code)) {
        sites++;
        final String args = _argsBlock(code, m.end - 1);
        for (final String marker in _wiredMarkers) {
          if (!args.contains(marker)) {
            violations.add('${entity.path}: MaterialApp 생성식에 `$marker` 없음');
          }
        }
      }
    }

    expect(
      sites,
      greaterThanOrEqualTo(1),
      reason: 'MaterialApp을 한 곳도 못 찾았다 — 탐지 정규식이 깨졌다',
    );
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('생성식 밖의 마커는 세지 않는다 — 배선 없는 루트를 가리지 못한다', () {
    // 마커 세 개가 파일 어딘가에 있어도, 생성식 안에 없으면 위반이어야 한다.
    const String source = '''
const a = 'locale: appLocale';
const b = 'supportedLocales: appSupportedLocales';
const c = 'localizationsDelegates: appLocalizationsDelegates';
Widget build() => MaterialApp(home: Placeholder());
''';
    final String code = _codeOnly(source.split('\n'));
    final RegExpMatch m = _site.firstMatch(code)!;
    final String args = _argsBlock(code, m.end - 1);

    expect(args,
        'MaterialApp(home: Placeholder())'.substring('MaterialApp'.length));
    for (final String marker in _wiredMarkers) {
      expect(args.contains(marker), isFalse, reason: marker);
    }
  });
}
