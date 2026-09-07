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
  Future<void> openSheet(WidgetTester tester, String groupId) async {
    // 팝업 본문(히어로+상세)이 기본 600px 뷰포트에서 잘려 버튼 탭이 빗나가지 않도록
    // 세로를 키운다. 검증 대상은 레이아웃이 아니라 확인 절차다.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
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

  testWidgets('만료일이 지난 후보는 팝업이 말로 알린다', (WidgetTester tester) async {
    // 후보 목록은 `status`만 보고 날짜는 보지 않으므로(`unsharedGifticonsProvider`),
    // 만료일이 지난 기프티콘도 그대로 후보에 뜬다 — 못 쓰는 것을 공유해 버리는 것이
    // 이 팝업이 막으려는 실수 중 하나다.
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons
        .addGifticon(gifticon(id: 'gx-1', expiryDate: DateTime(2020, 1, 1)));

    await openSheet(tester, g.id);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(find.text('만료일이 지난 기프티콘이에요. 그래도 공유할까요?'), findsOneWidget);
  });

  testWidgets('아직 유효한 후보에는 만료 안내를 띄우지 않는다', (WidgetTester tester) async {
    final Group g = await repo.createGroup(name: '가족', emoji: '🏠');
    await gifticons.addGifticon(gifticon(
      id: 'gx-1',
      expiryDate: DateTime.now().add(const Duration(days: 90)),
    ));

    await openSheet(tester, g.id);
    await tester.tap(find.text('아이스 아메리카노'));
    await tester.pumpAndSettle();

    expect(find.text('이 기프티콘을 공유할까요?'), findsOneWidget);
    expect(find.textContaining('만료일이 지난'), findsNothing);
  });
}
