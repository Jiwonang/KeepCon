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
import 'package:keepcon/features/scan/util/keep_all_ko.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  /// 저장 결과를 직접 들여다보기 위해 Repository 인스턴스를 손에 쥔 채 주입한다.
  late InMemoryGifticonRepository repo;

  /// 플랜을 바꿔 가며 검사하려면 auth 구현도 손에 쥐고 있어야 한다.
  late InMemoryAuthRepository auth;

  ProviderContainer makeContainer({
    List<Gifticon> seed = const <Gifticon>[],
    InMemoryAuthRepository? authRepository,
    InMemoryGifticonRepository? gifticonRepository,
  }) {
    repo = gifticonRepository ?? InMemoryGifticonRepository(seed: seed);
    auth = authRepository ?? InMemoryAuthRepository();

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 소유자만 다르게 채운 더미 기프티콘 [count]개 — 저장 한도 검사용.
  List<Gifticon> filledWallet(int count) {
    return List<Gifticon>.generate(
      count,
      (int i) => Gifticon(
        id: 'g_$i',
        ownerId: myId,
        brand: '브랜드$i',
        productName: '상품$i',
        price: 1000,
        barcode: '900000000000$i',
        category: '기타',
        expiryDate: DateTime(2027, 1, 31),
        registeredAt: DateTime(2026, 1, 1),
      ),
      growable: false,
    );
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
  Future<ProviderContainer> openManualForm(
    WidgetTester tester, {
    List<Gifticon> seed = const <Gifticon>[],
    InMemoryAuthRepository? authRepository,
    InMemoryGifticonRepository? gifticonRepository,
  }) async {
    // 폼 전체가 한 화면에 들어와야 탭이 스크롤에 걸리지 않는다.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProviderContainer container = makeContainer(
      seed: seed,
      authRepository: authRepository,
      gifticonRepository: gifticonRepository,
    );

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

  /// 어절 보호([KeepAllText])가 걸린 문구를 찾는다.
  ///
  /// `find.text`는 **못 찾는다** — 표시 문자열에 보이지 않는 WORD JOINER가 섞여
  /// 있기 때문이다. 그대로 두면 아래 `findsNothing` 가드들이 "안 뜬 것"이 아니라
  /// "못 찾은 것"으로 통과해, 저장이 실제로 일어나도 초록불이 된다.
  /// [KeepAllText]가 원문을 `semanticsLabel`에 남기므로 그것으로 대조한다.
  Finder keepAllText(String plain) => find.byWidgetPredicate(
        (Widget w) => w is Text && (w.semanticsLabel ?? w.data) == plain,
      );

  /// 라벨로 입력 필드를 찾는다(폼에 TextFormField가 여러 개라 위치가 아니라 라벨 기준).
  Finder fieldByLabel(String label) {
    return find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );
  }

  /// 입력 필드에 **지금 들어 있는 값**을 읽는다.
  ///
  /// `find.text`로는 대신할 수 없다 — 그건 화면 어딘가에 그 문자열이 있는지를 볼
  /// 뿐이라, 필드가 비어도 다른 위젯이 같은 문자열을 그리면 통과한다.
  String? fieldText(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(fieldByLabel(label)).controller?.text;

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
    expect(keepAllText('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);
    expect(find.text('기프티콘 정보 확인'), findsOneWidget);

    expect(await repo.getGifticons(myId), isEmpty);
  });

  testWidgets('유효기간만 비어도 저장되지 않는다', (WidgetTester tester) async {
    await openManualForm(tester);

    await fillRequired(tester, barcode: '8801234567890');
    // 날짜는 고르지 않는다.
    await tapSave(tester);

    expect(find.text('유효기간을 선택해 주세요.'), findsOneWidget);
    expect(keepAllText('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);
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
    expect(keepAllText('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);

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

  group('무료 플랜 저장 한도', () {
    const int limit = UserPlan.freeGifticonLimit;

    testWidgets('한도 직전($limit개 미만)에는 저장된다', (WidgetTester tester) async {
      await openManualForm(tester, seed: filledWallet(limit - 1));

      await fillRequired(tester, barcode: '8801234567890');
      await pickExpiryDate(tester);
      await tapSave(tester);

      expect(await repo.getGifticons(myId), hasLength(limit));
      expect(find.text('저장 한도에 도달했어요'), findsNothing);
    });

    testWidgets('한도에 도달하면 저장되지 않고 홈으로 나가며 안내가 뜬다', (WidgetTester tester) async {
      await openManualForm(tester, seed: filledWallet(limit));

      await fillRequired(tester, barcode: '8801234567890');
      await pickExpiryDate(tester);
      await tapSave(tester);

      expect(find.text('저장 한도에 도달했어요'), findsOneWidget);
      // 저장은 늘지 않았고 성공 문구도 뜨지 않는다.
      expect(await repo.getGifticons(myId), hasLength(limit));
      expect(keepAllText('기프티콘이 성공적으로 저장되었습니다.'), findsNothing);
      // 폼에 남겨 두지 않는다 — 입력을 고쳐도 저장될 수 없기 때문이다.
      expect(find.text('기프티콘 정보 확인'), findsNothing);
    });

    testWidgets('프리미엄은 한도를 넘어도 저장된다', (WidgetTester tester) async {
      final ProviderContainer container =
          await openManualForm(tester, seed: filledWallet(limit));

      await container
          .read(authRepositoryProvider)
          .updatePlan(plan: UserPlan.premium);

      await fillRequired(tester, barcode: '8801234567890');
      await pickExpiryDate(tester);
      await tapSave(tester);

      expect(await repo.getGifticons(myId), hasLength(limit + 1));
      expect(find.text('저장 한도에 도달했어요'), findsNothing);
    });

    testWidgets('사용 완료한 기프티콘은 한도에서 빠진다', (WidgetTester tester) async {
      // 한도만큼 있지만 하나를 사용 완료했다면 자리가 하나 난 것이다.
      //
      // 전체 개수로 세면 무료 사용자가 막다른 골목에 갇힌다 — 계약에 삭제 API가
      // 없고 dev/prod에서는 프리미엄 전환도 막혀 있어, 10개를 다 쓰면 등록이
      // 영구히 정지한다. '사용 완료 처리'가 유일한 탈출구이므로 그것이 실제로
      // 자리를 비우는지 고정한다.
      final List<Gifticon> wallet = <Gifticon>[
        ...filledWallet(limit - 1),
        filledWallet(limit).last.copyWith(status: GifticonStatus.used),
      ];

      await openManualForm(tester, seed: wallet);

      await fillRequired(tester, barcode: '8801234567890');
      await pickExpiryDate(tester);
      await tapSave(tester);

      expect(find.text('저장 한도에 도달했어요'), findsNothing);
      expect(await repo.getGifticons(myId), hasLength(limit + 1));
    });

    testWidgets('한도와 중복이 겹치면 한도를 먼저 알린다', (WidgetTester tester) async {
      // 한도를 채운 지갑의 마지막 항목과 **같은 바코드**로 저장을 시도한다.
      // 둘 다 해당하지만, 바코드를 고쳐도 저장되지 않으므로 한도가 맞는 안내다.
      final List<Gifticon> wallet = filledWallet(limit);
      await openManualForm(tester, seed: wallet);

      await fillRequired(tester, barcode: wallet.last.barcode!);
      await pickExpiryDate(tester);
      await tapSave(tester);

      expect(find.text('저장 한도에 도달했어요'), findsOneWidget);
      expect(find.text('이미 등록된 바코드 번호입니다.'), findsNothing);
      expect(find.text('이미 등록된 기프티콘'), findsNothing);
    });

    testWidgets('플랜을 확인하지 못하면 한도로 단정하지 않고 연결 확인을 안내한다',
        (WidgetTester tester) async {
      // 이 경로는 여태 어느 테스트도 지나지 않았다 — in-memory 구현은 조회가
      // 실패하지 않으므로, 실패를 만들려면 던지는 구현을 넣어야 한다.
      await openManualForm(
        tester,
        seed: filledWallet(limit),
        authRepository: _PlanUnavailableAuthRepository(),
      );

      await fillRequired(tester, barcode: '8801234567890');
      await pickExpiryDate(tester);
      await tapSave(tester);

      // `find.text`로는 못 찾는다 — 스낵바가 [KeepAllText]라 표시본에 보이지 않는
      // WORD JOINER가 섞인다. 그대로 두면 문구가 안 떠도 초록불이 된다.
      expect(
        keepAllText('플랜 정보를 확인하지 못했어요. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );

      // **표시본이 실제로 어절 보호를 거치는지 따로 못박는다.** 위 [keepAllText]는
      // `semanticsLabel ?? data`로 보므로 평범한 [Text]도 통과한다 — 그것만으로는
      // 이 스낵바를 [KeepAllText]에서 [Text]로 되돌려도 초록불이다(뮤테이션으로
      // 확인했다). 보호본을 직접 찾아야 그 되돌림이 빨개진다.
      expect(
        find.text(
          keepAllKo('플랜 정보를 확인하지 못했어요. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.'),
        ),
        findsOneWidget,
      );

      // 한도 안내로 단정하지 않는다 — 프리미엄이었을 수도 있다.
      expect(find.text('저장 한도에 도달했어요'), findsNothing);

      // 저장되지도 않고, 폼을 닫지도 않는다(입력을 잃으면 재시도 안내가 무의미하다).
      expect(await repo.getGifticons(myId), hasLength(limit));
      expect(find.text('기프티콘 정보 확인'), findsOneWidget);

      // **화면이 남아 있는 것만으로는 부족하다.** 폼을 유지한 채 입력만 비우는
      // 회귀도 위 단언을 통과한다 — 그러면 "다시 시도"가 처음부터 다시 치라는
      // 말이 되어 안내가 무의미해진다. 실제로 값이 남았는지 본다.
      expect(fieldText(tester, '브랜드 / 사용처'), '스타벅스');
      expect(fieldText(tester, '상품명'), '아메리카노 T');
      expect(fieldText(tester, '바코드 번호'), '8801234567890');
    });
  });

  testWidgets('저장 목록 조회가 실패하면 원시 예외가 화면에 새지 않는다', (WidgetTester tester) async {
    // 이 경로도 여태 어느 테스트도 지나지 않았다 — in-memory 구현은 조회가
    // 실패하지 않으므로, 실패를 만들려면 던지는 구현을 넣어야 한다.
    await openManualForm(
      tester,
      gifticonRepository: _ThrowingGifticonRepository(),
    );

    await fillRequired(tester, barcode: '8801234567890');
    await pickExpiryDate(tester);
    await tapSave(tester);

    expect(
      keepAllText('저장 목록을 확인하지 못했어요. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.'),
      findsOneWidget,
    );

    // **핵심 단언.** 예전에는 `'저장 목록을 확인하지 못했습니다: $e'`로 예외를 그대로
    // 실어 `[cloud_firestore/unavailable]` 같은 내부 식별자가 화면에 나왔다.
    // 문구가 다시 그렇게 바뀌면 여기서 빨개진다.
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Text &&
            ((w.semanticsLabel ?? w.data) ?? '').contains(_thrownMarker),
      ),
      findsNothing,
      reason: '예외 문자열이 사용자 문구에 실렸다',
    );

    // 폼은 유지된다 — 재시도 안내가 의미를 가지려면 입력이 남아야 한다.
    expect(find.text('기프티콘 정보 확인'), findsOneWidget);
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

/// 플랜 조회만 실패하는 auth 구현 — 오프라인(그리고 권한·서버 오류) 재현용.
///
/// Firebase 구현이 `Source.server`로 읽어 캐시로 폴백하지 않으므로, 연결이 없으면
/// [AuthRepository.getPlan]은 [AuthException]을 던진다. 나머지 동작은 그대로
/// 물려받는다 — 바꾸려는 것은 그 한 경로뿐이다.
/// 조회가 실패했을 때 예외 문자열이 화면에 새는지 보기 위한 표식.
///
/// 실제 백엔드가 내는 모양(`[cloud_firestore/…]`)을 흉내 낸다 — 사용자가 읽을 것도
/// 할 수 있는 것도 없는 내부 식별자다.
const String _thrownMarker = '[cloud_firestore/unavailable]';

/// 저장 목록 조회만 실패하는 기프티콘 저장소 — 오프라인·백엔드 장애 재현용.
class _ThrowingGifticonRepository extends InMemoryGifticonRepository {
  @override
  Future<List<Gifticon>> getGifticons(String ownerId) async {
    throw Exception('$_thrownMarker backend unavailable');
  }
}

class _PlanUnavailableAuthRepository extends InMemoryAuthRepository {
  @override
  Future<UserPlan> getPlan() async {
    throw const AuthException(
      AuthErrorCode.unknown,
      'getPlan failed: offline',
    );
  }
}
