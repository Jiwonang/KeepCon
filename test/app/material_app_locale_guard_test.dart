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

void main() {
  test('lib/의 모든 MaterialApp 생성 지점이 로케일 한 벌을 소비한다', () {
    // `MaterialApp(`·`MaterialApp<T>(`·`MaterialApp.router(` — 주석 줄(`//`·`///`)은 제외.
    final RegExp site = RegExp(r'\bMaterialApp(<[^>]*>)?(\.router)?\(');
    // 세 가지를 **모두** 본다. 델리게이트만 걸고 `locale`/`supportedLocales`를
    // 빠뜨리면 해석 결과가 `supportedLocales`의 기본값(en_US)이라 피커가 다시
    // 영어로 뜬다 — 배선이 있는데도 #147이 재발하는 모양이다(에이전트 리뷰가
    // 합성 세 번째 루트로 실측: 델리게이트만 건 루트에서 'OK'가 떴다).
    const List<String> wiredMarkers = <String>[
      'locale: appLocale',
      'supportedLocales: appSupportedLocales',
      'localizationsDelegates: appLocalizationsDelegates',
    ];

    final List<String> violations = <String>[];
    int sites = 0;

    for (final FileSystemEntity entity
        in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final List<String> lines = entity.readAsLinesSync();
      final int codeSites = lines
          .where(
              (String l) => !l.trimLeft().startsWith('//') && site.hasMatch(l))
          .length;
      if (codeSites == 0) continue;

      sites += codeSites;
      for (final String marker in wiredMarkers) {
        final int wired = lines.where((String l) => l.contains(marker)).length;
        if (wired < codeSites) {
          violations.add(
              '${entity.path}: MaterialApp $codeSites곳, `$marker` $wired곳');
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
}
