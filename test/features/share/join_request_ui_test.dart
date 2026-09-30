// 참여 요청 UI의 **보안 전제** 두 축을 고정한다.
//
//  ① 요청자 화면은 승인 전에 그룹을 식별할 정보를 보여주지 않는다. 링크는 유출될 수
//     있으므로, 링크만 쥔 사람이 그룹 이름·멤버를 알 수 있으면 승인제의 절반이 무너진다.
//  ② 대기 목록은 **방장만** 본다. 아직 멤버가 아닌 사람들의 이름이고, 보안 규칙도 같은
//     선을 긋는다 — 화면이 그 선을 넘으면 규칙이 막아 빈 목록이 되거나 오류가 난다.
//
// 두 축 모두 "문구"가 아니라 **무엇이 화면에 있고 없는가**로 검증한다.
//
// 방장 쪽 목록은 그룹 상세 안의 인라인 섹션도, 전체 화면 push도 아니라 **모달 팝업**
// (`JoinRequestsDialog`)이다. 진입점(그룹 상세의 '승인요청목록' 버튼)과 뱃지의 로딩·에러
// 규약은 `join_requests_entry_test.dart`가, 팝업의 스크림·크기·닫기는
// `join_requests_dialog_test.dart`가 따로 고정한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/widgets/join_requests_dialog.dart';
import 'package:keepcon/features/share/widgets/my_join_requests_card.dart';
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

  /// 승인요청목록 팝업이 **방장 여부 이중 방어**를 위해 `myGroupsProvider`를 거쳐
  /// 내 그룹을 watch한다. noSuchMethod에 맡기면 그룹 축이 항상 에러가 되어
  /// "그룹을 안다"가 전제인 비방장 안내를 시험할 길이 없다. 기본은 빈 목록
  /// (= 그룹을 모름 → 막지 않고 통과)이고, 필요한 테스트만 채운다.
  List<Group> groups = const <Group>[];

  @override
  Stream<List<Group>> watchGroups(String userId) =>
      Stream<List<Group>>.value(groups);

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

  /// 설정하면 승인이 이 게이트가 풀릴 때까지 **공중에 떠 있다가** 실패한다 —
  /// 왕복 중 행이 목록에서 빠지는 경우를 재현할 때 쓴다.
  Completer<void>? approveGate;

  @override
  Future<Group> approveJoinRequest(String id) async {
    approved.add(id);
    if (approveGate != null) await approveGate!.future;
    throw StateError('정원이 찼습니다'); // 승인 실패 경로를 재현한다
  }

  /// [approveGate]의 **성공** 짝. 승인 스텁은 항상 던지므로, "팝업이 닫힌 뒤 성공이
  /// 돌아오는" 칸은 거절로만 잴 수 있다.
  Completer<void>? rejectGate;

  @override
  Future<JoinRequest> rejectJoinRequest(String id) async {
    rejected.add(id);
    if (rejectGate != null) await rejectGate!.future;
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

  /// 승인요청목록을 **팝업으로** 띄운다 — 호스트 화면(실제로는 그룹 상세)을 두고 그 위에
  /// 연다. 전체 화면 push였다면 호스트가 트리에서 사라진다는 것이 이 구조의 요점이고,
  /// 그 축은 `join_requests_entry_test.dart`가 진짜 그룹 상세로 못박는다.
  Future<void> pumpDialog(
    WidgetTester tester,
    _StubShareRepository share, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authRepositoryProvider.overrideWithValue(auth),
          shareRepositoryProvider.overrideWithValue(share),
          errorReporterProvider.overrideWithValue(reporter),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showJoinRequestsDialog(ctx, 'g-secret'),
                  child: const Text('호스트 화면'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('호스트 화면'));
    if (settle) {
      await tester.pumpAndSettle();
      return;
    }
    // 첫 방출 전에는 스피너가 계속 돌아 정착하지 않는다 — 팝업 전환만 끝내고 멈춘다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('취소 도중 행이 목록에서 빠져도 실패의 진단이 남는다', (WidgetTester tester) async {
    // 왕복 중 방장이 승인하면 그 요청은 목록에서 걸러져 행이 폐기된다. 그때
    // `reportHandledFailure(ref, …)`는 죽은 `ref`에서 던져 조용히 아무것도 남기지
    // 않는다 — 리포터를 `await` 전에 잡아 두지 않았다면 이 단언이 빈 목록으로 깨진다.
    final _StubShareRepository share = _StubShareRepository()
      ..useMineController = true;
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
    share.mineController.add(<JoinRequest>[_req('a')]);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pump(); // 취소는 공중에 떠 있다.

    // 그 사이 방장이 승인 — 승인된 요청은 카드에서 걸러지므로 행이 사라진다.
    share.mineController
        .add(<JoinRequest>[_req('a', status: JoinRequestStatus.approved)]);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '취소 중…'), findsNothing,
        reason: '행이 폐기된 것이 이 테스트의 전제');

    share.cancelGate.completeError(StateError('이미 처리된 요청'));
    await tester.pumpAndSettle();

    expect(reporter.contexts, <String>['MyJoinRequestsCard.cancelJoinRequest']);
    // 안내 자원도 `await` 전에 잡혀 있어 사용자 안내는 그대로 뜬다.
    expect(find.text('요청을 취소하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  group('방장 승인 목록(JoinRequestsDialog)', () {
    testWidgets('대기 요청을 이름과 함께 보여준다', (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      );
      await pumpDialog(tester, share);

      // 화면 제목(AppBar)이 아니라 **팝업 헤더**다 — 목록이 모달로 옮겨졌다.
      expect(find.text('승인요청목록'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('대기 중 1명'), findsOneWidget);
      expect(find.text('지원'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '승인'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '거절'), findsOneWidget);
    });

    testWidgets('승인이 왼쪽, 거절이 오른쪽이다', (WidgetTester tester) async {
      // 순서가 뒤집히면 **같은 자리를 누르던 손이 반대 결정을 보낸다**. 승인은 멤버
      // 추가, 거절은 요청자에게 남는 기록이라 둘 다 가볍게 되돌릴 수 없다. Material
      // 관례(주 동작을 오른쪽 끝에)와 반대 방향이라 무심코 '고쳐질' 위험이 특히 크므로,
      // 문구 존재가 아니라 **x 좌표**로 못박는다.
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      );
      await pumpDialog(tester, share);

      final double approveX =
          tester.getCenter(find.widgetWithText(FilledButton, '승인')).dx;
      final double rejectX =
          tester.getCenter(find.widgetWithText(TextButton, '거절')).dx;
      expect(approveX, lessThan(rejectX));
    });

    testWidgets('로딩을 빈 목록으로 접지 않는다 — "요청 없음"과 구분되어야 한다',
        (WidgetTester tester) async {
      // 값을 주지 않는 스트림 = 로딩 지속.
      final _StubShareRepository share = _StubShareRepository();
      await pumpDialog(tester, share, settle: false);

      // 스피너가 떠야 한다. 빈 SizedBox로 접히면 방장이 대기자를 못 보고 지나간다.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('승인 실패는 정원을 이유로 알린다 — 계약상 정원은 이 시점에 검사된다',
        (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      );
      await pumpDialog(tester, share);

      await tester.tap(find.widgetWithText(FilledButton, '승인'));
      await tester.pumpAndSettle();

      expect(share.approved, <String>['a']);
      // 실패 문구는 **팝업 안**에 뜬다 — 스낵바는 배리어에 덮여 바랜다(픽셀 실측).
      expect(
          find.descendant(
              of: find.byType(Dialog),
              matching: find.textContaining('정원이 찼거나')),
          findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
          reporter.contexts, <String>['JoinRequestsDialog.approveJoinRequest']);
    });

    testWidgets('거절은 rejectJoinRequest를 부른다', (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      );
      await pumpDialog(tester, share);

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
      // 첫 방출 전에는 스피너가 계속 돌아 정착하지 않는다 — 구독만 시키고 진행한다.
      await pumpDialog(tester, share, settle: false);

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

    testWidgets('승인 도중 행이 목록에서 빠져도 실패의 진단과 안내가 남는다',
        (WidgetTester tester) async {
      // 대기 목록은 `status == pending` 질의라, 왕복 중 요청자가 취소하거나 다른
      // 기기에서 결정하면 행이 폐기된다. 형제(요청자 카드)와 같은 이유로, 리포터를
      // `await` 전에 잡아 두지 않았다면 보고가 조용히 빈다. 안내도 마찬가지인데,
      // 결과 배너는 행이 아니라 **팝업**이 소유하므로 행이 죽어도 살아 있다.
      final _StubShareRepository share = _StubShareRepository()
        ..useController = true
        ..approveGate = Completer<void>();
      addTearDown(share.pendingController.close);
      await pumpDialog(tester, share, settle: false);
      share.pendingController.add(<JoinRequest>[_req('a', displayName: '지원')]);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '승인'));
      await tester.pump(); // 승인은 공중에 떠 있다.

      // 그 사이 요청자가 취소 — 대기 목록에서 빠진다.
      share.pendingController.add(const <JoinRequest>[]);
      await tester.pumpAndSettle();
      expect(find.text('지원'), findsNothing, reason: '행이 폐기된 것이 이 테스트의 전제');

      share.approveGate!.complete();
      await tester.pumpAndSettle();

      expect(share.approved, <String>['a']);
      expect(
          reporter.contexts, <String>['JoinRequestsDialog.approveJoinRequest']);
      expect(find.textContaining('정원이 찼거나'), findsOneWidget);
    });

    testWidgets('팝업이 닫힌 뒤에 실패가 돌아오면 스낵바로 알린다', (WidgetTester tester) async {
      // 배리어 탭으로 언제든 닫을 수 있으므로, 결과가 팝업보다 늦게 오는 창이 있다.
      // 그때 조용히 사라지면 방장은 승인이 된 줄 안다. 팝업이 없으면 배리어도 없으니
      // 스낵바가 가려지지 않는다 — 이 경로에서만 스낵바를 쓴다.
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      )..approveGate = Completer<void>();
      await pumpDialog(tester, share);

      await tester.tap(find.widgetWithText(FilledButton, '승인'));
      await tester.pump();

      // 배리어를 탭해 팝업을 닫는다(요청은 아직 공중에 있다).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing, reason: '팝업이 닫힌 것이 이 테스트의 전제');

      share.approveGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('정원이 찼거나'), findsOneWidget);
    });

    testWidgets('팝업이 닫힌 뒤에 성공이 돌아와도 스낵바로 알린다', (WidgetTester tester) async {
      // 실패 칸만 고정해 두면 "성공은 목록이 갱신되니 안 알려도 된다"는 단순화가 조용히
      // 통과한다(뮤테이션으로 실증됨 — 성공 경로를 버려도 테스트가 전부 green이었다).
      // 그때 방장은 처리가 됐는지 알 길이 없다: 팝업도 없고 스낵바도 없다.
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      )..rejectGate = Completer<void>();
      await pumpDialog(tester, share);

      await tester.tap(find.widgetWithText(TextButton, '거절'));
      await tester.pump();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing, reason: '팝업이 닫힌 것이 이 테스트의 전제');

      share.rejectGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('참여 요청을 거절했어요.'), findsOneWidget);
    });

    testWidgets('에러를 빈 목록으로 접지 않는다 — 방장이 대기자를 지나치면 안 된다',
        (WidgetTester tester) async {
      final _StubShareRepository share = _StubShareRepository()
        ..failStreams = true;
      await pumpDialog(tester, share);

      expect(find.text('참여 요청을 불러오지 못했어요.'), findsOneWidget);
    });

    testWidgets("'다시 시도'가 원천을 재구독한다", (WidgetTester tester) async {
      // 형제(요청자 카드)와 같은 이유 — 문구만 보면 죽은 버튼도 통과한다.
      final _StubShareRepository share =
          _StubShareRepository(pending: <JoinRequest>[_req('a')])
            ..failStreams = true;
      await pumpDialog(tester, share);
      expect(find.text('참여 요청을 불러오지 못했어요.'), findsOneWidget);

      share.failStreams = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('참여 요청을 불러오지 못했어요.'), findsNothing);
      expect(find.text('대기 중 1명'), findsOneWidget);
    });

    testWidgets('요청이 0건이어도 빈 팝업이 아니라 안내를 보여준다', (WidgetTester tester) async {
      // 인라인 섹션이던 시절에는 0건이면 통째로 사라졌다(`SizedBox.shrink`).
      // 사용자가 스스로 연 팝업에서 그러면 빈 상자만 남는다.
      final _StubShareRepository share =
          _StubShareRepository(pending: const <JoinRequest>[]);
      await pumpDialog(tester, share);

      expect(find.text('대기 중인 참여 요청이 없어요.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '승인'), findsNothing);
    });

    testWidgets('마지막 한 건을 처리해 0건이 되어도 팝업은 닫히지 않는다',
        (WidgetTester tester) async {
      // 자동으로 닫으면 ①방금 띄운 결과 배너가 함께 사라지고 ②"닫힘"이 방장의 행동이
      // 아니라 데이터 변화가 된다(다른 기기가 처리해도 팝업이 제멋대로 사라진다).
      final _StubShareRepository share = _StubShareRepository()
        ..useController = true;
      addTearDown(share.pendingController.close);
      await pumpDialog(tester, share, settle: false);
      share.pendingController.add(<JoinRequest>[_req('a', displayName: '지원')]);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '거절'));
      await tester.pumpAndSettle();
      share.pendingController.add(const <JoinRequest>[]);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('대기 중인 참여 요청이 없어요.'), findsOneWidget);
      // 결과도 함께 남는다 — 사라지면 방장은 처리됐는지 알 수 없다.
      expect(find.text('참여 요청을 거절했어요.'), findsOneWidget);
    });

    testWidgets('방장이 아니면 목록 대신 사유를 설명한다 — 재시도는 틀린 처방이다',
        (WidgetTester tester) async {
      // 진입점이 방장에게만 보이지만 팝업도 한 겹 막는다. 비방장이 닿으면 대기 목록은
      // 보안 규칙에 막혀 에러가 되고, 그 자리의 '다시 시도'는 **영원히 성공할 수 없다**.
      final _StubShareRepository share = _StubShareRepository(
        pending: <JoinRequest>[_req('a', displayName: '지원')],
      )..groups = <Group>[
          Group(
            id: 'g-secret',
            name: '가족',
            emoji: '🏠',
            inviteToken: 'tok',
            members: <GroupMember>[
              const GroupMember(
                userId: 'someone-else',
                displayName: '방장',
                avatarEmoji: '👑',
                role: MemberRole.owner,
              ),
              GroupMember(
                userId: InMemoryAuthRepository.defaultUser.id,
                displayName: InMemoryAuthRepository.defaultUser.displayName,
                avatarEmoji: '🙂',
                role: MemberRole.member,
              ),
            ],
          ),
        ];
      await pumpDialog(tester, share);

      expect(find.text('참여 요청은 방장만 볼 수 있어요.'), findsOneWidget);
      expect(find.text('지원'), findsNothing);
      expect(find.text('다시 시도'), findsNothing);
    });
  });
}
