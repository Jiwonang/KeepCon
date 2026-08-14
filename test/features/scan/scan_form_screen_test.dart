/// scan — **앱이 실제로 띄우는 등록 폼**의 위젯 테스트.
///
/// ## 이 파일이 있는 이유
///
/// scan 폼은 코드가 두 벌이다. 테스트가 검증해 온 `GifticonForm`
/// (`widgets/gifticon_form.dart`)은 **앱 어디에서도 렌더링되지 않고**, 사용자가
/// 실제로 보는 것은 `scan_page.dart`의 `_GifticonFormScreen`이다. 그래서 전체 테스트가
/// 초록이어도 진짜 등록 화면은 커버리지가 0이었고, "저장되었습니다"만 뜨고 홈에는
/// 아무것도 없던 버그들이 CI를 통과한 채 살아 있었다.
///
/// 이 파일은 그 구멍을 메운다 — **사용자 경로 그대로** [ScanPage]를 띄우고
/// '직접 입력하기'를 눌러 진짜 폼 화면에 들어간 뒤 검증한다.
/// (`_GifticonFormScreen`이 private이라 직접 pump할 수 없는 것이 오히려 낫다.
///  경로를 통째로 지나야 이 파일이 막으려는 회귀를 잡을 수 있다.)
///
/// ## 검증 대상
/// 1. 필수 항목이 비면 저장이 **막히고** 화면에 머문다 (유효기간 포함).
/// 2. 금액은 선택 입력이라 비워도 저장되며 계약에는 0원으로 들어간다.
/// 3. 금액 입력에 천 단위 콤마가 붙고, 계약에는 콤마 없는 정수로 들어간다.
/// 4. 이미 등록된 바코드는 저장되지 않고 필드에 안내가 뜬다.
/// 5. 저장 버튼 연타로 같은 기프티콘이 두 번 저장되지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  /// 저장 결과를 직접 들여다보기 위해 Repository 인스턴스를 손에 쥔 채 주입한다.
  late InMemoryGifticonRepository repo;

  ProviderContainer makeContainer({List<Gifticon> seed = const <Gifticon>[]}) {
    repo = InMemoryGifticonRepository(seed: seed);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 이미 등록돼 있는 기프티콘(중복 검사 대상).
  Gifticon existing({required String barcode}) {
    return Gifticon(
      id: 'g_existing',
      ownerId: myId,
      brand: '스타벅스',
      productName: '아이스 카페 아메리카노T',
      price: 4500,
      barcode: barcode,
      category: '카페',
      expiryDate: DateTime(2027, 1, 31),
      registeredAt: DateTime(2026, 1, 1),
    );
  }

  /// [ScanPage]를 띄우고 '직접 입력하기'로 진짜 폼 화면까지 들어간다.
  Future<ProviderContainer> openManualForm(WidgetTester tester,
      {List<Gifticon> seed = const <Gifticon>[]}) async {
    // 폼 전체가 한 화면에 들어와야 탭이 스크롤에 걸리지 않는다.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProviderContainer container = makeContainer(seed: seed);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ScanPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('직접 입력하기'));
    await tester.pumpAndSettle();

    // 폼 화면에 도착했는지 먼저 확인한다 — 여기서 어긋나면 이후 실패가 엉뚱하게 읽힌다.
    expect(find.text('기프티콘 정보 확인'), findsOneWidget);

    return container;
  }

  /// 라벨로 입력 필드를 찾는다(폼에 TextFormField가 여러 개라 위치가 아니라 라벨 기준).
  Finder fieldByLabel(String label) {
    return find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );
  }

  Future<void> fillRequired(
    WidgetTester tester, {
    String brand = '스타벅스',
    String productName = '아메리카노 T',
    required String barcode,
    String? price,
  }) async {
    await tester.enterText(fieldByLabel('브랜드 / 사용처'), brand);
    await tester.enterText(fieldByLabel('상품명'), productName);
    await tester.enterText(fieldByLabel('바코드 번호'), barcode);

    if (price != null) {
      await tester.enterText(fieldByLabel('금액 / 금액권 잔액 (선택)'), price);
    }

    await tester.pumpAndSettle();
  }

  /// 유효기간 칸을 눌러 날짜 선택기를 띄우고 기본값(오늘)으로 확정한다.
  Future<void> pickExpiryDate(WidgetTester tester) async {
    await tester.tap(find.text('날짜를 선택해 주세요'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, '저장하기'));
    await tester.pumpAndSettle();
  }

  testWidgets('필수 항목이 비면 저장이 막히고 폼 화면에 머문다', (WidgetTester tester) async {
    await openManualForm(tester);

    await tapSave(tester);

    // 각 필수 항목에 안내가 뜬다.
    expect(find.text('브랜드를 입력해 주세요.'), findsOneWidget);
    expect(find.text('상품명을 입력해 주세요.'), findsOneWidget);

    // 유효기간은 Form validator가 없어 그냥 통과하던 구멍이었다 — 회귀 방지.
    expect(find.text('유효기간을 선택해 주세요.'), findsOneWidget);

    // 성공 문구가 뜨지 않고(가짜 성공 회귀 방지) 폼 화면에 그대로 남는다.
    expect(find.text('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);
    expect(find.text('기프티콘 정보 확인'), findsOneWidget);

    expect(await repo.getGifticons(myId), isEmpty);
  });

  testWidgets('유효기간만 비어도 저장되지 않는다', (WidgetTester tester) async {
    await openManualForm(tester);

    await fillRequired(tester, barcode: '8801234567890');
    // 날짜는 고르지 않는다.
    await tapSave(tester);

    expect(find.text('유효기간을 선택해 주세요.'), findsOneWidget);
    expect(find.text('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);
    expect(await repo.getGifticons(myId), isEmpty);
  });

  testWidgets('금액을 비워도 저장되고 계약에는 0원으로 들어간다', (WidgetTester tester) async {
    await openManualForm(tester);

    await fillRequired(tester, barcode: '8801234567890');
    await pickExpiryDate(tester);
    await tapSave(tester);

    final List<Gifticon> saved = await repo.getGifticons(myId);

    expect(saved, hasLength(1));
    expect(saved.single.price, 0);
    expect(saved.single.barcode, '8801234567890');
    expect(saved.single.status, GifticonStatus.available);
  });

  testWidgets('금액에 천 단위 콤마가 붙고 계약에는 정수로 들어간다', (WidgetTester tester) async {
    await openManualForm(tester);

    await fillRequired(
      tester,
      barcode: '8801234567890',
      price: '1500000',
    );

    // 화면에는 콤마가 붙은 형태로 보인다.
    expect(
      tester
          .widget<TextFormField>(fieldByLabel('금액 / 금액권 잔액 (선택)'))
          .controller
          ?.text,
      '1,500,000',
    );

    await pickExpiryDate(tester);
    await tapSave(tester);

    final List<Gifticon> saved = await repo.getGifticons(myId);

    expect(saved, hasLength(1));
    // 계약(Gifticon.price: int)에는 콤마가 제거된 정수가 들어간다.
    expect(saved.single.price, 1500000);
  });

  testWidgets('이미 등록된 바코드는 저장되지 않고 필드에 안내가 뜬다', (WidgetTester tester) async {
    const String duplicated = '8801234567890';

    await openManualForm(tester, seed: <Gifticon>[
      existing(barcode: duplicated),
    ]);

    await fillRequired(tester, barcode: duplicated, productName: '중복 테스트 상품');
    await pickExpiryDate(tester);
    await tapSave(tester);

    // 직접 입력 경로는 화면에 머무르며 바코드 필드 아래로 알린다.
    expect(find.text('이미 등록된 바코드 번호입니다.'), findsOneWidget);
    expect(find.text('기프티콘 정보 확인'), findsOneWidget);
    expect(find.text('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);

    // 시드 1건 그대로 — 새로 저장되지 않았다.
    expect(await repo.getGifticons(myId), hasLength(1));
  });

  testWidgets('필수 항목을 채우면 네 칸 모두 안내가 즉시 사라진다', (WidgetTester tester) async {
    await openManualForm(tester);

    // 먼저 저장을 눌러 네 칸 모두 빨간 상태로 만든다.
    await tapSave(tester);
    expect(find.text('브랜드를 입력해 주세요.'), findsOneWidget);

    // 채워 넣으면 저장을 다시 누르지 않아도 안내가 걷힌다.
    // (일부 칸만 즉시 갱신되면 채운 칸에 "입력해 주세요"가 남아 혼란스럽다)
    await fillRequired(tester, barcode: '8801234567890');

    expect(find.text('브랜드를 입력해 주세요.'), findsNothing);
    expect(find.text('상품명을 입력해 주세요.'), findsNothing);

    await pickExpiryDate(tester);
    expect(find.text('유효기간을 선택해 주세요.'), findsNothing);
  });

  testWidgets('바코드 없이도 등록된다(계약상 nullable)', (WidgetTester tester) async {
    await openManualForm(tester);

    // 바코드만 비워 둔다.
    await tester.enterText(fieldByLabel('브랜드 / 사용처'), '스타벅스');
    await tester.enterText(fieldByLabel('상품명'), '종이 쿠폰');
    await tester.pumpAndSettle();

    await pickExpiryDate(tester);
    await tapSave(tester);

    final List<Gifticon> saved = await repo.getGifticons(myId);

    expect(saved, hasLength(1));
    expect(saved.single.barcode, isNull);
  });

  testWidgets('바코드를 고치면 중복 안내가 사라진다', (WidgetTester tester) async {
    const String duplicated = '8801234567890';

    await openManualForm(tester, seed: <Gifticon>[
      existing(barcode: duplicated),
    ]);

    await fillRequired(tester, barcode: duplicated);
    await pickExpiryDate(tester);
    await tapSave(tester);

    expect(find.text('이미 등록된 바코드 번호입니다.'), findsOneWidget);

    await tester.enterText(fieldByLabel('바코드 번호'), '8809999999999');
    await tester.pumpAndSettle();

    expect(find.text('이미 등록된 바코드 번호입니다.'), findsNothing);
  });

  test('저장이 진행 중이면 중복 호출이 무시된다(연타로 두 번 저장되지 않는다)', () async {
    final ProviderContainer container = makeContainer();

    final GifticonFormController controller =
        container.read(gifticonFormControllerProvider.notifier);

    controller.startWith(ScanSource.manual);
    controller.setBrand('스타벅스');
    controller.setProductName('아메리카노 T');
    controller.setBarcode('8801234567890');
    controller.setExpiryDate(DateTime(2027, 1, 31));

    // 첫 호출을 기다리지 않고 곧바로 두 번째를 부른다 = 저장 버튼 연타.
    //
    // 이 가드가 없으면 두 호출이 나란히 중복 조회를 돌고, 둘 다 아직 아무것도
    // 저장되지 않은 목록을 보므로 **둘 다 통과해** 같은 바코드가 두 번 저장된다.
    final Future<Gifticon?> first = controller.submit();
    final Future<Gifticon?> second = controller.submit();

    final List<Gifticon?> results = await Future.wait(
      <Future<Gifticon?>>[first, second],
    );

    expect(results.where((Gifticon? g) => g != null), hasLength(1));
    expect(await repo.getGifticons(myId), hasLength(1));
  });
}
