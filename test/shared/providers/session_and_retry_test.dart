/// 계약 정본 `sessionUserProvider`(세션 스트림 승격) + `myGroupsRetryProvider`
/// (내 그룹 체인 수동 재시도 훅) 단위 테스트.
///
/// 이 슬라이스가 고정해야 할 것은 셋이다:
/// 1. **세션 정본화 후에도 구독은 하나다** — 두 소비자(세션 직접 소비 + `myGroupsProvider`)가
///    동시에 watch해도 `AuthRepository.watchCurrentUser`는 1회만 구독돼야 한다
///    (정본화의 목적이 "같은 스트림을 여러 번 열지 않는 것"이므로 핵심 단언은 **구독 횟수**다).
/// 2. **훅은 에러인 계층만 되살린다** — 세션만 에러 / 그룹만 에러 / 둘 다 에러 / 둘 다 정상.
///    멀쩡한 스트림 재구독은 읽기·과금 낭비이자 불필요한 로딩 깜빡임이다.
/// 3. **훅 이후 회복** — 원천이 정상화되면 `myGroupsProvider`가 다시 `AsyncData`가 된다
///    (승격 전에는 캐시된 에러가 private 체인에 갇혀 앱 재시작 전까지 회복 불가였다 — #13).
///
/// 계측을 위해 `watchCurrentUser`/`watchGroups`만 구현한 테스트용 repository를 SSOT
/// provider에 override 한다(계약 구현체에 테스트 전용 카운터를 넣지 않기 위함).
/// `my_groups_provider_test.dart`의 `_CountingShareRepository`와 같은 이디엄이며,
/// 여기서는 **실패 토글**과 **살아 있는 스트림에 에러 주입**이 추가로 필요하다
/// (순단 에러 = 이전 값을 보존한 에러는 새 구독으로는 재현되지 않는다).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/my_groups_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// `watchCurrentUser`의 호출/구독 수를 세고, 실패를 토글할 수 있는 테스트용 [AuthRepository].
///
/// 한 번의 호출당 단일 구독 스트림을 새로 만들어 "구독 하나 = 리스너 하나"가 되게 한다.
class _ScriptedAuthRepository implements AuthRepository {
  _ScriptedAuthRepository(this.user);

  /// 정상 구독 시 방출할 사용자(null이면 미로그인 확정).
  final User? user;

  /// true면 **새 구독**이 값 대신 에러를 방출한다(원천 장애 지속 상태).
  bool fail = false;

  /// `watchCurrentUser()` 호출 횟수(= 재구독 횟수).
  int watchCalls = 0;

  /// 현재 열려 있는 구독 수.
  int activeListens = 0;

  final List<StreamController<User?>> _controllers =
      <StreamController<User?>>[];

  /// 살아 있는 스트림에 에러를 밀어 넣는다(값을 방출한 뒤의 **순단 에러** 재현).
  void breakLiveStreams(Object error) {
    for (final StreamController<User?> c in _controllers) {
      if (!c.isClosed) c.addError(error);
    }
  }

  @override
  Stream<User?> watchCurrentUser() {
    watchCalls++;
    late final StreamController<User?> controller;
    controller = StreamController<User?>(
      onListen: () {
        activeListens++;
        if (fail) {
          controller.addError(StateError('auth down'));
        } else {
          controller.add(user);
        }
      },
      onCancel: () {
        activeListens--;
        _controllers.remove(controller);
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchCurrentUser만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

/// `watchGroups`의 호출/구독 수를 세고, 실패를 토글할 수 있는 테스트용 [ShareRepository].
class _ScriptedShareRepository implements ShareRepository {
  _ScriptedShareRepository(this.groups);

  /// 정상 구독 시 방출할 그룹 목록.
  final List<Group> groups;

  /// true면 **새 구독**이 목록 대신 에러를 방출한다.
  bool fail = false;

  /// `watchGroups(userId)` 호출 횟수(= 재구독 횟수).
  int watchCalls = 0;

  /// 현재 열려 있는 구독 수.
  int activeListens = 0;

  final List<StreamController<List<Group>>> _controllers =
      <StreamController<List<Group>>>[];

  /// 살아 있는 스트림에 에러를 밀어 넣는다(이전 값을 보존한 순단 에러).
  void breakLiveStreams(Object error) {
    for (final StreamController<List<Group>> c in _controllers) {
      if (!c.isClosed) c.addError(error);
    }
  }

  @override
  Stream<List<Group>> watchGroups(String userId) {
    watchCalls++;
    late final StreamController<List<Group>> controller;
    controller = StreamController<List<Group>>(
      onListen: () {
        activeListens++;
        if (fail) {
          controller.addError(StateError('groups down'));
        } else {
          controller.add(groups);
        }
      },
      onCancel: () {
        activeListens--;
        _controllers.remove(controller);
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchGroups만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

void main() {
  const User me = InMemoryAuthRepository.defaultUser;

  /// 방장 1명(=현재 사용자)만 있는 최소 유효 그룹(`Group`의 owner 불변식 충족).
  Group groupFixture(String id, String name) {
    return Group(
      id: id,
      name: name,
      emoji: '🎁',
      inviteCode: 'CODE$id',
      members: <GroupMember>[
        GroupMember(
          userId: me.id,
          displayName: me.displayName,
          avatarEmoji: '🙂',
          role: MemberRole.owner,
        ),
      ],
    );
  }

  /// 세션·그룹 스트림의 방출과 invalidate 스케줄이 반영될 때까지 이벤트 큐를 비운다.
  Future<void> settle() => pumpEventQueue();

  /// 계측 repository 두 개를 주입한 컨테이너.
  ProviderContainer makeContainer(
    _ScriptedAuthRepository auth,
    _ScriptedShareRepository share,
  ) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(auth),
        shareRepositoryProvider.overrideWithValue(share),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 그룹 체인이 살아 있도록 화면처럼 구독을 붙인다(에러는 삼킨다 — 화면의 배너 역할).
  void listenMyGroups(ProviderContainer container) {
    container.listen<AsyncValue<List<Group>>>(
      myGroupsProvider,
      (_, __) {},
      onError: (Object _, StackTrace __) {},
    );
  }

  /// 그룹 id 목록으로 접어 비교하기 쉽게 한다.
  List<String>? groupIds(ProviderContainer container) => container
      .read(myGroupsProvider)
      .valueOrNull
      ?.map((Group g) => g.id)
      .toList();

  group('세션 스트림 정본화 (구독 단일화)', () {
    test('세션 직접 소비 + myGroupsProvider 동시 watch → watchCurrentUser 구독 1회',
        () async {
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(me);
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')]);
      final ProviderContainer container = makeContainer(auth, share);

      // 소비자 2개: 세션을 직접 보는 화면(앱 게이트·share 등)과 그룹 목록 정본.
      container.listen<AsyncValue<User?>>(sessionUserProvider, (_, __) {});
      listenMyGroups(container);

      await settle();

      // 핵심 회귀: 정본을 소비하므로 my_groups가 두 번째 세션 구독을 열지 않는다
      // (승격 전에는 파일 내부 `_currentUserProvider`가 별도 구독이었다).
      expect(auth.watchCalls, 1, reason: '두 소비자가 같은 세션 정본 인스턴스를 봐야 한다');
      expect(auth.activeListens, 1);

      // 세션·그룹 양쪽이 정상 배선됐는지 확인.
      expect(container.read(sessionUserProvider).valueOrNull?.id, me.id);
      expect(share.watchCalls, 1);
      expect(groupIds(container), <String>['g1']);
    });

    test('마지막 소비자가 사라지면 세션 구독도 해제된다(autoDispose 수명)', () async {
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(me);
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')]);
      final ProviderContainer container = makeContainer(auth, share);

      final ProviderSubscription<AsyncValue<List<Group>>> sub =
          container.listen<AsyncValue<List<Group>>>(
        myGroupsProvider,
        (_, __) {},
        onError: (Object _, StackTrace __) {},
      );
      await settle();
      expect(auth.activeListens, 1);

      sub.close();
      await settle();
      expect(auth.activeListens, 0, reason: 'autoDispose 정본 — 잔존 세션 리스너 없음');
    });
  });

  group('재시도 훅 — 에러인 계층만 되살린다', () {
    test('둘 다 정상이면 아무것도 재구독하지 않는다', () async {
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(me);
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')]);
      final ProviderContainer container = makeContainer(auth, share);
      listenMyGroups(container);
      await settle();

      container.read(myGroupsRetryProvider).retry();
      await settle();

      expect(auth.watchCalls, 1, reason: '멀쩡한 세션을 재구독하면 화면이 이유 없이 깜빡인다');
      expect(share.watchCalls, 1, reason: '멀쩡한 그룹 스트림 재구독 = 불필요한 읽기·과금');
      expect(groupIds(container), <String>['g1']);
    });

    test('그룹 스트림만 에러 → 그룹만 재구독하고 세션은 건드리지 않는다', () async {
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(me);
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')])
            ..fail = true;
      final ProviderContainer container = makeContainer(auth, share);
      listenMyGroups(container);
      await settle();

      expect(container.read(myGroupsProvider), isA<AsyncError<List<Group>>>());
      expect(auth.watchCalls, 1);
      expect(share.watchCalls, 1);

      // 원천이 회복된 뒤 사용자가 재시도 버튼을 누른다.
      share.fail = false;
      container.read(myGroupsRetryProvider).retry();
      await settle();

      expect(share.watchCalls, 2, reason: '에러인 그룹 인스턴스는 재구독돼야 한다');
      expect(auth.watchCalls, 1, reason: '세션은 에러가 아니므로 재구독 대상이 아니다');
      expect(groupIds(container), <String>['g1'], reason: '훅 이후 데이터로 복귀');
    });

    test('세션만 에러 → 세션을 재구독하고, 그때까지 그룹은 구독조차 하지 않는다', () async {
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(me)
        ..fail = true;
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')]);
      final ProviderContainer container = makeContainer(auth, share);
      listenMyGroups(container);
      await settle();

      expect(container.read(myGroupsProvider), isA<AsyncError<List<Group>>>(),
          reason: '세션 에러는 그룹 목록으로 전파된다');
      expect(share.watchCalls, 0, reason: '세션이 확정되기 전에는 그룹을 구독하지 않는다');

      auth.fail = false;
      container.read(myGroupsRetryProvider).retry();
      await settle();

      expect(auth.watchCalls, 2, reason: '에러인 세션 계층이 재구독돼야 한다');
      // 세션이 살아나면 하위(그룹)는 체인을 따라 자동으로 구성된다.
      expect(share.watchCalls, 1);
      expect(groupIds(container), <String>['g1'], reason: '훅 이후 데이터로 복귀');
    });

    test('두 계층이 모두 에러(순단)면 둘 다 되살아나 데이터로 복귀한다', () async {
      // 승격 전 재시도가 불가능했던 바로 그 조합: 인증 스트림이 실패하면 캐시된 에러가
      // 세션·그룹 두 계층에 각각 생긴다. 한쪽만 되살리면 절반만 해소된다(QA [minor 5]).
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(me);
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')]);
      final ProviderContainer container = makeContainer(auth, share);
      listenMyGroups(container);
      await settle();
      expect(groupIds(container), <String>['g1']);

      // 값이 나온 뒤 양쪽 스트림이 함께 끊긴다(이전 값을 보존한 에러).
      auth.fail = true;
      share.fail = true;
      auth.breakLiveStreams(StateError('auth down'));
      share.breakLiveStreams(StateError('groups down'));
      await settle();
      expect(container.read(sessionUserProvider).hasError, isTrue);
      expect(container.read(myGroupsProvider).hasError, isTrue);

      // 훅이 없던 시절: invalidate(myGroupsProvider)는 dependency로 전파되지 않아
      // 캐시된 에러를 다시 읽을 뿐이었다(#13 실측). 그 무력함을 여기서 고정한다.
      container.invalidate(myGroupsProvider);
      await settle();
      expect(container.read(myGroupsProvider).hasError, isTrue,
          reason: 'invalidate(myGroupsProvider)만으로는 원천이 되살아나지 않는다');
      expect(auth.watchCalls, 1);

      // 원천 회복 후 훅 호출 — 두 계층 모두 재구독된다.
      auth.fail = false;
      share.fail = false;
      container.read(myGroupsRetryProvider).retry();
      await settle();

      expect(auth.watchCalls, 2, reason: '세션 계층 재구독');
      expect(share.watchCalls, 2, reason: '그룹 계층 재구독');
      expect(container.read(myGroupsProvider), isA<AsyncData<List<Group>>>());
      expect(groupIds(container), <String>['g1'], reason: '훅 이후 데이터로 복귀');
    });

    test('미로그인 확정 상태에서 훅을 불러도 그룹 스트림을 열지 않는다', () async {
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(null);
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')]);
      final ProviderContainer container = makeContainer(auth, share);
      listenMyGroups(container);
      await settle();

      expect(container.read(myGroupsProvider),
          const AsyncData<List<Group>>(<Group>[]));

      container.read(myGroupsRetryProvider).retry();
      await settle();

      expect(auth.watchCalls, 1, reason: '에러가 아닌 세션은 재구독 대상이 아니다');
      expect(share.watchCalls, 0, reason: '세션 없이 그룹을 구독하면 안 된다');
    });

    testWidgets('화면용 진입점 retryMyGroups(WidgetRef)도 같은 훅으로 동작한다',
        (WidgetTester tester) async {
      // share 화면들은 `retry*(WidgetRef)` 관용구로 재시도를 부른다(배너 콜백).
      // 그 시그니처가 실제로 동작하는지(= 계약이 화면에서 소비 가능한지) 고정한다.
      final _ScriptedAuthRepository auth = _ScriptedAuthRepository(me);
      final _ScriptedShareRepository share =
          _ScriptedShareRepository(<Group>[groupFixture('g1', '가족')])
            ..fail = true;
      late WidgetRef captured;

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authRepositoryProvider.overrideWithValue(auth),
            shareRepositoryProvider.overrideWithValue(share),
          ],
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              captured = ref;
              ref.watch(myGroupsProvider); // 화면처럼 체인을 살려 둔다.
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pump();
      expect(share.watchCalls, 1);

      share.fail = false;
      retryMyGroups(captured); // 배너의 onRetry 콜백이 하는 일.
      await tester.pump();
      await tester.pump();

      expect(share.watchCalls, 2, reason: '에러인 그룹 계층이 재구독돼야 한다');
      expect(auth.watchCalls, 1, reason: '멀쩡한 세션은 그대로 둔다');
    });
  });
}
