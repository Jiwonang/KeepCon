/// main 페이지 — 기프티콘 내용 수정 테스트.
///
/// 고정하려는 것:
///  ① 수정이 계약 [GifticonRepository.updateDetails]를 실제로 태우고, 상세가 새 값을 보여 준다.
///  ② **공유 가드** — 공유 중이면 열지 않고, 열어 둔 사이 공유되면 저장을 막는다(입력 유지).
///  ③ 바코드 중복은 등록 폼과 같게 막되, 자기 번호와 그대로인 번호는 막지 않는다.
///  ④ 실패 안내 — 공유 거부(유지)·이미 없음(둘 다 닫힘)·통신 실패(유지).
///  ⑤ 레거시 카테고리는 저장만으로 바뀌지 않는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/main/pages/gifticon_detail_page.dart';
import 'package:keepcon/features/main/pages/gifticon_edit_page.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/providers/raw_gifticons_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/providers/shared_gifticons_provider.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

final DateTime _now = DateTime(2026, 8, 18);
const String _ownerId = 'user-1';
const String _blockedByShare =
    '그룹에 공유 중이라 수정할 수 없어요. 공유 탭에서 공유를 회수한 뒤 수정해 주세요.';

const User _me = User(id: _ownerId, email: 'me@example.com', displayName: '나');

Gifticon _gifticon({
  String id = 'g1',
  String ownerId = _ownerId,
  String? barcode = '111',
  String category = '카페/음료',
}) {
  return Gifticon(
    id: id,
    ownerId: ownerId,
    brand: '스타벅스',
    productName: '아메리카노 T',
    category: category,
    price: 4500,
    barcode: barcode,
    expiryDate: _now.add(const Duration(days: 30)),
    registeredAt: _now,
  );
}

SharedGifticon _shared(ShareStatus status) {
  return SharedGifticon(
    id: 'shared-1',
    groupId: 'g_family',
    gifticonId: 'g1',
    sharedByUserId: _ownerId,
    brand: '스타벅스',
    productName: '아메리카노 T',
    expiryDate: _now.add(const Duration(days: 30)),
    status: status,
  );
}

void main() {
  late InMemoryGifticonRepository repo;
  late ProviderContainer container;

  List<Override> overrides(SharedGifticon? sharedItem, bool pending) =>
      <Override>[
        nowProvider.overrideWithValue(_now),
        gifticonRepositoryProvider.overrideWithValue(repo),
        rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
        sessionUserProvider.overrideWith((_) => Stream<User?>.value(_me)),
        sharedGifticonIdsProvider.overrideWithValue(pending
            ? const AsyncValue<Set<String>>.loading()
            : AsyncValue<Set<String>>.data(<String>{
                if (sharedItem != null) sharedItem.gifticonId,
              })),
        allSharedProvider.overrideWithValue(
          <SharedGifticon>[if (sharedItem != null) sharedItem],
        ),
      ];

  void boot(
    List<Gifticon> seed, {
    SharedGifticon? sharedItem,
    bool pending = false,
    InMemoryGifticonRepository? withRepo,
  }) {
    repo = withRepo ?? InMemoryGifticonRepository(seed: seed);
    container = ProviderContainer(overrides: overrides(sharedItem, pending));
    addTearDown(() {
      container.dispose();
      repo.dispose();
    });
  }

  /// 입력칸과 저장 버튼이 [ListView] 지연 생성에 걸리지 않게 화면을 길게 잡고, 상세를
  /// 홈 위에 push한다 — 닫힘(pop)을 보려면 아래에 돌아갈 화면이 있어야 한다.
  Future<void> mountDetail(WidgetTester tester, Gifticon g) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GifticonDetailPage(gifticon: g),
                    ),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<void> openEdit(WidgetTester tester) async {
    await tester.tap(find.byTooltip('수정'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await tester.pumpAndSettle();
  }

  testWidgets('저장하면 저장소에 반영되고 상세가 새 값을 보여 준다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tester.enterText(field('브랜드 / 사용처'), '투썸');
    await tester.enterText(field('금액 / 금액권 잔액 (선택)'), '5,000');
    await tester.enterText(field('바코드 번호'), '222');
    await tester.tap(find.text('카페/음료'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('베이커리').last);
    await tester.pumpAndSettle();
    await tapSave(tester);

    final Gifticon stored = (await repo.getGifticonById('g1'))!;
    expect(stored.productName, '라떼');
    expect(stored.brand, '투썸');
    expect(stored.price, 5000);
    expect(stored.barcode, '222');
    expect(stored.category, '베이커리');
    expect(find.byType(GifticonEditPage), findsNothing);
    expect(find.byType(GifticonDetailPage), findsOneWidget);
    expect(find.text('라떼'), findsOneWidget);
    expect(find.text('수정했어요.'), findsOneWidget);
  });

  testWidgets('바코드를 비우면 지워진다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('바코드 번호'), '');
    await tapSave(tester);

    expect((await repo.getGifticonById('g1'))!.barcode, isNull);
  });

  testWidgets('바꾼 것이 없으면 쓰지 않고 닫는다', (WidgetTester tester) async {
    final _CountingRepo counting = _CountingRepo(seed: <Gifticon>[_gifticon()]);
    boot(<Gifticon>[], withRepo: counting);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tapSave(tester);

    expect(counting.updates, 0);
    expect(find.byType(GifticonEditPage), findsNothing);
    expect(find.text('수정했어요.'), findsNothing);
  });

  testWidgets('필수 항목을 비우면 저장되지 않는다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('브랜드 / 사용처'), '  ');
    await tapSave(tester);

    expect(find.text('브랜드를 입력해 주세요.'), findsOneWidget);
    expect(find.byType(GifticonEditPage), findsOneWidget);
    expect((await repo.getGifticonById('g1'))!.brand, '스타벅스');
  });

  testWidgets('공유 중이면 수정 화면을 열지 않는다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], sharedItem: _shared(ShareStatus.available));
    await mountDetail(tester, _gifticon());

    await openEdit(tester);

    expect(find.byType(GifticonEditPage), findsNothing);
    expect(find.text(_blockedByShare), findsOneWidget);
  });

  testWidgets('그룹에서 사용 중이면 회수를 권하지 않고 막는다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], sharedItem: _shared(ShareStatus.inUse));
    await mountDetail(tester, _gifticon());

    await openEdit(tester);

    expect(find.byType(GifticonEditPage), findsNothing);
    expect(find.text('그룹에서 사용 중이라 지금은 수정할 수 없어요.'), findsOneWidget);
  });

  testWidgets('공유 여부가 확정되기 전에는 막는다(fail-closed)', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], pending: true);
    await mountDetail(tester, _gifticon());

    await openEdit(tester);

    expect(find.byType(GifticonEditPage), findsNothing);
    expect(find.text('공유 상태를 확인하는 중이에요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('공유 조회가 실패하면 "확인 중"이라 하지 않고 막는다', (WidgetTester tester) async {
    // 실패를 로딩처럼 말하면 끝나지 않을 일을 기다리게 한다.
    boot(<Gifticon>[_gifticon()]);
    container.updateOverrides(<Override>[
      ...overrides(null, false).take(4),
      sharedGifticonIdsProvider.overrideWithValue(
          const AsyncValue<Set<String>>.error('boom', StackTrace.empty)),
      allSharedProvider.overrideWithValue(const <SharedGifticon>[]),
    ]);
    await mountDetail(tester, _gifticon());

    await openEdit(tester);

    expect(find.byType(GifticonEditPage), findsNothing);
    expect(find.text('공유 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('공유가 이미 사용 완료면 수정할 수 있다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], sharedItem: _shared(ShareStatus.used));
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tapSave(tester);

    expect((await repo.getGifticonById('g1'))!.productName, '라떼');
  });

  testWidgets('열어 둔 사이 공유되면 저장을 막고 입력을 남긴다', (WidgetTester tester) async {
    // 판정을 화면을 열 때만 하면 입력하는 몇 분 사이의 공유를 놓친다.
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);
    await tester.enterText(field('상품명'), '라떼');

    container.updateOverrides(overrides(_shared(ShareStatus.available), false));
    await tester.pump();
    await tapSave(tester);

    expect(find.text(_blockedByShare), findsOneWidget);
    expect(find.byType(GifticonEditPage), findsOneWidget);
    expect(find.text('라떼'), findsOneWidget);
    expect((await repo.getGifticonById('g1'))!.productName, '아메리카노 T');
  });

  testWidgets('다른 기프티콘의 바코드로 바꾸면 막는다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon(), _gifticon(id: 'g2', barcode: '222')]);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('바코드 번호'), '222');
    await tapSave(tester);

    expect(find.text('이미 등록된 바코드 번호입니다.'), findsOneWidget);
    expect((await repo.getGifticonById('g1'))!.barcode, '111');

    // 번호를 고치면 안내가 사라지고 저장된다.
    await tester.enterText(field('바코드 번호'), '333');
    await tester.pump();
    expect(find.text('이미 등록된 바코드 번호입니다.'), findsNothing);
    await tapSave(tester);
    expect((await repo.getGifticonById('g1'))!.barcode, '333');
  });

  testWidgets('중복 상대가 사라지면 같은 번호로 다시 저장할 수 있다', (WidgetTester tester) async {
    // 지난 판정을 믿고 막으면 화면을 다시 열기 전까지 저장할 수 없다.
    boot(<Gifticon>[_gifticon(), _gifticon(id: 'g2', barcode: '222')]);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('바코드 번호'), '222');
    await tapSave(tester);
    expect(find.text('이미 등록된 바코드 번호입니다.'), findsOneWidget);

    await repo.deleteGifticon('g2');
    await tapSave(tester);

    expect((await repo.getGifticonById('g1'))!.barcode, '222');
  });

  testWidgets('이미 겹쳐 있는 번호는 그대로 두면 다른 필드를 고칠 수 있다',
      (WidgetTester tester) async {
    // 옛 데이터의 중복이 다른 필드의 수정까지 막으면 고칠 길이 없다.
    boot(<Gifticon>[_gifticon(), _gifticon(id: 'g2')]);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tapSave(tester);

    expect((await repo.getGifticonById('g1'))!.productName, '라떼');
  });

  testWidgets('중복을 확인하지 못하면 저장하지 않는다', (WidgetTester tester) async {
    boot(<Gifticon>[],
        withRepo: _FailingListRepo(seed: <Gifticon>[_gifticon()]));
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('바코드 번호'), '222');
    await tapSave(tester);

    expect(
        find.text('바코드 중복을 확인하지 못했어요. 연결을 확인하고 다시 시도해 주세요.'), findsOneWidget);
    expect((await repo.getGifticonById('g1'))!.barcode, '111');
  });

  testWidgets('백엔드가 공유 때문에 거부하면 그렇게 알리고 입력을 남긴다', (WidgetTester tester) async {
    // 그 타입은 StateError의 하위 타입이라, 순서를 바꿔 잡으면 "이미 삭제됐다"고 닫는다.
    boot(<Gifticon>[],
        withRepo: _ThrowingUpdateRepo(GifticonShareBlockedException('g1'),
            seed: <Gifticon>[_gifticon()]));
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tapSave(tester);

    expect(find.text('공유 중인 그룹이 있어 수정할 수 없어요. 전에 나간 그룹에 공유해 둔 것일 수 있어요.'),
        findsOneWidget);
    expect(find.byType(GifticonEditPage), findsOneWidget);
  });

  testWidgets('이미 없으면 수정 화면과 상세를 함께 닫는다', (WidgetTester tester) async {
    boot(<Gifticon>[],
        withRepo: _ThrowingUpdateRepo(StateError('Gifticon not found: g1'),
            seed: <Gifticon>[_gifticon()]));
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tapSave(tester);

    expect(find.byType(GifticonEditPage), findsNothing);
    expect(find.byType(GifticonDetailPage), findsNothing);
    expect(find.text('이미 삭제된 기프티콘이에요.'), findsOneWidget);
  });

  testWidgets('통신 실패는 재시도를 권하고 입력을 남긴다', (WidgetTester tester) async {
    boot(<Gifticon>[],
        withRepo: _ThrowingUpdateRepo(Exception('오프라인'),
            seed: <Gifticon>[_gifticon()]));
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tapSave(tester);

    expect(find.text('저장하지 못했어요. 연결을 확인하고 다시 시도해 주세요.'), findsOneWidget);
    expect(find.byType(GifticonEditPage), findsOneWidget);
    expect(find.text('라떼'), findsOneWidget);
  });

  testWidgets('목록에 없는 레거시 카테고리는 저장만으로 바뀌지 않는다', (WidgetTester tester) async {
    final Gifticon legacy = _gifticon(category: '카페');
    boot(<Gifticon>[legacy]);
    await mountDetail(tester, legacy);
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tapSave(tester);

    final Gifticon stored = (await repo.getGifticonById('g1'))!;
    expect(stored.productName, '라떼');
    expect(stored.category, '카페');
  });

  testWidgets('저장을 기다리는 사이 뒤로 갔으면 아래 화면을 닫지 않는다', (WidgetTester tester) async {
    final _PendingUpdateRepo pending =
        _PendingUpdateRepo(seed: <Gifticon>[_gifticon()]);
    boot(<Gifticon>[], withRepo: pending);
    await mountDetail(tester, _gifticon());
    await openEdit(tester);

    await tester.enterText(field('상품명'), '라떼');
    await tester.tap(find.widgetWithText(ElevatedButton, '저장'));
    await tester.pump();

    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.byType(GifticonDetailPage), findsOneWidget);

    pending.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(GifticonDetailPage), findsOneWidget,
        reason: '미리 잡아 둔 경로로 pop하면 상세가 닫힌다');
  });

  testWidgets('남의 기프티콘에는 수정 버튼이 없다', (WidgetTester tester) async {
    final Gifticon others = _gifticon(ownerId: 'someone-else');
    boot(<Gifticon>[others]);
    await mountDetail(tester, others);

    expect(find.byTooltip('수정'), findsNothing);
  });
}

class _CountingRepo extends InMemoryGifticonRepository {
  _CountingRepo({super.seed});

  int updates = 0;

  @override
  Future<Gifticon> updateDetails(String id, GifticonDetails details) {
    updates++;
    return super.updateDetails(id, details);
  }
}

/// [updateDetails]만 [error]로 실패시키는 저장소.
class _ThrowingUpdateRepo extends InMemoryGifticonRepository {
  _ThrowingUpdateRepo(this.error, {super.seed});

  final Object error;

  @override
  Future<Gifticon> updateDetails(String id, GifticonDetails details) async =>
      throw error;
}

/// 중복 검사의 목록 읽기만 실패시키는 저장소.
class _FailingListRepo extends InMemoryGifticonRepository {
  _FailingListRepo({super.seed});

  @override
  Future<List<Gifticon>> getGifticons(String ownerId) async =>
      throw Exception('오프라인');
}

/// [updateDetails]가 [gate]가 열릴 때까지 끝나지 않는 저장소(느린 망).
class _PendingUpdateRepo extends InMemoryGifticonRepository {
  _PendingUpdateRepo({super.seed});

  final Completer<void> gate = Completer<void>();

  @override
  Future<Gifticon> updateDetails(String id, GifticonDetails details) async {
    await gate.future;
    return super.updateDetails(id, details);
  }
}
