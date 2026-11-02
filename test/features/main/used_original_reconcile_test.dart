/// `usedOriginalsReconcileProvider` — 보정이 **로그인 사용자마다 한 번** 돌고, 실패를
/// 화면 대신 진단 경로로 보내는가.
///
/// 보정 자체(무엇을 맞추는가)는 공유 계약 스위트와 Firestore 고유 테스트가 고정한다.
/// 여기서는 트리거만 본다 — 진입마다 돌면 원본마다 조회가 붙고, 한 번도 안 돌면
/// 어긋남이 영구히 남는다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/main/main_page.dart';
import 'package:keepcon/features/main/state/used_original_reconcile.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/providers/session_provider.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

class _CountingShareRepository implements ShareRepository {
  int calls = 0;
  Object? failWith;

  @override
  Future<int> reconcileUsedOriginals() async {
    calls++;
    final Object? error = failWith;
    if (error != null) throw error;
    return 2;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '이 테스트는 reconcileUsedOriginals만 사용한다 (호출됨: ${invocation.memberName})',
      );
}

class _SpyErrorReporter implements ErrorReporter {
  final List<String> contexts = <String>[];

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    contexts.add(context);
  }
}

void main() {
  late _CountingShareRepository repo;
  late _SpyErrorReporter reporter;
  late InMemoryAuthRepository auth;
  late ProviderContainer container;

  setUp(() {
    repo = _CountingShareRepository();
    reporter = _SpyErrorReporter();
    auth = InMemoryAuthRepository();
    container = ProviderContainer(
      overrides: <Override>[
        shareRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
        errorReporterProvider.overrideWithValue(reporter),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);
  });

  /// 메인 화면처럼 결과를 쓰지 않고 붙들기만 한다.
  void enterMain() => container.listen<AsyncValue<int>>(
        usedOriginalsReconcileProvider,
        (_, __) {},
      );

  test('진입하면 한 번 돌고, 다시 들어와도 다시 돌지 않는다', () async {
    enterMain();
    await pumpEventQueue();
    expect(repo.calls, 1);
    expect(container.read(usedOriginalsReconcileProvider).valueOrNull, 2);

    enterMain();
    await pumpEventQueue();
    expect(repo.calls, 1, reason: '원본마다 조회가 붙는 작업이라 진입마다 돌리지 않는다');
  });

  test('계정이 바뀌면 새 사용자로 한 번 더 돈다 — 로그아웃 동안에는 돌지 않는다', () async {
    enterMain();
    await pumpEventQueue();
    expect(repo.calls, 1);

    await auth.signOut();
    await pumpEventQueue();
    expect(repo.calls, 1, reason: '미로그인이면 보정할 원본이 없다');
    expect(container.read(usedOriginalsReconcileProvider).valueOrNull, 0);

    await auth.signUp(
      email: 'next-user@keepcon.test',
      password: 'keepcon',
      displayName: '다음 사용자',
    );
    await pumpEventQueue();
    expect(repo.calls, 2);
  });

  test('실패는 화면에 올리지 않고 진단 경로로 남긴다', () async {
    repo.failWith = Exception('네트워크 단절');

    enterMain();
    await pumpEventQueue();

    final AsyncValue<int> state =
        container.read(usedOriginalsReconcileProvider);
    expect(state.hasError, isFalse, reason: '보정은 사용자가 요청한 동작이 아니다');
    expect(state.valueOrNull, 0);
    expect(reporter.contexts, <String>['usedOriginalsReconcileProvider'],
        reason: '조용히 삼키면 보정이 영영 안 도는 결함이 드러나지 않는다');
  });

  testWidgets('MainPage를 띄우면 보정이 한 번 돈다 — 화면의 구독 연결을 고정한다',
      (WidgetTester tester) async {
    // 위 테스트들은 provider를 직접 구독해 MainPage의 `ref.listen` 줄이 빠져도
    // 통과한다. 여기서는 화면을 실제로 띄워 그 연결을 고정한다.
    const User me =
        User(id: 'user-1', email: 'me@keepcon.app', displayName: '나');
    final InMemoryGifticonRepository gifticons = InMemoryGifticonRepository();
    addTearDown(gifticons.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          shareRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(auth),
          errorReporterProvider.overrideWithValue(reporter),
          gifticonRepositoryProvider.overrideWithValue(gifticons),
          sessionUserProvider.overrideWith((_) => Stream<User?>.value(me)),
        ],
        child: const MaterialApp(home: MainPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.calls, 1, reason: '메인 진입이 보정을 트리거해야 한다');
    expect(reporter.contexts, isEmpty);
  });
}
