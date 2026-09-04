/// share 내부 사용자별 스트림 family(사용 이력·공유 후보 기프티콘)의 **수명 규약** 회귀 테스트.
///
/// ## 고정하는 결함
/// `_usageLogsByUserProvider`·`_gifticonsByUserProvider`가 keepAlive였을 때:
/// 로그아웃 순간 인증을 잃은 백엔드 리스너는 permission-denied로 **종료**되는데,
/// keepAlive는 그 에러를 앱 수명 동안 캐시하고 재구독하지 않는다. 같은 계정으로
/// 재로그인해도 사용 이력 화면·공유 시트가 "불러오지 못했어요" 배너에 박제되어,
/// 수동 재시도를 누르기 전까지 회복이 없었다. 같은 파일의 참여 요청 family 2곳도
/// 같은 결함 기전이며 **별도 PR**(`fix/join-request-provider-lifetime`)이 다룬다 —
/// 이 파일이 그 축을 커버하는 것이 아니다.
///
/// ## 고정하는 규약
/// 두 family는 autoDispose다 — 로그아웃(세션 폴딩의 재계산)이 family를 놓으면 구독이
/// 해제되고, 재로그인은 **새 인스턴스**로 새로 구독한다. 죽은 에러가 남을 자리가 없다.
/// `_groupsByUserProvider`(`my_groups_provider.dart`)와 같은 수명 규약이며, 계측 방식
/// (구독 수 세기)은 `my_groups_provider_test.dart`의 이디엄을 따른다.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/share/state/share_providers.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// `watchUsageLogs`의 **호출 수·활성 구독 수**를 세는 테스트용 [ShareRepository].
///
/// 마지막으로 만든 컨트롤러를 노출해, 테스트가 "로그아웃으로 리스너가
/// permission-denied로 죽는" 순간을 `addError`로 재현할 수 있게 한다.
/// 이 테스트가 쓰는 계약 메서드는 watch 하나뿐이므로 나머지는 [noSuchMethod]로 막는다.
class _CountingShareRepository implements ShareRepository {
  _CountingShareRepository({this.logs = const <UsageLog>[]});

  /// 구독 시 방출할 값.
  final List<UsageLog> logs;

  int usageCalls = 0;
  int activeUsageListens = 0;
  StreamController<List<UsageLog>>? lastUsageController;

  @override
  Stream<List<UsageLog>> watchUsageLogs(String userId) {
    usageCalls++;
    late final StreamController<List<UsageLog>> controller;
    controller = StreamController<List<UsageLog>>(
      onListen: () {
        activeUsageListens++;
        controller.add(logs);
      },
      onCancel: () {
        activeUsageListens--;
      },
    );
    lastUsageController = controller;
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchUsageLogs만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

/// `watchGifticons`의 **호출 수·활성 구독 수**를 세는 테스트용 [GifticonRepository].
class _CountingGifticonRepository implements GifticonRepository {
  _CountingGifticonRepository({this.gifticons = const <Gifticon>[]});

  /// 구독 시 방출할 값.
  final List<Gifticon> gifticons;

  int calls = 0;
  int activeListens = 0;
  StreamController<List<Gifticon>>? lastController;

  @override
  Stream<List<Gifticon>> watchGifticons(String ownerId) {
    calls++;
    late final StreamController<List<Gifticon>> controller;
    controller = StreamController<List<Gifticon>>(
      onListen: () {
        activeListens++;
        controller.add(gifticons);
      },
      onCancel: () {
        activeListens--;
      },
    );
    lastController = controller;
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 watchGifticons만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

void main() {
  UsageLog logFixture(String id) {
    return UsageLog(
      id: id,
      groupId: 'g1',
      sharedGifticonId: 's1',
      userId: 'u-any',
      brand: '스타벅스',
      productName: '아메리카노',
      usedAt: DateTime.utc(2026, 9, 1),
    );
  }

  Gifticon gifticonFixture(String id, {required String ownerId}) {
    return Gifticon(
      id: id,
      ownerId: ownerId,
      brand: '스타벅스',
      productName: '아메리카노 T',
      category: '카페',
      price: 4500,
      barcode: '9788901234567',
      expiryDate: DateTime.utc(2027, 1, 1),
      registeredAt: DateTime.utc(2026, 9, 1),
    );
  }

  /// 스트림 방출·autoDispose 해제가 반영될 때까지 이벤트 큐를 비운다.
  Future<void> settle() => pumpEventQueue();

  Future<void> relogin(InMemoryAuthRepository auth) => auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );

  group('usageLogsProvider 체인 수명 (사용 이력 화면)', () {
    test('로그아웃이 구독을 해제하고, 같은 계정 재로그인이 새로 구독한다', () async {
      final _CountingShareRepository repo = _CountingShareRepository(
        logs: <UsageLog>[logFixture('l1')],
      );
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          shareRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);

      // 사용 이력 화면이 keepAlive 파생(usageLogsProvider)을 구독한다.
      container.listen<AsyncValue<List<UsageLog>>>(
        usageLogsProvider,
        (_, __) {},
      );
      await settle();
      expect(repo.usageCalls, 1);

      // 로그아웃 직전 리스너가 죽고(permission-denied), 이어서 세션이 풀린다 — 실제 순서.
      repo.lastUsageController!.addError(StateError('permission-denied'));
      await settle();
      // 양성 대조: 죽은 에러가 실제로 캐시된 **뒤에** 로그아웃해야 한다 — 이 단언이
      // 없으면 세션 null이 먼저 전달돼 에러가 버려진 채로도 통과하는 공허한 테스트가 된다.
      expect(container.read(usageLogsProvider).hasError, isTrue);
      await auth.signOut();
      await settle();
      expect(
        repo.activeUsageListens,
        0,
        reason: '세션이 풀리면 폴딩이 family를 놓아 autoDispose가 구독을 닫는다',
      );
      expect(
        container.read(usageLogsProvider),
        const AsyncData<List<UsageLog>>(<UsageLog>[]),
        reason: '미로그인 확정은 빈 목록 폴딩',
      );

      // 같은 계정으로 재로그인 — family는 새 인스턴스라 새로 구독한다.
      // (회귀: keepAlive면 같은 userId 인스턴스가 박제된 에러를 그대로 돌려줬다.)
      await relogin(auth);
      await settle();
      expect(repo.usageCalls, 2, reason: '재로그인은 백엔드를 새로 구독해야 한다');
      final AsyncValue<List<UsageLog>> revived =
          container.read(usageLogsProvider);
      expect(revived.hasError, isFalse, reason: '이전 세션의 죽은 에러가 남으면 안 된다');
      expect(
        revived.valueOrNull?.map((UsageLog l) => l.id),
        <String>['l1'],
      );
    });
  });

  group('shareableGifticonsProvider 체인 수명 (공유 시트 후보)', () {
    test('로그아웃이 구독을 해제하고, 같은 계정 재로그인이 새로 구독한다', () async {
      final InMemoryAuthRepository auth = InMemoryAuthRepository();
      final _CountingGifticonRepository repo = _CountingGifticonRepository(
        gifticons: <Gifticon>[
          gifticonFixture('g1', ownerId: InMemoryAuthRepository.defaultUser.id),
        ],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          gifticonRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);

      container.listen<AsyncValue<List<Gifticon>>>(
        shareableGifticonsProvider,
        (_, __) {},
      );
      await settle();
      expect(repo.calls, 1);

      repo.lastController!.addError(StateError('permission-denied'));
      await settle();
      // 양성 대조 — 근거는 위 usageLogs 케이스와 같다.
      expect(container.read(shareableGifticonsProvider).hasError, isTrue);
      await auth.signOut();
      await settle();
      expect(
        repo.activeListens,
        0,
        reason: '세션이 풀리면 폴딩이 family를 놓아 autoDispose가 구독을 닫는다',
      );

      await relogin(auth);
      await settle();
      expect(repo.calls, 2, reason: '재로그인은 백엔드를 새로 구독해야 한다');
      final AsyncValue<List<Gifticon>> revived =
          container.read(shareableGifticonsProvider);
      expect(revived.hasError, isFalse, reason: '이전 세션의 죽은 에러가 남으면 안 된다');
      expect(
        revived.valueOrNull?.map((Gifticon g) => g.id),
        <String>['g1'],
        reason: '재로그인 뒤에는 후보 계산이 새 구독으로 계속돼야 한다',
      );
    });
  });
}
