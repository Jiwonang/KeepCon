/// main 목록 체인이 **세션 계약 정본**(`sessionUserProvider`)을 소비하는지 고정하는 테스트.
///
/// 이 슬라이스가 옮긴 것은 소스뿐이고 동작은 불변이어야 한다. 고정할 것은 넷이다:
/// 1. **화면이 실제로 정본을 본다** — `MainPage`를 실제로 띄우고 **정본만 override** 해서,
///    자체 `watchCurrentUser()` 구독으로 되돌아가면 실패하게 한다(게이트 테스트
///    `auth_flow_test.dart`와 같은 형태). provider를 두 번 `listen`하는 대역 단언은
///    Riverpod 자체 속성만 고정할 뿐 화면의 소비를 고정하지 못한다(QA v2.7 [minor 2]).
/// 2. **구독은 하나다** — 목록 체인과 화면이 동시에 세션을 봐도 `watchCurrentUser`는 1회만
///    구독된다(승격 전 main의 `currentUserProvider`는 정본과 별도 인스턴스였다 — 매트릭스 #13).
/// 3. **`select` 협소 구독** — 같은 uid·다른 `displayName` 재방출(mypage 프로필 편집의
///    `updateDisplayName`+`reload` 경로)에 `watchGifticons`가 **재구독되지 않는다**
///    (QA v2.7 [medium 1]. 삭제된 별칭의 `==` 필터로도 못 걸렀던 경로다).
/// 4. **폴딩 규약이 유지된다** — 로그아웃(세션 `data(null)`)이면 목록이 비워지고, 세션
///    순단(이전 값을 보존한 에러)에는 보고 있던 목록이 사라지지 않는다(`valueOrNull` 규약).
///
/// 계측용 repository를 SSOT provider에 override 하는 이디엄은
/// `test/shared/providers/session_and_retry_test.dart`와 같다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/features/main/state/gifticon_list_providers.dart';
import 'package:keepcon/shared/providers/raw_gifticons_provider.dart';
import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

/// `watchCurrentUser` 구독 수를 세고, 세션 이벤트를 스크립트로 밀어 넣는 [AuthRepository].
///
/// 미구현 멤버는 이 테스트가 부르지 않는다(세션 축만 계측 — 범위 밖 호출은 폭발시킨다).
class _CountingAuthRepository implements AuthRepository {
  /// `watchCurrentUser()` 호출 횟수(= 구독 시도 횟수).
  int watchCalls = 0;

  final List<StreamController<User?>> _controllers =
      <StreamController<User?>>[];

  /// 살아 있는 세션 스트림에 값을 방출한다(로그인/로그아웃/계정 전환/프로필 갱신).
  void emit(User? user) {
    for (final StreamController<User?> c in _controllers) {
      if (!c.isClosed) c.add(user);
    }
  }

  /// 살아 있는 세션 스트림에 에러를 밀어 넣는다(값 방출 뒤의 **순단 에러**).
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
      onCancel: () => _controllers.remove(controller),
    );
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  User? get currentUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} — 이 테스트 범위 밖');
}

/// `watchGifticons` **구독 수**를 세는 계측 [GifticonRepository].
///
/// 이 수치가 곧 비용이다 — Firestore에서 재구독은 목록 리스너 teardown/재수립이라
/// 쿼리가 통째로 다시 읽힌다. 목록 조회 외의 계약 메서드는 이 테스트가 쓰지 않는다.
class _CountingGifticonRepository implements GifticonRepository {
  _CountingGifticonRepository(this._inner);

  final InMemoryGifticonRepository _inner;

  /// `watchGifticons()` 호출 횟수(= 목록 스트림 재수립 횟수).
  int watchCalls = 0;

  @override
  Stream<List<Gifticon>> watchGifticons(String ownerId) {
    watchCalls++;
    return _inner.watchGifticons(ownerId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} — 이 테스트 범위 밖');
}

void main() {
  const User me = User(
    id: 'user-1',
    email: 'me@keepcon.app',
    displayName: '나',
  );

  final DateTime now = DateTime.now();
  Gifticon fixture(String id) => Gifticon(
        id: id,
        ownerId: me.id,
        brand: '스타벅스',
        productName: '아메리카노 T',
        category: '카페',
        price: 4500,
        expiryDate: now.add(const Duration(days: 5)),
        registeredAt: now,
        status: GifticonStatus.available,
      );

  /// 세션·목록 스트림의 방출이 반영될 때까지 이벤트 큐를 비운다
  /// (`session_and_retry_test.dart`와 같은 이디엄).
  Future<void> settle() => pumpEventQueue();

  InMemoryGifticonRepository seededGifticons() =>
      InMemoryGifticonRepository(seed: <Gifticon>[fixture('g-1')]);

  ProviderContainer makeContainer(
    _CountingAuthRepository auth, {
    GifticonRepository? gifticons,
  }) {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        authRepositoryProvider.overrideWithValue(auth),
        gifticonRepositoryProvider
            .overrideWithValue(gifticons ?? seededGifticons()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  List<String> visibleIds(ProviderContainer container) =>
      (container.read(visibleGifticonsProvider).valueOrNull ??
              const <Gifticon>[])
          .map((Gifticon g) => g.id)
          .toList();

  testWidgets('MainPage가 세션 정본을 소비한다 — 자체 세션 구독을 열지 않는다',
      (WidgetTester tester) async {
    // 정본만 override 한다. 화면이나 목록 체인이 자체 `watchCurrentUser()` 구독으로
    // 되돌아가면 계측 repository가 호출돼 watchCalls가 0을 넘는다(= 실패).
    final _CountingAuthRepository auth = _CountingAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          gifticonRepositoryProvider.overrideWithValue(seededGifticons()),
          sessionUserProvider.overrideWith((_) => Stream<User?>.value(me)),
        ],
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.watchCalls, 0, reason: 'main은 정본 밖에서 세션 스트림을 열지 않아야 한다');
    // 정본이 준 uid로 목록 체인이 실제로 조회했는지 — 화면 렌더로 확인.
    expect(find.text('스타벅스'), findsWidgets);
  });

  test('목록 체인과 화면이 동시에 세션을 봐도 watchCurrentUser 구독은 1회', () async {
    final _CountingAuthRepository auth = _CountingAuthRepository();
    final ProviderContainer container = makeContainer(auth);

    // 소비자 2개(목록 체인 + 세션 직접 소비)가 같은 정본 인스턴스를 봐야 한다.
    container.listen<AsyncValue<List<Gifticon>>>(
        rawGifticonsProvider, (_, __) {});
    container.listen<AsyncValue<User?>>(sessionUserProvider, (_, __) {});
    auth.emit(me);
    await settle();

    expect(auth.watchCalls, 1, reason: 'main이 정본을 소비하므로 세션 스트림은 하나다');
    expect(visibleIds(container), <String>['g-1']);
  });

  test('같은 uid·다른 displayName 재방출에는 watchGifticons가 재구독되지 않는다', () async {
    // mypage 프로필 편집(`updateDisplayName` + `reload`)이 만드는 세션 재방출 경로.
    // 세션을 통째로 watch하면 create가 재실행돼 목록 스트림이 teardown/재수립된다
    // (QA v2.7 [medium 1]) — `select((s) => s.valueOrNull?.id)`가 그것을 막는다.
    final _CountingAuthRepository auth = _CountingAuthRepository();
    final _CountingGifticonRepository gifticons =
        _CountingGifticonRepository(seededGifticons());
    final ProviderContainer container =
        makeContainer(auth, gifticons: gifticons);
    container.listen<AsyncValue<List<Gifticon>>>(
        rawGifticonsProvider, (_, __) {});

    auth.emit(me);
    await settle();
    expect(gifticons.watchCalls, 1);
    expect(visibleIds(container), <String>['g-1']);

    auth.emit(me.copyWith(displayName: '바뀐 이름'));
    await settle();

    expect(gifticons.watchCalls, 1,
        reason: 'id가 그대로면 목록 스트림을 끊었다 다시 붙일 이유가 없다(재구독 = 쿼리 재읽기)');
    expect(visibleIds(container), <String>['g-1']);

    // 계정 전환(다른 uid)은 반대로 **반드시** 재구독돼야 한다 — 협소화가 반응성을
    // 죽이지 않았는지 같은 테스트에서 확인한다.
    auth.emit(me.copyWith(id: 'user-2'));
    await settle();
    expect(gifticons.watchCalls, 2, reason: 'uid가 바뀌면 새 소유자의 목록을 구독해야 한다');
    expect(visibleIds(container), isEmpty, reason: 'user-2의 기프티콘은 없다');
  });

  test('로그아웃(세션 data(null))이면 목록이 비워진다', () async {
    final _CountingAuthRepository auth = _CountingAuthRepository();
    final ProviderContainer container = makeContainer(auth);
    container.listen<AsyncValue<List<Gifticon>>>(
        rawGifticonsProvider, (_, __) {});

    auth.emit(me);
    await settle();
    expect(visibleIds(container), <String>['g-1']);

    auth.emit(null); // 미로그인 확정.
    await settle();
    expect(visibleIds(container), isEmpty,
        reason: '로그아웃하면 남의 화면에 목록이 남으면 안 된다');
  });

  test('세션 순단(보존 값 있는 에러)에는 보고 있던 목록이 유지된다', () async {
    final _CountingAuthRepository auth = _CountingAuthRepository();
    final ProviderContainer container = makeContainer(auth);
    container.listen<AsyncValue<List<Gifticon>>>(
        rawGifticonsProvider, (_, __) {});

    auth.emit(me);
    await settle();
    expect(visibleIds(container), <String>['g-1']);

    // `.value`/`.when`으로 접으면 여기서 목록이 통째로 사라진다(#13 / QA [medium 1]).
    auth.breakLiveStreams(StateError('auth blip'));
    await settle();
    expect(container.read(sessionUserProvider).hasError, isTrue);
    expect(visibleIds(container), <String>['g-1'], reason: '순단은 로그아웃이 아니다');
  });
}
