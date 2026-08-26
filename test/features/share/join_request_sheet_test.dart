// 초대 링크로 들어온 사람은 **합류하지 않고 요청만 한다** — 그 전환의 회귀 고정.
//
// 이 시트는 원래 `joinGroup(token)`을 불러 **즉시 멤버로 만들었다.** 링크가 유출되면
// 그대로 참여 경로가 되므로, 링크 소지를 "참여 자격"에서 "**요청** 자격"으로 낮춘 것이
// 이번 변경의 핵심이다. 그래서 여기서 고정하는 것은 화면 문구가 아니라 **어느 저장소
// 메서드를 부르는가**이다 — 문구만 바꾸고 `joinGroup`을 그대로 두면 승인제는 장식이 된다.
//
// 함께 고정하는 것:
//  - 승인 전 화면에 **그룹을 식별할 정보가 없다**(이름·이모지·멤버 수). 링크만 쥔 사람이
//    그룹 정보를 알 수 있으면 승인제의 절반이 무너진다.
//  - 실패 안내에 **정원을 말하지 않는다**. 계약상 정원 검사는 승인 시점이라 요청 단계의
//    실패 사유가 아니다(대기자가 자리를 선점하지 못하게 한 설계).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/widgets/share_sheets.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// 호출된 메서드만 기록하는 스텁.
///
/// [noSuchMethod]로 나머지를 막아 **예상 밖 경로가 조용히 통과하지 않게** 한다 —
/// 옛 `joinGroup`은 v3.8에서 **계약에서 삭제**됐으므로, 그 경로로 되돌아가는 회귀는
/// 이제 이 스파이가 아니라 **컴파일러가** 막는다(없는 메서드는 부를 수 없다).
class _SpyShareRepository implements ShareRepository {
  _SpyShareRepository({this.fail = false, this.expired = false});

  final bool fail;

  /// 만료로 거부한다 — 화면이 이 실패만 **구별해서** 안내해야 한다.
  final bool expired;

  final List<String> requestedTokens = <String>[];

  @override
  Future<JoinRequest> requestToJoin(String inviteToken) async {
    requestedTokens.add(inviteToken);
    if (expired) throw InviteExpiredException(inviteToken);
    if (fail) throw StateError('초대가 유효하지 않습니다');
    return JoinRequest(
      id: 'g1_u1',
      groupId: 'g1',
      userId: 'u1',
      displayName: '나',
      avatarEmoji: '🙂',
      requestedAt: DateTime(2026, 1, 1),
      status: JoinRequestStatus.pending,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        '이 테스트가 기대하지 않은 호출: ${invocation.memberName}',
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
  Future<void> pumpSheet(
    WidgetTester tester,
    _SpyShareRepository share,
    _SpyErrorReporter reporter,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          shareRepositoryProvider.overrideWithValue(share),
          errorReporterProvider.overrideWithValue(reporter),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showJoinGroupSheet(context, initialToken: 'TOKEN123'),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('링크로 열린 시트는 requestToJoin을 부른다(즉시 합류가 아니다)',
      (WidgetTester tester) async {
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tester.tap(find.widgetWithText(ElevatedButton, '참여 요청 보내기'));
    await tester.pumpAndSettle();

    expect(share.requestedTokens, <String>['TOKEN123']);
    // 옛 `joinGroup` 경로로의 회귀는 계약에서 그 메서드가 사라져 컴파일이 막는다
    // (v3.8). 여기서는 새 경로가 실제로 불리는지만 본다.
  });

  testWidgets('요청 후 화면은 승인 대기만 알리고 그룹을 식별할 정보를 담지 않는다',
      (WidgetTester tester) async {
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tester.tap(find.widgetWithText(ElevatedButton, '참여 요청 보내기'));
    await tester.pumpAndSettle();

    expect(find.text('참여 요청을 보냈어요'), findsOneWidget);
    expect(
      find.textContaining('방장이 승인하기 전까지는 참여할 수 없어요'),
      findsOneWidget,
    );
    // "참여했다"고 오해할 문구가 남아 있으면 안 된다.
    expect(find.textContaining('그룹에 참여했어요'), findsNothing);
    // 요청 결과가 화면으로 새지 않는지 — **스텁이 실제로 돌려주는 값**으로 고정한다.
    // (`groupId: 'g1'`, `id: 'g1_u1'` — Firestore 문서 id에 groupId가 박히므로 둘 다 걸린다.)
    // 없는 문자열을 찾으면 항진명제가 되어 회귀를 못 잡는다.
    expect(find.textContaining('g1'), findsNothing);
  });

  testWidgets('요청이 실패하면 이유를 알리되 정원은 말하지 않는다', (WidgetTester tester) async {
    final _SpyShareRepository share = _SpyShareRepository(fail: true);
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tester.tap(find.widgetWithText(ElevatedButton, '참여 요청 보내기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('요청을 보낼 수 없어요'), findsOneWidget);
    // 정원 검사는 승인 시점이라 요청 실패의 사유가 아니다(계약).
    expect(find.textContaining('정원'), findsNothing);
    // 대기 화면으로 넘어가지 않는다 — 실패했는데 접수된 것처럼 보이면 안 된다.
    expect(find.text('참여 요청을 보냈어요'), findsNothing);
    // 실패 원인은 개발자에게 남는다.
    expect(reporter.contexts, <String>['JoinGroupSheet.requestToJoin']);
  });

  testWidgets('만료는 구별해서 알린다 — "만료된 초대코드"라고 말한다', (WidgetTester tester) async {
    // 초대코드는 5분이라 만료가 **정상 경로**다. 다른 실패와 뭉뚱그리면 사용자는
    // 코드를 잘못 들었는지 시간이 지난 것인지 알 수 없어 같은 코드를 계속 다시
    // 입력한다. 만료라고 말해 주면 다음 행동이 하나로 정해진다(재발급 요청).
    final _SpyShareRepository share = _SpyShareRepository(expired: true);
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tester.tap(find.widgetWithText(ElevatedButton, '참여 요청 보내기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('만료된 초대코드'), findsOneWidget);
    // 뭉뚱그린 문구로 되돌아가면 이 단언이 잡는다.
    expect(find.textContaining('잘못됐을 수 있'), findsNothing);
    expect(find.text('참여 요청을 보냈어요'), findsNothing);
    expect(reporter.contexts, <String>['JoinGroupSheet.requestToJoin']);
  });

  testWidgets('만료가 아닌 실패는 만료라고 말하지 않는다', (WidgetTester tester) async {
    // 반대 방향도 고정한다 — "없는 코드"를 "만료됐다"고 말하면 존재한 적 없는
    // 그룹을 기다리게 만든다.
    final _SpyShareRepository share = _SpyShareRepository(fail: true);
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tester.tap(find.widgetWithText(ElevatedButton, '참여 요청 보내기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('만료'), findsNothing);
  });
}
