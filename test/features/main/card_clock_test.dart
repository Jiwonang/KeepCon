/// 홈 목록 카드의 **D-day 뱃지가 시계 정본을 따르는지** 고정하는 테스트.
///
/// 이 테스트가 없으면 카드를 `StatelessWidget` + `DateTime.now()`로 되돌려도 전체 스위트가
/// 그대로 통과한다(뮤테이션으로 실측했다). 그러면 목록 필터·통계는 [nowProvider]의 "오늘"을
/// 보는데 카드만 실제 시계를 봐서, 앱을 켜 둔 채 날짜가 넘어가면 요약은 "만료 임박 0개"인데
/// 카드는 빨간 어긋남이 난다 — `now_provider.dart`가 승격 사유로 인용한 그 사고다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/providers/raw_gifticons_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

void main() {
  const User me =
      User(id: 'user-1', email: 'me@keepcon.test', displayName: '나');

  /// 만료가 2026-08-30인 기프티콘 하나만 있는 홈 화면.
  Future<void> pumpHome(WidgetTester tester, {required DateTime now}) async {
    final auth = InMemoryAuthRepository();
    final gifticons = InMemoryGifticonRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          shareRepositoryProvider.overrideWithValue(
            InMemoryShareRepository(
              authRepository: auth,
              gifticonRepository: gifticons,
              seed: false,
            ),
          ),
          sessionUserProvider.overrideWith((_) => Stream<User?>.value(me)),
          nowProvider.overrideWithValue(now),
          rawGifticonsProvider.overrideWith(
            (_) => Stream<List<Gifticon>>.value(<Gifticon>[
              Gifticon(
                id: 'g-1',
                ownerId: me.id,
                brand: '스타벅스',
                productName: '아메리카노 T',
                category: '카페',
                price: 4500,
                expiryDate: DateTime(2026, 8, 30),
                registeredAt: DateTime(2026, 8, 1),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('카드 D-day가 nowProvider의 "오늘"을 따른다', (WidgetTester tester) async {
    // 8/23 기준 만료 8/30 → D-7.
    await pumpHome(tester, now: DateTime(2026, 8, 23, 15));
    expect(find.text('D-7'), findsOneWidget,
        reason: '카드가 시계 정본을 보지 않으면 실제 오늘 기준으로 계산된다');
  });

  testWidgets('시계가 하루 넘어가면 카드도 따라 바뀐다', (WidgetTester tester) async {
    // 같은 기프티콘, 시계만 하루 뒤 → D-6이어야 한다. 카드가 `DateTime.now()`를 직접
    // 읽으면 두 케이스가 같은 값을 내므로 이 단언이 깨진다.
    await pumpHome(tester, now: DateTime(2026, 8, 24, 15));
    expect(find.text('D-6'), findsOneWidget);
    expect(find.text('D-7'), findsNothing);
  });

  testWidgets('시계 기준으로 이미 지났으면 만료로 표시한다', (WidgetTester tester) async {
    await pumpHome(tester, now: DateTime(2026, 9, 1, 15));
    expect(find.text('만료'), findsWidgets,
        reason: '실제 시계를 읽으면 아직 만료 전이라 D-day가 뜬다');
  });
}
