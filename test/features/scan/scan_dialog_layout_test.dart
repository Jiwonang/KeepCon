/// scan — **안내 다이얼로그가 좁은 화면에서 넘치지 않는지** 지키는 테스트.
///
/// ## 이 파일이 있는 이유
///
/// 저장 결과 안내는 둘이다 — 한도 도달, 중복 등록. 둘은 같은 배치 규약
/// (`_ResultDialog`)을 공유하도록 고쳤지만, **중복 다이얼로그는 브라우저
/// 프리뷰로 띄울 수 없다.** 카메라·갤러리로 등록할 때만 뜨고(수동 입력은 필드
/// 안내로 처리한다) 웹에는 그 경로가 없기 때문이다. 그래서 한도 쪽만 눈으로
/// 확인하고 중복 쪽은 확인하지 못한 채 남았다.
///
/// 눈으로 못 보는 것은 테스트가 대신 본다. 여기서는 좁은 폭에서 두 다이얼로그를
/// 실제로 띄우고 **넘치는 위젯이 없는지**를 고정한다.
///
/// ⚠️ 이 테스트가 지키는 것은 "넘치지 않는다"이지 "예쁘다"가 아니다. 줄바꿈이
/// 어절 경계에서 일어나는지는 `keep_all_ko_test.dart`가 따로 고정한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  /// 한도 검사용 더미 — 소유자만 같고 나머지는 서로 다르게 채운다.
  List<Gifticon> filledWallet(int count) => List<Gifticon>.generate(
        count,
        (int i) => Gifticon(
          id: 'seed-$i',
          ownerId: myId,
          brand: '브랜드$i',
          productName: '상품$i',
          price: 1000,
          barcode: '880000000000$i',
          category: '기타',
          expiryDate: DateTime(2030, 1, 1),
          registeredAt: DateTime(2026, 1, 1),
          status: GifticonStatus.available,
        ),
      );

  /// [width]px 화면에서 수동 입력 폼까지 들어간다.
  Future<ProviderContainer> openFormAt(
    WidgetTester tester,
    double width, {
    List<Gifticon> seed = const <Gifticon>[],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    // 폼 전체가 한 화면에 들어와야 탭이 스크롤에 걸리지 않는다(세로는 넉넉히).
    tester.view.physicalSize = Size(width, 2600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(
          InMemoryGifticonRepository(seed: seed),
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

    await tester.tap(find.text('직접 입력하기'));
    await tester.pumpAndSettle();
    expect(find.text('기프티콘 정보 확인'), findsOneWidget);

    return container;
  }

  Finder fieldByLabel(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(TextFormField),
      );

  Future<void> fillAndSave(WidgetTester tester,
      {required String barcode}) async {
    await tester.enterText(fieldByLabel('브랜드 / 사용처'), '테스트');
    await tester.enterText(fieldByLabel('상품명'), '테스트 상품');
    await tester.enterText(fieldByLabel('바코드 번호'), barcode);
    await tester.pumpAndSettle();

    await tester.tap(find.text('날짜를 선택해 주세요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '저장하기'));
    await tester.pumpAndSettle();
  }

  // 320: 옛 소형 기기 / 360: 흔한 안드로이드 / 375: iPhone SE·13 mini 급.
  const List<double> narrowWidths = <double>[320, 360, 375];

  /// 지금 떠 있는 다이얼로그가 **공유 배치 규약**을 쓰고 있는지 확인한다.
  ///
  /// 넘침 여부만 보면 중복 다이얼로그 쪽은 사실상 통과가 보장된다 — 내용이
  /// 감싸지는 [Text]들의 [Column]이라 구조상 넘칠 수가 없고, 실제로 그 안에
  /// 400px 고정폭을 심는 변이를 넣어도 테스트가 잡지 못했다. 그래서 "넘쳤나"가
  /// 아니라 **"내가 넣은 규약이 실제로 걸려 있나"** 를 직접 본다. 누군가
  /// `insetPadding`을 되돌리면 여기서 걸린다.
  void expectSharedInset(WidgetTester tester, {required bool narrow}) {
    final AlertDialog dialog = tester.widget<AlertDialog>(
      find.byType(AlertDialog),
    );

    expect(
      dialog.insetPadding,
      EdgeInsets.symmetric(horizontal: narrow ? 16 : 40, vertical: 24),
      reason: narrow
          ? '좁은 화면에서 여백을 줄여 본문 폭을 돌려주지 않고 있다'
          : '넓은 화면에서는 기본 여백을 유지해야 한다',
    );
  }

  group('저장 한도 다이얼로그', () {
    for (final double width in narrowWidths) {
      testWidgets('${width.toInt()}px에서 넘치지 않는다', (WidgetTester tester) async {
        await openFormAt(
          tester,
          width,
          seed: filledWallet(UserPlan.freeGifticonLimit),
        );

        await fillAndSave(tester, barcode: '9990000000001');

        expect(find.text('저장 한도에 도달했어요'), findsOneWidget);
        expectSharedInset(tester, narrow: true);
        expect(
          tester.takeException(),
          isNull,
          reason: '${width.toInt()}px에서 한도 다이얼로그가 넘쳤다',
        );
      });
    }

    testWidgets('넓은 화면에서는 기본 여백을 유지한다', (WidgetTester tester) async {
      await openFormAt(
        tester,
        800,
        seed: filledWallet(UserPlan.freeGifticonLimit),
      );

      await fillAndSave(tester, barcode: '9990000000001');

      expect(find.text('저장 한도에 도달했어요'), findsOneWidget);
      expectSharedInset(tester, narrow: false);
    });
  });

  group('중복 등록 다이얼로그', () {
    // **웹 프리뷰로는 이 다이얼로그에 도달할 수 없다** — 카메라/갤러리 경로에서만
    // 뜬다. 그 경로를 테스트에서 재현하려면 폼에 들어간 뒤 입력 소스를 바꿔야
    // 한다(수동이면 다이얼로그가 아니라 필드 안내로 처리된다).
    for (final double width in narrowWidths) {
      testWidgets('${width.toInt()}px에서 넘치지 않는다', (WidgetTester tester) async {
        const String duplicated = '8801234567890';

        final ProviderContainer container = await openFormAt(
          tester,
          width,
          seed: <Gifticon>[
            Gifticon(
              id: 'existing',
              ownerId: myId,
              brand: '스타벅스',
              productName: '아이스 카페 아메리카노 톨 사이즈',
              price: 4500,
              barcode: duplicated,
              category: '카페/음료',
              expiryDate: DateTime(2030, 3, 20),
              registeredAt: DateTime(2026, 1, 1),
              status: GifticonStatus.available,
            ),
          ],
        );

        // 카메라 경로로 바꾼다 — 이 소스일 때만 다이얼로그가 뜬다.
        container
            .read(gifticonFormControllerProvider.notifier)
            .startWith(ScanSource.camera);
        await tester.pumpAndSettle();

        await fillAndSave(tester, barcode: duplicated);

        expect(find.text('이미 등록된 기프티콘'), findsOneWidget);
        // 형제인 한도 다이얼로그와 **같은** 배치 규약을 쓰는지가 핵심이다 —
        // 한쪽만 고쳐져 여백이 어긋나는 것이 이 변경이 막으려던 상태다.
        expectSharedInset(tester, narrow: true);
        expect(
          tester.takeException(),
          isNull,
          reason: '${width.toInt()}px에서 중복 다이얼로그가 넘쳤다',
        );
      });
    }
  });
}
