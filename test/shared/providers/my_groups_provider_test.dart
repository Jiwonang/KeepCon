/// 계약 정본 `myGroupsProvider` 단위 테스트.
///
/// 이 승격의 목적은 "코드 중복 제거"가 아니라 **구독 중복 제거**다 — 승격 전에는
/// scan과 share가 각자의 provider 체인을 가져서 같은 사용자에 대해
/// `ShareRepository.watchGroups`가 두 번 구독됐다(Firestore에서는 리스너 2개 =
/// 읽기·과금 2배). 그래서 이 파일의 핵심 단언은 **구독 횟수**다.
///
/// 구독을 세기 위해 `watchGroups`만 구현한 테스트용 [_CountingShareRepository]를
/// `shareRepositoryProvider`에 override 한다(InMemory 구현에는 구독 카운터가 없고,
/// 계약 구현체에 테스트 전용 계측을 넣지 않기 위함). 세션은 계약 mock
/// [InMemoryAuthRepository]를 그대로 쓴다(기본=로그인 상태, `initialUser: null`=미로그인).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/providers/my_groups_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// `watchGroups`의 **호출 수와 실제 스트림 구독 수**를 세는 테스트용 [ShareRepository].
///
/// 호출 수만으로는 부족하다 — provider가 스트림을 만들고 구독하지 않을 수도 있으므로,
/// `onListen`/`onCancel`로 활성 구독 수([activeListens])까지 센다. 한 번의
/// `watchGroups` 호출당 하나의 단일 구독 스트림을 새로 만들어, 실제 백엔드처럼
/// "구독 하나 = 리스너 하나"가 되게 한다.
///
/// 이 테스트가 쓰는 계약 메서드는 `watchGroups`뿐이므로 나머지는 [noSuchMethod]로
/// 막아 둔다(잘못 호출되면 조용히 통과하지 않고 즉시 실패한다).
class _CountingShareRepository implements ShareRepository {
  _CountingShareRepository({this.groups = const <Group>[], this.error});

  /// 구독 시 방출할 그룹 목록.
  final List<Group> groups;

  /// null이 아니면 목록 대신 이 에러를 방출한다(에러 전파 검증용).
  final Object? error;

  /// `watchGroups(userId)` 호출 횟수.
  int watchGroupsCalls = 0;

  /// 누적 구독 횟수(해제해도 줄지 않음).
  int totalListens = 0;

  /// 현재 열려 있는 구독 수(해제 시 감소).
  int activeListens = 0;

  /// 구독 요청된 userId 목록(세션 배선 확인용).
  final List<String> requestedUserIds = <String>[];

  @override
  Stream<List<Group>> watchGroups(String userId) {
    watchGroupsCalls++;
    requestedUserIds.add(userId);

    final Object? failure = error;
    late final StreamController<List<Group>> controller;

    controller = StreamController<List<Group>>(
      onListen: () {
        totalListens++;
        activeListens++;
        if (failure != null) {
          controller.addError(failure);
        } else {
          controller.add(groups);
        }
      },
      onCancel: () {
        activeListens--;
      },
    );

    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchGroups만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  /// 방장 1명(=현재 사용자)만 있는 최소 유효 그룹(`Group`의 owner 불변식 충족).
  Group groupFixture(String id, String name) {
    return Group(
      id: id,
      name: name,
      emoji: '🎁',
      inviteCode: 'CODE$id',
      members: <GroupMember>[
        GroupMember(
          userId: myId,
          displayName: InMemoryAuthRepository.defaultUser.displayName,
          avatarEmoji: '🙂',
          role: MemberRole.owner,
        ),
      ],
    );
  }

  /// 계측 repository(+선택적 세션)를 주입한 컨테이너.
  ProviderContainer makeContainer(
    _CountingShareRepository repo, {
    AuthRepository? auth,
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

  /// 세션·그룹 스트림의 첫 방출이 반영될 때까지 이벤트 큐를 비운다.
  ///
  /// flutter_test 내장 [pumpEventQueue]에 위임한다(기본 20회 — 수동
  /// Duration.zero 루프를 재구현하지 않는다. in_memory_auth_repository_test와
  /// 같은 이디엄).
  Future<void> settle() => pumpEventQueue();

  /// 빈 목록 폴딩 파생(테스트 로컬).
  ///
  /// scan의 `scanTargetGroupsProvider`와 동형이지만 **일부러 import하지 않는다**:
  /// lib/shared 정본 테스트가 lib/features에 의존하면(역방향 의존) 페이지 내부
  /// 리팩터링이 정본 테스트를 깨뜨리고, 반대로 페이지가 정본 소비를 끊어도 이
  /// 테스트는 통과해 회귀를 놓친다. 정본 테스트는 정본 + 테스트 로컬 파생으로
  /// 닫혀 있어야 한다.
  final AutoDisposeProvider<List<Group>> foldedDerivedProvider =
      Provider.autoDispose<List<Group>>(
    (Ref ref) => ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[],
  );

  group('구독 단일화 (이 승격의 목적)', () {
    test('scan 파생과 share 정본을 동시에 watch해도 watchGroups 구독은 1회', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        groups: <Group>[groupFixture('g1', '가족'), groupFixture('g2', '친구')],
      );
      final ProviderContainer container = makeContainer(repo);

      // 두 페이지가 실제 화면에서 하듯 각자의 소비 지점을 동시에 구독한다.
      // - share: 정본 AsyncValue를 그대로 소비
      // - scan : 정본을 빈 목록으로 접는 폴딩 파생(테스트 로컬 — scan과 동형)
      container.listen<AsyncValue<List<Group>>>(myGroupsProvider, (_, __) {});
      container.listen<List<Group>>(foldedDerivedProvider, (_, __) {});

      await settle();

      // 핵심 회귀: 소비자가 2개여도 백엔드 구독은 1개다.
      expect(repo.watchGroupsCalls, 1, reason: '두 소비자가 같은 정본 인스턴스를 봐야 한다');
      expect(repo.totalListens, 1);
      expect(repo.activeListens, 1);
      expect(repo.requestedUserIds, <String>[myId]);

      // 두 소비 지점이 같은 목록을 본다(같은 스트림에서 나온 값).
      expect(
        container.read(myGroupsProvider).valueOrNull?.map((Group g) => g.id),
        <String>['g1', 'g2'],
      );
      expect(
        container.read(foldedDerivedProvider).map((Group g) => g.id),
        <String>['g1', 'g2'],
      );
    });

    test('scan 파생만 해제하면 구독이 유지되고, 마지막 소비자가 사라지면 해제된다', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        groups: <Group>[groupFixture('g1', '가족')],
      );
      final ProviderContainer container = makeContainer(repo);

      final ProviderSubscription<AsyncValue<List<Group>>> shareSub =
          container.listen<AsyncValue<List<Group>>>(
        myGroupsProvider,
        (_, __) {},
      );
      final ProviderSubscription<List<Group>> scanSub =
          container.listen<List<Group>>(foldedDerivedProvider, (_, __) {});

      await settle();
      expect(repo.activeListens, 1);

      // 스캔 플로우 이탈 — 상시 탭(share)이 보고 있으므로 구독은 살아 있어야 한다.
      scanSub.close();
      await settle();
      expect(repo.activeListens, 1, reason: 'share가 listen 중이면 정본은 유지된다');
      expect(repo.watchGroupsCalls, 1, reason: '재구독(중복 읽기)이 발생하면 안 된다');

      // 마지막 소비자까지 사라지면 autoDispose가 실제 구독을 닫는다.
      shareSub.close();
      await settle();
      expect(repo.activeListens, 0, reason: 'autoDispose 정본 — 잔존 리스너 없음');
    });

    test('keepAlive 소비자가 정본(autoDispose)을 watch해도 동작하고 수명을 붙잡는다', () async {
      // share의 파생 provider들(`groupByIdProvider`·`allSharedProvider` 등)이 이 형태다.
      // autoDispose 정본을 keepAlive가 watch하는 조합이 Riverpod에서 허용되는지가
      // 정본의 수명 결정(autoDispose)의 전제이므로, 그 전제를 여기서 고정한다.
      final _CountingShareRepository repo = _CountingShareRepository(
        groups: <Group>[groupFixture('g1', '가족')],
      );
      final ProviderContainer container = makeContainer(repo);

      final Provider<List<String>> keepAliveDerived =
          Provider<List<String>>((Ref ref) {
        return ref
                .watch(myGroupsProvider)
                .valueOrNull
                ?.map((Group g) => g.id)
                .toList() ??
            const <String>[];
      });

      final ProviderSubscription<List<String>> sub =
          container.listen<List<String>>(keepAliveDerived, (_, __) {});
      await settle();

      expect(container.read(keepAliveDerived), <String>['g1']);
      expect(repo.activeListens, 1);

      // ⚠️ keepAlive 소비자는 리스너가 사라져도 스스로 dispose되지 않으므로, 정본을
      // 계속 watch한 채 **구독을 붙잡는다**. share의 파생 provider들이 keepAlive인
      // 한, 공유 탭을 한 번 열면 그 뒤로는 컨테이너 수명 동안 구독이 유지된다는 뜻이다
      // (= 승격 전 share의 keepAlive 체인과 동일한 수명 — 동작 변화 없음).
      // scan 쪽 이득은 "두 번째 구독이 더 이상 열리지 않는다"는 점이다.
      sub.close();
      await settle();
      expect(
        repo.activeListens,
        1,
        reason: 'keepAlive 소비자가 정본 수명을 붙잡는다(설계상 의도 — share 탭 수명과 동일)',
      );

      // 컨테이너(=앱 스코프)가 사라지면 함께 해제된다.
      container.dispose();
      expect(repo.activeListens, 0);
    });

    test('미로그인이면 구독을 아예 열지 않고 빈 목록으로 확정한다', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        groups: <Group>[groupFixture('g1', '가족')],
      );
      final ProviderContainer container = makeContainer(
        repo,
        auth: InMemoryAuthRepository(initialUser: null),
      );

      container.listen<AsyncValue<List<Group>>>(myGroupsProvider, (_, __) {});
      await settle();

      expect(repo.watchGroupsCalls, 0, reason: '세션 없이 그룹을 구독하면 안 된다');
      expect(container.read(myGroupsProvider),
          const AsyncData<List<Group>>(<Group>[]));
    });
  });

  group('노출 형태 = AsyncValue (로딩/에러 구분 보존)', () {
    test('세션 확정 전에는 로딩을 전파하고, scan 파생은 빈 목록으로 접는다', () {
      final _CountingShareRepository repo = _CountingShareRepository(
        groups: <Group>[groupFixture('g1', '가족')],
      );
      final ProviderContainer container = makeContainer(repo);

      // settle 전(세션 스트림 첫 방출 전) — 정본은 로딩을 숨기지 않는다.
      expect(
          container.read(myGroupsProvider), isA<AsyncLoading<List<Group>>>());

      // 같은 순간 scan은 빈 목록을 본다('내 지갑' 타일만 있는 정상 상태).
      expect(container.read(foldedDerivedProvider), isEmpty);
    });

    test('그룹 스트림 에러는 AsyncError로 전파되고, 접을 때 rethrow하지 않는다', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        error: StateError('boom'),
      );
      final ProviderContainer container = makeContainer(repo);

      container.listen<AsyncValue<List<Group>>>(
        myGroupsProvider,
        (_, __) {},
        onError: (Object _, StackTrace __) {},
      );
      await settle();

      final AsyncValue<List<Group>> value = container.read(myGroupsProvider);
      expect(value, isA<AsyncError<List<Group>>>());

      // `.value`는 이전 값 없는 AsyncError에서 rethrow하므로 정본/파생 모두
      // `valueOrNull`을 쓴다 — 첫 방출이 에러여도 소비 지점이 throw하지 않아야 한다.
      expect(value.valueOrNull, isNull);
      expect(() => container.read(foldedDerivedProvider), returnsNormally);
      expect(container.read(foldedDerivedProvider), isEmpty);
    });
  });
}
