/// 만료 알림 예약 배선 테스트.
///
/// 고정할 것은 셋이다:
/// 1. 기프티콘 목록이 바뀌면 예약이 갱신된다(스캔 추가·공유 동기화가 모두 이 경로로 온다).
/// 2. 로그아웃(위젯 폐기)하면 예약이 취소된다.
/// 3. **폐기 이후에는 대기열이 되살아나지 않는다** — 예약이 진행 중일 때 로그아웃하면
///    진행 중이던 작업이 끝나며 대기열로 재예약해, 이전 사용자의 기프티콘 이름이
///    알림에 뜰 수 있었다(CodeRabbit 리뷰 지적).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/app/expiry_notification_sync.dart';
import 'package:keepcon/features/main/state/gifticon_list_providers.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/notifications/expiry_notification_scheduler.dart';
import 'package:keepcon/shared/providers/notification_providers.dart';

/// 호출을 기록하고, 필요하면 [gate]로 예약을 붙잡아 두는 스케줄러 대역.
class _FakeScheduler implements ExpiryNotificationScheduler {
  /// [sync]에 넘어온 목록들(호출 순서대로).
  final List<List<Gifticon>> synced = <List<Gifticon>>[];

  /// [cancelAll] 호출 횟수.
  int cancelAllCalls = 0;

  /// 열려 있으면 [sync]가 완료되지 않고 대기한다(동시성 상황 재현용).
  Completer<void>? gate;

  @override
  Future<int> sync(List<Gifticon> gifticons) async {
    synced.add(gifticons);
    final Completer<void>? g = gate;
    if (g != null) await g.future;
    return gifticons.length;
  }

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  @override
  Future<NotificationPermissionStatus> currentPermission() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.granted;
}

Gifticon _g(String id) => Gifticon(
      id: id,
      ownerId: 'user-1',
      brand: '스타벅스',
      productName: '아메리카노 T',
      category: '카페',
      price: 4500,
      expiryDate: DateTime(2030, 1, 1),
      registeredAt: DateTime(2026, 1, 1),
      status: GifticonStatus.available,
    );

void main() {
  late StreamController<List<Gifticon>> lists;
  late _FakeScheduler scheduler;

  setUp(() {
    lists = StreamController<List<Gifticon>>.broadcast();
    scheduler = _FakeScheduler();
  });

  tearDown(() => lists.close());

  Future<void> mount(WidgetTester tester, {required Widget child}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          rawGifticonsProvider.overrideWith((_) => lists.stream),
          expiryNotificationSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: MaterialApp(home: child),
      ),
    );
  }

  testWidgets('목록이 바뀌면 예약을 갱신한다', (WidgetTester tester) async {
    await mount(tester, child: const ExpiryNotificationSync(child: SizedBox()));
    await tester.pump();

    lists.add(<Gifticon>[_g('a')]);
    await tester.pump();
    await tester.pump();

    expect(scheduler.synced, hasLength(1));
    expect(scheduler.synced.single.single.id, 'a');
  });

  testWidgets('로그아웃(폐기)하면 예약을 취소한다', (WidgetTester tester) async {
    await mount(tester, child: const ExpiryNotificationSync(child: SizedBox()));
    await tester.pump();

    // 위젯을 트리에서 걷어낸다 = AuthGate가 로그인 화면으로 바꾼 상황.
    await mount(tester, child: const SizedBox());
    await tester.pump();

    expect(scheduler.cancelAllCalls, 1);
  });

  testWidgets('폐기 뒤에는 대기열이 되살아나지 않는다', (WidgetTester tester) async {
    scheduler.gate = Completer<void>();

    await mount(tester, child: const ExpiryNotificationSync(child: SizedBox()));
    await tester.pump();

    // 첫 목록 → 예약 시작(gate에 걸려 완료되지 않는다).
    lists.add(<Gifticon>[_g('first')]);
    await tester.pump();
    await tester.pump();
    expect(scheduler.synced, hasLength(1));

    // 두 번째 목록 → 진행 중이므로 대기열에 쌓인다.
    lists.add(<Gifticon>[_g('second')]);
    await tester.pump();
    await tester.pump();
    expect(scheduler.synced, hasLength(1), reason: '아직 대기열에만 있어야 한다');

    // 로그아웃.
    await mount(tester, child: const SizedBox());
    await tester.pump();

    // 진행 중이던 예약이 이제 끝난다 — 여기서 대기열이 되살아나면 안 된다.
    scheduler.gate!.complete();
    await tester.pump();
    await tester.pump();

    expect(
      scheduler.synced,
      hasLength(1),
      reason: '폐기 이후 이전 사용자의 목록이 다시 예약되면 안 된다',
    );
    expect(scheduler.cancelAllCalls, 1);
  });
}
