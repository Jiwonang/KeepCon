// 참여 요청 UI의 **보안 전제** 두 축을 고정한다.
//
//  ① 요청자 화면은 승인 전에 그룹을 식별할 정보를 보여주지 않는다. 링크는 유출될 수
//     있으므로, 링크만 쥔 사람이 그룹 이름·멤버를 알 수 있으면 승인제의 절반이 무너진다.
//  ② 대기 목록은 **방장만** 본다. 아직 멤버가 아닌 사람들의 이름이고, 보안 규칙도 같은
//     선을 긋는다 — 화면이 그 선을 넘으면 규칙이 막아 빈 목록이 되거나 오류가 난다.
//
// 두 축 모두 "문구"가 아니라 **무엇이 화면에 있고 없는가**로 검증한다.
library;

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

  final List<String> approved = <String>[];
  final List<String> rejected = <String>[];

  @override
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId) =>
      Stream<List<JoinRequest>>.value(mine);

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) =>
      pending == null
          ? const Stream<List<JoinRequest>>.empty()
          : Stream<List<JoinRequest>>.value(pending!);

  @override
  Future<void> cancelJoinRequest(String id) async {}

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

    testWidgets('요청이 없으면 아무것도 그리지 않는다', (WidgetTester tester) async {
      final _StubShareRepository share =
          _StubShareRepository(pending: const <JoinRequest>[]);
      await pump(tester, share,
          child: const PendingJoinRequestsSection(groupId: 'g-secret'));

      expect(find.text('참여 요청'), findsNothing);
    });
  });
}
