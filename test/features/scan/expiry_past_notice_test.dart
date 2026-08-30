/// scan — 유효기간이 지난 날짜일 때의 화면 동작.
///
/// 두 가지를 고정한다:
///
/// 1. **피커가 죽지 않는다.** 폼에 들어 있는 값이 피커 범위 밖이면
///    `showDatePicker`가 assert로 죽는다. 그 값은 사용자가 고른 것이 아니라
///    **OCR이 프리필한 것**이라 범위 밖일 수 있다 — 파서는 이미지에 적힌 대로
///    읽으므로 2020년 이전도 낸다(`gifticon_ocr_fixture_test.dart`가
///    `DateTime(2016, 2, 12)`로 못박고 있다).
/// 2. **지난 날짜는 알리되 막지 않는다.** `GifticonStatus.expired`가 계약상 정상
///    상태라 이미 만료된 것을 기록해 두는 것도 정당한 사용이다. 진짜 위험은 OCR
///    오인식을 모르고 저장하는 쪽이라, 저장을 막는 대신 눈에 띄게 한다.
///
/// 폼에는 `ScanPage`에서 내비게이션을 타고 도달한다 — 이 폼은 폼 상태 컨트롤러의
/// 세션(`startWith`)을 전제하므로 직접 pump하면 실제 경로가 만들지 않는 상태에서
/// 검증하게 된다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/theme/app_theme.dart';

void main() {
  const String pastNotice = '이미 지난 날짜예요. 맞는지 확인해 주세요.';

  /// 화면이 보는 '지금'. 고정하지 않으면 자정 경계에서 코드가 아니라 달력 때문에
  /// 빨개진다(이 저장소는 같은 유형으로 2026-08-27 CI가 실제로 터진 이력이 있다).
  final DateTime now = DateTime(2026, 8, 30, 14, 30);

  /// `ScanPage` → '직접 입력하기'로 폼까지 간다.
  Future<ProviderContainer> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[nowProvider.overrideWithValue(now)],
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

    return container;
  }

  /// OCR이 프리필한 상황을 재현한다 — 사용자가 고른 것이 아니라 폼에 이미 값이
  /// 들어와 있는 상태다.
  void prefillExpiry(ProviderContainer container, DateTime date) {
    container.read(gifticonFormControllerProvider.notifier).setExpiryDate(date);
  }

  testWidgets('지난 날짜가 프리필돼 있으면 안내가 뜬다', (WidgetTester tester) async {
    final ProviderContainer container = await openForm(tester);

    prefillExpiry(container, DateTime(2016, 2, 12));
    await tester.pumpAndSettle();

    expect(find.text(pastNotice), findsOneWidget);
  });

  testWidgets('안내가 떠도 저장은 막히지 않는다 — 만료 기록도 정당한 사용이다',
      (WidgetTester tester) async {
    final ProviderContainer container = await openForm(tester);

    prefillExpiry(container, DateTime(2016, 2, 12));
    await tester.pumpAndSettle();

    expect(find.text(pastNotice), findsOneWidget);
    // 필수 항목 안내는 유효기간이 아니라 **다른 칸** 때문에 떠야 한다.
    // 유효기간이 저장을 막았다면 '유효기간을 선택해 주세요.'가 뜬다.
    expect(find.text('유효기간을 선택해 주세요.'), findsNothing);
  });

  testWidgets('오늘 만료는 안내하지 않는다 — 그날까지 유효하다', (WidgetTester tester) async {
    final ProviderContainer container = await openForm(tester);

    prefillExpiry(container, DateTime(2026, 8, 30));
    await tester.pumpAndSettle();

    expect(find.text(pastNotice), findsNothing);
  });

  testWidgets('앞으로의 날짜는 안내하지 않는다', (WidgetTester tester) async {
    final ProviderContainer container = await openForm(tester);

    prefillExpiry(container, DateTime(2027, 1, 31));
    await tester.pumpAndSettle();

    expect(find.text(pastNotice), findsNothing);
  });

  testWidgets('피커 범위 밖 값이 프리필돼 있어도 날짜 칸을 눌러 열 수 있다',
      (WidgetTester tester) async {
    // 이 테스트가 지키는 것이 크래시다. 클램프가 없으면 `showDatePicker`의
    // assert가 여기서 터진다(`initialDate`가 `firstDate`보다 앞선다).
    final ProviderContainer container = await openForm(tester);

    prefillExpiry(container, DateTime(2016, 2, 12));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2016.02.12'));
    await tester.pumpAndSettle();

    // 피커가 떴다 = assert를 통과했다.
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
