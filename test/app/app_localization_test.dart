/// #147 — 한국어 앱의 날짜 피커가 영어로 뜨던 문제의 회귀 테스트.
///
/// 두 가지를 못박는다. ①앱 셸의 로케일 한 벌(`app_localization.dart`)이 실제로
/// Material 내장 문구를 한국어로 만든다 ②`MaterialApp` 두 곳이 그 한 벌을 **실제로
/// 소비한다** — 한쪽만 고치면 다른 화면에서 같은 증상이 남는 구조라, 소비 여부를
/// 각각 고정해야 한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/app/app_localization.dart';
import 'package:keepcon/app/emulator_unavailable_page.dart';
import 'package:keepcon/main.dart';

void main() {
  testWidgets('로케일 한 벌을 쓰면 날짜 피커가 한국어로 뜬다(취소·확인·날짜 선택)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: appLocale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showDatePicker(
              context: context,
              initialDate: DateTime(2026, 8, 30),
              firstDate: DateTime(2026, 1, 1),
              lastDate: DateTime(2027, 12, 31),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('취소'), findsOneWidget);
    expect(find.text('확인'), findsOneWidget);
    expect(find.text('날짜 선택'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('EmulatorUnavailableApp이 로케일 한 벌을 소비한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(EmulatorUnavailableApp(onRetrySucceeded: () {}));

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, appLocale);
    expect(app.supportedLocales, appSupportedLocales);
    expect(app.localizationsDelegates, appLocalizationsDelegates);
  });

  testWidgets('KeepConApp이 로케일 한 벌을 소비한다', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KeepConApp(target: null)),
    );

    final MaterialApp app =
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, appLocale);
    expect(app.supportedLocales, appSupportedLocales);
    expect(app.localizationsDelegates, appLocalizationsDelegates);
  });
}
