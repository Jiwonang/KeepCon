/// 홈 검색바 + 정렬/필터 진입점 — 동작을 고정하는 테스트.
///
/// 고정할 것은 넷이다:
/// 1. **검색은 다른 필터와 AND로 묶인다** — 결합을 `GifticonFilter.matches` 한 곳에서만
///    하는지 확인한다. 검색만 따로 걸러 내면 헤더가 센 개수와 목록에 남은 개수가 갈린다
///    (이 화면이 만료 배너에서 이미 한 번 밟은 함정이다).
/// 2. **역방향 동기화** — 헤더의 해제(×)로 필터를 통째로 되돌리면 검색창의 글자도 함께
///    사라져야 한다. 안 그러면 목록은 전체인데 검색창에는 글자가 남아, 사용자는 "검색
///    중인데 왜 다 보이지"를 만난다.
/// 3. **빈 상태 문구가 상황을 구분한다** — 하나도 없는 것과 걸러져서 안 보이는 것에
///    같은 문구("새 기프티콘을 추가해 보세요")를 쓰면 가진 것이 사라졌다고 읽힌다.
/// 4. **죽은 진입점이 되살아났다** — 필터 버튼과 정렬 라벨은 그려만 놓고 눌리지 않았다
///    (`onTap: () {}` / onTap 없음). 둘 다 같은 시트를 여는지 고정한다.
///
/// 픽스처·harness 이디엄은 `expiry_banner_test.dart`와 같다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/features/main/state/gifticon_filter.dart';
import 'package:keepcon/features/main/state/gifticon_list_providers.dart';
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

  /// 고정 기준 시각(실제 시계 금지 — 자정을 넘기면 경계 테스트가 통째로 밀린다).
  final DateTime fixedNow = DateTime(2030, 5, 15, 10, 0);

  Gifticon g(
    String id, {
    int daysLeft = 30,
    GifticonStatus status = GifticonStatus.available,
    String brand = '스타벅스',
    String productName = '아메리카노 T',
    String category = '카페',
  }) =>
      Gifticon(
        id: id,
        ownerId: me.id,
        brand: brand,
        productName: productName,
        category: category,
        price: 4500,
        expiryDate: fixedNow.add(Duration(days: daysLeft)),
        registeredAt: fixedNow,
        status: status,
      );

  ProviderContainer containerWith(List<Gifticon> seed) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider
            .overrideWithValue(InMemoryGifticonRepository(seed: seed)),
        sessionUserProvider.overrideWith((_) => Stream<User?>.value(me)),
        nowProvider.overrideWithValue(fixedNow),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  List<String> visibleIds(ProviderContainer container) =>
      (container.read(visibleGifticonsProvider).valueOrNull ??
              const <Gifticon>[])
          .map((Gifticon x) => x.id)
          .toList();

  Future<ProviderContainer> pumpHome(
    WidgetTester tester,
    List<Gifticon> seed,
  ) async {
    final ProviderContainer container = containerWith(seed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  // ───────────────────────── GifticonFilter — 순수 로직 ─────────────────────────

  group('GifticonFilter — 검색어 정규화', () {
    test('앞뒤 공백을 없애고 소문자로 접어 보관한다', () {
      expect(
        GifticonFilter.none.withSearchQuery('  StarBucks  ').searchQuery,
        'starbucks',
      );
    });

    test('공백뿐인 입력은 검색 해제로 본다', () {
      final GifticonFilter f = GifticonFilter.none.withSearchQuery('   ');
      expect(f.searchQuery, isEmpty);
      expect(f.hasSearchQuery, isFalse);
    });

    test('정규화 결과가 같으면 같은 필터다 — 목록이 헛되이 재계산되지 않는다', () {
      expect(
        GifticonFilter.none.withSearchQuery('스벅'),
        GifticonFilter.none.withSearchQuery(' 스벅 '),
      );
    });
  });

  group('GifticonFilter — 검색 매칭', () {
    final Gifticon starbucks = g('a', brand: '스타벅스', productName: '아메리카노 T');

    bool matches(String query) => GifticonFilter.none
        .withSearchQuery(query)
        .matches(starbucks, now: fixedNow);

    test('브랜드 부분일치로 통과한다', () => expect(matches('스타'), isTrue));

    test('상품명 부분일치로도 통과한다 — 둘 중 하나만 맞으면 된다',
        () => expect(matches('아메리'), isTrue));

    test('어느 쪽에도 없으면 걸러진다', () => expect(matches('버거'), isFalse));

    test('대소문자를 가리지 않는다', () {
      final Gifticon cu = g('b', brand: 'CU', productName: 'Americano');
      expect(
        GifticonFilter.none.withSearchQuery('cu').matches(cu, now: fixedNow),
        isTrue,
      );
      expect(
        GifticonFilter.none.withSearchQuery('AMERI').matches(cu, now: fixedNow),
        isTrue,
      );
    });
  });

  group('GifticonFilter — 다른 조건과의 결합', () {
    test('검색과 카테고리는 AND다 — 둘 다 맞아야 남는다', () {
      final GifticonFilter f =
          GifticonFilter.none.withCategory('편의점').withSearchQuery('스타');

      // 카테고리는 맞지만 검색어가 안 맞는다.
      expect(
        f.matches(g('x', brand: 'CU', category: '편의점'), now: fixedNow),
        isFalse,
      );
      // 검색어는 맞지만 카테고리가 안 맞는다.
      expect(
        f.matches(g('y', brand: '스타벅스', category: '카페'), now: fixedNow),
        isFalse,
      );
      // 둘 다 맞는다.
      expect(
        f.matches(g('z', brand: '스타벅스', category: '편의점'), now: fixedNow),
        isTrue,
      );
    });

    test('검색과 만료 임박도 AND다', () {
      final GifticonFilter f =
          GifticonFilter.none.withExpiringSoonOnly(true).withSearchQuery('스타');

      expect(
        f.matches(g('soon', daysLeft: 3, brand: '스타벅스'), now: fixedNow),
        isTrue,
      );
      expect(
        f.matches(g('later', daysLeft: 40, brand: '스타벅스'), now: fixedNow),
        isFalse,
      );
    });

    test('withSearchQuery는 이미 걸린 다른 조건을 보존한다', () {
      final GifticonFilter f = GifticonFilter.none
          .withStatus(GifticonStatus.used)
          .withCategory('카페')
          .withExpiringSoonOnly(true)
          .withSearchQuery('스벅');

      expect(f.statusFilter, GifticonStatus.used);
      expect(f.categoryFilter, '카페');
      expect(f.expiringSoonOnly, isTrue);
      expect(f.searchQuery, '스벅');
    });
  });

  group('GifticonFilter — 활성 여부 구분', () {
    final GifticonFilter searchOnly = GifticonFilter.none.withSearchQuery('스벅');

    test('검색어는 계약 FilterOption이 아니므로 hasOptionFilter에 세지 않는다', () {
      expect(searchOnly.hasOptionFilter, isFalse);
    });

    test('그래도 isAnyActive다 — 헤더의 해제(×)가 나와야 한다', () {
      expect(searchOnly.isAnyActive, isTrue);
    });

    test('아무것도 안 걸리면 비활성이다', () {
      expect(GifticonFilter.none.isAnyActive, isFalse);
      expect(GifticonFilter.none.hasSearchQuery, isFalse);
    });
  });

  // ───────────────────────── 목록 파이프라인 ─────────────────────────

  group('visibleGifticonsProvider — 검색 적용', () {
    test('검색어를 걸면 목록이 줄고, 정렬은 그대로 유지된다', () async {
      final ProviderContainer container = containerWith(<Gifticon>[
        g('sb-far', daysLeft: 40, brand: '스타벅스'),
        g('sb-soon', daysLeft: 2, brand: '스타벅스'),
        g('cu', daysLeft: 1, brand: 'CU'),
      ]);
      container.listen<AsyncValue<List<Gifticon>>>(
          visibleGifticonsProvider, (_, __) {});
      await pumpEventQueue();

      expect(visibleIds(container), <String>['cu', 'sb-soon', 'sb-far']);

      container.read(filterProvider.notifier).state =
          container.read(filterProvider).withSearchQuery('스타');
      await pumpEventQueue();

      // CU가 빠지고, 남은 둘은 여전히 만료임박순(기본 정렬)이다.
      expect(visibleIds(container), <String>['sb-soon', 'sb-far']);
    });
  });

  // ───────────────────────── 홈 화면 ─────────────────────────

  group('홈 검색바', () {
    testWidgets('입력하면 목록이 걸러지고 헤더가 "검색 결과 N개"로 바뀐다',
        (WidgetTester tester) async {
      final ProviderContainer container = await pumpHome(tester, <Gifticon>[
        g('sb', brand: '스타벅스'),
        g('cu', brand: 'CU', productName: '삼각김밥'),
      ]);

      expect(find.text('전체 2개'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '스타');
      await tester.pumpAndSettle();

      expect(container.read(filterProvider).searchQuery, '스타');
      expect(visibleIds(container), <String>['sb']);
      expect(find.text('검색 결과 1개'), findsOneWidget,
          reason: '걸러진 목록을 "전체"라고 부르면 기프티콘이 사라졌다고 읽힌다');
    });

    testWidgets('헤더의 해제(×)는 검색창의 글자까지 함께 비운다', (WidgetTester tester) async {
      // 역방향 동기화 회귀 — 필터만 풀리고 입력창에 글자가 남으면 "검색 중인데 왜 다
      // 보이지"가 된다.
      final ProviderContainer container = await pumpHome(tester, <Gifticon>[
        g('sb', brand: '스타벅스'),
        g('cu', brand: 'CU'),
      ]);

      await tester.enterText(find.byType(TextField), '스타');
      await tester.pumpAndSettle();
      expect(visibleIds(container), <String>['sb']);

      // 섹션 헤더의 해제(×) — 검색창 안의 지우기 버튼과 구분해서 집는다.
      await tester.tap(find.descendant(
        of: find.byType(InkResponse),
        matching: find.byIcon(Icons.close),
      ));
      await tester.pumpAndSettle();

      expect(container.read(filterProvider), GifticonFilter.none);
      expect(visibleIds(container), <String>['sb', 'cu']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
    });

    testWidgets('검색창의 지우기 버튼도 검색을 푼다', (WidgetTester tester) async {
      final ProviderContainer container =
          await pumpHome(tester, <Gifticon>[g('sb', brand: '스타벅스')]);

      await tester.enterText(find.byType(TextField), '스타');
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(TextField),
        matching: find.byType(IconButton),
      ));
      await tester.pumpAndSettle();

      expect(container.read(filterProvider).hasSearchQuery, isFalse);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
    });

    testWidgets('검색과 만료 임박이 겹치면 나머지 조건이 걸린 것을 헤더가 알린다',
        (WidgetTester tester) async {
      await pumpHome(tester, <Gifticon>[
        g('soon', daysLeft: 2, brand: '스타벅스'),
        g('far', daysLeft: 40, brand: '스타벅스'),
      ]);

      await tester.tap(find.text('확인')); // 만료 임박 필터 on
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '스타');
      await tester.pumpAndSettle();

      expect(find.text('검색 결과 1개 · 필터 적용'), findsOneWidget);
    });
  });

  group('홈 빈 상태 문구', () {
    testWidgets('검색 결과가 0건이면 조건을 바꾸라고 안내한다', (WidgetTester tester) async {
      await pumpHome(tester, <Gifticon>[g('sb', brand: '스타벅스')]);

      await tester.enterText(find.byType(TextField), '없는브랜드');
      await tester.pumpAndSettle();

      expect(find.textContaining('조건에 맞는 기프티콘이 없습니다'), findsOneWidget);
      expect(find.textContaining('새 기프티콘을 추가해'), findsNothing,
          reason: '걸러져서 안 보이는 것을 "없으니 추가하라"고 하면 가진 것이 사라졌다고 읽힌다');
    });

    testWidgets('정말 하나도 없으면 추가를 권한다', (WidgetTester tester) async {
      await pumpHome(tester, const <Gifticon>[]);

      expect(find.textContaining('새 기프티콘을 추가해'), findsOneWidget);
    });
  });

  group('정렬/필터 시트 진입점', () {
    testWidgets('필터 버튼을 누르면 시트가 열린다', (WidgetTester tester) async {
      await pumpHome(tester, <Gifticon>[g('sb')]);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(find.text('정렬 · 필터'), findsOneWidget);
      expect(find.text('상태 전체'), findsOneWidget);
      expect(find.text('카테고리 전체'), findsOneWidget);
    });

    testWidgets('정렬 라벨을 눌러도 같은 시트가 열린다', (WidgetTester tester) async {
      // 화살표까지 그려 놓고 눌리지 않으면 고장으로 읽힌다.
      await pumpHome(tester, <Gifticon>[g('sb')]);

      await tester.tap(find.text('만료임박순'));
      await tester.pumpAndSettle();

      expect(find.text('정렬 · 필터'), findsOneWidget);
    });

    testWidgets('시트에서 고른 정렬이 목록에 반영된다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpHome(tester, <Gifticon>[
        g('sb', daysLeft: 40, brand: '스타벅스'),
        g('cu', daysLeft: 2, brand: 'CU'),
      ]);
      expect(visibleIds(container), <String>['cu', 'sb']);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.tap(find.text('만료임박순').last); // 정렬 드롭다운을 연다
      await tester.pumpAndSettle();
      await tester.tap(find.text('브랜드명순').last);
      await tester.pumpAndSettle();

      expect(container.read(sortOptionProvider), SortOption.brandAsc);
      expect(visibleIds(container), <String>['cu', 'sb'],
          reason: 'CU < 스타벅스 (사전순)');
    });
  });
}
