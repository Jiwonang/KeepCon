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

import 'dart:async';

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
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
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
    InMemoryGifticonRepository? withRepo,
  }) {
    repo = withRepo ?? InMemoryGifticonRepository(seed: seed);
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
    boot(<Gifticon>[_gifticon()], sharedItem: _shared(ShareStatus.available));
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

    // 회수(`cancelShare`)는 available만 받으므로 회수를 권하면 안 된다.
    expect(find.text('그룹에서 사용 중이라 지금은 삭제할 수 없어요.'), findsOneWidget);
    expect(find.text(_blockedByShare), findsNothing);
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

  testWidgets('공유 여부가 확정되기 전에는 막는다(fail-closed)', (WidgetTester tester) async {
    boot(<Gifticon>[_gifticon()], sharedIdsPending: true);
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('공유 상태를 확인하는 중이에요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    expect(await repo.getGifticonById('g1'), isNotNull);
  });

  testWidgets('다이얼로그가 열린 사이 공유되면 확정 시점에 다시 막는다', (WidgetTester tester) async {
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
      sharedGifticonIdsProvider.overrideWithValue(
          const AsyncValue<Set<String>>.data(<String>{'g1'})),
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

  testWidgets('다른 기기가 먼저 지웠으면 그렇게 알리고 상세를 닫는다', (WidgetTester tester) async {
    // 목록에는 이미 없다(다른 기기가 지운 뒤 스트림이 따라왔다). 상세는 진입 스냅샷으로
    // 떠 있다.
    boot(<Gifticon>[],
        withRepo: _ThrowingDeleteRepo(StateError('Gifticon not found: g1')));
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('이미 삭제된 기프티콘이에요.'), findsOneWidget);
    expect(find.byType(GifticonDetailPage), findsNothing,
        reason: '남겨 두면 진입 스냅샷으로 없는 것을 보여준다');
  });

  testWidgets('백엔드가 공유 때문에 거부하면 그렇게 알리고 닫지 않는다', (WidgetTester tester) async {
    // 규칙이 화면 가드가 못 보는 공유(전에 나간 그룹 등)를 보고 커밋을 거부한 경우.
    // 그 타입은 StateError의 하위 타입이라, 순서를 바꿔 잡으면 "이미 삭제됐다"고 말하고
    // 살아 있는 기프티콘의 상세를 닫는다.
    boot(<Gifticon>[],
        withRepo: _ThrowingDeleteRepo(GifticonShareBlockedException('g1'),
            seed: <Gifticon>[_gifticon()]));
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(
        find.text('공유 중인 그룹이 있어 삭제할 수 없어요. '
            '전에 나간 그룹에 공유해 둔 것일 수 있어요.'),
        findsOneWidget);
    expect(find.text('이미 삭제된 기프티콘이에요.'), findsNothing);
    expect(find.byType(GifticonDetailPage), findsOneWidget);
  });

  testWidgets('통신 실패는 재시도를 권하고 상세를 그대로 둔다', (WidgetTester tester) async {
    boot(<Gifticon>[],
        withRepo: _ThrowingDeleteRepo(Exception('오프라인'),
            seed: <Gifticon>[_gifticon()]));
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('삭제하지 못했어요. 연결을 확인하고 다시 시도해 주세요.'), findsOneWidget);
    expect(find.byType(GifticonDetailPage), findsOneWidget);
  });

  testWidgets('기다리는 사이 뒤로 갔으면 성공해도 아래 화면을 닫지 않는다', (WidgetTester tester) async {
    // 미리 잡아 둔 navigator로 그대로 pop하면 상세가 아니라 **홈**이 닫힌다.
    final _PendingDeleteRepo pending =
        _PendingDeleteRepo(seed: <Gifticon>[_gifticon()]);
    boot(<Gifticon>[], withRepo: pending);
    await mountDetail(tester, _gifticon());

    await tester.tap(deleteButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pump();

    // 요청이 끝나기 전에 사용자가 뒤로 간다.
    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);

    pending.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('열기'), findsOneWidget, reason: '홈이 닫히면 빈 화면이 된다');
    expect(await pending.getGifticonById('g1'), isNull);
  });
}

/// [deleteGifticon]만 [error]로 실패시키는 저장소.
class _ThrowingDeleteRepo extends InMemoryGifticonRepository {
  _ThrowingDeleteRepo(this.error, {super.seed});

  final Object error;

  @override
  Future<void> deleteGifticon(String id) async => throw error;
}

/// [deleteGifticon]이 [gate]가 열릴 때까지 끝나지 않는 저장소(느린 망).
class _PendingDeleteRepo extends InMemoryGifticonRepository {
  _PendingDeleteRepo({super.seed});

  final Completer<void> gate = Completer<void>();

  @override
  Future<void> deleteGifticon(String id) async {
    await gate.future;
    return super.deleteGifticon(id);
  }
}
