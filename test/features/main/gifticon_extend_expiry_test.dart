/// main 페이지 — 만료된 기프티콘의 "기프티콘 기간 연장하기" 테스트.
///
/// 고정하려는 것은 셋이다:
///  ① **노출 조건** — 만료됐고, 사용 완료가 아니고, 등록한 본인이고, 공유 경로가 확정된
///     뒤에만 버튼이 뜬다. 이건 장식이 아니라 안전장치다(아래 ③).
///  ② 개인 경로 — 계약 [GifticonRepository.extendExpiry]를 실제로 태워 만료일이 옮겨지고
///     저장된 `expired`가 `available`로 되살아나며, 그 결과가 화면에 반영된다.
///  ③ **공유 경로** — 그룹에 공유 중이면 [ShareRepository.extendSharedExpiry]를 타야 한다.
///     개인 경로를 부르면 원본만 옮겨지고 **그룹 스냅샷은 옛 날짜로 남는데, 그 어긋남은
///     어느 화면에도 보이지 않는다.** 그래서 여기서는 계약 구현을 실제로 태워 스냅샷과
///     원본이 **함께** 옮겨지는 것을 단언한다(요구사항의 "양쪽 동기화").
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
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

final DateTime _now = DateTime(2026, 8, 18);
const String _ownerId = 'user-1';
const String _buttonLabel = '기프티콘 기간 연장하기';

const User _me = User(
  id: _ownerId,
  email: 'me@example.com',
  displayName: '나',
);

Gifticon _gifticon({
  String id = 'g1',
  String ownerId = _ownerId,
  GifticonStatus status = GifticonStatus.available,
  Duration expiresIn = const Duration(days: -3),
}) {
  return Gifticon(
    id: id,
    ownerId: ownerId,
    brand: '스타벅스',
    productName: '아메리카노 T',
    category: '카페',
    price: 4500,
    barcode: '9788901234567',
    expiryDate: _now.add(expiresIn),
    registeredAt: _now.subtract(const Duration(days: 60)),
    status: status,
  );
}

void main() {
  late InMemoryGifticonRepository repo;
  late ProviderContainer container;

  /// [sharedItem]을 주면 "그 기프티콘이 그룹에 공유돼 있다"를 흉내 낸다.
  /// [sharedIdsPending]은 공유 판정이 아직 확정 전(로딩)인 상태다.
  void boot(
    List<Gifticon> seed, {
    SharedGifticon? sharedItem,
    bool sharedIdsPending = false,
    bool sharedIdsFailed = false,
  }) {
    repo = InMemoryGifticonRepository(seed: seed);
    final AsyncValue<Set<String>> idsState = sharedIdsFailed
        ? const AsyncValue<Set<String>>.error('boom', StackTrace.empty)
        : sharedIdsPending
            ? const AsyncValue<Set<String>>.loading()
            : AsyncValue<Set<String>>.data(<String>{
                if (sharedItem != null) sharedItem.gifticonId,
              });
    container = ProviderContainer(
      overrides: <Override>[
        nowProvider.overrideWithValue(_now),
        gifticonRepositoryProvider.overrideWithValue(repo),
        rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
        sessionUserProvider.overrideWith((_) => Stream<User?>.value(_me)),
        sharedGifticonIdsProvider.overrideWithValue(idsState),
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

  /// 기본 뷰포트(800×600)는 상세 화면보다 짧아 하단 버튼이 [ListView]의 지연 생성에
  /// 걸려 아예 빌드되지 않는다. 화면을 길게 잡아 "노출 조건이 맞는가"를 단언한다.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> mountDetail(
    WidgetTester tester,
    Gifticon g, {
    ProviderContainer? c,
  }) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c ?? container,
        child: MaterialApp(home: GifticonDetailPage(gifticon: g)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 날짜 선택기를 열고 **초기 선택값 그대로** 확정한다.
  ///
  /// 초기값은 화면이 계산한 하한(= 만료된 기프티콘이면 오늘)이라, 어느 달력 칸을 눌러야
  /// 하는지에 테스트가 의존하지 않는다. 고르는 날짜 자체는 이 테스트의 관심사가 아니고
  /// "선택 결과가 계약 경로로 흘러가는가"가 관심사다.
  Future<void> tapExtendAndConfirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '연장'));
    await tester.pumpAndSettle();
  }

  group('노출 조건', () {
    testWidgets('만료된 내 기프티콘에는 버튼이 뜬다', (WidgetTester tester) async {
      boot(<Gifticon>[_gifticon()]);
      await mountDetail(tester, _gifticon());

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsOneWidget);
    });

    testWidgets('아직 만료되지 않았으면 버튼이 없다', (WidgetTester tester) async {
      final Gifticon alive = _gifticon(expiresIn: const Duration(days: 10));
      boot(<Gifticon>[alive]);
      await mountDetail(tester, alive);

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('만료일 당일은 아직 쓸 수 있으므로 버튼이 없다', (WidgetTester tester) async {
      // 경계 — `isExpiredByDate`는 만료일 당일을 만료로 보지 않는다("2026-08-18까지"는
      // 그 날을 포함하는 표기다). 여기서 버튼이 뜨면 아직 쓸 수 있는 기프티콘에
      // 연장을 권하는 셈이다.
      final Gifticon today = _gifticon(expiresIn: Duration.zero);
      boot(<Gifticon>[today]);
      await mountDetail(tester, today);

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('저장된 status가 expired면 날짜가 남아 있어도 버튼이 뜬다',
        (WidgetTester tester) async {
      // 만료 판정의 실질 정본은 날짜지만, 레거시·데모 시드에는 저장된 `expired`가 있다.
      // 사용자에게는 그것도 똑같이 '만료'로 보이므로 연장 경로가 열려야 한다.
      final Gifticon stored = _gifticon(
        status: GifticonStatus.expired,
        expiresIn: const Duration(days: 10),
      );
      boot(<Gifticon>[stored]);
      await mountDetail(tester, stored);

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsOneWidget);
    });

    testWidgets('사용 완료한 것은 기간을 늘려도 못 쓰므로 버튼이 없다', (WidgetTester tester) async {
      final Gifticon used = _gifticon(status: GifticonStatus.used);
      boot(<Gifticon>[used]);
      await mountDetail(tester, used);

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('등록한 본인이 아니면 버튼이 없다', (WidgetTester tester) async {
      // 요구사항: "최초에 등록한 사람만 연장할 수 있다". main은 자기 목록만 보지만,
      // 상세는 진입 스냅샷을 폴백으로 들고 있어 남의 것이 표시될 여지가 있다.
      final Gifticon others = _gifticon(ownerId: 'someone-else');
      boot(<Gifticon>[others]);
      await mountDetail(tester, others);

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('그룹에서 이미 사용된 공유 항목에는 버튼이 없다', (WidgetTester tester) async {
      // 다른 멤버가 내 공유분을 사용해도 **내 원본은 available로 남는다**(원본 동기화는
      // 소유자 권한이 없어 건너뛴다). `!used`만 보면 이 상태에서 버튼이 뜨고, 누르면
      // 계약 가드가 반드시 거부한다 — 몇 번을 눌러도 같은 실패다.
      final SharedGifticon usedInGroup = SharedGifticon(
        id: 'shared-1',
        groupId: 'g_family',
        gifticonId: 'g1',
        sharedByUserId: _ownerId,
        brand: '스타벅스',
        productName: '아메리카노 T',
        expiryDate: _now.subtract(const Duration(days: 3)),
        status: ShareStatus.used,
      );
      boot(<Gifticon>[_gifticon()], sharedItem: usedInGroup);
      await mountDetail(tester, _gifticon());

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('공유 여부가 확정되기 전에는 버튼 대신 안내가 뜬다(fail-closed)',
        (WidgetTester tester) async {
      // 로딩을 "공유 안 됨"으로 접으면 개인 경로가 열려, 공유 중인 기프티콘의 원본만
      // 옮겨지고 그룹 스냅샷은 옛 날짜로 남는다.
      boot(<Gifticon>[_gifticon()], sharedIdsPending: true);
      await mountDetail(tester, _gifticon());

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
      expect(find.text('공유 상태를 확인하는 중이에요…'), findsOneWidget);
    });

    testWidgets('공유 여부 조회가 실패하면 재시도 경로를 준다', (WidgetTester tester) async {
      boot(<Gifticon>[_gifticon()], sharedIdsFailed: true);
      await mountDetail(tester, _gifticon());

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
      expect(
          find.text('공유 상태를 확인하지 못해 사용 완료와 기간 연장을 잠시 막아 뒀어요.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '다시 시도'), findsOneWidget);
    });
  });

  testWidgets('연장·사용 완료 버튼이 함께 뜰 때 서로 맞닿지 않는다', (WidgetTester tester) async {
    // 만료됐고·아직 사용 전이고·공유 중이 아닌 기프티콘은 **두 버튼이 함께** 뜬다.
    // 사이 여백이 없으면 두 개의 큰 버튼이 붙어 그려지고 오탭이 생긴다(코드리뷰 검출).
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());

    final Finder extend = find.widgetWithText(ElevatedButton, _buttonLabel);
    final Finder markUsed = find.widgetWithText(ElevatedButton, '사용 완료');
    expect(extend, findsOneWidget);
    expect(markUsed, findsOneWidget);
    expect(
      tester.getTopLeft(markUsed).dy - tester.getBottomLeft(extend).dy,
      greaterThanOrEqualTo(12.0),
    );
  });

  testWidgets('고를 수 있는 날이 없으면 이유를 알린다 — 조용한 무반응이 아니다',
      (WidgetTester tester) async {
    // 상한(2035-12-31)까지 만료일이 차 있는데 저장된 status가 expired인 문서가 있다
    // (레거시·데모 시드). 하한이 상한을 넘어 선택기를 열 수 없는데, 그때 조용히
    // 돌아가면 사용자는 버튼이 먹통이라고 읽는다(코드리뷰 검출).
    final Gifticon atLimit = Gifticon(
      id: 'g1',
      ownerId: _ownerId,
      brand: '스타벅스',
      productName: '아메리카노 T',
      category: '카페',
      price: 4500,
      expiryDate: DateTime(2035, 12, 31),
      registeredAt: _now,
      status: GifticonStatus.expired,
    );
    boot(<Gifticon>[atLimit]);
    await mountDetail(tester, atLimit);

    await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('2035.12.31까지만 연장할 수 있어요.'), findsOneWidget);
  });

  group('선택 가능 하한', () {
    // 하한 계산은 이 화면의 계약이다 — "저장소가 거부하는 값을 화면이 먼저 내주지
    // 않는다". 값을 단언하지 않으면 하한을 401일 밀어도 스위트가 통과한다(뮤테이션 실측).

    testWidgets('이미 만료된 것은 오늘부터 고를 수 있다', (WidgetTester tester) async {
      boot(<Gifticon>[_gifticon()]);
      await mountDetail(tester, _gifticon());

      await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .firstDate,
        DateTime(2026, 8, 18),
      );
    });

    testWidgets('만료일이 남아 있으면 그 다음 날부터고, 저장소가 그 값을 받는다',
        (WidgetTester tester) async {
      // 만료일 당일은 `isLaterExpiryDate`가 거부한다(같은 날은 연장이 아니다).
      // 하한이 하루 어긋나면 화면이 내준 값을 저장소가 튕겨 낸다.
      final Gifticon stored = _gifticon(
        status: GifticonStatus.expired,
        expiresIn: const Duration(days: 10), // 2026-08-28
      );
      boot(<Gifticon>[stored]);
      await mountDetail(tester, stored);

      await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DatePickerDialog>(find.byType(DatePickerDialog))
            .firstDate,
        DateTime(2026, 8, 29),
      );

      await tester.tap(find.widgetWithText(TextButton, '연장'));
      await tester.pumpAndSettle();

      expect(
          (await repo.getGifticonById('g1'))!.expiryDate, DateTime(2026, 8, 29),
          reason: '화면이 내준 하한을 저장소가 실제로 받는다');
    });
  });

  group('개인 경로(공유 중이 아닌 기프티콘)', () {
    testWidgets('날짜를 고르면 계약 extendExpiry로 만료일이 실제로 옮겨진다',
        (WidgetTester tester) async {
      boot(<Gifticon>[_gifticon()]);
      await mountDetail(tester, _gifticon());

      await tapExtendAndConfirm(tester);

      final Gifticon after = (await repo.getGifticonById('g1'))!;
      expect(after.expiryDate.isAfter(_gifticon().expiryDate), isTrue,
          reason: '연장은 만료일을 뒤로만 옮긴다');
      // 화면도 새 값을 따라간다 — 더 이상 만료가 아니므로 버튼이 사라진다.
      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('저장된 expired는 available로 되살아난다', (WidgetTester tester) async {
      final Gifticon stored = _gifticon(status: GifticonStatus.expired);
      boot(<Gifticon>[stored]);
      await mountDetail(tester, stored);

      await tapExtendAndConfirm(tester);

      expect(
          (await repo.getGifticonById('g1'))!.status, GifticonStatus.available);
    });

    testWidgets('날짜 선택을 취소하면 아무것도 바뀌지 않는다', (WidgetTester tester) async {
      boot(<Gifticon>[_gifticon()]);
      await mountDetail(tester, _gifticon());

      await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      await tester.pumpAndSettle();

      expect((await repo.getGifticonById('g1'))!.expiryDate,
          _gifticon().expiryDate);
      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsOneWidget);
    });
  });

  testWidgets('날짜 선택기가 열려 있는 사이 공유되면 개인 경로로 새지 않는다',
      (WidgetTester tester) async {
    // 판정을 빌드 시점에 클로저로 잡아 두면, 모달이 열려 있는 동안(몇 초~몇 분) 다른
    // 기기가 그룹에 공유해도 그대로 개인 경로를 부른다 — 그러면 그룹 스냅샷만 옛 날짜로
    // 남고 **어느 화면에도 보이지 않는 어긋남**이 된다. fail-closed 가드가 이 창에서만
    // fail-open 하던 것을 잡는다(에이전트 리뷰 검출).
    boot(<Gifticon>[_gifticon()]);
    await mountDetail(tester, _gifticon());

    await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // 선택기가 열린 사이 공유됐다.
    final SharedGifticon nowShared = SharedGifticon(
      id: 'shared-1',
      groupId: 'g_family',
      gifticonId: 'g1',
      sharedByUserId: _ownerId,
      brand: '스타벅스',
      productName: '아메리카노 T',
      expiryDate: _gifticon().expiryDate,
      status: ShareStatus.available,
    );
    container.updateOverrides(<Override>[
      nowProvider.overrideWithValue(_now),
      gifticonRepositoryProvider.overrideWithValue(repo),
      rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
      sessionUserProvider.overrideWith((_) => Stream<User?>.value(_me)),
      sharedGifticonIdsProvider.overrideWithValue(
          const AsyncValue<Set<String>>.data(<String>{'g1'})),
      allSharedProvider.overrideWithValue(<SharedGifticon>[nowShared]),
    ]);
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '연장'));
    await tester.pumpAndSettle();

    // 공유 경로를 탔다는 증거: 개인 저장소의 원본은 건드려지지 않았다. (이 컨테이너의
    // ShareRepository는 그 항목을 모르므로 계약 가드가 거부하고 화면이 안내한다.)
    expect(
        (await repo.getGifticonById('g1'))!.expiryDate, _gifticon().expiryDate,
        reason: '공유 중인 기프티콘을 개인 경로로 연장하면 안 된다');
  });

  testWidgets('공유 중이면 스냅샷과 원본이 함께 옮겨진다 — 계약 구현을 실제로 태운다',
      (WidgetTester tester) async {
    // 이 테스트가 이 화면의 존재 이유를 지킨다. 개인 경로를 부르면 원본만 옮겨지고
    // 그룹 화면은 옛 만료일을 계속 보여준다 — 어느 화면에도 안 보이는 어긋남이다.
    final InMemoryAuthRepository auth = InMemoryAuthRepository();
    final InMemoryGifticonRepository gifticons = InMemoryGifticonRepository();
    final InMemoryShareRepository share = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
    addTearDown(() {
      share.dispose();
      auth.dispose();
      gifticons.dispose();
    });

    final String myId = InMemoryAuthRepository.defaultUser.id;
    final Gifticon mine = Gifticon(
      id: 'gift-A',
      ownerId: myId,
      brand: '스타벅스',
      productName: '아메리카노 T',
      category: '카페',
      price: 4500,
      barcode: '9788901234567',
      expiryDate: _now.subtract(const Duration(days: 3)),
      registeredAt: _now.subtract(const Duration(days: 60)),
    );
    await gifticons.addGifticon(mine);
    final SharedGifticon shared =
        await share.shareGifticon(groupId: 'g_family', gifticon: mine);

    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        nowProvider.overrideWithValue(_now),
        authRepositoryProvider.overrideWithValue(auth),
        gifticonRepositoryProvider.overrideWithValue(gifticons),
        shareRepositoryProvider.overrideWithValue(share),
        rawGifticonsProvider
            .overrideWith((_) => gifticons.watchGifticons(myId)),
      ],
    );
    addTearDown(c.dispose);

    await mountDetail(tester, mine, c: c);
    // 판정 근거가 주입이 아니라 **계약 구현**임을 먼저 확인한다.
    expect(c.read(sharedGifticonIdsProvider).valueOrNull, contains('gift-A'));

    await tapExtendAndConfirm(tester);

    final Gifticon origin = (await gifticons.getGifticonById('gift-A'))!;
    final SharedGifticon? snapshot =
        (await share.getSharedGifticons('g_family'))
            .where((SharedGifticon s) => s.id == shared.id)
            .firstOrNull;
    expect(origin.expiryDate.isAfter(mine.expiryDate), isTrue);
    expect(snapshot, isNotNull);
    expect(snapshot!.expiryDate, origin.expiryDate,
        reason: '그룹 스냅샷과 원본이 같은 만료일을 가리켜야 한다');
  });
}
