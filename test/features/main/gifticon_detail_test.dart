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
import 'package:keepcon/shared/providers/shared_gifticons_provider.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

const String _ownerId = 'user-1';
final DateTime _now = DateTime(2026, 8, 18);

Gifticon _gifticon({
  String id = 'g1',
  String productName = '아메리카노 T',
  String? barcode = '9788901234567',
  GifticonStatus status = GifticonStatus.available,
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
  );
}

void main() {
  late InMemoryGifticonRepository repo;
  late ProviderContainer container;

  /// 저장소 하나를 목록 스트림과 provider 양쪽에 물린다 — 상세에서 상태를 바꾸면
  /// 목록도 같은 인스턴스를 보고 있어야 화면이 따라간다(계약 SSOT provider 규약).
  ///
  /// [sharedIds]로 "이 기프티콘이 그룹에 공유돼 있는가"를 주입한다. 기본값은 확정된 빈
  /// 집합 — 공유된 것이 없다. `null`을 주면 **아직 확정 전(로딩)** 을 흉내 낸다.
  void boot(
    List<Gifticon> seed, {
    Set<String>? sharedIds = const <String>{},
    bool sharedIdsFailed = false,
  }) {
    repo = InMemoryGifticonRepository(seed: seed);
    final AsyncValue<Set<String>> sharedState = sharedIdsFailed
        ? const AsyncValue<Set<String>>.error('boom', StackTrace.empty)
        : sharedIds == null
            ? const AsyncValue<Set<String>>.loading()
            : AsyncValue<Set<String>>.data(sharedIds);
    container = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider.overrideWithValue(repo),
        rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
        sharedGifticonIdsProvider.overrideWithValue(sharedState),
      ],
    );
    // 정리는 **여기서** 등록한다(전역 `tearDown` 금지). 이 파일에는 boot()을 쓰지 않고
    // 자기 컨테이너를 직접 만드는 테스트가 있는데, 전역 tearDown에 두면 그 테스트가
    // 초기화되지 않은 `late` 변수를 건드린다 — 단독 실행하면 LateInitializationError로
    // 죽고, 전체 스위트에서는 앞 테스트가 채워 둔 값 덕에 **가려진다**(이미 dispose된
    // 객체를 한 번 더 닫는데 둘 다 멱등이라 조용히 통과). CodeRabbit 리뷰에서 검출.
    addTearDown(() {
      container.dispose();
      repo.dispose();
    });
  }

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
    // 번호는 `drawText`(캔버스 그리기)가 아니라 별도 [Text] 위젯이 그린다 —
    // 스크린리더가 읽고 복사도 되어야 하기 때문이다. 이 단언이 그 위젯을 고정한다.
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
    // 공유 여부의 근거는 [SharedGifticon.gifticonId] 집합이다.
    final Gifticon shared = _gifticon();
    boot(<Gifticon>[shared], sharedIds: <String>{'g1'});
    await mountDetail(tester, shared);

    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsNothing);
    expect(
      find.text('그룹에 공유 중이에요. 사용 완료 처리는 공유 탭에서 해주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('공유 여부가 확정되기 전에는 버튼을 열지 않는다(fail-closed)',
      (WidgetTester tester) async {
    // 회귀 방어: 로딩을 "공유 안 됨"으로 접으면 그룹 목록이 도착하기 전 몇 프레임 동안
    // 버튼이 열린다. 그 창에서 누르면 원본만 used가 되고 그룹 항목은 '사용 가능'으로
    // 남아, 다른 멤버가 이미 쓴 기프티콘을 매장에서 꺼내게 된다.
    final Gifticon g = _gifticon();
    boot(<Gifticon>[g], sharedIds: null);
    await mountDetail(tester, g);

    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsNothing);
    expect(find.text('공유 상태를 확인하는 중이에요…'), findsOneWidget);
    // 로딩은 곧 풀리므로 재시도 버튼을 주지 않는다(에러일 때만 준다).
    expect(find.widgetWithText(TextButton, '다시 시도'), findsNothing);
  });

  testWidgets('공유 상태 조회가 실패하면 되살릴 버튼을 준다', (WidgetTester tester) async {
    // 회귀 방어: fail-closed로 막아 놓고 재시도 경로를 주지 않으면, 콜드 스타트에서 한 번
    // 실패한 에러가 캐시된 채 남아(StreamProvider는 스스로 재구독하지 않고
    // sharedGifticonsProvider는 non-autoDispose) **앱을 껐다 켜기 전까지** 모든 기프티콘의
    // 사용 완료가 영구히 막힌다. 상세를 나갔다 들어와도 풀리지 않는다.
    final Gifticon g = _gifticon();
    boot(<Gifticon>[g], sharedIdsFailed: true);
    await mountDetail(tester, g);

    expect(find.widgetWithText(ElevatedButton, '사용 완료'), findsNothing);
    expect(find.text('공유 상태를 확인하지 못해 사용 완료를 잠시 막아 뒀어요.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '다시 시도'), findsOneWidget);
  });

  testWidgets('실제 공유(ShareRepository.shareGifticon) 후 버튼이 닫힌다',
      (WidgetTester tester) async {
    // 위 테스트들은 집합을 주입하지만, 이 테스트는 **계약 구현을 실제로 태워** 판정
    // 근거가 맞는지 본다. 승격 전에는 `Gifticon.targetGroupId`로 판정했는데, 그 필드는
    // 등록 시점에 그룹을 지정한 경우에만 채워지고 `shareGifticon`은 건드리지 않아
    // — 즉 아래 시나리오에서 가드가 통째로 죽어 있었다(코드리뷰 검출).
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
      expiryDate: _now.add(const Duration(days: 30)),
      registeredAt: _now,
    );
    await gifticons.addGifticon(mine);
    // 등록은 개인 지갑으로 했고(targetGroupId 없음), 나중에 그룹에 공유한다 —
    // 이것이 흔한 경로다.
    await share.shareGifticon(groupId: 'g_family', gifticon: mine);

    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(auth),
        gifticonRepositoryProvider.overrideWithValue(gifticons),
        shareRepositoryProvider.overrideWithValue(share),
        rawGifticonsProvider
            .overrideWith((_) => gifticons.watchGifticons(myId)),
      ],
    );
    addTearDown(c.dispose);

    useTallViewport(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(home: GifticonDetailPage(gifticon: mine)),
      ),
    );
    await tester.pumpAndSettle();

    expect(c.read(sharedGifticonIdsProvider).valueOrNull, contains('gift-A'));
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

  testWidgets('통신 실패로 전이가 실패하면 그 사실을 알린다', (WidgetTester tester) async {
    // 회귀 방어: `on StateError`만 잡던 시절엔 통신 실패가 통째로 삼켜졌다. 호출부가
    // `onPressed: () => _confirm…()`이라 반환 Future가 버려져 unhandled async error가
    // 되고 **화면에는 아무 일도 일어나지 않는다** — 사용자는 버튼이 먹통이라 여겨
    // 여러 번 누르거나, 반대로 됐으려니 하고 매장을 나선다.
    //
    // `updateStatus`는 Firestore `runTransaction`을 쓰는데 트랜잭션은 오프라인 큐잉이
    // 안 되므로, 망이 끊기면 StateError가 아닌 FirebaseException으로 떨어진다.
    boot(<Gifticon>[_gifticon()]);
    final ProviderContainer failing = ProviderContainer(
      overrides: <Override>[
        gifticonRepositoryProvider
            .overrideWithValue(_FailingUpdateRepo(repo, Exception('오프라인'))),
        rawGifticonsProvider.overrideWith((_) => repo.watchGifticons(_ownerId)),
      ],
    );
    addTearDown(failing.dispose);

    useTallViewport(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: failing,
        child: MaterialApp(home: GifticonDetailPage(gifticon: _gifticon())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '사용 완료'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '사용 완료'));
    await tester.pumpAndSettle();

    expect(find.textContaining('다시 시도해 주세요'), findsOneWidget,
        reason: '실패를 알리지 않으면 버튼이 먹통으로 읽힌다');
    // 성공 안내가 함께 뜨면 더 나쁘다 — 안 된 일을 됐다고 말하는 셈이다.
    expect(find.text('사용 완료로 변경했어요.'), findsNothing);
  });
}

/// `updateStatus`만 실패시키는 데코레이터. 나머지는 실제 저장소에 위임한다.
class _FailingUpdateRepo implements GifticonRepository {
  _FailingUpdateRepo(this._inner, this._error);

  final GifticonRepository _inner;
  final Object _error;

  @override
  Future<Gifticon> updateStatus(String id, GifticonStatus status) async =>
      throw _error;

  @override
  Future<Gifticon> addGifticon(Gifticon gifticon) =>
      _inner.addGifticon(gifticon);

  @override
  Future<List<Gifticon>> getGifticons(String ownerId) =>
      _inner.getGifticons(ownerId);

  @override
  Future<Gifticon?> getGifticonById(String id) => _inner.getGifticonById(id);

  @override
  Stream<List<Gifticon>> watchGifticons(String ownerId) =>
      _inner.watchGifticons(ownerId);
}
