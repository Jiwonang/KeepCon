/// 참여 요청 provider **수명 규약** 회귀 테스트.
///
/// ## 고정하는 결함 (실측 재현)
/// `pendingJoinRequestsProvider`·`_myJoinRequestsByUserProvider`가 keepAlive였을 때:
/// 로그아웃 순간 인증을 잃은 백엔드 리스너는 permission-denied로 **종료**되는데,
/// keepAlive는 그 에러를 앱 수명 동안 캐시하고 재구독하지 않는다. 같은 계정으로
/// 재로그인해도 방장의 대기 목록(= 요청 도착의 **유일한 신호**)이 "참여 요청을
/// 불러오지 못했어요"에 박제되어, 이후의 참여 요청을 영영 승인할 수 없었다.
/// 같은 기기에서 방장→요청자→방장 순으로 계정을 바꾸는 시연이 정확히 이 경로다.
///
/// ## 고정하는 규약
/// 두 family는 autoDispose다 — 마지막 소비자가 떠나면(화면 이탈, 로그아웃의
/// AuthGate 트리 교체, 세션 폴딩의 재계산) 구독이 해제되고, 다음 진입은 **새로**
/// 구독한다. 죽은 에러가 남을 자리가 없다. `_groupsByUserProvider`
/// (`my_groups_provider.dart`)와 같은 수명 규약이며, 계측 방식(구독 수 세기)은
/// `my_groups_provider_test.dart`의 이디엄을 따른다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/state/share_providers.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// 참여 요청 두 스트림의 **호출 수·활성 구독 수**를 세는 테스트용 [ShareRepository].
///
/// 마지막으로 만든 컨트롤러를 노출해, 테스트가 "로그아웃으로 리스너가
/// permission-denied로 죽는" 순간을 `addError`로 재현할 수 있게 한다.
/// 이 테스트가 쓰는 계약 메서드는 두 watch뿐이므로 나머지는 [noSuchMethod]로 막는다.
class _CountingShareRepository implements ShareRepository {
  _CountingShareRepository({
    this.pending = const <JoinRequest>[],
    this.mine = const <JoinRequest>[],
  });

  /// 대기 목록 구독 시 방출할 값.
  final List<JoinRequest> pending;

  /// 내 요청 구독 시 방출할 값.
  final List<JoinRequest> mine;

  int pendingCalls = 0;
  int activePendingListens = 0;
  StreamController<List<JoinRequest>>? lastPendingController;

  int myCalls = 0;
  int activeMyListens = 0;
  StreamController<List<JoinRequest>>? lastMyController;

  /// 내 요청 구독에 요청된 userId 목록(세션 배선 확인용).
  final List<String> requestedUserIds = <String>[];

  Stream<List<JoinRequest>> _make(
    List<JoinRequest> value,
    void Function(StreamController<List<JoinRequest>>) remember,
    void Function(int) bump,
  ) {
    late final StreamController<List<JoinRequest>> controller;
    controller = StreamController<List<JoinRequest>>(
      onListen: () {
        bump(1);
        controller.add(value);
      },
      onCancel: () {
        bump(-1);
      },
    );
    remember(controller);
    return controller.stream;
  }

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) {
    pendingCalls++;
    return _make(
      pending,
      (StreamController<List<JoinRequest>> c) => lastPendingController = c,
      (int d) => activePendingListens += d,
    );
  }

  @override
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId) {
    myCalls++;
    requestedUserIds.add(userId);
    return _make(
      mine,
      (StreamController<List<JoinRequest>> c) => lastMyController = c,
      (int d) => activeMyListens += d,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 참여 요청 watch 2종만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  JoinRequest requestFixture(String id, {String groupId = 'g1'}) {
    return JoinRequest(
      id: id,
      groupId: groupId,
      userId: 'u-requester',
      displayName: '요청자',
      avatarEmoji: '🙂',
      requestedAt: DateTime.utc(2026, 9, 1),
    );
  }

  ProviderContainer makeContainer(
    _CountingShareRepository repo, {
    InMemoryAuthRepository? auth,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        shareRepositoryProvider.overrideWithValue(repo),
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 스트림 방출·autoDispose 해제가 반영될 때까지 이벤트 큐를 비운다.
  Future<void> settle() => pumpEventQueue();

  group('pendingJoinRequestsProvider 수명 (방장의 대기 목록)', () {
    test('리스너가 에러로 죽은 뒤 화면을 떠났다 다시 열면 새로 구독한다', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        pending: <JoinRequest>[requestFixture('r1')],
      );
      final ProviderContainer container = makeContainer(repo);

      // 방장이 그룹 상세를 연다 — 섹션 위젯이 watch를 시작한다.
      final ProviderSubscription<AsyncValue<List<JoinRequest>>> sub =
          container.listen<AsyncValue<List<JoinRequest>>>(
        pendingJoinRequestsProvider('g1'),
        (_, __) {},
      );
      await settle();
      expect(repo.pendingCalls, 1);
      expect(
        container
            .read(pendingJoinRequestsProvider('g1'))
            .valueOrNull
            ?.map((JoinRequest r) => r.id),
        <String>['r1'],
      );

      // 로그아웃 — 인증을 잃은 리스너가 permission-denied로 죽는다.
      repo.lastPendingController!.addError(StateError('permission-denied'));
      await settle();
      expect(
          container.read(pendingJoinRequestsProvider('g1')).hasError, isTrue);

      // AuthGate가 트리를 교체하며 마지막 소비자가 사라진다(화면 이탈과 같은 모양).
      sub.close();
      await settle();
      expect(
        repo.activePendingListens,
        0,
        reason: 'autoDispose — 마지막 소비자가 떠나면 죽은 스트림째 해제된다',
      );

      // 재로그인한 방장이 그룹 상세를 다시 연다 — **새 구독**이어야 한다.
      // (회귀: keepAlive면 재구독 없이 박제된 에러가 그대로 반환됐다.)
      container.listen<AsyncValue<List<JoinRequest>>>(
        pendingJoinRequestsProvider('g1'),
        (_, __) {},
      );
      await settle();
      expect(repo.pendingCalls, 2, reason: '재진입은 백엔드를 새로 구독해야 한다');
      final AsyncValue<List<JoinRequest>> revived =
          container.read(pendingJoinRequestsProvider('g1'));
      expect(revived.hasError, isFalse, reason: '이전 세션의 죽은 에러가 남으면 안 된다');
      expect(
        revived.valueOrNull?.map((JoinRequest r) => r.id),
        <String>['r1'],
        reason: '재로그인 뒤에는 그 사이 도착한 요청이 보여야 한다',
      );
    });
  });

  group('joinRequestsProvider 체인 수명 (요청자의 내 요청 카드)', () {
    test('로그아웃이 구독을 해제하고, 같은 계정 재로그인이 새로 구독한다', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        mine: <JoinRequest>[requestFixture('r1')],
      );
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final ProviderContainer container = makeContainer(repo, auth: auth);

      // 공유 탭이 keepAlive 파생(joinRequestsProvider)을 구독한다.
      container.listen<AsyncValue<List<JoinRequest>>>(
        joinRequestsProvider,
        (_, __) {},
      );
      await settle();
      expect(repo.myCalls, 1);
      expect(repo.requestedUserIds, <String>[myId]);

      // 로그아웃 직전 리스너가 죽고(permission-denied), 이어서 세션이 풀린다 — 실제 순서.
      repo.lastMyController!.addError(StateError('permission-denied'));
      await auth.signOut();
      await settle();
      expect(
        repo.activeMyListens,
        0,
        reason: '세션이 풀리면 폴딩이 family를 놓아 autoDispose가 구독을 닫는다',
      );
      expect(
        container.read(joinRequestsProvider),
        const AsyncData<List<JoinRequest>>(<JoinRequest>[]),
        reason: '미로그인 확정은 빈 목록 폴딩',
      );

      // 같은 계정으로 재로그인 — family는 새 인스턴스라 새로 구독한다.
      // (회귀: keepAlive면 같은 userId 인스턴스가 박제된 에러를 그대로 돌려줬다.)
      await auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );
      await settle();
      expect(repo.myCalls, 2, reason: '재로그인은 백엔드를 새로 구독해야 한다');
      // "같은 계정"이 이 테스트의 전제다 — 키가 달라지면 재구독은 autoDispose가
      // 아니라 새 family 인스턴스 생성으로도 일어나므로 아무것도 증명하지 못한다.
      expect(repo.requestedUserIds, <String>[myId, myId]);
      final AsyncValue<List<JoinRequest>> revived =
          container.read(joinRequestsProvider);
      expect(revived.hasError, isFalse, reason: '이전 세션의 죽은 에러가 남으면 안 된다');
      expect(
        revived.valueOrNull?.map((JoinRequest r) => r.id),
        <String>['r1'],
      );
    });
  });
}
