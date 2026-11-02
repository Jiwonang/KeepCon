/// main 페이지 — 기프티콘 상세의 삭제 테스트.
///
/// 고정하려는 것:
///  ① 삭제가 계약 [GifticonRepository.deleteGifticon]을 실제로 태우고, 성공하면 상세를
///     닫는다(지운 것의 상세를 남겨 두면 진입 스냅샷으로 없는 것을 보여준다).
///  ② **공유 가드** — 그룹에 아직 쓰이지 않은 공유 항목이 있으면 지우지 않고 회수를
///     안내한다. 사용 완료된 공유 항목은 이력이라 막지 않는다. 공유 여부가 확정되기
///     전에는 막는다(fail-closed).
///  ③ 확인 다이얼로그가 열려 있는 사이 공유가 생기면 확정 시점에 다시 막는다.
///  ④ 남의 기프티콘에는 삭제 버튼이 없다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/main/pages/gifticon_detail_page.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/providers/raw_gifticons_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/providers/shared_gifticons_provider.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

final DateTime _now = DateTime(2026, 8, 18);
const String _ownerId = 'user-1';
const String _blockedByShare =
    '그룹에 공유 중이라 삭제할 수 없어요. 공유 탭에서 공유를 회수한 뒤 삭제해 주세요.';

const User _me = User(
  id: _ownerId,
  email: 'me@example.com',
  displayName: '나',
);

Gifticon _gifticon({String ownerId = _ownerId}) {
  return Gifticon(
    id: 'g1',
    ownerId: ownerId,
    brand: '스타벅스',
    productName: '아메리카노 T',
    category: '카페',
    price: 4500,
    barcode: '9788901234567',
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

  /// [sharedItem]을 주면 "그 기프티콘이 그룹에 공유돼 있다"를 흉내 낸다.
  void boot(
    List<Gifticon> seed, {
    SharedGifticon? sharedItem,
    bool sharedIdsPending = false,
  }) {
    repo = InMemoryGifticonRepository(seed: seed);
    container = ProviderContainer(
      overrides: <Override>[
        nowProvider.overrideWithValue(_now),
        gifticonRepositoryProvider.overrideWithValue(repo),
        rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
        sessionUserProvider.overrideWith((_) => Stream<User?>.value(_me)),
        sharedGifticonIdsProvider.overrideWithValue(sharedIdsPending
            ? const AsyncValue<Set<String>>.loading()
            : AsyncValue<Set<String>>.data(<String>{
                if (sharedItem != null) sharedItem.gifticonId,
              })),
        allSharedProvider.overrideWithValue(
          <SharedGifticon>[if (sharedItem != null) sharedItem],
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      repo.dispose();
    });
  }

  /// 상세를 **홈 위에 push**해 띄운다 — 삭제 뒤 화면이 닫히는지(pop) 보려면 아래에
  /// 돌아갈 화면이 있어야 한다.
  Future<void> mountDetail(WidgetTester tester, Gifticon g) async {
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
    expect(find.byType(GifticonDetailPage), findsOneWidget);
  }

  Finder deleteButton() => find.byTooltip('삭제');

  testWidgets('확인하면 저장소에서 지워지고 상세가 닫힌다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(await repo.getGifticonById('g1'), isNull);
    expect(find.byType(GifticonDetailPage), findsNothing,
        reason: '지운 기프티콘의 상세가 남으면 진입 스냅샷으로 없는 것을 보여준다');
    expect(find.text('기프티콘을 삭제했어요.'), findsOneWidget);
  });

  testWidgets('확인 다이얼로그에서 닫으면 그대로다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '닫기'));
    await tester.pumpAndSettle();

    expect(await repo.getGifticonById('g1'), isNotNull);
    expect(find.byType(GifticonDetailPage), findsOneWidget);
  });

  testWidgets('그룹에 공유 중이면 묻지 않고 회수를 안내한다', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()],
        sharedItem: _shared(ShareStatus.available));
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(_blockedByShare), findsOneWidget);
    expect(await repo.getGifticonById('g1'), isNotNull);
  });

  testWidgets('그룹에서 사용 중(inUse)이어도 막는다 — used만 이력이다',
      (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], sharedItem: _shared(ShareStatus.inUse));
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(find.text(_blockedByShare), findsOneWidget);
    expect(await repo.getGifticonById('g1'), isNotNull);
  });

  testWidgets('공유 항목이 이미 사용 완료면 지울 수 있다 — 이력은 그룹에 남는다',
      (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], sharedItem: _shared(ShareStatus.used));
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(await repo.getGifticonById('g1'), isNull);
  });

  testWidgets('공유 여부가 확정되기 전에는 막는다(fail-closed)',
      (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], sharedIdsPending: true);
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('공유 상태를 확인하는 중이에요. 잠시 후 다시 시도해 주세요.'),
        findsOneWidget);
    expect(await repo.getGifticonById('g1'), isNotNull);
  });

  testWidgets('다이얼로그가 열린 사이 공유되면 확정 시점에 다시 막는다',
      (WidgetTester tester) async {
    // 공유 판정을 다이얼로그 **앞에서만** 읽으면, 그 사이 다른 기기가 그룹에 공유한
    // 원본을 지워 그룹에 원본 없는 공유 항목을 남긴다.
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    container.updateOverrides(<Override>[
      nowProvider.overrideWithValue(_now),
      gifticonRepositoryProvider.overrideWithValue(repo),
      rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
      sessionUserProvider.overrideWith((_) => Stream<User?>.value(_me)),
      sharedGifticonIdsProvider
          .overrideWithValue(const AsyncValue<Set<String>>.data(<String>{'g1'})),
      allSharedProvider
          .overrideWithValue(<SharedGifticon>[_shared(ShareStatus.available)]),
    ]);
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text(_blockedByShare), findsOneWidget);
    expect(await repo.getGifticonById('g1'), isNotNull);
  });

  testWidgets('남의 기프티콘에는 삭제 버튼이 없다', (WidgetTester tester) async {
    final Gifticon others = _gifticon(ownerId: 'someone-else');
    boot(<Gifticon>[others]);
    await mountDetail(tester, others);

    expect(deleteButton(), findsNothing);
  });
}
