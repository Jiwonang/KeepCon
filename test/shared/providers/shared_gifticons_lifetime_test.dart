/// 계약 정본 [sharedGifticonsProvider]의 **수명 규약(autoDispose)** 회귀 테스트.
///
/// ## 고정하는 결함
/// keepAlive였을 때: 로그아웃 순간 인증을 잃은 백엔드 리스너는 permission-denied로
/// **종료**되는데, keepAlive는 그 에러를 앱 수명 동안 캐시하고 재구독하지 않는다.
/// 같은 계정으로 재로그인해도 그룹별 인스턴스가 박제된 에러를 그대로 돌려줘 공유
/// 목록·상세·시트가 배너에 영구히 머물렀다. 탈퇴한 그룹의 스테일 인스턴스도 앱 수명
/// 동안 남아, 재시도 훅이 family 전체 invalidate를 못 쓰는 이유가 되기도 했다.
///
/// ## 고정하는 규약
/// family는 autoDispose다 — 마지막 소비자가 떠나면(화면 이탈, 로그아웃·그룹 탈퇴로
/// keepAlive 파생([allSharedProvider] 등)이 재계산되며 놓음) 구독이 해제되고, 다음
/// 진입은 **새로** 구독한다. `_groupsByUserProvider`(`my_groups_provider.dart`)와 같은
/// 수명 규약이며, 계측 방식(구독 수 세기)은 `my_groups_provider_test.dart`의 이디엄을
/// 따른다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/shared_gifticons_provider.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// `watchGroups`·`watchSharedGifticons`의 **호출 수·활성 구독 수**를 세는 테스트용
/// [ShareRepository]. 그룹 목록은 컨트롤러로 직접 방출해 멤버십 변화(탈퇴)를 재현한다.
class _CountingShareRepository implements ShareRepository {
  final StreamController<List<Group>> groupsController =
      StreamController<List<Group>>.broadcast();

  final Map<String, int> sharedCalls = <String, int>{};
  final Map<String, int> activeSharedListens = <String, int>{};
  final Map<String, StreamController<List<SharedGifticon>>> sharedControllers =
      <String, StreamController<List<SharedGifticon>>>{};

  @override
  Stream<List<Group>> watchGroups(String userId) {
    return groupsController.stream;
  }

  @override
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId) {
    sharedCalls[groupId] = (sharedCalls[groupId] ?? 0) + 1;
    late final StreamController<List<SharedGifticon>> controller;
    controller = StreamController<List<SharedGifticon>>(
      onListen: () {
        activeSharedListens[groupId] = (activeSharedListens[groupId] ?? 0) + 1;
        controller.add(const <SharedGifticon>[]);
      },
      onCancel: () {
        activeSharedListens[groupId] = (activeSharedListens[groupId] ?? 0) - 1;
      },
    );
    sharedControllers[groupId] = controller;
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchGroups/watchSharedGifticons만 사용한다 '
        '(호출됨: ${invocation.memberName})',
      );
}

void main() {
  final String myId = InMemoryAuthRepository.defaultUser.id;

  Group groupFixture(String id) => Group(
        id: id,
        name: '그룹 $id',
        emoji: '🏠',
        inviteToken: 'token-$id',
        members: <GroupMember>[
          GroupMember(
            userId: myId,
            displayName: InMemoryAuthRepository.defaultUser.displayName,
            avatarEmoji: '🙂',
            role: MemberRole.owner,
          ),
        ],
      );

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

  group('sharedGifticonsProvider 수명 (그룹별 공유 스트림)', () {
    test('리스너가 에러로 죽은 뒤 화면을 떠났다 다시 열면 새로 구독한다', () async {
      final _CountingShareRepository repo = _CountingShareRepository();
      final ProviderContainer container =
          makeContainer(repo, InMemoryAuthRepository());

      // 그룹 상세가 watch를 시작한다(위젯 직접 소비 경로 — group_detail_page.dart).
      final ProviderSubscription<AsyncValue<List<SharedGifticon>>> sub =
          container.listen<AsyncValue<List<SharedGifticon>>>(
        sharedGifticonsProvider('g1'),
        (_, __) {},
      );
      await settle();
      expect(repo.sharedCalls['g1'], 1);

      // 로그아웃 — 인증을 잃은 리스너가 permission-denied로 죽는다.
      repo.sharedControllers['g1']!.addError(StateError('permission-denied'));
      await settle();
      expect(container.read(sharedGifticonsProvider('g1')).hasError, isTrue);

      // AuthGate가 트리를 교체하며 마지막 소비자가 사라진다(화면 이탈과 같은 모양).
      sub.close();
      await settle();
      expect(
        repo.activeSharedListens['g1'],
        0,
        reason: 'autoDispose — 마지막 소비자가 떠나면 죽은 스트림째 해제된다',
      );

      // 재로그인 뒤 다시 연다 — **새 구독**이어야 한다.
      // (회귀: keepAlive면 재구독 없이 박제된 에러가 그대로 반환됐다.)
      container.listen<AsyncValue<List<SharedGifticon>>>(
        sharedGifticonsProvider('g1'),
        (_, __) {},
      );
      await settle();
      expect(repo.sharedCalls['g1'], 2, reason: '재진입은 백엔드를 새로 구독해야 한다');
      expect(
        container.read(sharedGifticonsProvider('g1')).hasError,
        isFalse,
        reason: '이전 세션의 죽은 에러가 남으면 안 된다',
      );
    });

    test('로그아웃이 keepAlive 파생의 그룹별 구독을 해제하고, 재로그인이 새로 구독한다', () async {
      final _CountingShareRepository repo = _CountingShareRepository();
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final ProviderContainer container = makeContainer(repo, auth);

      // 공유 탭의 keepAlive 파생이 그룹 목록을 가로질러 그룹별 스트림을 붙잡는다.
      container.listen<List<SharedGifticon>>(allSharedProvider, (_, __) {});
      await settle();
      repo.groupsController.add(<Group>[groupFixture('g1')]);
      await settle();
      expect(repo.sharedCalls['g1'], 1);
      expect(repo.activeSharedListens['g1'], 1);

      // 로그아웃 직전 리스너가 죽고, 이어서 세션이 풀린다 — 실제 순서.
      repo.sharedControllers['g1']!.addError(StateError('permission-denied'));
      await settle();
      // 양성 대조: 죽은 에러가 실제로 캐시된 **뒤에** 로그아웃해야 한다 — 이 단언이
      // 없으면 세션 null이 먼저 전달돼 에러가 버려진 채로도 통과하는 공허한 테스트가 된다.
      expect(container.read(sharedGifticonsProvider('g1')).hasError, isTrue);
      await auth.signOut();
      await settle();
      expect(
        repo.activeSharedListens['g1'],
        0,
        reason: '그룹 목록이 빈 폴딩으로 재계산되며 파생이 놓으면 autoDispose가 구독을 닫는다',
      );

      // 같은 계정으로 재로그인 — 그룹 목록이 돌아오면 **새 인스턴스**로 새로 구독한다.
      await auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );
      await settle();
      repo.groupsController.add(<Group>[groupFixture('g1')]);
      await settle();
      expect(repo.sharedCalls['g1'], 2, reason: '재로그인은 백엔드를 새로 구독해야 한다');
      expect(
        container.read(sharedGifticonsProvider('g1')).hasError,
        isFalse,
        reason: '이전 세션의 죽은 에러가 남으면 안 된다',
      );
    });

    test('그룹에서 빠지면 그 그룹의 스테일 인스턴스가 해제된다(비멤버 구독 잔존 금지)', () async {
      final _CountingShareRepository repo = _CountingShareRepository();
      final ProviderContainer container =
          makeContainer(repo, InMemoryAuthRepository());

      container.listen<List<SharedGifticon>>(allSharedProvider, (_, __) {});
      await settle();
      repo.groupsController
          .add(<Group>[groupFixture('g1'), groupFixture('g2')]);
      await settle();
      expect(repo.activeSharedListens['g1'], 1);
      expect(repo.activeSharedListens['g2'], 1);

      // g2에서 탈퇴 — 멤버십이 끊긴 그룹의 리스너는 곧 permission-denied가 되므로,
      // 목록에서 빠지는 순간 구독도 함께 끊겨야 한다(keepAlive 시절에는 앱 수명 동안
      // 남아 재시도 훅이 family 전체 invalidate를 못 쓰는 이유였다).
      repo.groupsController.add(<Group>[groupFixture('g1')]);
      await settle();
      expect(
        repo.activeSharedListens['g2'],
        0,
        reason: '떠난 그룹의 인스턴스는 소비자가 놓는 순간 스스로 정리된다',
      );
      expect(
        repo.activeSharedListens['g1'],
        1,
        reason: '남은 그룹의 구독은 그대로다(재구독 없음)',
      );
      expect(repo.sharedCalls['g1'], 1, reason: '남은 그룹을 재구독하지 않는다');
    });
  });
}
