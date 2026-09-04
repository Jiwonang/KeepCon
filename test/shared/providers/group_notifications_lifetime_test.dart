/// 알림 정본 내부 family(`_notificationsByUserProvider`·`_notifReadAtByUserProvider`)의
/// **수명 규약(autoDispose)** 회귀 테스트.
///
/// ## 고정하는 결함
/// 두 family가 keepAlive였을 때: 로그아웃 순간 인증을 잃은 백엔드 리스너는
/// permission-denied로 **종료**되는데, keepAlive는 그 에러를 앱 수명 동안 캐시하고
/// 재구독하지 않는다. 같은 계정으로 재로그인해도 세 화면(공유 탭 헤더·마이페이지·홈
/// 헤더)의 알림 벨·알림 센터가 에러에 박제되고, 읽음 시각 축은 `valueOrNull` 폴딩이
/// 영구히 null이 되어 **전부 안읽음** 과대 표시가 앱 수명 동안 남았다.
///
/// ## 고정하는 규약
/// 두 family는 autoDispose다 — 로그아웃(세션 폴딩·uid select의 재계산)이 family를
/// 놓으면 구독이 해제되고, 재로그인은 **새 인스턴스**로 새로 구독한다.
/// `_groupsByUserProvider`(`my_groups_provider.dart`)와 같은 수명 규약이며, 계측 방식
/// (구독 수 세기)은 `my_groups_provider_test.dart`의 이디엄을 따른다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/group_notifications_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// `watchNotifications`·`watchNotificationsReadAt`의 **호출 수·활성 구독 수**를 세는
/// 테스트용 [ShareRepository]. 마지막 컨트롤러를 노출해 "로그아웃으로 리스너가
/// permission-denied로 죽는" 순간을 `addError`로 재현한다.
class _CountingShareRepository implements ShareRepository {
  _CountingShareRepository({
    this.notifications = const <GroupNotification>[],
    this.readAt,
  });

  /// 알림 구독 시 방출할 값.
  final List<GroupNotification> notifications;

  /// 읽음 시각 구독 시 방출할 값.
  final DateTime? readAt;

  int notifCalls = 0;
  int activeNotifListens = 0;
  StreamController<List<GroupNotification>>? lastNotifController;

  int readAtCalls = 0;
  int activeReadAtListens = 0;
  StreamController<DateTime?>? lastReadAtController;

  @override
  Stream<List<GroupNotification>> watchNotifications(String userId) {
    notifCalls++;
    late final StreamController<List<GroupNotification>> controller;
    controller = StreamController<List<GroupNotification>>(
      onListen: () {
        activeNotifListens++;
        controller.add(notifications);
      },
      onCancel: () {
        activeNotifListens--;
      },
    );
    lastNotifController = controller;
    return controller.stream;
  }

  @override
  Stream<DateTime?> watchNotificationsReadAt(String userId) {
    readAtCalls++;
    late final StreamController<DateTime?> controller;
    controller = StreamController<DateTime?>(
      onListen: () {
        activeReadAtListens++;
        controller.add(readAt);
      },
      onCancel: () {
        activeReadAtListens--;
      },
    );
    lastReadAtController = controller;
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 알림 watch 2종만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

void main() {
  GroupNotification notifFixture(String id) {
    return GroupNotification(
      id: id,
      groupId: 'g1',
      type: GroupNotificationType.registered,
      title: '새 기프티콘',
      message: '아메리카노가 공유됐어요.',
      createdAt: DateTime.utc(2026, 9, 1),
    );
  }

  /// 스트림 방출·autoDispose 해제가 반영될 때까지 이벤트 큐를 비운다.
  Future<void> settle() => pumpEventQueue();

  ProviderContainer makeContainer(
    _CountingShareRepository repo,
    InMemoryAuthRepository auth,
  ) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        shareRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> relogin(InMemoryAuthRepository auth) => auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );

  group('notificationsProvider 체인 수명 (알림 목록)', () {
    test('로그아웃이 구독을 해제하고, 같은 계정 재로그인이 새로 구독한다', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        notifications: <GroupNotification>[notifFixture('n1')],
      );
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final ProviderContainer container = makeContainer(repo, auth);

      // 알림 벨(세 화면)이 keepAlive 파생(notificationsProvider)을 구독한다.
      container.listen<AsyncValue<List<GroupNotification>>>(
        notificationsProvider,
        (_, __) {},
      );
      await settle();
      expect(repo.notifCalls, 1);

      // 로그아웃 직전 리스너가 죽고(permission-denied), 이어서 세션이 풀린다 — 실제 순서.
      repo.lastNotifController!.addError(StateError('permission-denied'));
      await settle();
      // 양성 대조: 죽은 에러가 실제로 캐시된 **뒤에** 로그아웃해야 한다 — 이 단언이
      // 없으면 세션 null이 먼저 전달돼 에러가 버려진 채로도 통과하는 공허한 테스트가 된다.
      expect(container.read(notificationsProvider).hasError, isTrue);
      await auth.signOut();
      await settle();
      expect(
        repo.activeNotifListens,
        0,
        reason: '세션이 풀리면 폴딩이 family를 놓아 autoDispose가 구독을 닫는다',
      );
      expect(
        container.read(notificationsProvider),
        const AsyncData<List<GroupNotification>>(<GroupNotification>[]),
        reason: '미로그인 확정은 빈 목록 폴딩',
      );

      // 같은 계정으로 재로그인 — family는 새 인스턴스라 새로 구독한다.
      // (회귀: keepAlive면 같은 userId 인스턴스가 박제된 에러를 그대로 돌려줬다.)
      await relogin(auth);
      await settle();
      expect(repo.notifCalls, 2, reason: '재로그인은 백엔드를 새로 구독해야 한다');
      final AsyncValue<List<GroupNotification>> revived =
          container.read(notificationsProvider);
      expect(revived.hasError, isFalse, reason: '이전 세션의 죽은 에러가 남으면 안 된다');
      expect(
        revived.valueOrNull?.map((GroupNotification n) => n.id),
        <String>['n1'],
        reason: '재로그인 뒤에는 그 사이 도착한 알림이 보여야 한다',
      );
    });
  });

  group('notificationsReadAtProvider 체인 수명 (안읽음 판정 축)', () {
    test('로그아웃이 구독을 해제하고, 재로그인이 새로 구독해 읽음 시각을 되찾는다', () async {
      final DateTime lastRead = DateTime.utc(2026, 9, 2);
      final _CountingShareRepository repo =
          _CountingShareRepository(readAt: lastRead);
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final ProviderContainer container = makeContainer(repo, auth);

      container.listen<DateTime?>(notificationsReadAtProvider, (_, __) {});
      await settle();
      expect(repo.readAtCalls, 1);
      expect(container.read(notificationsReadAtProvider), lastRead);

      // 로그아웃 직전 리스너가 죽는다 — keepAlive면 이 에러가 박제되어 재로그인 후에도
      // 폴딩이 영구 null(전부 안읽음 과대 표시)이었다. addError를 로그아웃보다 먼저
      // **settle까지 마쳐** 죽은 에러가 살아 있는 인스턴스에 전달된 것을 보장한다
      // (폴딩은 copyWithPrevious 보존 값을 돌려줘 에러를 밖에서 관측할 수 없으므로,
      // 이 케이스의 실질 회귀 고정은 아래 readAtCalls 재구독 단언이다).
      repo.lastReadAtController!.addError(StateError('permission-denied'));
      await settle();
      await auth.signOut();
      await settle();
      expect(
        repo.activeReadAtListens,
        0,
        reason: 'uid select가 null로 재계산되며 family를 놓아 autoDispose가 구독을 닫는다',
      );
      expect(container.read(notificationsReadAtProvider), isNull,
          reason: '미로그인은 null 폴딩(전부 안읽음 보수 방향)');

      await relogin(auth);
      await settle();
      expect(repo.readAtCalls, 2, reason: '재로그인은 백엔드를 새로 구독해야 한다');
      expect(
        container.read(notificationsReadAtProvider),
        lastRead,
        reason: '새 구독이 읽음 시각을 되찾아야 안읽음 뱃지가 과대 표시되지 않는다',
      );
    });
  });
}
