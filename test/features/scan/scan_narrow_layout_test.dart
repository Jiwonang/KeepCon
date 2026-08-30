/// scan — **좁은 화면에서 레이아웃이 넘치지 않는지** 지키는 테스트.
///
/// ## 이 파일이 있는 이유
///
/// '자주 쓰는 카테고리' 그리드는 타일 높이를 `childAspectRatio`로 잡고 있었다.
/// 그러면 높이가 **폭에서 나오는데** 타일 내용(아이콘 칸·간격·한 줄 라벨·여백)은
/// 높이가 고정이라, 화면이 좁아지면 타일이 내용보다 낮아져 넘쳤다.
///
/// 넘침은 디버그 빌드에서 매 프레임 예외를 던지고 릴리스에서는 **내용이 잘린 채
/// 조용히 지나간다.** 눈으로만 확인하면 넓은 화면에서는 멀쩡해 보여 놓치기 쉬워,
/// 실제로 두 번 연속 잘못된 값으로 고쳤다가 실기동에서야 드러났다:
///
/// 1. 행간을 계수(1.6)로 어림 → 360px에서 5.5px 모자람
///    (`치킨/피자`처럼 `/`가 섞인 라벨은 폰트 폴백으로 2px 더 높다)
/// 2. 테두리를 '선택/비선택 차이'로 계산 → 선택된 타일만 2.0px 모자람
///    (Flutter는 [BoxDecoration] 테두리 두께를 Container padding에 더한다)
///
/// 3. 아이콘 칸을 상수로 두어 확대된 이모지가 칸을 넘어 라벨을 덮음
///    (이 건은 **예외를 던지지 않아** 넘침 어서션으로는 못 잡는다 — 칸을 직접 잰다)
///
/// 그래서 어림을 버리고 [TextPainter]로 실측하도록 바꿨다.
///
/// ⚠️ **이 파일이 덮지 못하는 것**(뮤테이션으로 확인 — 아래를 되돌려도 통과한다):
/// - 폰트 폴백으로 라벨마다 높이가 갈리는 상황. `flutter test`는 합성 폰트를 써서
///   폴백이 없고 여섯 라벨 실측이 전부 같아진다 — `minExtentFor`가 최댓값 루프를
///   도는 유일한 이유를 이 환경에서는 재현할 수 없다.
/// - `minExtentFor`의 `+ 1` 반올림 여유.
/// - `ScanResultDialog.mutedStyle`의 행간 값.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

void main() {
  /// [width]px 화면에서 스캔 첫 화면을 띄운다.
  Future<void> pumpScanAt(
    WidgetTester tester,
    double width, {
    ThemeData? theme,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(
          InMemoryGifticonRepository(),
        ),
        authRepositoryProvider.overrideWithValue(InMemoryAuthRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: const ScanPage(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('스캔 첫 화면 — 좁은 폭', () {
    // 320: 옛 소형 기기 / 360: 흔한 안드로이드 / 375: iPhone SE·13 mini 급.
    // 셋 다 카테고리 타일이 넘치던 구간이다.
    for (final double width in <double>[320, 360, 375, 390]) {
      testWidgets('${width.toInt()}px에서 넘치는 위젯이 없다', (
        WidgetTester tester,
      ) async {
        await pumpScanAt(tester, width);

        // 오버플로는 렌더링 예외로 나타난다. 잡히면 그 자리에서 실패시킨다.
        expect(
          tester.takeException(),
          isNull,
          reason: '${width.toInt()}px에서 레이아웃이 넘쳤다',
        );
      });
    }

    // 라벨 높이를 **실제로 재고 있는지** 고정한다.
    //
    // 폭·배율만 흔드는 위 케이스들로는 이 회귀를 못 잡는다 — `flutter test`는
    // 합성 폰트를 써서 **폰트 폴백이 일어나지 않고**, 여섯 라벨의 실측 높이가
    // 전부 같아진다. 게다가 계수 어림값이 실측보다 커서 바닥이 오히려 넉넉해진다.
    // 즉 minExtentFor가 루프를 도는 유일한 이유(라벨마다 높이가 다르다)를
    // 이 환경에서는 재현할 수 없다.
    //
    // 대신 **테마가 지정한 행간**을 축으로 쓴다. 실측은 그것을 따라가지만 계수
    // 어림은 못 따라가므로, 실측을 어림으로 되돌리면 여기서 바닥이 모자라 넘친다.
    //
    // ⚠️ 그래도 남는 것: 폰트 폴백으로 라벨마다 높이가 갈리는 상황과 `+ 1`
    // 반올림 여유는 이 파일이 덮지 못한다. 값을 바꿔도 CI는 green이다.
    testWidgets('라벨 행간이 큰 테마에서도 넘치지 않는다', (WidgetTester tester) async {
      final ThemeData tall = AppTheme.light.copyWith(
        textTheme: AppTheme.light.textTheme.copyWith(
          bodyMedium: AppTheme.light.textTheme.bodyMedium?.copyWith(height: 3),
        ),
      );

      await pumpScanAt(tester, 360, theme: tall);

      expect(tester.takeException(), isNull);
    });

    // 접근성 설정으로 글자를 키우면 라벨이 커진다 — 타일도 같이 커져야 한다.
    // Android 14는 배율을 200%까지 허용하므로 2.0까지 본다.
    for (final double scale in <double>[1.3, 2.0]) {
      testWidgets('글자를 $scale배로 키워도 넘치지 않는다', (WidgetTester tester) async {
        await pumpScanAt(tester, 360, textScaler: TextScaler.linear(scale));

        expect(tester.takeException(), isNull);
      });
    }

    // 카테고리 아이콘 칸도 글자 배율을 따라야 한다.
    //
    // 칸 안에 든 이모지는 [Icon]이 아니라 [Text]라 배율을 따라 커지는데, 칸을
    // 상수로 고정하면 이모지가 칸을 넘어 아래 라벨을 덮는다. **이 결함은 예외를
    // 던지지 않는다** — `SizedBox`가 tight 제약이라 렌더 객체는 자기 크기를 그대로
    // 보고하고 이모지만 밖으로 그려진다. 그래서 위의 '넘치지 않는다' 케이스들로는
    // 원리상 못 잡고, 칸 높이를 직접 재야 한다.
    testWidgets('아이콘 칸이 글자 배율을 따라간다', (WidgetTester tester) async {
      const double scale = 2.0;
      const double emojiSize = 30; // CategoryTile._emojiSize

      await pumpScanAt(
        tester,
        360,
        textScaler: const TextScaler.linear(scale),
      );

      // 이모지를 감싼 가장 가까운 SizedBox = 아이콘 칸.
      final Size box = tester.getSize(
        find
            .ancestor(of: find.text('☕'), matching: find.byType(SizedBox))
            .first,
      );

      expect(
        box.height,
        greaterThanOrEqualTo(emojiSize * scale),
        reason: '아이콘 칸이 확대된 이모지보다 낮다 — 이모지가 라벨을 덮는다',
      );
    });
  });
}
