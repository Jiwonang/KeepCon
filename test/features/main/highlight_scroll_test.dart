/// 강조가 **목록보다 먼저** 걸리는 경로 테스트.
///
/// 알림으로 앱이 처음 열리면 강조는 즉시 걸리지만 기프티콘 목록은 저장소에서 잠시 뒤에
/// 온다. 그 시점에는 목록 위젯이 마운트되지도 않았거나 대상 카드가 없어 스크롤을
/// 건너뛰는데, 강조 id는 그대로라 리스너는 다시 울리지 않는다 — 재시도가 없으면 카드가
/// 강조된 채 화면 밖에 남는다(CodeRabbit 리뷰 지적).
///
/// ⚠️ 스크롤 위치 자체는 여기서 단언하지 않는다. [SliverList]가 지연 생성이라 대상이
/// 빌드되는지가 뷰포트 크기에 좌우되고(기본 테스트 뷰포트에서는 카드가 두 장만 빌드된다),
/// 그걸 고정하면 레이아웃을 조금만 바꿔도 깨지는 취약한 테스트가 된다. 여기서 고정하는
/// 것은 **목록이 늦게 와도 강조가 유실되지 않는다**는 것이다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/shared/providers/raw_gifticons_provider.dart';
import 'package:keepcon/features/main/state/highlighted_gifticon.dart';
import 'package:keepcon/shared/models/gifticon.dart';

List<Gifticon> _seed(int count) {
  final DateTime now = DateTime(2026, 8, 8);
  return <Gifticon>[
    for (int i = 0; i < count; i++)
      Gifticon(
        id: 'g$i',
        ownerId: 'user-1',
        brand: '브랜드$i',
        productName: '상품$i',
        category: '카페',
        price: 4500,
        expiryDate: now.add(Duration(days: 30 + i)),
        registeredAt: now,
        status: GifticonStatus.available,
      ),
  ];
}

void main() {
  late StreamController<List<Gifticon>> lists;
  late ProviderContainer container;

  setUp(() {
    lists = StreamController<List<Gifticon>>.broadcast();
    container = ProviderContainer(
      overrides: <Override>[
        rawGifticonsProvider.overrideWith((_) => lists.stream),
      ],
    );
  });

  tearDown(() {
    lists.close();
    container.dispose();
  });

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MainPage()),
        ),
      );

  testWidgets('강조가 목록보다 먼저 걸려도 목록 도착 후 강조가 유지된다', (WidgetTester tester) async {
    await mount(tester);
    await tester.pump();

    // 알림 탭 — 목록은 아직 비어 있다(저장소 응답 전).
    container.read(highlightedGifticonIdProvider.notifier).highlight('g0');
    await tester.pump();
    expect(find.text('상품0'), findsNothing, reason: '아직 목록이 없다');

    // 목록이 뒤늦게 도착한다.
    lists.add(_seed(6));
    await tester.pump();
    await tester.pump();

    expect(find.text('상품0'), findsOneWidget);
    expect(
      container.read(highlightedGifticonIdProvider),
      'g0',
      reason: '목록이 늦게 와도 강조는 살아 있어야 한다',
    );

    await tester.pump(highlightDuration + const Duration(seconds: 1));
  });

  testWidgets('강조가 만료되면 거둬진다 — 목록이 있어도 같다', (WidgetTester tester) async {
    await mount(tester);
    await tester.pump();
    lists.add(_seed(6));
    await tester.pump();
    await tester.pump();

    container.read(highlightedGifticonIdProvider.notifier).highlight('g1');
    await tester.pump();
    expect(container.read(highlightedGifticonIdProvider), 'g1');

    await tester.pump(highlightDuration + const Duration(seconds: 1));
    expect(container.read(highlightedGifticonIdProvider), isNull);
  });

  testWidgets('목록에 없는 대상이면 조용히 넘어간다(예외 없음)', (WidgetTester tester) async {
    await mount(tester);
    await tester.pump();
    lists.add(_seed(6));
    await tester.pump();
    await tester.pump();

    // 필터로 빠졌거나 이미 삭제된 기프티콘.
    container.read(highlightedGifticonIdProvider.notifier).highlight('없는id');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    await tester.pump(highlightDuration + const Duration(seconds: 1));
  });
}
