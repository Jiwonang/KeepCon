/// 알림 탭 목적지 → 홈 탭 전환 + 카드 강조 배선 테스트.
///
/// 고정할 것:
/// 1. 강조 목적지를 소비하면 **홈 탭**으로 전환하고 대상 id를 강조 상태에 싣는다.
/// 2. 초대 목적지와 달리 공유 탭으로 가지 않는다(목적지별 처리가 갈리는지).
/// 3. 앱이 떠 있는 중에 도착한 강조 목적지도 소비한다(웜 스타트 경로).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/app/keepcon_shell.dart';
import 'package:keepcon/features/main/state/highlighted_gifticon.dart';
import 'package:keepcon/shared/deeplink/app_destination.dart';
import 'package:keepcon/shared/providers/deep_link_providers.dart';

void main() {
  testWidgets('강조 목적지를 소비하면 홈 탭에서 대상 id를 강조한다', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        pendingDestinationProvider
            .overrideWith((_) => const GifticonHighlightDestination('g-42')),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    // pumpAndSettle은 강조 만료 타이머까지 흘려보내므로, 소비 직후를 보려면
    // 프레임 단위로 진행해야 한다.
    await tester.pump();
    await tester.pump();

    expect(container.read(highlightedGifticonIdProvider), 'g-42');
    // 소비 후 버스는 비워져야 한다(탭을 오갈 때 다시 끌려가지 않도록).
    expect(container.read(pendingDestinationProvider), isNull);
    // 초대 목적지와 달리 참여 시트는 열리지 않는다.
    expect(find.widgetWithText(ElevatedButton, '참여하기'), findsNothing);

    // 남은 만료 타이머를 흘려보낸다(테스트 종료 시 pending timer로 실패하지 않도록).
    await tester.pump(highlightDuration + const Duration(seconds: 1));
  });

  testWidgets('앱이 떠 있는 중에 도착한 강조 목적지도 소비한다', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(container.read(highlightedGifticonIdProvider), isNull);

    container.read(pendingDestinationProvider.notifier).state =
        const GifticonHighlightDestination('g-late');
    await tester.pump();
    await tester.pump();

    expect(container.read(highlightedGifticonIdProvider), 'g-late');

    await tester.pump(highlightDuration + const Duration(seconds: 1));
  });

  testWidgets('강조는 일정 시간 뒤 자동으로 거둬진다', (WidgetTester tester) async {
    // 계속 남겨두면 다음에 홈에 들어왔을 때도 이유 없이 카드가 빛나 보인다.
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        pendingDestinationProvider
            .overrideWith((_) => const GifticonHighlightDestination('seed-1')),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(highlightedGifticonIdProvider), 'seed-1');

    await tester.pump(highlightDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(container.read(highlightedGifticonIdProvider), isNull);
  });
}
