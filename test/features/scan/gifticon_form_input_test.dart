/// GifticonForm 입력 보조 기능 위젯 테스트.
///
/// 검증 대상(수동 입력 보완):
/// 1. 카테고리 프리셋 칩 선택 → Riverpod 폼 상태 반영 → 입력창 동기화
/// 2. 같은 칩 재탭 → 선택 해제(미입력 = 저장 시 "기타" 보정)
/// 3. 유효기간 빠른 선택 버튼 → expiryDate 반영
/// 4. 금액 입력 시 천 단위 콤마 표시 + parsedPrice 정합성
///
/// 카메라 스캔 화면(mobile_scanner)은 위젯 테스트에서 플러그인 초기화가
/// 불가하므로 이 파일의 범위에서 제외한다(결과 반환 인터페이스만 얇게 유지).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/state/gifticon_form_state.dart';
import 'package:keepcon/features/scan/util/expiry_quick_pick.dart';
import 'package:keepcon/features/scan/widgets/gifticon_form.dart';

void main() {
  /// 폼을 넉넉한 화면에 띄우고, 상태를 직접 읽을 수 있는 컨테이너를 돌려준다.
  ///
  /// 세로가 짧으면 ListView 하단 항목(유효기간·저장 버튼)이 화면 밖으로 나가
  /// 탭이 실패하므로 테스트 뷰포트를 크게 잡는다.
  Future<ProviderContainer> pumpForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ProviderContainer container = ProviderContainer();

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: GifticonForm(),
          ),
        ),
      ),
    );

    return container;
  }

  group('카테고리 프리셋 칩', () {
    testWidgets('프리셋 목록의 모든 칩이 표시된다', (WidgetTester tester) async {
      await pumpForm(tester);

      for (final String preset in kScanCategoryPresets) {
        expect(
          find.widgetWithText(ChoiceChip, preset),
          findsOneWidget,
          reason: '$preset 칩이 있어야 한다',
        );
      }
    });

    testWidgets('칩을 누르면 폼 상태의 category에 반영된다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpForm(tester);

      expect(container.read(gifticonFormControllerProvider).category, '');

      await tester.tap(find.widgetWithText(ChoiceChip, '카페'));
      await tester.pump();

      expect(container.read(gifticonFormControllerProvider).category, '카페');

      // 칩 선택 상태도 함께 갱신된다.
      final ChoiceChip chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '카페'),
      );

      expect(chip.selected, isTrue);
    });

    testWidgets('칩 선택이 자유 입력창에도 동기화된다', (WidgetTester tester) async {
      await pumpForm(tester);

      // 칩을 누르기 전에는 카테고리 입력창이 비어 있다.
      final Finder categoryField = find.ancestor(
        of: find.text('카테고리'),
        matching: find.byType(TextFormField),
      );

      expect(categoryField, findsOneWidget);

      expect(
        tester.widget<TextFormField>(categoryField).controller?.text,
        '',
      );

      await tester.tap(find.widgetWithText(ChoiceChip, '편의점'));
      await tester.pump();

      // _syncController가 입력창 텍스트까지 갱신한다.
      expect(
        tester.widget<TextFormField>(categoryField).controller?.text,
        '편의점',
      );
    });

    testWidgets('선택된 칩을 다시 누르면 미입력으로 되돌아간다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpForm(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, '치킨'));
      await tester.pump();

      expect(container.read(gifticonFormControllerProvider).category, '치킨');

      await tester.tap(find.widgetWithText(ChoiceChip, '치킨'));
      await tester.pump();

      // 빈 값이면 저장 시 계약 기본값으로 보정된다.
      expect(container.read(gifticonFormControllerProvider).category, '');
    });

    testWidgets('마지막 프리셋은 계약 기본값과 동일하다', (WidgetTester tester) async {
      await pumpForm(tester);

      expect(kScanCategoryPresets.last, kDefaultCategory);
    });
  });

  group('유효기간 빠른 선택', () {
    testWidgets('+30일 버튼이 오늘 기준 만료일을 채운다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpForm(tester);

      expect(container.read(gifticonFormControllerProvider).expiryDate, isNull);

      final DateTime before = DateTime.now();

      await tester.tap(find.widgetWithText(OutlinedButton, '+30일'));
      await tester.pump();

      final DateTime? picked =
          container.read(gifticonFormControllerProvider).expiryDate;

      expect(picked, isNotNull);

      // 탭 시점의 "오늘"이 자정 경계를 넘지 않았다면 정확히 일치한다.
      // 경계에서 흔들리지 않도록 before/after 두 기준 중 하나와 일치하는지 본다.
      final DateTime after = DateTime.now();

      expect(
        picked,
        anyOf(
          ExpiryQuickPick.after30Days.resolve(before),
          ExpiryQuickPick.after30Days.resolve(after),
        ),
      );
    });

    testWidgets('+1년 버튼도 동일하게 동작하며 표시 문구가 갱신된다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpForm(tester);

      await tester.tap(find.widgetWithText(OutlinedButton, '+1년'));
      await tester.pump();

      final DateTime? picked =
          container.read(gifticonFormControllerProvider).expiryDate;

      expect(picked, isNotNull);

      // 날짜 선택 버튼의 라벨이 "유효기간 선택 *"에서 실제 날짜로 바뀐다.
      expect(find.text('유효기간 선택 *'), findsNothing);

      final String label = '유효기간: '
          '${picked!.year}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';

      expect(find.text(label), findsOneWidget);
    });

    testWidgets('빠른 선택 버튼 3개가 모두 표시된다', (WidgetTester tester) async {
      await pumpForm(tester);

      for (final ExpiryQuickPick pick in ExpiryQuickPick.values) {
        expect(
          find.widgetWithText(OutlinedButton, pick.label),
          findsOneWidget,
          reason: '${pick.label} 버튼이 있어야 한다',
        );
      }
    });
  });

  group('금액 콤마 포맷', () {
    testWidgets('입력한 금액이 콤마와 함께 표시되고 int로 파싱된다', (WidgetTester tester) async {
      final ProviderContainer container = await pumpForm(tester);

      final Finder priceField = find.ancestor(
        of: find.text('금액(원) *'),
        matching: find.byType(TextFormField),
      );

      expect(priceField, findsOneWidget);

      await tester.enterText(priceField, '45000');
      await tester.pump();

      // 화면에는 콤마가 붙은 형태로 표시된다.
      expect(
        tester.widget<TextFormField>(priceField).controller?.text,
        '45,000',
      );

      final GifticonFormState state =
          container.read(gifticonFormControllerProvider);

      // 상태에는 콤마 포함 문자열이 저장돼도 계약 변환은 정상이다.
      expect(state.price, '45,000');
      expect(state.parsedPrice, 45000);
    });
  });
}
