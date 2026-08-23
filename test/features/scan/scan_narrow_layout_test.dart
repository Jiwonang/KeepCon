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
/// 그래서 어림을 버리고 [TextPainter]로 실측하도록 바꿨고, 이 테스트가 그
/// 계산을 고정한다. 폭·글자 크기 어느 쪽이 바뀌어도 여기서 먼저 걸린다.
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
  Future<void> pumpScanAt(WidgetTester tester, double width) async {
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
        child: MaterialApp(theme: AppTheme.light, home: const ScanPage()),
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

    testWidgets('글자를 크게 키워도 넘치지 않는다', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 900);
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

      // 접근성 설정으로 글자를 키우면 라벨이 커진다 — 타일도 같이 커져야 한다.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ScanPage(),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
