/// 홈 헤더 알림 벨의 **진입점**과 **뱃지 실연동**을 고정하는 테스트.
///
/// 이 벨은 오래 장식이었다 — `IconButton`이 아니라 `Icon`이라 탭이 감지되지 않았고,
/// 빨간 점은 provider가 아니라 하드코딩이라 안읽음이 0이어도 켜져 있었다. 공유 탭·
/// 마이페이지의 벨만 실연동으로 고쳐지면서 홈이 빠진 것이다. 고칠 때 함께 굳히지 않으면
/// 같은 형태로 되돌아가도 아무 테스트도 울리지 않는다.
///
/// 고정할 것은 셋이다:
/// 1. **탭이 알림 목록으로 간다** — 벨을 실제로 눌러 [GroupNotificationsPage]가 뜨는지 본다.
/// 2. **뱃지가 안읽음 정본을 따른다** — 0이면 뱃지 자체가 없고, 있으면 그 수가 보인다.
/// 3. **두 자리는 `9+`로 접힌다** — 공유 탭 벨과 같은 표기여야 한다(같은 위젯을 쓰므로
///    표기가 갈릴 수 없다는 것을 여기서 확인한다).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/features/share/pages/group_notifications_page.dart';
import 'package:keepcon/shared/providers/group_notifications_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

void main() {
  /// 홈 화면을 띄운다. 안읽음 수는 계약 정본을 직접 고정해 뱃지만 격리 검증한다
  /// (mypage 벨 테스트와 같은 이디엄).
  Future<void> pumpHome(WidgetTester tester, {int? unread}) async {
    final InMemoryAuthRepository auth = InMemoryAuthRepository();
    final InMemoryGifticonRepository gifticons = InMemoryGifticonRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(
            InMemoryShareRepository(
              authRepository: auth,
              gifticonRepository: gifticons,
            ),
          ),
          if (unread != null)
            unreadNotificationCountProvider.overrideWithValue(unread),
        ],
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 헤더의 알림 벨.
  Finder bell() => find.byTooltip('알림');

  testWidgets('벨을 누르면 알림 목록 화면으로 들어간다', (WidgetTester tester) async {
    await pumpHome(tester, unread: 0);

    expect(find.byType(GroupNotificationsPage), findsNothing);

    await tester.tap(bell());
    await tester.pumpAndSettle();

    expect(find.byType(GroupNotificationsPage), findsOneWidget,
        reason: '벨은 장식이 아니라 알림 센터 진입점이어야 한다');
  });

  testWidgets('안읽음이 0이면 뱃지를 그리지 않는다', (WidgetTester tester) async {
    await pumpHome(tester, unread: 0);

    expect(bell(), findsOneWidget);
    // 벨 안쪽으로 좁혀 본다 — 홈 통계 카드에도 '0'이 있어 화면 전체 검색은 무의미하다.
    expect(
        find.descendant(of: bell(), matching: find.byType(Text)), findsNothing,
        reason: '0건은 표시할 것이 없다는 뜻이다 — 빈 뱃지도 남기지 않는다');
  });

  testWidgets('안읽음 수가 뱃지에 그대로 보인다', (WidgetTester tester) async {
    await pumpHome(tester, unread: 3);

    expect(
        find.descendant(of: bell(), matching: find.text('3')), findsOneWidget);
  });

  testWidgets('두 자리 안읽음은 9+로 접는다', (WidgetTester tester) async {
    await pumpHome(tester, unread: 12);

    expect(
        find.descendant(of: bell(), matching: find.text('9+')), findsOneWidget);
    expect(find.text('12'), findsNothing, reason: '뱃지가 아이콘을 덮지 않게 접어야 한다');
  });
}
