/// 공유 시트 — **탭 한 번이 곧바로 쓰기가 되지 않는다**는 규약의 회귀 테스트.
///
/// 후보 타일은 상품명 한 줄과 `브랜드 · ~만료일` 한 줄이 전부라, 같은 브랜드 기프티콘을
/// 여러 장 가진 사용자에게는 어느 것을 눌렀는지 타일만으로 구분되지 않는다. 그런데 공유는
/// 되돌리려면 다른 화면의 공유 취소를 타야 하고, 그 사이 다른 멤버가 써 버리면 되돌릴
/// 방법 자체가 없다. 그래서 탭과 쓰기 사이에 **상세 확인 팝업**을 둔다.
///
/// 이 파일이 고정하는 것 넷:
/// ① 탭만으로는 저장소가 호출되지 않는다(팝업까지만 간다).
/// ② 팝업이 **누른 그 기프티콘의** 상세를 보여준다(금액·카테고리·만료일·바코드) — 이게
///    없으면 팝업은 확인 절차가 아니라 클릭 한 번 더일 뿐이다.
/// ③ '아니오'/바깥 탭은 공유하지 않는다(결과 없는 닫힘은 fail-closed).
/// ④ '예'를 눌러야 공유된다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/widgets/share_sheets.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String me = InMemoryAuthRepository.defaultUser.id;

  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository repo;

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    repo = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      seed: false,
    );
  });

  tearDown(() {
    repo.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  Gifticon gifticon({
    required String id,
    String productName = '아이스 아메리카노',
    int price = 3000,
    String category = '카페',
    String? barcode,
    DateTime? expiryDate,
  }) =>
      Gifticon(
        id: id,
        ownerId: me,
        brand: '메가커피',
        productName: productName,
        price: price,
        category: category,
        barcode: barcode,
        expiryDate: expiryDate ?? DateTime(2027, 1, 1),
        registeredAt: DateTime(2026, 1, 1),
      );

  /// 시트를 연 상태까지 만든다. 시트는 함수형 API라 진입점 버튼을 둔 호스트에서 연다.
  ///
  /// [size]·[textScale]은 좁은/큰 글꼴 화면에서 결정 버튼이 살아남는지 보는 축이고,
  /// [now]는 만료·임박 판정을 고정하기 위한 것이다(`nowProvider` 정본 override).
  Future<void> openSheet(
    WidgetTester tester,
    String groupId, {
    Size size = const Size(1000, 3000),
    double textScale = 1.0,
    DateTime? now,
  }) async {
    // 기본값은 본문이 잘리지 않는 큰 뷰포트다 — 대부분의 테스트가 보는 것은 레이아웃이
    // 아니라 확인 절차라, 탭이 스크롤 밖으로 빗나가는 소음을 없앤다.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(repo),
          if (now != null) nowProvider.overrideWithValue(now),
        ],
        child: MaterialApp(
          // 다이얼로그도 Navigator 안이라 이 builder가 함께 덮는다.
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showShareGifticonSheet(context, groupId),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<List<SharedGifticon>> sharedIn(String groupId) =>
      repo.watchSharedGifticons(groupId).first;

  testWidgets('후보를 탭하면 공유되지 않고 상세 확인 팝업이 먼저 뜬다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', barcode: '9412 3344 5566'));

    await openSheet(tester, g.id);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    // 질문 라벨과 두 선택지가 있다.
    expect(find.text('이 기프티콘을 공유할까요?'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '예'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '아니오'), findsOneWidget);

    // 상세가 실려 있다 — 타일에 없던 값들(금액·카테고리·바코드)이 대조의 근거다.
    expect(find.text('3,000원'), findsOneWidget);
    expect(find.text('카페'), findsOneWidget);
    expect(find.text('2027.01.01 만료'), findsOneWidget);
    expect(find.text('9412 3344 5566'), findsOneWidget);

    // 아직 아무것도 쓰지 않았다.
    expect(await sharedIn(g.id), isEmpty);
  });

  testWidgets('팝업은 목록이 아니라 누른 그 항목의 상세를 보여준다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons.addGifticon(gifticon(id: 'gx-1', price: 3000));
    await gifticons.addGifticon(gifticon(
      id: 'gx-2',
      productName: '카페라떼',
      price: 4500,
      category: '카페 · 라지',
    ));

    await openSheet(tester, g.id);
    await tester.tap(find.text('카페라떼'));
    await tester.pumpAndSettle();

    expect(find.text('4,500원'), findsOneWidget);
    expect(find.text('카페 · 라지'), findsOneWidget);
    // 고르지 않은 쪽의 값은 팝업에 없다(뒤에 깔린 시트 타일은 금액을 적지 않는다).
    expect(find.text('3,000원'), findsNothing);
  });

  testWidgets("'아니오'를 누르면 공유하지 않고 시트로 돌아간다", (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons.addGifticon(gifticon(id: 'gx-1'));

    await openSheet(tester, g.id);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '아니오'));
    await tester.pumpAndSettle();

    expect(await sharedIn(g.id), isEmpty);
    expect(find.text('이 기프티콘을 공유할까요?'), findsNothing);
    // 시트는 그대로 열려 있다 — 실수로 눌렀다면 옳은 항목을 다시 고를 수 있어야 한다.
    expect(find.text('내 기프티콘에서 선택'), findsOneWidget);
  });

  testWidgets('바깥을 눌러 닫아도 공유하지 않는다(결과 없는 닫힘은 아니오)',
      (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons.addGifticon(gifticon(id: 'gx-1'));

    await openSheet(tester, g.id);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();
    // 배리어(팝업 바깥)를 탭 — `showDialog`의 기본 동작으로 결과 없이 닫힌다.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('이 기프티콘을 공유할까요?'), findsNothing);
    expect(await sharedIn(g.id), isEmpty);
  });

  testWidgets("'예'를 누르면 공유되고 시트가 닫힌다", (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons.addGifticon(gifticon(id: 'gx-1'));

    await openSheet(tester, g.id);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '예'));
    await tester.pumpAndSettle();

    final List<SharedGifticon> shared = await sharedIn(g.id);
    expect(shared, hasLength(1));
    expect(shared.single.gifticonId, 'gx-1');
    expect(find.text('아이스 아메리카노를 공유했어요.'), findsOneWidget);
    expect(find.text('내 기프티콘에서 선택'), findsNothing); // 시트가 닫혔다.
  });

  // ── 만료·임박은 색이 아니라 문장으로 알린다 ────────────────────────────────
  //
  // 후보 목록은 `status`만 보고 날짜는 보지 않으므로(`unsharedGifticonsProvider`),
  // 만료일이 지났거나 코앞인 기프티콘도 그대로 후보에 뜬다. 붉은 글씨 한 줄로만 암시하면
  // 이 팝업이 막으려던 실수(못 쓰는 것을 공유)가 그대로 통과한다.
  //
  // 판정 시각은 `nowProvider` 정본을 override해 고정한다 — 실제 시계에 기대면 이 단언들이
  // 어느 날 갑자기 하루씩 밀린다.
  final DateTime fixedNow = DateTime(2026, 6, 1, 10);

  testWidgets('만료일이 지난 후보는 팝업이 말로 알린다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', expiryDate: DateTime(2026, 5, 31)));

    await openSheet(tester, g.id, now: fixedNow);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(find.text('만료일이 지난 기프티콘이에요. 그래도 공유할까요?'), findsOneWidget);
  });

  testWidgets('만료 임박(D-1) 후보는 남은 기간을 알린다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', expiryDate: DateTime(2026, 6, 2)));

    await openSheet(tester, g.id, now: fixedNow);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    // 임박은 실수가 아니라 정보다 — 캐묻지 않고 남은 기간만 말한다.
    expect(find.text('만료까지 1일 남은 기프티콘이에요.'), findsOneWidget);
    expect(find.textContaining('만료일이 지난'), findsNothing);
  });

  testWidgets('오늘 만료되는 후보는 그렇게 말한다(D-0은 아직 만료가 아니다)',
      (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', expiryDate: DateTime(2026, 6, 1)));

    await openSheet(tester, g.id, now: fixedNow);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 만료되는 기프티콘이에요.'), findsOneWidget);
  });

  testWidgets('넉넉히 남은 후보에는 만료 안내를 띄우지 않는다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', expiryDate: DateTime(2026, 9, 1)));

    await openSheet(tester, g.id, now: fixedNow);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(find.text('이 기프티콘을 공유할까요?'), findsOneWidget);
    expect(find.textContaining('만료일이 지난'), findsNothing);
    expect(find.textContaining('만료까지'), findsNothing);
  });

  testWidgets('세로가 짧고 글꼴이 큰 화면에서도 결정 버튼은 화면 안에 남는다',
      (WidgetTester tester) async {
    // 회귀 방어: 질문·배너까지 스크롤 밖에 고정으로 두면 가로 모드·분할 화면에서 고정분이
    // 가용 높이를 넘겨 '예'가 화면 밖으로 나갔다(배리어로 닫을 수만 있고 공유는 완료할 수
    // 없는 상태). 배너가 뜨는 만료 케이스가 임계가 가장 낮으므로 그 조합으로 잰다.
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons.addGifticon(gifticon(
      id: 'gx-1',
      barcode: '9412 3344 5566',
      expiryDate: DateTime(2026, 5, 31),
    ));

    await openSheet(
      tester,
      g.id,
      size: const Size(720, 360),
      textScale: 1.5,
      now: fixedNow,
    );
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // RenderFlex 오버플로 없음.
    final Rect yes = tester.getRect(find.widgetWithText(TextButton, '예'));
    // 뷰포트(360)가 아니라 **팝업의 아래끝**(360 − insetPadding 40 = 320)으로 잰다.
    // 뷰포트로 재면 40px 슬랙이 생겨, 회귀를 일으켜도 통과한다 — 결함을 되돌리고
    // 오버플로 단언만 무력화하면 336 ≤ 360으로 빠져나갔다(뮤테이션으로 확인).
    expect(yes.bottom, lessThanOrEqualTo(320.0));
    // 실제로 눌리기까지 확인한다 — 화면 안에 있어도 잘려 있으면 탭이 빗나간다.
    await tester.tap(find.widgetWithText(TextButton, '예'));
    await tester.pumpAndSettle();
    expect(await sharedIn(g.id), hasLength(1));
  });

  // 위 테스트의 **반대 방향**. 버튼을 살리려고 배너·질문을 스크롤 안으로 넣으면, 이번엔
  // 그것들이 첫 화면 밖으로 밀린다 — 사용자는 무엇을 묻는지도 만료 경고도 못 본 채
  // '예/아니오'만 본다. 그런데 **오버플로 예외가 나지 않아 조용히 지나간다**(위 테스트는
  // 이 상태를 green으로 통과시켰다). 그래서 위치로 직접 잰다.
  //
  // ⚠️ 뷰포트 목록에 **720x360@1.5를 반드시 포함한다.** 이 파일이 이미 쓰던 조합인데
  // 첫 화면 축이 그것을 비켜 갔고, 하필 거기서 배너가 밀린다(스크롤 뷰포트가 212px뿐이라
  // 질문·부제까지만 물리적으로 들어간다). 그래서 케이스마다 **그 높이에서 달성 가능한
  // 것**을 명시적으로 적는다 — 전부 같은 목록으로 뭉뚱그리면 좁은 화면이 목록에서 빠진다.
  for (final ({String label, Size size, double scale, List<String> visible}) c
      in <({String label, Size size, double scale, List<String> visible})>[
    (
      label: '360x640 기본 글꼴(구형·컴팩트 폰)',
      size: const Size(360, 640),
      scale: 1.0,
      // 대조 근거까지 전부 — 바코드는 "같은 브랜드·같은 상품 두 장"을 가르는 마지막
      // 단서라, 이게 첫 화면 밖이면 이 팝업의 존재 이유가 무너진다.
      visible: <String>[
        '이 기프티콘을 공유할까요?',
        '만료일이 지난 기프티콘이에요. 그래도 공유할까요?',
        '9412 3344 5566',
      ],
    ),
    (
      label: '360x800 글꼴 1.5배',
      size: const Size(360, 800),
      scale: 1.5,
      visible: <String>[
        '이 기프티콘을 공유할까요?',
        '만료일이 지난 기프티콘이에요. 그래도 공유할까요?',
      ],
    ),
    (
      label: '720x360 글꼴 1.5배(가로 모드·분할 화면)',
      size: const Size(720, 360),
      scale: 1.5,
      // 이 높이에는 배너까지 안 들어간다(위젯 주석의 '남은 구멍'). 적어도 **무엇을
      // 묻는지**는 항상 보인다는 것만 못박는다.
      visible: <String>['이 기프티콘을 공유할까요?', '공유하면 그룹 멤버 누구나 사용할 수 있어요.'],
    ),
  ]) {
    testWidgets('${c.label} — ${c.visible.length}개 항목이 첫 화면에 보인다',
        (WidgetTester tester) async {
      final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
      await gifticons.addGifticon(gifticon(
        id: 'gx-1',
        barcode: '9412 3344 5566',
        expiryDate: DateTime(2026, 5, 31), // 만료 → 배너가 뜨는 최악 조합.
      ));

      await openSheet(tester, g.id,
          size: c.size, textScale: c.scale, now: fixedNow);
      await tester.tap(find.text('아이스 아메리카노'));
      await tester.pumpAndSettle();

      final Rect viewport = tester.getRect(find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      ));
      for (final String text in c.visible) {
        expect(tester.getRect(find.text(text)).bottom,
            lessThanOrEqualTo(viewport.bottom),
            reason: '"$text"가 스크롤 아래로 밀렸다 — 스크롤하지 않으면 안 보인다');
      }
    });
  }

  // 임박 배너의 임계(`expirySoonDays` = 7). 이 경계가 비어 있으면 임계를 조용히
  // 바꿔도 아무도 모른다 — D-1·D-0·D-92만으로는 3으로 좁혀도 전부 통과했다(뮤테이션).
  testWidgets('임박 경계 — D-7은 알린다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', expiryDate: DateTime(2026, 6, 8)));

    await openSheet(tester, g.id, now: fixedNow); // 2026-06-01 → D-7
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(find.text('만료까지 7일 남은 기프티콘이에요.'), findsOneWidget);
  });

  testWidgets('임박 경계 — D-8은 알리지 않는다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', expiryDate: DateTime(2026, 6, 9)));

    await openSheet(tester, g.id, now: fixedNow); // 2026-06-01 → D-8
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(find.textContaining('만료까지'), findsNothing);
  });

  testWidgets('팝업이 라우트 이름을 알리고, 버튼 이름에 무엇에 대한 예/아니오인지 담는다',
      (WidgetTester tester) async {
    // `namesRoute`/`semanticsLabel`이 실제로 트리에 실리는지. 저장소에 시맨틱스 회귀
    // 테스트가 하나도 없어(`grep ensureSemantics test/` → 0건) 이 층이 비어 있었다.
    final SemanticsHandle handle = tester.ensureSemantics();
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons.addGifticon(gifticon(id: 'gx-1'));

    await openSheet(tester, g.id);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    // 라벨 존재만 보면 `namesRoute`를 지워도 통과한다(뮤테이션으로 확인) — 다이얼로그
    // 진입을 **라우트 이름으로 읽어 주게** 하는 것은 그 플래그다. 플래그까지 단언한다.
    expect(
      tester.getSemantics(find.bySemanticsLabel('기프티콘 공유 확인')),
      // `containsSemantics`는 v3.40 이후 deprecated — 같은 부분 매칭을 하는 후속이다.
      isSemantics(label: '기프티콘 공유 확인', namesRoute: true),
    );
    expect(find.bySemanticsLabel('예, 공유하기'), findsOneWidget);
    expect(find.bySemanticsLabel('아니오, 공유하지 않기'), findsOneWidget);
    // 라우트 이름이 본문을 삼키지 않는지 — 질문이 자기 노드로 남아야 한다.
    expect(find.bySemanticsLabel('이 기프티콘을 공유할까요?'), findsOneWidget);
    handle.dispose();
  });
}
