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
/// 이 파일은 그 반대 방향을 계측한다: **아무것도 watch하지 않는 위젯**에서 훅을 부르고
/// (체인이 마운트된 적 없는 컨텍스트 — `exists`가 false인 상태), 어떤 백엔드 스트림도
/// 구독되지 않았음을 단언한다. 가드를 지우면 read가 인스턴스를 만들며 실제 구독이
/// 열리므로 카운터가 0이 아니게 되어 실패한다(뮤테이션으로 확인).
///
/// 훅이 `WidgetRef` 전용 자유 함수라 [ProviderContainer]만으로는 부를 수 없어 위젯
/// 테스트 형태를 쓴다 — 위젯은 버튼 하나뿐이고 provider를 하나도 watch하지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/state/share_providers.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/group_notifications_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/shared_gifticons_provider.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// 세션 스트림 **구독 횟수**를 세는 [AuthRepository](가드가 풀리면 여기가 먼저 늘어난다).
class _CountingAuthRepository implements AuthRepository {
  int watchCalls = 0;

  @override
  Stream<User?> watchCurrentUser() {
    watchCalls++;
    return Stream<User?>.value(InMemoryAuthRepository.defaultUser);
  }

  @override
  User? get currentUser => InMemoryAuthRepository.defaultUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchCurrentUser만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

/// share 계약의 watch 스트림 **구독 횟수**를 축별로 세는 [ShareRepository].
class _CountingShareRepository implements ShareRepository {
  int groupCalls = 0;
  int usageCalls = 0;
  int notifCalls = 0;
  int readAtCalls = 0;
  int sharedCalls = 0;

  /// 어느 축이든 한 번이라도 구독됐는지(가드가 풀렸다는 신호).
  int get totalCalls =>
      groupCalls + usageCalls + notifCalls + readAtCalls + sharedCalls;

  @override
  Stream<List<Group>> watchGroups(String userId) {
    groupCalls++;
    return Stream<List<Group>>.value(const <Group>[]);
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
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watch 스트림만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

/// 기프티콘 목록 스트림 **구독 횟수**를 세는 [GifticonRepository].
class _CountingGifticonRepository implements GifticonRepository {
  int watchCalls = 0;

  @override
  Stream<List<Gifticon>> watchGifticons(String ownerId) {
    watchCalls++;
    return Stream<List<Gifticon>>.value(const <Gifticon>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchGifticons만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

/// provider를 **하나도 watch하지 않는** 호스트 — 버튼 콜백에서 훅만 부른다.
///
/// 이것이 이 파일의 계측 장치다: 체인이 마운트된 적 없으므로 훅 안의 `exists`가 전부
/// false여야 하고, 따라서 어떤 백엔드 스트림도 구독되지 않아야 한다.
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

void main() {
  late _CountingAuthRepository auth;
  late _CountingShareRepository share;
  late _CountingGifticonRepository gifticons;

  setUp(() {
    auth = _CountingAuthRepository();
    share = _CountingShareRepository();
    gifticons = _CountingGifticonRepository();
  });

  /// 훅을 마운트되지 않은 컨텍스트에서 한 번 호출한다.
  Future<void> tapRetry(
    WidgetTester tester,
    void Function(WidgetRef ref) hook,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          shareRepositoryProvider.overrideWithValue(share),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
        ],
        child: MaterialApp(home: _RetryHost(hook)),
      ),
    );
    await tester.pumpAndSettle();

    // 양성 대조: 호스트가 정말 아무것도 구독하지 않은 상태여야 한다 — 이 단언이 없으면
    // 아래 "0" 단언이 '가드가 막았다'가 아니라 '원래 구독이 있었다'와 구분되지 않는다.
    expect(auth.watchCalls, 0, reason: '호스트는 세션조차 watch하지 않는다');
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
  }

  group('마운트되지 않은 컨텍스트의 재시도는 아무것도 구독하지 않는다', () {
    testWidgets('retryNotifications — 세션·rawGifticons·알림 2축 모두', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retryNotifications);
      expectNoSubscription();
    });

    testWidgets('retryUsageLogs — 세션·사용 이력', (WidgetTester tester) async {
      await tapRetry(tester, retryUsageLogs);
      expectNoSubscription();
    });

    testWidgets('retryShareCandidates — 세션·그룹·그룹별 공유·내 기프티콘', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retryShareCandidates);
      expectNoSubscription();
    });

    testWidgets('retryFailedSharedGifticonStreams — 그룹 목록 축', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retryFailedSharedGifticonStreams);
      expectNoSubscription();
    });

    testWidgets('retrySharedGifticonIds — 그룹 + 그룹별 공유 합성 경로', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retrySharedGifticonIds);
      expectNoSubscription();
    });

    testWidgets('retrySharedItemLookup — 그룹 + 그룹별 공유 합성 경로', (
      WidgetTester tester,
    ) async {
      await tapRetry(tester, retrySharedItemLookup);
      expectNoSubscription();
    });
  });
}
