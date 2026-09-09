/// share 페이지 — 공유 기프티콘 상세의 "기프티콘 기간 연장하기" 테스트.
///
/// 고정하려는 것은 둘이다:
///  ① **노출 조건** — 공유자 본인이고, 만료됐고, 사용 완료가 아닐 때만. 요구사항이
///     "최초 등록한 사람만 연장"이고, 공유자와 등록자가 갈리지 않는 근거는 보안 규칙에
///     있다(공유 문서 생성은 원본 소유를 요구한다). 화면의 이 조건은 UX 필터이고 실제
///     방어선은 규칙·계약 가드지만, 조건이 무너지면 **누를 때마다 반드시 실패하는 버튼**이
///     남는다.
///  ② **양쪽 동기화** — 그룹에서 연장하면 그룹 스냅샷과 **원본**이 함께 옮겨진다. 계약
///     구현을 실제로 태워 확인한다. 스냅샷만 옮기면 공유자의 개인 목록은 옛 만료일을
///     계속 보여주고, 그 어긋남은 어느 화면에도 보이지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/shared_gifticon_detail_page.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

const String _buttonLabel = '기프티콘 기간 연장하기';

void main() {
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;
  late InMemoryShareRepository share;
  late String me;

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    share = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
    );
    me = InMemoryAuthRepository.defaultUser.id;
    addTearDown(() {
      share.dispose();
      auth.dispose();
      gifticons.dispose();
    });
  });

  Gifticon mine({
    String id = 'gx-1',
    DateTime? expiry,
    GifticonStatus status = GifticonStatus.available,
  }) =>
      Gifticon(
        id: id,
        ownerId: me,
        brand: '메가커피',
        productName: '아이스 아메리카노',
        price: 3000,
        category: '카페',
        barcode: '9788901234567',
        // 기본은 **이미 지난 날짜** — 이 화면의 연장 경로가 겨냥하는 상태다.
        // 고정 과거 날짜라 시계와 무관하게 만료로 판정된다.
        expiryDate: expiry ?? DateTime(2020, 1, 1),
        registeredAt: DateTime(2019, 1, 1),
        status: status,
      );

  /// 내 만료된 기프티콘 하나를 새 그룹에 공유하고 상세를 띄울 준비를 한다.
  Future<(SharedGifticon, Gifticon)> shareMineExpired(
      {DateTime? expiry}) async {
    final Group g = await share.createGroup(name: '가족', emoji: '🏠');
    final Gifticon origin = mine(expiry: expiry);
    await gifticons.addGifticon(origin);
    final SharedGifticon item =
        await share.shareGifticon(groupId: g.id, gifticon: origin);
    return (item, origin);
  }

  /// 기본 뷰포트는 상세 화면보다 짧아 하단 버튼이 [ListView] 지연 생성에 걸린다.
  Future<void> mount(WidgetTester tester, String itemId,
      {DateTime? now}) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(share),
          if (now != null) nowProvider.overrideWithValue(now),
        ],
        child: MaterialApp(home: SharedGifticonDetailPage(itemId: itemId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 날짜 선택기를 열고 **초기 선택값 그대로** 확정한다(초기값 = 화면이 계산한 하한).
  Future<void> tapExtendAndConfirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '연장'));
    await tester.pumpAndSettle();
  }

  group('노출 조건', () {
    testWidgets('내가 공유한 만료 항목에는 버튼이 뜬다', (WidgetTester tester) async {
      final (SharedGifticon item, _) = await shareMineExpired();
      await mount(tester, item.id);

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsOneWidget);
    });

    testWidgets('남이 공유한 항목에는 버튼이 없다 — 등록자만 연장한다', (WidgetTester tester) async {
      // 시드의 `s_1`은 u_mom이 공유했고 사용 가능·잠김 없음이다. 시계를 만료 뒤로
      // 옮기면 **공유자 여부만** 다른 조건이 되어, 그 하나가 버튼을 막는지 고립해서 본다.
      await mount(tester, 's_1', now: DateTime(2026, 10, 15));

      expect(find.text('스타벅스'), findsWidgets, reason: '항목을 실제로 그렸는지 먼저 확인');
      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('아직 만료되지 않았으면 버튼이 없다', (WidgetTester tester) async {
      final (SharedGifticon item, _) =
          await shareMineExpired(expiry: DateTime(2030, 1, 1));
      await mount(tester, item.id);

      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });

    testWidgets('이미 사용 완료된 항목에는 버튼이 없다', (WidgetTester tester) async {
      final (SharedGifticon item, _) = await shareMineExpired();
      await share.markUsed(item.id);
      await mount(tester, item.id);

      expect(find.text('이미 사용 완료된 기프티콘이에요.'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
    });
  });

  testWidgets('연장하면 그룹 스냅샷과 원본이 함께 옮겨진다', (WidgetTester tester) async {
    // 이 화면의 존재 이유. 스냅샷만 옮기면 공유자의 개인 목록은 옛 만료일을 계속
    // 보여주고, 그 어긋남은 어느 화면에도 보이지 않는다.
    final (SharedGifticon item, Gifticon origin) = await shareMineExpired();
    await mount(tester, item.id);

    await tapExtendAndConfirm(tester);

    final SharedGifticon after = (await share.getSharedGifticons(item.groupId))
        .firstWhere((SharedGifticon s) => s.id == item.id);
    final Gifticon? updatedOrigin = await gifticons.getGifticonById(origin.id);
    expect(after.expiryDate.isAfter(origin.expiryDate), isTrue);
    expect(updatedOrigin!.expiryDate, after.expiryDate,
        reason: '그룹 스냅샷과 원본이 같은 만료일을 가리켜야 한다');
    // 연장했으므로 더 이상 만료가 아니다 — 버튼이 사라진다.
    expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsNothing);
  });

  testWidgets('연장하면 그룹 알림이 남는다', (WidgetTester tester) async {
    // 만료돼서 못 쓰겠다고 판단했던 멤버가 다시 쓸 수 있게 된 것을 알 유일한 경로다.
    final (SharedGifticon item, _) = await shareMineExpired();
    await mount(tester, item.id);

    await tapExtendAndConfirm(tester);

    final List<GroupNotification> notis = await share.getNotifications(me);
    expect(
      notis.where((GroupNotification n) =>
          n.type == GroupNotificationType.expiryExtended),
      isNotEmpty,
    );
  });

  testWidgets('날짜 선택을 취소하면 아무것도 바뀌지 않는다', (WidgetTester tester) async {
    final (SharedGifticon item, Gifticon origin) = await shareMineExpired();
    await mount(tester, item.id);

    await tester.tap(find.widgetWithText(ElevatedButton, _buttonLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    final SharedGifticon after = (await share.getSharedGifticons(item.groupId))
        .firstWhere((SharedGifticon s) => s.id == item.id);
    expect(after.expiryDate, item.expiryDate);
    expect((await gifticons.getGifticonById(origin.id))!.expiryDate,
        origin.expiryDate);
    expect(find.widgetWithText(ElevatedButton, _buttonLabel), findsOneWidget);
  });
}
