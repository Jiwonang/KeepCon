/// 재시도 훅의 **exists 가드** 회귀 테스트 — "검사가 곧 낭비 구독이 되는" 것을 막는다.
///
/// ## 고정하는 규약
/// 훅들은 에러 여부를 보려고 원천을 `ref.read`하는데, `read`는 **살아 있지 않은
/// 인스턴스를 새로 만들어 실제 스트림을 구독한다**(autoDispose면 곧 버려질 구독이고,
/// keepAlive인 `rawGifticonsProvider`는 그 낭비 구독이 컨테이너 수명 동안 잔존한다).
/// 그래서 모든 검사용 read는 [WidgetRef.exists]로 가드한다 — 계약 훅
/// `MyGroupsRetry.retry`(`my_groups_provider.dart`)가 정본으로 세워 둔 규약이다.
///
/// ## 왜 이 파일이 필요한가 (커버리지 방향)
/// 기존 테스트(`share_error_ui_test.dart` 등)는 전부 **체인이 마운트된 화면**에서
/// 재시도를 누른다 — 거기서는 `exists`가 항상 true라 **가드를 통째로 지워도 green**이다
/// (실측: 가드를 `(true)`로 치환하면 720/720 통과). 즉 "가드가 과하게 막지 않는가"만
/// 검증되고 "가드가 실제로 막아야 할 때 막는가"는 아무도 보지 않았다.
///
/// ## 호스트가 셋인 이유 — 가드는 **중첩**돼 있다
/// 훅은 바깥에서 상위 축(세션·그룹 목록)을, 안쪽에서 사용자별 family 인스턴스를
/// 가드한다. 바깥이 먼저 `return`하므로 **아무것도 마운트하지 않은 호스트 하나로는
/// 안쪽 가드에 도달조차 못 한다** — 그 상태로는 안쪽 가드(현재 7개)를 지워도 전부
/// 통과한다(에이전트 리뷰가 안쪽만 뮤테이션해 실측). 그래서 도달 깊이가 다른 호스트를
/// 셋 둔다:
///
/// | 호스트 | watch하는 것 | 도달하는 가드 |
/// |---|---|---|
/// | [_RetryHost] | 없음 | 바깥 — `exists(session)`·`exists(rawGifticons)`·`exists(myGroups)` |
/// | [_SessionOnlyHost] | 세션 | 안쪽 — `exists(logs)`·`exists(mine)`(기프티콘)·`exists(mine)`(참여 요청)·`exists(notifs)`·`exists(readAt)`·`exists(groups)` |
/// | [_GroupsHost] | 세션 + 내 그룹 목록 | 안쪽 — `exists(perGroup)` |
///
/// 각 호스트는 자기가 마운트한 축이 **실제로 세어지는지**를 먼저 단언한다(계측 생존
/// 증거). 그 단언이 없으면 오버라이드가 끊겨 계측기가 아예 연결되지 않아도 "구독 0"이
/// 나와 전 케이스가 공허하게 통과한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/state/share_providers.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/group_notifications_provider.dart';
import 'package:keepcon/shared/providers/my_groups_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/providers/shared_gifticons_provider.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// 세션 스트림 **구독 횟수**를 세는 [AuthRepository](가드가 풀리면 여기가 먼저 늘어난다).
class _CountingAuthRepository implements AuthRepository {
  int watchCalls = 0;

  /// `noSuchMethod`로 흘러간 예상 밖 호출 — 아래 [_CountingShareRepository] 참조.
  final List<Symbol> unexpected = <Symbol>[];

  @override
  Stream<User?> watchCurrentUser() {
    watchCalls++;
    return Stream<User?>.value(InMemoryAuthRepository.defaultUser);
  }

  @override
  User? get currentUser => InMemoryAuthRepository.defaultUser;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add(invocation.memberName);
    throw UnimplementedError(
      '이 테스트는 watchCurrentUser만 사용한다 (호출됨: ${invocation.memberName})',
    );
  }
}

/// share 계약의 watch 스트림 **구독 횟수**를 축별로 세는 [ShareRepository].
class _CountingShareRepository implements ShareRepository {
  /// `watchGroups`가 방출할 목록(그룹 축까지 마운트하는 [_GroupsHost]용).
  List<Group> groups = const <Group>[];

  int groupCalls = 0;
  int usageCalls = 0;
  int notifCalls = 0;
  int readAtCalls = 0;
  int sharedCalls = 0;
  int myJoinCalls = 0;
  int pendingJoinCalls = 0;

  /// `noSuchMethod`로 흘러간 예상 밖 호출.
  ///
  /// **던지는 것만으로는 트립와이어가 되지 않는다** — 예외가 [StreamProvider]의 create
  /// 안에서 나면 Riverpod이 [AsyncError]로 삼켜 테스트는 초록으로 통과한다(실측). 그래서
  /// 호출을 기록해 두고 단언한다.
  final List<Symbol> unexpected = <Symbol>[];

  /// 계약의 watch 스트림 **7축 중 하나라도** 구독됐는지(가드가 풀렸다는 신호).
  ///
  /// 참여 요청 2축도 훅이 건드린다(`retryMyJoinRequests`·`retryPendingJoinRequests` —
  /// PR #164에서 도착). 세지 않으면 그 축을 가드 없이 구독해도 카운터가 0으로 남는다 —
  /// 이 파일이 막으려는 false green이다.
  int get totalCalls =>
      groupCalls +
      usageCalls +
      notifCalls +
      readAtCalls +
      sharedCalls +
      myJoinCalls +
      pendingJoinCalls;

  @override
  Stream<List<Group>> watchGroups(String userId) {
    groupCalls++;
    return Stream<List<Group>>.value(groups);
  }

  @override
  Stream<List<UsageLog>> watchUsageLogs(String userId) {
    usageCalls++;
    return Stream<List<UsageLog>>.value(const <UsageLog>[]);
  }

  @override
  Stream<List<GroupNotification>> watchNotifications(String userId) {
    notifCalls++;
    return Stream<List<GroupNotification>>.value(const <GroupNotification>[]);
  }

  @override
  Stream<DateTime?> watchNotificationsReadAt(String userId) {
    readAtCalls++;
    return Stream<DateTime?>.value(null);
  }

  @override
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId) {
    sharedCalls++;
    return Stream<List<SharedGifticon>>.value(const <SharedGifticon>[]);
  }

  @override
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId) {
    myJoinCalls++;
    return Stream<List<JoinRequest>>.value(const <JoinRequest>[]);
  }

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) {
    pendingJoinCalls++;
    return Stream<List<JoinRequest>>.value(const <JoinRequest>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add(invocation.memberName);
    throw UnimplementedError(
      '이 테스트는 watch 스트림만 사용한다 (호출됨: ${invocation.memberName})',
    );
  }
}

/// 기프티콘 목록 스트림 **구독 횟수**를 세는 [GifticonRepository].
class _CountingGifticonRepository implements GifticonRepository {
  int watchCalls = 0;

  /// `noSuchMethod`로 흘러간 예상 밖 호출 — [_CountingShareRepository] 참조.
  final List<Symbol> unexpected = <Symbol>[];

  @override
  Stream<List<Gifticon>> watchGifticons(String ownerId) {
    watchCalls++;
    return Stream<List<Gifticon>>.value(const <Gifticon>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add(invocation.memberName);
    throw UnimplementedError(
      '이 테스트는 watchGifticons만 사용한다 (호출됨: ${invocation.memberName})',
    );
  }
}

/// provider를 **하나도 watch하지 않는** 호스트 — 바깥 가드에 도달한다.
class _RetryHost extends ConsumerWidget {
  const _RetryHost(this.onRetry);

  final void Function(WidgetRef ref) onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => onRetry(ref),
          child: const Text('재시도'),
        ),
      ),
    );
  }
}

/// 세션 축**만** watch하는 호스트 — 사용자별 하위 family는 만들어진 적이 없다.
///
/// [_RetryHost]는 바깥 가드에서 전부 멈춰 **안쪽 인스턴스 가드에 도달하지 못한다.**
class _SessionOnlyHost extends ConsumerWidget {
  const _SessionOnlyHost(this.onRetry);

  final void Function(WidgetRef ref) onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionUserProvider);
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => onRetry(ref),
          child: const Text('재시도'),
        ),
      ),
    );
  }
}

/// 세션 + 내 그룹 목록까지 watch하는 호스트 — `exists(perGroup)`에 도달하는 유일한 형태.
class _GroupsHost extends ConsumerWidget {
  const _GroupsHost(this.onRetry);

  final void Function(WidgetRef ref) onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(myGroupsProvider);
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => onRetry(ref),
          child: const Text('재시도'),
        ),
      ),
    );
  }
}

void main() {
  late _CountingAuthRepository auth;
  late _CountingShareRepository share;
  late _CountingGifticonRepository gifticons;

  setUp(() {
    auth = _CountingAuthRepository();
    share = _CountingShareRepository();
    gifticons = _CountingGifticonRepository();
  });

  List<Override> overrides() => <Override>[
        authRepositoryProvider.overrideWithValue(auth),
        shareRepositoryProvider.overrideWithValue(share),
        gifticonRepositoryProvider.overrideWithValue(gifticons),
      ];

  /// 예상 밖 계약 호출이 없었는지 — create 안에서 던진 예외는 삼켜지므로 직접 단언한다.
  void expectNoUnexpectedCalls() {
    expect(auth.unexpected, isEmpty);
    expect(share.unexpected, isEmpty);
    expect(gifticons.unexpected, isEmpty);
  }

  /// 훅을 **아무것도 마운트되지 않은** 컨텍스트에서 한 번 호출한다(바깥 가드 축).
  Future<void> tapRetry(
    WidgetTester tester,
    void Function(WidgetRef ref) hook,
  ) async {
    bool invoked = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          home: _RetryHost((WidgetRef ref) {
            invoked = true;
            hook(ref);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 사전 조건(양성 대조가 아니다 — 계측 생존은 아래 `tapRetryWithSession`이 증명한다):
    // 호스트가 정말 아무것도 구독하지 않은 상태에서 출발했는지 확인한다.
    expect(auth.watchCalls, 0, reason: '호스트는 세션조차 watch하지 않는다');
    expect(share.totalCalls, 0);
    expect(gifticons.watchCalls, 0);

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();
    expect(invoked, isTrue, reason: '탭이 훅을 실제로 불렀는지 — 안 불렀으면 0은 공허하다');
  }

  /// 훅을 **세션만 마운트된** 컨텍스트에서 호출한다(안쪽 인스턴스 가드 축).
  Future<void> tapRetryWithSession(
    WidgetTester tester,
    void Function(WidgetRef ref) hook,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(home: _SessionOnlyHost(hook)),
      ),
    );
    await tester.pumpAndSettle();

    // 진짜 양성 대조 — 계측기가 살아 있으면 마운트한 축은 반드시 세어진다.
    expect(auth.watchCalls, 1, reason: '세션은 마운트됐다 — 계측 생존 증거');
    expect(share.totalCalls, 0);
    expect(gifticons.watchCalls, 0);

    await tester.tap(find.text('재시도'));
    await tester.pumpAndSettle();
  }

  /// 훅 호출이 **아무 스트림도 열지 않았음**을 단언한다.
  void expectNoSubscription() {
    expect(
      auth.watchCalls,
      0,
      reason: '세션 read가 가드 없이 나가면 watchCurrentUser가 구독된다',
    );
    expect(
      share.totalCalls,
      0,
      reason: '검사용 read가 가드 없이 나가면 그 축의 스트림이 구독된다',
    );
    expect(
      gifticons.watchCalls,
      0,
      reason: 'keepAlive인 rawGifticons는 낭비 구독이 컨테이너 수명 동안 잔존한다',
    );
    expectNoUnexpectedCalls();
  }

  group('마운트되지 않은 컨텍스트 — 바깥 가드가 상위 축을 열지 않는다', () {
    testWidgets('retryNotifications — 세션·rawGifticons', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retryNotifications);
      expectNoSubscription();
    });

    testWidgets('retryUsageLogs — 세션', (WidgetTester tester) async {
      await tapRetry(tester, retryUsageLogs);
      expectNoSubscription();
    });

    testWidgets('retryShareCandidates — 세션·그룹 목록', (WidgetTester tester) async {
      await tapRetry(tester, retryShareCandidates);
      expectNoSubscription();
    });

    testWidgets('retryFailedSharedGifticonStreams — 그룹 목록', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retryFailedSharedGifticonStreams);
      expectNoSubscription();
    });

    testWidgets('retrySharedGifticonIds — 그룹 목록(합성 경로)', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retrySharedGifticonIds);
      expectNoSubscription();
    });

    testWidgets('retrySharedItemLookup — 그룹 목록(합성 경로)', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retrySharedItemLookup);
      expectNoSubscription();
    });

    // 인자 없는 경로(share 메인)와 groupId 경로(그룹 상세) 둘 다. groupId 경로의
    // `invalidate`는 없는 인스턴스에 no-op이라 구독을 열지 않는다(계약 dartdoc 참조).
    testWidgets('retrySharedGifticons — 인자 없음', (WidgetTester tester) async {
      await tapRetry(tester, retrySharedGifticons);
      expectNoSubscription();
    });

    testWidgets('retrySharedGifticons(groupId:) — invalidate는 인스턴스를 만들지 않는다', (
      WidgetTester tester,
    ) async {
      await tapRetry(
        tester,
        (WidgetRef ref) => retrySharedGifticons(ref, groupId: 'g1'),
      );
      expectNoSubscription();
    });

    // 참여 요청 축 2개(PR #164에서 도착). 형제 훅 전부를 같은 축으로 재는 것이 이 파일의
    // 규약이다 — 빠뜨리면 그 훅만 가드 없이 자라도 아무도 모른다.
    testWidgets('retryMyJoinRequests — 세션', (WidgetTester tester) async {
      await tapRetry(tester, retryMyJoinRequests);
      expectNoSubscription();
    });

    testWidgets('retryPendingJoinRequests — invalidate만(구독 없음)', (
      WidgetTester tester,
    ) async {
      await tapRetry(
        tester,
        (WidgetRef ref) => retryPendingJoinRequests(ref, 'g1'),
      );
      expectNoSubscription();
    });
  });

  group('세션만 마운트된 컨텍스트 — 안쪽 가드가 사용자별 인스턴스를 열지 않는다', () {
    testWidgets('retryUsageLogs — exists(logs)', (WidgetTester tester) async {
      await tapRetryWithSession(tester, retryUsageLogs);
      expect(share.usageCalls, 0, reason: '미마운트 사용 이력 인스턴스를 만들면 안 된다');
      expectNoUnexpectedCalls();
    });

    testWidgets('retryMyJoinRequests — exists(mine)',
        (WidgetTester tester) async {
      await tapRetryWithSession(tester, retryMyJoinRequests);
      expect(share.myJoinCalls, 0, reason: '미마운트 내 참여 요청 인스턴스를 만들면 안 된다');
      expectNoUnexpectedCalls();
    });

    testWidgets('retryNotifications — exists(notifs)·exists(readAt)', (
      WidgetTester tester,
    ) async {
      await tapRetryWithSession(tester, retryNotifications);
      expect(share.notifCalls, 0, reason: '미마운트 알림 인스턴스');
      expect(share.readAtCalls, 0, reason: '미마운트 읽음 시각 인스턴스');
      expect(gifticons.watchCalls, 0, reason: '미마운트 rawGifticons');
      expectNoUnexpectedCalls();
    });

    testWidgets('retryShareCandidates — exists(mine)·exists(groups)', (
      WidgetTester tester,
    ) async {
      await tapRetryWithSession(tester, retryShareCandidates);
      expect(gifticons.watchCalls, 0, reason: '미마운트 내 기프티콘 인스턴스');
      expect(
        share.groupCalls,
        0,
        reason: '미마운트 그룹 인스턴스(MyGroupsRetry.retry)',
      );
      expectNoUnexpectedCalls();
    });
  });

  group('그룹 목록까지 마운트된 컨텍스트 — 그룹별 공유 인스턴스 가드', () {
    testWidgets('retryFailedSharedGifticonStreams — exists(perGroup)', (
      WidgetTester tester,
    ) async {
      share.groups = <Group>[
        Group(
          id: 'g1',
          name: '테스트 그룹',
          emoji: '🎁',
          inviteToken: 'tok',
          members: <GroupMember>[
            GroupMember(
              userId: InMemoryAuthRepository.defaultUser.id,
              displayName: InMemoryAuthRepository.defaultUser.displayName,
              avatarEmoji: '🙂',
              role: MemberRole.owner,
            ),
          ],
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: const MaterialApp(
            home: _GroupsHost(retryFailedSharedGifticonStreams),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 양성 대조 — 그룹 축이 실제로 마운트·계측된 상태에서의 단언이어야 한다.
      expect(share.groupCalls, 1, reason: '그룹 축은 마운트됐다 — 계측 생존 증거');
      expect(share.sharedCalls, 0);

      await tester.tap(find.text('재시도'));
      await tester.pumpAndSettle();

      expect(share.sharedCalls, 0, reason: '미마운트 그룹별 공유 인스턴스를 열면 안 된다');
      expectNoUnexpectedCalls();
    });
  });
}
