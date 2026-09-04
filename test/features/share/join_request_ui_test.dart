// 참여 요청 UI의 **보안 전제** 두 축을 고정한다.
//
//  ① 요청자 화면은 승인 전에 그룹을 식별할 정보를 보여주지 않는다. 링크는 유출될 수
//     있으므로, 링크만 쥔 사람이 그룹 이름·멤버를 알 수 있으면 승인제의 절반이 무너진다.
//  ② 대기 목록은 **방장만** 본다. 아직 멤버가 아닌 사람들의 이름이고, 보안 규칙도 같은
//     선을 긋는다 — 화면이 그 선을 넘으면 규칙이 막아 빈 목록이 되거나 오류가 난다.
//
// 두 축 모두 "문구"가 아니라 **무엇이 화면에 있고 없는가**로 검증한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/widgets/my_join_requests_card.dart';
import 'package:keepcon/features/share/widgets/pending_join_requests_section.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

JoinRequest _req(
  String id, {
  JoinRequestStatus status = JoinRequestStatus.pending,
  String displayName = '요청자',
}) =>
    JoinRequest(
      id: id,
      groupId: 'g-secret',
      userId: 'u-$id',
      displayName: displayName,
      avatarEmoji: '🙂',
      requestedAt: DateTime(2026, 1, 1),
      status: status,
    );

/// 두 스트림만 지원하는 스텁. 나머지 호출은 막아 예상 밖 경로를 드러낸다.
class _StubShareRepository implements ShareRepository {
  _StubShareRepository({this.mine = const <JoinRequest>[], this.pending});

  final List<JoinRequest> mine;

  /// `null`이면 스트림을 열어 둔 채 값을 주지 않는다(로딩 상태 재현).
  final List<JoinRequest>? pending;

  /// 목록을 여러 번 방출해야 하는 테스트용(예: 한 건 처리 후 줄어드는 목록).
  final StreamController<List<JoinRequest>> pendingController =
      StreamController<List<JoinRequest>>.broadcast();

  /// `true`면 [pending] 대신 [pendingController]를 흘린다.
  bool useController = false;

  /// `true`면 두 스트림이 에러를 방출한다(인덱스 미배포·규칙 거부 재현).
  bool failStreams = false;

  final List<String> approved = <String>[];
  final List<String> rejected = <String>[];

  @override
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId) {
    if (failStreams) {
      return Stream<List<JoinRequest>>.error(StateError('인덱스 없음'));
    }
    if (useMineController) return mineController.stream;
    return Stream<List<JoinRequest>>.value(mine);
  }

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) {
    if (failStreams) {
      return Stream<List<JoinRequest>>.error(StateError('규칙 거부'));
    }
    if (useController) return pendingController.stream;
    return pending == null
        ? const Stream<List<JoinRequest>>.empty()
        : Stream<List<JoinRequest>>.value(pending!);
  }

  final List<String> cancelled = <String>[];

  /// `mine`을 여러 번 방출해야 하는 테스트용(목록이 줄어드는 경우).
  final StreamController<List<JoinRequest>> mineController =
      StreamController<List<JoinRequest>>.broadcast();
  bool useMineController = false;

  /// `true`면 취소가 즉시 끝난다(게이트를 기다리지 않는다).
  bool cancelImmediately = false;

  /// 완료를 테스트가 제어한다 — '처리 중' 상태를 관측하려면 멈춰 있어야 한다.
  final Completer<void> cancelGate = Completer<void>();

  @override
  Future<void> cancelJoinRequest(String id) async {
    cancelled.add(id);
    if (cancelImmediately) return;
    await cancelGate.future;
  }

  @override
  Future<Group> approveJoinRequest(String id) async {
    approved.add(id);
    throw StateError('정원이 찼습니다'); // 승인 실패 경로를 재현한다
  }

  @override
  Future<JoinRequest> rejectJoinRequest(String id) async {
    rejected.add(id);
    return _req(id, status: JoinRequestStatus.rejected);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('기대하지 않은 호출: ${invocation.memberName}');
}

/// 보고된 라벨만 기록한다.
///
/// 기본 구현은 콘솔에 쓰므로, 이 테스트가 **일부러 태우는** 승인 실패가 스택 트레이스째
/// CI 로그에 쏟아져 진짜 실패와 섞인다. 겸사겸사 배선도 고정한다.
class _SpyErrorReporter implements ErrorReporter {
  final List<String> contexts = <String>[];

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    contexts.add(context);
  }
}

void main() {
  late InMemoryAuthRepository auth;
  late _SpyErrorReporter reporter;

  setUp(() {
    auth = InMemoryAuthRepository();
    reporter = _SpyErrorReporter();
  });
  tearDown(() => auth.dispose());

  Future<void> pump(WidgetTester tester, _StubShareRepository share,
      {required Widget child}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          shareRepositoryProvider.overrideWithValue(share),
          errorReporterProvider.overrideWithValue(reporter),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('요청자 화면', () {
    testWidgets('승인 전에는 그룹을 식별할 정보를 보여주지 않는다', (WidgetTester tester) async {
      final _StubShareRepository share =
          _StubShareRepository(mine: <JoinRequest>[_req('a')]);
      await pump(tester, share, child: const MyJoinRequestsCard());

      expect(find.text('보낸 참여 요청'), findsOneWidget);
      expect(find.text('대기 중'), findsOneWidget);
      // groupId가 화면 어디에도 새지 않는다 — 이 카드의 존재 이유다.
      expect(find.textContaining('g-secret'), findsNothing);
    });

    testWidgets('거절도 남는다 — 비멤버는 그룹 알림을 못 읽으므로 유일한 통보 경로다',
        (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        mine: <JoinRequest>[_req('a', status: JoinRequestStatus.rejected)],
      );
      await pump(tester, share, child: const MyJoinRequestsCard());

      expect(find.text('거절됨'), findsOneWidget);
      // 거절된 요청에는 취소 버튼이 없다(이미 끝난 결정이다).
      expect(find.widgetWithText(TextButton, '취소'), findsNothing);
    });

    testWidgets('승인된 요청은 그룹 목록에 나타나므로 여기서 중복 표시하지 않는다',
        (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        mine: <JoinRequest>[_req('a', status: JoinRequestStatus.approved)],
      );
      await pump(tester, share, child: const MyJoinRequestsCard());

      // 표시할 것이 없으면 카드 자체를 그리지 않는다.
      expect(find.text('보낸 참여 요청'), findsNothing);
    });
  });

  testWidgets('요청자 카드도 에러를 삼키지 않는다 — 거절 통보의 유일한 경로다',
      (WidgetTester tester) async {
    final _StubShareRepository share = _StubShareRepository()
      ..failStreams = true;
    await pump(tester, share, child: const MyJoinRequestsCard());

    expect(find.text('보낸 참여 요청을 불러오지 못했어요.'), findsOneWidget);
  });

  testWidgets("요청자 카드의 '다시 시도'가 원천을 재구독한다", (WidgetTester tester) async {
    // 배너를 띄우는 것만으로는 배선의 절반만 고정된다 — 버튼이 아무 일도 하지 않아도
    // 문구 단언은 통과한다(뮤테이션으로 확인). 탭 → 복구까지 눌러 본다.
    final _StubShareRepository share =
        _StubShareRepository(mine: <JoinRequest>[_req('a')])
          ..failStreams = true;
    await pump(tester, share, child: const MyJoinRequestsCard());
    expect(find.text('보낸 참여 요청을 불러오지 못했어요.'), findsOneWidget);

    share.failStreams = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('보낸 참여 요청을 불러오지 못했어요.'), findsNothing);
    expect(find.text('보낸 참여 요청'), findsOneWidget);
  });

  testWidgets('취소 중에는 취소 버튼이 잠긴다 — 두 번 누르면 두 번 호출된다',
      (WidgetTester tester) async {
    final _StubShareRepository share =
        _StubShareRepository(mine: <JoinRequest>[_req('a')]);
    await pump(tester, share, child: const MyJoinRequestsCard());

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pump();

    // 첫 탭으로 호출은 한 번. 버튼은 잠겨 있어야 한다.
    expect(share.cancelled, <String>['a']);
    final TextButton btn = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '취소 중…'),
    );
    expect(btn.onPressed, isNull, reason: '취소 중인데 버튼이 열려 있다 — 두 번째 탭이 중복 호출된다');

    share.cancelGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('한 건을 취소해도 남은 요청의 취소 버튼이 잠기지 않는다', (WidgetTester tester) async {
    // key가 없으면 목록이 [a,b]→[b]로 줄 때 index 0의 State가 재사용돼 b가 a의
    // `_busy = true`를 물려받는다 — 형제 `_PendingRow`에서 실측한 사고와 같다.
    final _StubShareRepository share = _StubShareRepository()
      ..useMineController = true
      ..cancelImmediately = true;
    addTearDown(share.mineController.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          shareRepositoryProvider.overrideWithValue(share),
          errorReporterProvider.overrideWithValue(reporter),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MyJoinRequestsCard()),
        ),
      ),
    );
    await tester.pump();

    share.mineController.add(<JoinRequest>[_req('a'), _req('b')]);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '취소'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(TextButton, '취소').first);
    await tester.pumpAndSettle();
    share.mineController.add(<JoinRequest>[_req('b')]);
    await tester.pumpAndSettle();

    final TextButton left =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '취소'));
    expect(left.onPressed, isNotNull, reason: '남은 행이 앞 행의 _busy 를 물려받았다');
  });

  group('방장 승인 목록', () {
    testWidgets('대기 요청을 이름과 함께 보여준다', (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      );
      await pump(tester, share,
          child: const PendingJoinRequestsSection(groupId: 'g-secret'));

      expect(find.text('참여 요청'), findsOneWidget);
      expect(find.text('지원'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '승인'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '거절'), findsOneWidget);
    });

    testWidgets('로딩을 빈 목록으로 접지 않는다 — "요청 없음"과 구분되어야 한다',
        (WidgetTester tester) async {
      // 값을 주지 않는 스트림 = 로딩 지속.
      final _StubShareRepository share = _StubShareRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authRepositoryProvider.overrideWithValue(auth),
            shareRepositoryProvider.overrideWithValue(share),
            errorReporterProvider.overrideWithValue(reporter),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PendingJoinRequestsSection(groupId: 'g-secret'),
            ),
          ),
        ),
      );
      await tester.pump();

      // 스피너가 떠야 한다. 빈 SizedBox로 접히면 방장이 대기자를 못 보고 지나간다.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('승인 실패는 정원을 이유로 알린다 — 계약상 정원은 이 시점에 검사된다',
        (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      );
      await pump(tester, share,
          child: const PendingJoinRequestsSection(groupId: 'g-secret'));

      await tester.tap(find.widgetWithText(FilledButton, '승인'));
      await tester.pumpAndSettle();

      expect(share.approved, <String>['a']);
      expect(find.textContaining('정원이 찼거나'), findsOneWidget);
      expect(reporter.contexts,
          <String>['PendingJoinRequests.approveJoinRequest']);
    });

    testWidgets('거절은 rejectJoinRequest를 부른다', (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      );
      await pump(tester, share,
          child: const PendingJoinRequestsSection(groupId: 'g-secret'));

      await tester.tap(find.widgetWithText(TextButton, '거절'));
      await tester.pumpAndSettle();

      expect(share.rejected, <String>['a']);
      expect(share.approved, isEmpty); // 두 버튼이 뒤바뀌지 않았다
    });

    testWidgets('한 건을 처리해도 남은 요청의 버튼이 잠기지 않는다', (WidgetTester tester) async {
      // key가 없으면 목록이 [A,B]→[B]로 줄 때 Flutter가 index 0의 State를 재사용해
      // B가 A의 `_busy = true`를 물려받는다 — 방장이 두 번째 요청을 영영 처리 못 한다.
      final _StubShareRepository share = _StubShareRepository()
        ..useController = true;
      addTearDown(share.pendingController.close);
      // 공용 pump는 pumpAndSettle을 쓰는데, 첫 방출 전에는 스피너가 계속 돌아
      // 정착하지 않는다 — 여기서는 구독만 시키고 프레임 단위로 진행한다.
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authRepositoryProvider.overrideWithValue(auth),
            shareRepositoryProvider.overrideWithValue(share),
            errorReporterProvider.overrideWithValue(reporter),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PendingJoinRequestsSection(groupId: 'g-secret'),
            ),
          ),
        ),
      );
      await tester.pump();

      share.pendingController.add(<JoinRequest>[
        _req('a', displayName: '가나'),
        _req('b', displayName: '다라'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('가나'), findsOneWidget);

      // 첫 행 거절 → 목록이 한 건으로 줄어든다.
      await tester.tap(find.widgetWithText(TextButton, '거절').first);
      await tester.pumpAndSettle();
      share.pendingController.add(<JoinRequest>[_req('b', displayName: '다라')]);
      await tester.pumpAndSettle();

      expect(find.text('다라'), findsOneWidget);
      final FilledButton approve =
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '승인'));
      expect(approve.onPressed, isNotNull,
          reason: '남은 행의 승인 버튼이 앞 행의 처리 중 상태를 물려받았다');
    });

    testWidgets('에러를 빈 목록으로 접지 않는다 — 방장이 대기자를 지나치면 안 된다',
        (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository()
        ..failStreams = true;
      await pump(tester, share,
          child: const PendingJoinRequestsSection(groupId: 'g-secret'));

      expect(find.text('참여 요청을 불러오지 못했어요.'), findsOneWidget);
    });

    testWidgets("'다시 시도'가 원천을 재구독한다", (WidgetTester tester) async {
      // 형제(요청자 카드)와 같은 이유 — 문구만 보면 죽은 버튼도 통과한다.
      final _StubShareRepository share =
          _StubShareRepository(pending: <JoinRequest>[_req('a')])
            ..failStreams = true;
      await pump(tester, share,
          child: const PendingJoinRequestsSection(groupId: 'g-secret'));
      expect(find.text('참여 요청을 불러오지 못했어요.'), findsOneWidget);

      share.failStreams = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('참여 요청을 불러오지 못했어요.'), findsNothing);
      expect(find.text('참여 요청'), findsOneWidget);
    });

    testWidgets('요청이 없으면 아무것도 그리지 않는다', (WidgetTester tester) async {
      final _StubShareRepository share =
          _StubShareRepository(pending: const <JoinRequest>[]);
      await pump(tester, share,
          child: const PendingJoinRequestsSection(groupId: 'g-secret'));

      expect(find.text('참여 요청'), findsNothing);
    });
  });
}
