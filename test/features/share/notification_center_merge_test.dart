/// 알림 센터가 **그룹 알림 + 개인 만료 알림**을 한 목록으로 보여주는지 고정하는 테스트.
///
/// 개인 만료 알림은 저장된 기록이 아니라 내 기프티콘에서 계산해 복원한 것이라, 두 축이
/// 조용히 어긋나기 쉽다 — 병합이 빠지면 목록에는 그룹 알림만 뜨고 뱃지 숫자만 맞거나,
/// 반대로 숫자만 늘고 목록에는 안 보인다. 어느 쪽도 화면을 봐서는 알기 어렵다.
///
/// 고정할 것은 넷이다:
/// 1. 두 축이 **한 목록**에 최신순으로 섞인다.
/// 2. 안읽음 수가 **합산**된다(벨 3곳이 같은 수를 본다).
/// 3. 개인 항목을 탭하면 **목적지 버스**에 실린다(딥링크·푸시와 같은 통로).
/// 4. 그룹 알림 축이 에러면 배너가 뜬다 — 파생 축이 값을 냈다고 실패를 감추지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/pages/notification_center_page.dart';
import 'package:keepcon/shared/deeplink/app_destination.dart';
import 'package:keepcon/shared/models/app_notification.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/deep_link_providers.dart';
import 'package:keepcon/shared/providers/group_notifications_provider.dart';
import 'package:keepcon/shared/providers/raw_gifticons_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';

/// D-3 알림이 오늘 오전에 이미 울린 기프티콘(만료 3일 뒤).
Gifticon _expiringSoon() => Gifticon(
      id: 'g-1',
      ownerId: 'user-1',
      brand: '투썸',
      productName: '케이크',
      category: '카페',
      price: 25000,
      expiryDate: DateTime.now().add(const Duration(days: 3)),
      registeredAt: DateTime.now().subtract(const Duration(days: 30)),
    );

GroupNotification _groupNotif({required DateTime at}) => GroupNotification(
      id: 'n-1',
      groupId: 'grp-1',
      type: GroupNotificationType.registered,
      title: '새 기프티콘',
      message: '가족 그룹에 등록됐어요',
      createdAt: at,
    );

void main() {
  /// 두 축을 직접 고정해 병합만 격리 검증한다(저장소 시드에 의존하지 않는다).
  ProviderContainer makeContainer({
    List<GroupNotification> group = const <GroupNotification>[],
    List<Gifticon> gifticons = const <Gifticon>[],
    DateTime? readAt,
  }) {
    final container = ProviderContainer(
      overrides: <Override>[
        notificationsProvider.overrideWithValue(AsyncData(group)),
        rawGifticonsProvider.overrideWith(
          (_) => Stream<List<Gifticon>>.value(gifticons),
        ),
        notificationsReadAtProvider.overrideWithValue(readAt),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('두 축이 한 목록에 최신순으로 섞인다', () async {
    final container = makeContainer(
      group: <GroupNotification>[
        _groupNotif(at: DateTime.now().subtract(const Duration(minutes: 1))),
      ],
      gifticons: <Gifticon>[_expiringSoon()],
    );
    // 원천 목록 스트림이 첫 값을 낼 때까지 흘려보낸다.
    container.listen(rawGifticonsProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    final List<AppNotification> items =
        container.read(allNotificationsProvider).valueOrNull ??
            const <AppNotification>[];

    expect(items.whereType<GroupNotificationItem>(), hasLength(1));
    expect(items.whereType<ExpiryNotificationItem>(), isNotEmpty,
        reason: '개인 만료 알림이 목록에 없으면 병합이 빠진 것이다');
    // 방금 만든 그룹 알림이 오전 9시 발송분보다 최신이다.
    expect(items.first, isA<GroupNotificationItem>());
    for (int i = 1; i < items.length; i++) {
      expect(items[i - 1].createdAt.isBefore(items[i].createdAt), isFalse,
          reason: '최신순이 아니면 목록이 뒤섞여 보인다');
    }
  });

  test('안읽음 수가 두 축 합산이다', () async {
    final container = makeContainer(
      group: <GroupNotification>[_groupNotif(at: DateTime.now())],
      gifticons: <Gifticon>[_expiringSoon()],
      readAt: null, // 한 번도 안 읽음 = 전부 안읽음.
    );
    container.listen(rawGifticonsProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    final int total = (container.read(allNotificationsProvider).valueOrNull ??
            <AppNotification>[])
        .length;
    expect(container.read(unreadNotificationCountProvider), total,
        reason: '벨 숫자가 목록 길이와 다르면 어느 한쪽이 축을 빠뜨린 것이다');
    expect(total, greaterThan(1), reason: '두 축이 모두 들어 있어야 합산을 검증할 수 있다');
  });

  test('읽음 시각 이후 것만 안읽음으로 센다 — 파생 항목도 같은 타임스탬프를 따른다', () async {
    final container = makeContainer(
      gifticons: <Gifticon>[_expiringSoon()],
      // 지금 읽었으면 과거에 울린 만료 알림은 전부 읽음이다.
      readAt: DateTime.now(),
    );
    container.listen(rawGifticonsProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);

    expect(container.read(allNotificationsProvider).valueOrNull, isNotEmpty);
    expect(container.read(unreadNotificationCountProvider), 0,
        reason: '파생 항목에 별도 읽음 저장소가 없어도 같은 타임스탬프로 갈려야 한다');
  });

  test('그룹 알림 축의 에러는 파생 축이 값을 내도 감춰지지 않는다', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        notificationsProvider.overrideWithValue(
          AsyncError<List<GroupNotification>>(
              StateError('boom'), StackTrace.empty),
        ),
        rawGifticonsProvider.overrideWith(
          (_) => Stream<List<Gifticon>>.value(<Gifticon>[_expiringSoon()]),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(allNotificationsProvider).hasError, isTrue,
        reason: '일부만 빠진 목록이 정상처럼 보이면 사용자가 실패를 모른다');
  });

  testWidgets('개인 알림을 탭하면 목적지 버스에 실리고 화면이 닫힌다', (WidgetTester tester) async {
    final auth = InMemoryAuthRepository();
    final gifticons =
        InMemoryGifticonRepository(seed: <Gifticon>[_expiringSoon()]);
    late ProviderContainer container;

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
        ],
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: NotificationCenterPage());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 개인 만료 알림 카드(예약 문구와 같은 제목)를 찾아 누른다.
    final Finder card = find.textContaining('만료되는 기프티콘이 있어요');
    expect(card, findsWidgets, reason: '개인 만료 알림이 목록에 떠야 한다');

    await tester.tap(card.first);
    await tester.pumpAndSettle();

    final AppDestination? destination =
        container.read(pendingDestinationProvider);
    expect(destination, isA<GifticonHighlightDestination>(),
        reason: '딥링크·푸시와 같은 통로로 보내야 경로마다 동작이 갈리지 않는다');
    expect((destination! as GifticonHighlightDestination).gifticonId, 'g-1');
  });
}
