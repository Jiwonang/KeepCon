/// main 페이지 — 기프티콘 상세(카드 탭 → 바코드 → 사용 완료) 테스트.
///
/// 고정하려는 것은 셋이다:
///  ① 목록 카드를 누르면 상세가 열리고 **바코드 번호가 보인다**.
///  ② 사용 완료 버튼이 계약 [GifticonRepository.updateStatus]를 실제로 태워 상태를 바꾸고,
///     그 결과가 상세 화면과 목록에 함께 반영된다(같은 저장소 인스턴스 공유).
///  ③ 버튼 **노출 조건** — terminal 상태(used)나 그룹 공유 중이면 누를 수 없어야 한다.
///     ③은 화면 장식이 아니라 안전장치다: 공유 중인 것을 여기서 used로 바꾸면 원본만
///     바뀌고 그룹의 SharedGifticon은 '사용 가능'으로 남아, 다른 멤버가 이미 쓴 것을
///     매장에서 꺼내게 된다(공유→원본 단방향 동기화만 계약에 있다).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/features/main/pages/gifticon_detail_page.dart';
import 'package:keepcon/features/main/state/gifticon_filter.dart';
import 'package:keepcon/features/main/state/gifticon_list_providers.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

const String _ownerId = 'user-1';
final DateTime _now = DateTime(2026, 8, 18);

Gifticon _gifticon({
  String id = 'g1',
  String productName = '아메리카노 T',
  String? barcode = '9788901234567',
  GifticonStatus status = GifticonStatus.available,
  String? targetGroupId,
}) {
  return Gifticon(
    id: id,
    ownerId: _ownerId,
    brand: '스타벅스',
    productName: productName,
    category: '카페',
    price: 4500,
    barcode: barcode,
    expiryDate: _now.add(const Duration(days: 30)),
    registeredAt: _now,
    status: status,
    targetGroupId: targetGroupId,
  );
}

void main() {
  late InMemoryGifticonRepository repo;
  late ProviderContainer container;

  /// 저장소 하나를 목록 스트림과 provider 양쪽에 물린다 — 상세에서 상태를 바꾸면
  /// 목록도 같은 인스턴스를 보고 있어야 화면이 따라간다(계약 SSOT provider 규약).
  void boot(List<Gifticon> seed) {
    repo = InMemoryGifticonRepository(seed: seed);
    container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(repo),
        rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
      ],
    );
  }

  tearDown(() {
    container.dispose();
    repo.dispose();
  });

  /// 기본 테스트 뷰포트(800×600)는 상세 화면보다 짧아, 하단의 사용 완료 버튼과 안내
  /// 배너가 [ListView]의 지연 생성에 걸려 **아예 빌드되지 않는다**(찾을 수도 없다).
  /// 화면을 길게 잡아 "보이는가"가 아니라 "노출 조건이 맞는가"를 단언한다.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> mountMain(WidgetTester tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mountDetail(WidgetTester tester, Gifticon g) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: GifticonDetailPage(gifticon: g)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('목록 카드를 누르면 상세가 열리고 바코드 번호가 보인다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountMain(tester);

    expect(find.byType(GifticonDetailPage), findsNothing);

    await tester.tap(find.text('아메리카노 T'));
    await tester.pumpAndSettle();

    expect(find.byType(GifticonDetailPage), findsOneWidget);
    // BarcodeWidget이 drawText로 번호를 함께 그린다.
    expect(find.text('9788901234567'), findsWidgets);
    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsOneWidget);
  });

  testWidgets('사용 완료 → 확인하면 계약 updateStatus로 상태가 실제 전이된다',
      (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());

    await tester.tap(find.widgetWithText(ElevatedButton, '사용 완료'));
    await tester.pumpAndSettle();

    // 되돌릴 수 없는 전이라 확인을 한 번 받는다.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '사용 완료'));
    await tester.pumpAndSettle();

    expect((await repo.getGifticonById('g1'))!.status, GifticonStatus.used);
    // 화면도 새 상태를 따라간다 — 버튼은 사라지고 안내가 뜬다.
    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsNothing);
    expect(find.text('이미 사용 완료한 기프티콘이에요.'), findsOneWidget);
  });

  testWidgets('확인 다이얼로그에서 닫으면 상태가 그대로다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());

    await tester.tap(find.widgetWithText(ElevatedButton, '사용 완료'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '닫기'));
    await tester.pumpAndSettle();

    expect(
      (await repo.getGifticonById('g1'))!.status,
      GifticonStatus.available,
    );
    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsOneWidget);
  });

  testWidgets('이미 사용 완료면 버튼이 없다 — terminal 전이라 호출 자체가 StateError',
      (WidgetTester tester) async {
    final Gifticon used = _gifticon(status: GifticonStatus.used);
    boot(<Gifticon>[used]);
    await mountDetail(tester, used);

    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsNothing);
    expect(find.text('이미 사용 완료한 기프티콘이에요.'), findsOneWidget);
  });

  testWidgets('그룹 공유 중이면 버튼 대신 공유 탭으로 안내한다', (WidgetTester tester) async {
    final Gifticon shared = _gifticon(targetGroupId: 'group-1');
    boot(<Gifticon>[shared]);
    await mountDetail(tester, shared);

    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsNothing);
    expect(
      find.text('그룹에 공유 중이에요. 사용 완료 처리는 공유 탭에서 해주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('바코드 번호가 없으면 안내로 대체한다', (WidgetTester tester) async {
    final Gifticon noBarcode = _gifticon(barcode: null);
    boot(<Gifticon>[noBarcode]);
    await mountDetail(tester, noBarcode);

    expect(find.text('바코드 번호가 없어요.'), findsOneWidget);
  });

  testWidgets('상태 필터가 걸려 있어도 사용 완료 후 상세가 사라지지 않는다',
      (WidgetTester tester) async {
    // 회귀 방어: 상세가 표시 목록(visibleGifticonsProvider)을 봤다면, '사용가능' 필터가
    // 걸린 상태에서 사용 완료를 누르는 순간 항목이 표시 목록에서 빠져 화면이 "찾을 수
    // 없어요"로 바뀐다 — 방금 성공한 조작이 오류처럼 읽힌다. 원천 목록을 봐야 한다.
    boot(<Gifticon>[_gifticon()]);
    container.read(filterProvider.notifier).state =
        GifticonFilter.none.withStatus(GifticonStatus.available);
    await mountDetail(tester, _gifticon());

    await tester.tap(find.widgetWithText(ElevatedButton, '사용 완료'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '사용 완료'));
    await tester.pumpAndSettle();

    // 상세는 여전히 그 기프티콘을 보여주고, 새 상태를 반영한다.
    expect(find.text('아메리카노 T'), findsOneWidget);
    expect(find.text('이미 사용 완료한 기프티콘이에요.'), findsOneWidget);
  });
}
