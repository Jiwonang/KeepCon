/// 홈 만료 임박 배너 — 목록 파생·문구·확인 버튼 동작을 고정하는 테스트.
///
/// 고정할 것은 셋이다:
/// 1. **판정 경계** — `expiringSoonGifticonsProvider`가 D-0~D-7만 담고, 이미 만료된 것과
///    사용 완료(`used`)는 뺀다. 이 경계가 흔들리면 배너·통계 카드·만료 알림이 동시에
///    어긋난다(판정은 계약 `expiry_policy.dart` SSOT에 위임돼 있다).
/// 2. **개수와 대표 항목이 한 원천에서 나온다** — 예전 배너는 개수를 원천 통계에서,
///    대표 브랜드를 **필터·정렬이 끝난 표시 목록**에서 각각 가져왔다. 그래서 필터를 걸면
///    "3개 만료"인데 제목은 폴백 '기프티콘'이 뜨는 불일치가 났다. 필터를 걸어도 배너가
///    원천 기준을 유지하는지 확인한다.
/// 3. **확인 버튼이 실제로 목록을 거른다** — 승격 전에는 `onTap: () {}` 빈 콜백이라
///    눌러도 아무 일이 없었다. 되돌릴 수단(토글·헤더 해제)까지 함께 고정한다.
///
/// repository를 SSOT provider에 override 하는 이디엄은 `main_session_consumer_test.dart`와 같다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/features/main/state/gifticon_filter.dart';
import 'package:keepcon/features/main/state/gifticon_list_providers.dart';
import 'package:keepcon/features/main/state/gifticon_stats.dart';
import 'package:keepcon/features/main/state/now_provider.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

void main() {
  const User me = User(
    id: 'user-1',
    email: 'me@keepcon.app',
    displayName: '나',
  );

  /// 고정 기준 시각. **실제 시계를 쓰지 않는다** — 픽스처를 `DateTime.now()`로 만들고
  /// 프로덕션도 자기 시계를 읽으면, 실행이 로컬 자정을 넘기는 순간 모든 픽스처가 하루씩
  /// 밀려 경계 테스트가 통째로 깨진다(재현 불가능한 red CI).
  ///
  /// 실제 오늘과 한참 떨어진 날짜인 것도 의도다: 프로덕션 코드 어딘가가 [nowProvider]를
  /// 안 거치고 `DateTime.now()`를 직접 읽으면 D-day가 수천 일로 튀어 **테스트가 즉시
  /// 실패한다**. 오늘과 가까운 값이면 그 실수가 조용히 통과한다.
  final DateTime fixedNow = DateTime(2030, 5, 15, 10, 0);

  /// 만료까지 [daysLeft]일 남은 기프티콘. 음수면 이미 만료된 것.
  Gifticon g(
    String id, {
    required int daysLeft,
    GifticonStatus status = GifticonStatus.available,
    String brand = '스타벅스',
    String productName = '아메리카노 T',
  }) =>
      Gifticon(
        id: id,
        ownerId: me.id,
        brand: brand,
        productName: productName,
        category: '카페',
        price: 4500,
        expiryDate: fixedNow.add(Duration(days: daysLeft)),
        registeredAt: fixedNow,
        status: status,
      );

  /// [now]를 주면 그 시각으로 화면을 구성한다(날짜 경과 시뮬레이션). 기본은 [fixedNow].
  ProviderContainer containerWith(List<Gifticon> seed, {DateTime? now}) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider
            .overrideWithValue(InMemoryGifticonRepository(seed: seed)),
        sessionUserProvider.overrideWith((_) => Stream<User?>.value(me)),
        nowProvider.overrideWithValue(now ?? fixedNow),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<String>> expiringSoonIds(List<Gifticon> seed) async {
    final ProviderContainer container = containerWith(seed);
    container.listen<List<Gifticon>>(expiringSoonGifticonsProvider, (_, __) {});
    await pumpEventQueue();
    return container
        .read(expiringSoonGifticonsProvider)
        .map((Gifticon x) => x.id)
        .toList();
  }

  List<String> visibleIds(ProviderContainer container) =>
      (container.read(visibleGifticonsProvider).valueOrNull ??
              const <Gifticon>[])
          .map((Gifticon x) => x.id)
          .toList();

  /// [seed]를 담은 홈 화면을 띄운다. 반환된 container로 필터 상태를 검사한다.
  Future<ProviderContainer> pumpHome(
    WidgetTester tester,
    List<Gifticon> seed, {
    DateTime? now,
  }) async {
    final ProviderContainer container = containerWith(seed, now: now);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('expiringSoonGifticonsProvider — 판정 경계', () {
    test('D-0(오늘 만료)과 D-7(임계 당일)은 포함한다', () async {
      final List<String> ids = await expiringSoonIds(<Gifticon>[
        g('today', daysLeft: 0),
        g('edge', daysLeft: 7),
      ]);
      expect(ids, containsAll(<String>['today', 'edge']),
          reason: '만료일 당일은 아직 쓸 수 있고, 임계값 7일은 이하이므로 임박이다');
    });

    test('D-8은 제외한다', () async {
      expect(await expiringSoonIds(<Gifticon>[g('far', daysLeft: 8)]), isEmpty);
    });

    test('이미 만료된 것은 임박이 아니다', () async {
      // 하한(0)이 없던 시절 `daysLeft <= 7`은 음수도 통과시켜 만료된 것을 임박으로 셌다.
      expect(
          await expiringSoonIds(<Gifticon>[g('gone', daysLeft: -1)]), isEmpty);
    });

    test('사용 완료(used)는 남은 날짜와 무관하게 제외한다', () async {
      final List<String> ids = await expiringSoonIds(<Gifticon>[
        g('used', daysLeft: 2, status: GifticonStatus.used),
        g('live', daysLeft: 2),
      ]);
      expect(ids, <String>['live']);
    });

    test('만료 임박순으로 정렬한다 — 배너가 first를 "가장 급한 것"으로 쓴다', () async {
      final List<String> ids = await expiringSoonIds(<Gifticon>[
        g('d5', daysLeft: 5),
        g('d1', daysLeft: 1),
        g('d3', daysLeft: 3),
      ]);
      expect(ids, <String>['d1', 'd3', 'd5']);
    });

    test('통계의 만료 임박 개수는 이 목록의 길이와 항상 같다', () async {
      // 조건을 두 곳에 적으면 한쪽만 고쳐져 어긋난다 — 통계가 목록을 재사용하는지 고정.
      final ProviderContainer container = containerWith(<Gifticon>[
        g('a', daysLeft: 1),
        g('b', daysLeft: 6),
        g('c', daysLeft: 30),
        g('d', daysLeft: -3),
      ]);
      container.listen<GifticonStats>(gifticonStatsProvider, (_, __) {});
      await pumpEventQueue();

      expect(container.read(gifticonStatsProvider).expiringSoonCount, 2);
      expect(container.read(expiringSoonGifticonsProvider).length, 2);
    });
  });

  group('만료 배너 — 렌더링', () {
    testWidgets('임박한 것이 없으면 배너를 그리지 않는다', (WidgetTester tester) async {
      await pumpHome(tester, <Gifticon>[g('far', daysLeft: 30)]);

      expect(find.textContaining('곧 만료'), findsNothing);
      expect(find.text('확인'), findsNothing);
    });

    testWidgets('1개면 상품명과 남은 일수를 보여준다', (WidgetTester tester) async {
      await pumpHome(tester, <Gifticon>[
        g('a', daysLeft: 3, brand: '스타벅스', productName: '아메리카노 T'),
      ]);

      expect(find.text('스타벅스 곧 만료!'), findsOneWidget);
      expect(find.text('아메리카노 T · 3일 뒤 만료'), findsOneWidget);
    });

    testWidgets('오늘 만료면 "오늘 만료"로 읽힌다', (WidgetTester tester) async {
      await pumpHome(tester, <Gifticon>[g('a', daysLeft: 0)]);

      expect(find.textContaining('오늘 만료'), findsOneWidget);
    });

    testWidgets('여러 개면 가장 급한 브랜드와 나머지 개수를 보여준다', (WidgetTester tester) async {
      await pumpHome(tester, <Gifticon>[
        g('d5', daysLeft: 5, brand: 'CU'),
        g('d1', daysLeft: 1, brand: '스타벅스'),
        g('d3', daysLeft: 3, brand: 'GS25'),
      ]);

      // 정렬본의 first = D-1 스타벅스.
      expect(find.text('스타벅스 외 2개 곧 만료!'), findsOneWidget);
      expect(find.text('3개의 기프티콘이 7일 내 만료됩니다'), findsOneWidget);
    });
  });

  group('만료 배너 — 확인 버튼', () {
    testWidgets('확인을 누르면 목록이 만료 임박 건만 남는다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpHome(tester, <Gifticon>[
        g('soon', daysLeft: 2, brand: '스타벅스'),
        g('later', daysLeft: 40, brand: '메가커피'),
      ]);

      expect(find.text('전체 2개'), findsOneWidget);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(container.read(filterProvider).expiringSoonOnly, isTrue);
      expect(visibleIds(container), <String>['soon']);
      expect(find.text('만료 임박 1개'), findsOneWidget,
          reason: '걸러진 목록을 "전체"라고 부르면 기프티콘이 사라졌다고 읽힌다');
    });

    testWidgets('필터 결과는 배너가 센 목록과 정확히 일치한다', (WidgetTester tester) async {
      // 배너 목록과 목록 필터가 같은 술어(isExpiringSoonGifticon)를 쓰는지 고정한다.
      // 조건이 두 곳으로 갈라지면 "3개 만료"라고 알린 뒤 필터를 걸었을 때 2개만 남는
      // 식으로 어긋난다.
      final ProviderContainer container = await pumpHome(tester, <Gifticon>[
        g('d1', daysLeft: 1),
        g('d7', daysLeft: 7),
        g('d8', daysLeft: 8),
        g('used', daysLeft: 2, status: GifticonStatus.used),
        g('gone', daysLeft: -1),
      ]);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      final List<String> bannerIds = container
          .read(expiringSoonGifticonsProvider)
          .map((Gifticon x) => x.id)
          .toList();
      expect(bannerIds, <String>['d1', 'd7']);
      expect(visibleIds(container), bannerIds);
    });

    testWidgets('날짜가 하루 지나도 배너와 필터가 같은 시계를 본다', (WidgetTester tester) async {
      // 회귀 방지: 배너 목록과 표시 목록이 각자 `DateTime.now()`를 읽던 시절, 두
      // provider는 **무효화 트리거도 달랐다** — 배너 목록은 원천이 바뀔 때만, 표시
      // 목록은 필터가 바뀔 때도 재계산됐다. 그래서 자정을 넘긴 뒤 확인을 누르면 배너는
      // 어제 기준, 목록은 오늘 기준으로 판정해 개수가 갈렸다. 술어를 하나로 합쳐도
      // 시계가 갈리면 답은 그대로 갈린다.
      //
      // D-8 항목은 기준일엔 임박이 아니지만 하루 뒤엔 D-7이라 임박이 된다 — 두 소비자가
      // 같은 시각을 봐야만 둘 다 "임박"으로 답한다.
      final ProviderContainer container = await pumpHome(
        tester,
        <Gifticon>[g('d8', daysLeft: 8), g('far', daysLeft: 40)],
        now: fixedNow.add(const Duration(days: 1)),
      );

      expect(
        container.read(expiringSoonGifticonsProvider).map((Gifticon x) => x.id),
        <String>['d8'],
        reason: '하루 지났으므로 D-8이던 것이 D-7이 되어 임박이다',
      );

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(visibleIds(container), <String>['d8'],
          reason: '필터도 같은 시각으로 판정해야 배너가 센 것과 일치한다');
      expect(find.text('만료 임박 1개'), findsOneWidget);
    });

    testWidgets('필터가 걸려도 배너는 원천 기준을 유지한다', (WidgetTester tester) async {
      // 예전 버그 재발 방지: 대표 항목을 표시 목록에서 뽑으면 필터 적용 후 제목이 흔들렸다.
      await pumpHome(tester, <Gifticon>[
        g('soon', daysLeft: 2, brand: '스타벅스'),
        g('later', daysLeft: 40, brand: '메가커피'),
      ]);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      expect(find.text('스타벅스 곧 만료!'), findsOneWidget);
    });

    testWidgets('버튼은 토글이다 — 해제를 누르면 필터가 풀린다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpHome(tester, <Gifticon>[
        g('soon', daysLeft: 2),
        g('later', daysLeft: 40),
      ]);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('해제'), findsOneWidget,
          reason: '홈에 필터 컨트롤이 없어 이 버튼이 유일한 해제 수단이다');

      await tester.tap(find.text('해제'));
      await tester.pumpAndSettle();

      expect(container.read(filterProvider), GifticonFilter.none);
      expect(find.text('전체 2개'), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
    });

    testWidgets('섹션 헤더의 X로도 필터를 풀 수 있다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpHome(tester, <Gifticon>[
        g('soon', daysLeft: 2),
        g('later', daysLeft: 40),
      ]);

      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(container.read(filterProvider), GifticonFilter.none);
      expect(find.text('전체 2개'), findsOneWidget);
    });
  });
}
