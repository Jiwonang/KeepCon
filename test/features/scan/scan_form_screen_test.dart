/// scan — **앱이 실제로 띄우는 등록 폼**의 위젯 테스트.
///
/// ## 이 파일이 있는 이유
///
/// 한때 scan 폼은 코드가 두 벌이었다. 테스트가 검증하던 `GifticonForm`
/// (`widgets/gifticon_form.dart`)은 **앱 어디에서도 렌더링되지 않았고**, 사용자가
/// 실제로 보는 것은 `pages/gifticon_form_page.dart`의 `GifticonFormScreen`이다. 그래서 전체 테스트가
/// 초록이어도 진짜 등록 화면은 커버리지가 0이었고, "저장되었습니다"만 뜨고 홈에는
/// 아무것도 없던 버그들이 CI를 통과한 채 살아 있었다.
///
/// 그 죽은 위젯과 테스트는 삭제됐다. 이제 진짜 등록 화면을 pump하는 위젯 테스트는
/// 이 파일과 `scan_dialog_layout_test.dart`(좁은 폭 다이얼로그 오버플로) 둘뿐이다 —
/// 폼을 고치면 두 파일을 함께 본다.
///
/// 이 파일은 그 구멍을 메운다 — **사용자 경로 그대로** [ScanPage]를 띄우고
/// '직접 입력하기'를 눌러 진짜 폼 화면에 들어간 뒤 검증한다.
/// (⚠️ `GifticonFormScreen`은 이제 **공개**라 직접 pump할 수 있지만, 원칙적으로
/// 그러지 않는다 — 이 폼은 `GifticonFormController`의 세션(`startWith`)을 전제하므로
/// 직접 pump하면 실제 경로가 만들지 않는 상태에서 검증하게 된다. 예전에는 private이
/// 그것을 막아 줬고, 지금은 이 규약이 막는다. 경로를 통째로 지나야 이 파일이 막으려는
/// 회귀를 잡을 수 있다. **예외는 갤러리 도착 하나다** — `ScanPage._openForm`이
/// `ImagePicker()`를 안에서 직접 만들어 주입점이 없으므로, `openGalleryForm`이
/// 그 경로의 컨트롤러 호출을 재현한 뒤 직접 pump한다. 세션 재현 없는 직접 pump의
/// 근거로 읽지 말 것.)
///
/// ## 검증 대상
/// 1. 필수 항목이 비면 저장이 **막히고** 화면에 머문다 (유효기간 포함).
/// 2. 금액은 선택 입력이라 비워도 저장되며 계약에는 0원으로 들어간다.
/// 3. 금액 입력에 천 단위 콤마가 붙고, 계약에는 콤마 없는 정수로 들어간다.
/// 4. 이미 등록된 바코드는 저장되지 않고 필드에 안내가 뜬다.
/// 5. 저장 버튼 연타로 같은 기프티콘이 두 번 저장되지 않는다.
/// 6. 저장물에 로컬 이미지 경로가 실리지 않고, 폼 상태에는 남는다
///    (⚠️ **미리보기 쪽은 이 파일이 지키지 않는다** — `scan_page.dart`의
///    `imagePath: file.path` 두 줄을 지워도 전체 652건이 통과한다).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/pages/gifticon_form_page.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/util/keep_all_ko.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';
import 'package:keepcon/shared/util/date_format.dart' show formatYmdDot;

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  /// 저장 결과를 직접 들여다보기 위해 Repository 인스턴스를 손에 쥔 채 주입한다.
  late InMemoryGifticonRepository repo;

  /// 플랜을 바꿔 가며 검사하려면 auth 구현도 손에 쥐고 있어야 한다.
  late InMemoryAuthRepository auth;

  /// 진단 경로가 실제로 불렸는지 보기 위한 스파이.
  ///
  /// 늘 주입한다 — 기본 구현([DebugPrintErrorReporter])을 그대로 두면 실패 경로
  /// 테스트마다 스택트레이스가 통째로 찍혀 출력이 묻힌다.
  late _SpyErrorReporter reporter;

  ProviderContainer makeContainer({
    List<Gifticon> seed = const <Gifticon>[],
    InMemoryAuthRepository? authRepository,
    InMemoryGifticonRepository? gifticonRepository,
  }) {
    repo = gifticonRepository ?? InMemoryGifticonRepository(seed: seed);
    auth = authRepository ?? InMemoryAuthRepository();
    reporter = _SpyErrorReporter();

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
        errorReporterProvider.overrideWithValue(reporter),
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

  /// 폼 전체가 한 화면에 들어와야 탭이 스크롤에 걸리지 않는다.
  ///
  /// 두 진입 helper([openManualForm]·[openGalleryForm])가 같은 값을 써야 한다 —
  /// 갈라지면 한쪽 테스트만 off-screen 탭으로 죽어 경로 간 행위 차이로 오독된다.
  void setFormViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// [ScanPage]를 띄우고 '직접 입력하기'로 진짜 폼 화면까지 들어간다.
  Future<ProviderContainer> openManualForm(
    WidgetTester tester, {
    List<Gifticon> seed = const <Gifticon>[],
    InMemoryAuthRepository? authRepository,
    InMemoryGifticonRepository? gifticonRepository,
  }) async {
    setFormViewport(tester);

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

    // **원인이 사라지지는 않았다.** 화면에서 걷어낸 것은 진단으로 옮긴 것이지
    // 버린 것이 아니다 — 이 단언이 없으면 `_reportFailure` 호출을 통째로 지워도
    // 초록불이다.
    expect(reporter.contexts, contains('GifticonFormController.getGifticons'));
    expect(reporter.errors.single.toString(), contains(_thrownMarker));
  });

  testWidgets('유효기간 라벨이 공유 정본 표기(YYYY.MM.DD)를 쓴다', (WidgetTester tester) async {
    // 이 라벨은 여태 어느 테스트도 고정하지 않았고, 그래서 `lib/` 전체에서
    // 유일하게 `2026-09-30`(하이픈)으로 남아 있었다 — **같은 화면의 중복 등록
    // 다이얼로그조차** 점 표기였다. 계약 매트릭스 v2.4가 "통일했다"고 기록했지만
    // 그 전환은 삭제된 죽은 폼에만 적용돼 있었다.
    final ProviderContainer container = await openManualForm(tester);
    await pickExpiryDate(tester);

    // 기대값을 **라벨이 실제로 읽는 상태**에서 만든다. 정본 함수를 재구현하지 않고
    // 그대로 호출한다 — 여기서 손으로 조립하면 이 테스트가 막으려는 갈라짐을
    // 테스트가 다시 만든다.
    //
    // `DateTime.now()`로 만들지 않는 이유는 **자정**이다. 선택기가 `initialDate`를
    // 읽는 순간과 이 줄 사이에는 pumpAndSettle 두 번과 탭 두 번이 끼어 있어, 그
    // 사이에 날짜가 넘어가면 코드가 아니라 달력 때문에 빨개진다. 이 저장소는 같은
    // 유형으로 2026-08-27T00:31Z CI가 실제로 터진 이력이 있다
    // (`test/features/share/notification_center_merge_test.dart:73`).
    final DateTime? picked =
        container.read(gifticonFormControllerProvider).expiryDate;

    expect(picked, isNotNull, reason: '날짜 선택기가 값을 확정하지 못했다');

    final String expected = formatYmdDot(picked!);

    expect(find.text(expected), findsOneWidget);

    // 옛 표기가 남아 있지 않은지도 본다(둘 다 뜨는 상태를 통과시키지 않는다).
    expect(find.text(expected.replaceAll('.', '-')), findsNothing);
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

  /// 갤러리 경로의 도착 상태를 재현해 폼을 연다.
  ///
  /// 갤러리 경로는 위젯 테스트로 통째로 지날 수 없다 — `ScanPage._openForm`이
  /// `ImagePicker()`를 안에서 직접 만들어 주입점이 없다. 그래서 그 경로가
  /// 컨트롤러에 하는 일(`startWith` → `prefillFromRecognition`)을 그대로 재현한
  /// 뒤 폼을 pump한다. ⚠️ `scan_page.dart`의 갤러리 분기와 어긋나면 이 테스트는
  /// 실제 경로가 만들지 않는 상태를 검증하게 된다 — 그 분기를 바꾸면 여기도
  /// 함께 볼 것. [ocrBarcode]가 null이면 "이미지에서 바코드를 못 읽은" 도착이다
  /// (실제 경로의 `scanResult.firstBarcodeValue`가 null인 경우와 같다).
  Future<ProviderContainer> openGalleryForm(
    WidgetTester tester, {
    String? ocrBarcode,
    List<Gifticon> seed = const <Gifticon>[],
  }) async {
    setFormViewport(tester);

    final ProviderContainer container = makeContainer(seed: seed);
    final GifticonFormController controller =
        container.read(gifticonFormControllerProvider.notifier);

    controller.startWith(ScanSource.gallery);
    controller.prefillFromRecognition(
      brand: '스타벅스',
      productName: '아메리카노 T',
      barcode: ocrBarcode,
      category: '카페/음료',
      // 실제 갤러리 도착은 **항상** imagePath를 싣는다(image_picker가 경로 없는
      // 파일을 주지 않는다) — 빼면 이미지 미리보기 블록이 없는, 실제 경로가
      // 만들 수 없는 레이아웃을 검증하게 된다. 파일은 존재하지 않아도 된다 —
      // 폼의 Image.file은 errorBuilder로 같은 200px 블록을 유지한다.
      imagePath: '/tmp/keepcon_scan/frame.jpg',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const GifticonFormScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return container;
  }

  const String barcodeUnreadNotice = '이미지에서 바코드를 읽지 못했어요. 직접 입력해 주세요.';

  testWidgets('갤러리에서 바코드를 못 읽고 오면 필드에 안내가 뜨고, 직접 입력하면 사라진다',
      (WidgetTester tester) async {
    await openGalleryForm(tester, ocrBarcode: null);

    // 안내가 뜬다 — 바코드는 계약상 선택 항목이라 이 안내가 없으면 빈 채로
    // 조용히 저장되고, 사용자는 매장에서야 제시할 것이 없다는 걸 안다.
    expect(find.text(barcodeUnreadNotice), findsOneWidget);

    // 직접 채우면 안내는 할 일을 다한 것 — 사라진다.
    await tester.enterText(fieldByLabel('바코드 번호'), '8801234567890');
    await tester.pumpAndSettle();
    expect(find.text(barcodeUnreadNotice), findsNothing);

    // 도로 지우면 다시 뜬다 — "이미지에서 못 읽었다"는 사실은 그대로다.
    await tester.enterText(fieldByLabel('바코드 번호'), '');
    await tester.pumpAndSettle();
    expect(find.text(barcodeUnreadNotice), findsOneWidget);
  });

  testWidgets('갤러리라도 바코드가 프리필됐으면 안내가 없다', (WidgetTester tester) async {
    await openGalleryForm(tester, ocrBarcode: '8801234567890');

    expect(find.text(barcodeUnreadNotice), findsNothing);

    // 프리필된 값을 사용자가 지워도 안내는 뜨지 않는다 — 판정은 열리는 시점에
    // 고정이다("이미지에서 읽지 못했다"는 과거 사실). 지운 뒤에 띄우면 실제로는
    // 읽힌 바코드에 "읽지 못했어요"라고 거짓말하게 된다. 이 단언이 없으면
    // 판정을 키 입력마다 재평가하도록 "고치는" 회귀가 이 파일 전체를 통과한다.
    await tester.enterText(fieldByLabel('바코드 번호'), '');
    await tester.pumpAndSettle();
    expect(find.text(barcodeUnreadNotice), findsNothing);
  });

  testWidgets('갤러리-미인식에서 직접 입력한 바코드가 중복이면 홈이 아니라 폼에 머문다',
      (WidgetTester tester) async {
    // 미인식 안내("직접 입력해 주세요")를 따라 손으로 친 번호가 중복일 때 홈으로
    // 내쫓으면, 함께 채운 브랜드·상품명·날짜가 통째로 사라지고 정작 고칠 수 있는
    // 번호는 고칠 기회를 잃는다 — 직접 입력 경로와 같은 대우여야 한다.
    const String duplicated = '8801234567890';

    await openGalleryForm(
      tester,
      ocrBarcode: null,
      seed: <Gifticon>[existing(barcode: duplicated)],
    );

    await fillRequired(tester, barcode: duplicated);
    await pickExpiryDate(tester);
    await tapSave(tester);

    // 폼에 머물며 필드 안내로 알린다(직접 입력 경로와 같은 화면).
    expect(find.text('기프티콘 정보 확인'), findsOneWidget);
    expect(find.text('이미 등록된 바코드 번호입니다.'), findsOneWidget);
    // 홈 팝업 경로로 가지 않았다.
    expect(find.text('이미 등록된 기프티콘'), findsNothing);
  });

  testWidgets('직접 입력 경로에는 바코드 안내가 없다', (WidgetTester tester) async {
    // 직접 입력은 이미지 자체가 없으므로 "읽지 못했다"는 안내가 성립하지 않는다.
    await openManualForm(tester);

    expect(find.text(barcodeUnreadNotice), findsNothing);
  });

  testWidgets('저장 진행 중에는 버튼이 \'저장 중…\'으로 바뀌고 눌리지 않는다',
      (WidgetTester tester) async {
    // 저장은 목록 조회 + (한도 상황이면) 플랜 서버 확인까지 물려 수십 초가 걸릴
    // 수 있다. 진행 표시가 없으면 죽은 화면과 구분되지 않아 사용자가 이탈한다.
    final _GatedGifticonRepository gated = _GatedGifticonRepository();

    await openManualForm(tester, gifticonRepository: gated);
    await fillRequired(tester, barcode: '8801234567890');
    await pickExpiryDate(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, '저장하기'));
    await tester.pump();

    // 조회가 막혀 있는 동안 = 진행 중. 문구가 바뀌고 버튼은 비활성이다.
    final Finder inProgressButton =
        find.widgetWithText(ElevatedButton, '저장 중…');
    expect(inProgressButton, findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '저장하기'), findsNothing);
    expect(
      tester.widget<ElevatedButton>(inProgressButton).onPressed,
      isNull,
    );

    // 조회를 풀어 주면 저장이 끝나고 문구가 돌아온다(폼은 pop되므로 화면 기준
    // 검증은 저장 완료 여부로 한다).
    gated.release();
    await tester.pumpAndSettle();
    expect(await gated.getGifticons(myId), hasLength(1));
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

  test('저장물에는 로컬 이미지 경로가 실리지 않는다 — 미리보기용 폼 상태에는 남는다', () async {
    // 스캔·갤러리 경로가 실제로 넣는 값은 **로컬 파일 경로**다(image_picker의
    // 임시 파일 / `Directory.systemTemp`의 프레임). 그 경로는 어디에서도
    // 표시되지 않고(홈 카드는 `http(s)`만 렌더, 상세는 이미지를 안 싣는다) OS가
    // 임시 디렉터리를 청소하면 무효가 되는데, Firestore 구현은 그것을 문서에
    // 그대로 쓴다 — 즉 채우면 깨진 경로가 쌓인다.
    //
    // 이 테스트가 없으면 그냥 지웠을 때 **아무 테스트도 죽지 않아서**, 다음
    // 사람이 "빠뜨린 필드"로 읽고 되돌려도 CI가 초록이다.
    const String localFramePath = '/tmp/keepcon_scan/frame.jpg';

    final ProviderContainer container = makeContainer();

    final GifticonFormController controller =
        container.read(gifticonFormControllerProvider.notifier);

    controller.startWith(ScanSource.camera);
    controller.setBrand('노랑통닭');
    controller.setProductName('(오리지널/순살)3종세트');
    controller.setBarcode('8801234567890');
    controller.setExpiryDate(DateTime(2027, 1, 31));
    controller.setImagePath(localFramePath);

    final Gifticon? saved = await controller.submit();

    expect(saved, isNotNull);

    // 저장물에는 실리지 않는다 — 반환값과 저장소 양쪽으로 본다.
    //
    // ⚠️ 다만 in-memory 구현은 `addGifticon`이 저장한 **바로 그 인스턴스**를
    //    돌려주므로(`_store.add(saved); return saved;`) 아래 두 줄은 원리상
    //    갈라질 수 없다 — 중복 방어이지 "리포지토리가 따로 채워 넣는 경우"의
    //    보증이 아니다. 그 축이 실재하는 곳은 문서 왕복을 거치는 Firebase
    //    구현(`_toDoc`/`_fromDoc`)인데 `flutter test`는 in-memory만 돌린다.
    expect(saved!.imagePath, isNull);
    expect((await repo.getGifticons(myId)).single.imagePath, isNull);

    // 폼 상태에는 그대로 남는다 — 미리보기(`gifticon_form_page.dart`)가 쓰는
    // 값이라, 저장이 그것까지 지우면 저장 전 화면이 깨진다.
    expect(
      container.read(gifticonFormControllerProvider).imagePath,
      localFramePath,
    );
  });
}

/// 플랜 조회만 실패하는 auth 구현 — 오프라인(그리고 권한·서버 오류) 재현용.
///
/// Firebase 구현이 `Source.server`로 읽어 캐시로 폴백하지 않으므로, 연결이 없으면
/// [AuthRepository.getPlan]은 [AuthException]을 던진다. 나머지 동작은 그대로
/// 물려받는다 — 바꾸려는 것은 그 한 경로뿐이다.
class _PlanUnavailableAuthRepository extends InMemoryAuthRepository {
  @override
  Future<UserPlan> getPlan() async {
    throw const AuthException(
      AuthErrorCode.unknown,
      'getPlan failed: offline',
    );
  }
}

/// 진단 경로가 무엇을 받았는지 들여다보는 스파이.
class _SpyErrorReporter implements ErrorReporter {
  final List<String> contexts = <String>[];
  final List<Object> errors = <Object>[];

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    contexts.add(context);
    errors.add(error);
  }
}

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

/// 첫 조회를 [release]까지 붙들어 두는 기프티콘 저장소 — 저장 진행 중 화면 재현용.
///
/// 타이머가 아니라 [Completer]로 막는다 — `Stream.periodic`류는 teardown에서
/// `Pending timers`로 죽는다(이 저장소의 알려진 함정).
class _GatedGifticonRepository extends InMemoryGifticonRepository {
  final Completer<void> _gate = Completer<void>();

  /// 멱등이다 — 두 번 불려도 죽지 않는다(tearDown의 방어적 release 대비).
  /// 완료 여부의 정본은 [Completer.isCompleted] 하나다.
  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<List<Gifticon>> getGifticons(String ownerId) async {
    // 풀린 뒤의 호출(테스트 말미의 저장 확인)은 막지 않는다.
    if (!_gate.isCompleted) {
      await _gate.future;
    }
    return super.getGifticons(ownerId);
  }
}
