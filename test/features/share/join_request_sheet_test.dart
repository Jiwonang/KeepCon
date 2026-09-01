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
//  - 딥링크로 열린 **확인 모드는 링크 토큰을 화면에 싣지 않는다**. 22자 base64url은
//    사용자가 읽을 값도 고칠 값도 아니라, 입력란에 담으면 실수로 지울 여지만 생긴다.
//  - **만료 안내는 자격증명의 모양을 추측하지 않는다.** 링크와 코드는 다음 행동이 다른데
//    (링크 재발급 vs 새 코드 요청), v3.0 이전 링크 토큰이 6자리 숫자라 모양으로 가르면
//    멀쩡한 링크가 '만료된 코드'로 안내된다. 종류는 저장소가 폴백 조회로 확정해
//    `InviteExpiredException.isCode`로 실어 보내고, 화면은 그것을 그대로 쓴다. 그래서
//    이 파일의 스파이도 종류를 **지정받는다** — 스파이가 모양으로 판정하면 화면의
//    오분류가 스파이의 같은 오분류에 가려 green으로 지나간다.
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
  _SpyShareRepository({
    this.fail = false,
    this.expiredKinds = const <String, bool>{},
  });

  final bool fail;

  /// 만료로 거부할 자격증명 → **저장소가 확정한 종류**(`true` = 6자리 초대코드,
  /// `false` = 링크 토큰). 표에 없는 자격증명은 만료가 아니다.
  ///
  /// **bool 플래그 하나가 아니라 표인 것이 요점이다.** 실제 저장소는 코드 조회 문서를
  /// 먼저 보고 없으면 링크로 폴백해 종류를 확정하므로, 그 판정은 자격증명의 **모양과
  /// 독립**이다 — 6자리 링크 토큰에서 둘이 갈린다. 스파이가 종류를 지정받아야 화면이
  /// 모양을 다시 추측하는지 아닌지를 테스트가 가를 수 있다. 스파이도 모양으로
  /// 판정하면 화면의 오분류가 스파이의 같은 오분류에 가려 green으로 지나간다.
  ///
  /// 자격증명별인 이유는 한 시트가 **두 종류를 차례로** 보낼 수 있기 때문이다 —
  /// 만료된 링크로 실패한 뒤 6자리 코드로 갈아타는 경로가 그것이고, 값 하나로는
  /// 그 두 번째 응답을 다르게 줄 수 없다.
  final Map<String, bool> expiredKinds;

  final List<String> requestedTokens = <String>[];

  @override
  Future<JoinRequest> requestToJoin(String inviteToken) async {
    requestedTokens.add(inviteToken);
    final bool? isCode = expiredKinds[inviteToken];
    if (isCode != null) {
      throw InviteExpiredException(inviteToken, isCode: isCode);
    }
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

/// 두 모드가 공유하는 CTA. 하는 일이 하나라 문구도 하나다.
const String _cta = '그룹 참여 요청하기';

void main() {
  /// 시트를 띄운다. [linkToken]이 있으면 딥링크 진입(확인 모드), `null`이면 공유 탭의
  /// 참여 버튼으로 연 것(입력 모드)과 같다.
  Future<void> pumpSheet(
    WidgetTester tester,
    _SpyShareRepository share,
    _SpyErrorReporter reporter, {
    String? linkToken = 'TOKEN123',
  }) async {
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
                      showJoinGroupSheet(context, initialToken: linkToken),
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

  Future<void> tapCta(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, _cta));
    await tester.pumpAndSettle();
  }

  testWidgets('링크로 열린 시트는 requestToJoin을 부른다(즉시 합류가 아니다)',
      (WidgetTester tester) async {
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tapCta(tester);

    expect(share.requestedTokens, <String>['TOKEN123']);
    // 옛 `joinGroup` 경로로의 회귀는 계약에서 그 메서드가 사라져 컴파일이 막는다
    // (v3.8). 여기서는 새 경로가 실제로 불리는지만 본다.
  });

  testWidgets('확인 모드는 링크 토큰을 보여주지도 입력란을 두지도 않는다', (WidgetTester tester) async {
    // 딥링크로 온 사람에게 토큰은 읽을 값도 고칠 값도 아니다. 입력란에 담으면
    // autofocus로 키보드가 뜨고, 전체선택 한 번에 토큰이 날아간다.
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    expect(find.text('TOKEN123'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    // 그래도 보내는 값은 그 토큰이다 — 화면에 없을 뿐 state가 들고 있다.
    await tapCta(tester);
    expect(share.requestedTokens, <String>['TOKEN123']);
  });

  testWidgets('입력 모드는 입력한 값을 자격증명으로 보낸다', (WidgetTester tester) async {
    // 공유 탭에서 연 경로 — 방장이 불러 준 6자리 코드를 손으로 넣는다.
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter, linkToken: null);

    await tester.enterText(find.byType(TextField), '482913');
    await tapCta(tester);

    expect(share.requestedTokens, <String>['482913']);
  });

  testWidgets('요청 후 화면은 승인 대기만 알리고 그룹을 식별할 정보를 담지 않는다',
      (WidgetTester tester) async {
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tapCta(tester);

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

    await tapCta(tester);

    expect(find.textContaining('요청을 보낼 수 없어요'), findsOneWidget);
    // 정원 검사는 승인 시점이라 요청 실패의 사유가 아니다(계약).
    expect(find.textContaining('정원'), findsNothing);
    // 대기 화면으로 넘어가지 않는다 — 실패했는데 접수된 것처럼 보이면 안 된다.
    expect(find.text('참여 요청을 보냈어요'), findsNothing);
    // 실패 원인은 개발자에게 남는다.
    expect(reporter.contexts, <String>['JoinGroupSheet.requestToJoin']);
  });

  testWidgets('만료된 **코드**는 코드 재발급을 안내한다', (WidgetTester tester) async {
    // 초대코드는 5분이라 만료가 **정상 경로**다. 다른 실패와 뭉뚱그리면 사용자는
    // 코드를 잘못 들었는지 시간이 지난 것인지 알 수 없어 같은 코드를 계속 다시
    // 입력한다. 만료라고 말해 주면 다음 행동이 하나로 정해진다(재발급 요청).
    //
    // 6자리는 **입력 모드**로 넣는다 — 딥링크가 싣는 것은 언제나 링크 토큰이라,
    // 코드를 initialToken으로 넘기면 현실에 없는 경로를 고정하게 된다.
    final _SpyShareRepository share =
        _SpyShareRepository(expiredKinds: <String, bool>{'482913': true});
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter, linkToken: null);

    await tester.enterText(find.byType(TextField), '482913');
    await tapCta(tester);

    expect(find.textContaining('만료된 초대코드'), findsOneWidget);
    // 뭉뚱그린 문구로 되돌아가면 이 단언이 잡는다.
    expect(find.textContaining('잘못됐을 수 있'), findsNothing);
    expect(find.text('참여 요청을 보냈어요'), findsNothing);
    expect(reporter.contexts, <String>['JoinGroupSheet.requestToJoin']);
  });

  testWidgets('만료된 **링크**는 링크 재발급을 안내한다', (WidgetTester tester) async {
    // ⚠️ `InviteExpiredException`은 초대코드 전용이 아니다 — 계약이 `credential`을
    //    "링크 토큰 또는 6자리 코드"로 정의하므로 만료된 링크도 같은 예외를 던진다.
    //    확인 모드가 보내는 것은 **링크 토큰**이므로, 하나로 뭉뚱그리면 링크가 만료된
    //    사람에게 "새 **코드**를 요청하세요"라고 말하게 된다. 코드를 받아 와도 만료된
    //    링크는 그대로라 다음 행동이 틀린 안내다.
    final _SpyShareRepository share =
        _SpyShareRepository(expiredKinds: <String, bool>{'TOKEN123': false});
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter); // 기본값 = 링크 토큰

    await tapCta(tester);

    expect(find.textContaining('만료된 초대 링크'), findsOneWidget);
    expect(find.textContaining('링크 재발급'), findsOneWidget);
    // 코드 재발급을 안내하면 안 된다 — 코드를 받아도 링크는 그대로다.
    expect(find.textContaining('새 코드를 요청'), findsNothing);
    expect(find.text('참여 요청을 보냈어요'), findsNothing);
  });

  testWidgets('확인 모드는 6자리 링크 토큰도 링크로 안내한다', (WidgetTester tester) async {
    // v3.0 이전 링크 토큰은 **6자리 숫자**였고 아직 살아 있다 — 팀 공용 시드
    // `482913`이 그것이고, deep_link_parser_test가 `/invite/482913`을
    // `InviteDestination('482913')`로 못박고 있다.
    //
    // 모양으로 가르면 그 멀쩡한 링크가 '만료된 코드'로 안내되어, 코드를 받아 와도
    // 링크는 그대로인 틀린 다음 행동을 시킨다. 확인 모드에서는 추측할 이유가 없다 —
    // 딥링크가 싣는 것은 정의상 링크 토큰이다.
    final _SpyShareRepository share =
        _SpyShareRepository(expiredKinds: <String, bool>{'482913': false});
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter, linkToken: '482913');

    await tapCta(tester);

    expect(find.textContaining('만료된 초대 링크'), findsOneWidget);
    expect(find.textContaining('만료된 초대코드'), findsNothing);
  });

  testWidgets('입력 모드에 붙여넣은 6자리 링크 토큰도 링크로 안내한다', (WidgetTester tester) async {
    // 바로 위 확인 모드 케이스의 **입력 모드 짝**이다. 확인 모드는 "딥링크가 싣는 것은
    // 정의상 링크 토큰"이라는 화면 밖 사실로 추측을 건너뛸 수 있었지만, 입력 모드에는
    // 그런 신호가 없다 — 사용자가 링크에서 토큰만 떼어 손으로 붙여넣으면 화면이 보는
    // 것은 `482913` 여섯 글자뿐이다.
    //
    // 그래서 모양으로 가르는 한 이 경로는 **원리상 고칠 수 없었다.** 항구적 해결은
    // 저장소가 폴백 조회로 이미 확정한 판정을 예외에 실어 보내는 것이고
    // (`InviteExpiredException.isCode`), 이 테스트가 그 계약이 화면까지 도달하는지를
    // 고정한다. 화면이 `isWellFormedInviteCode`로 되돌아가면 여기서 잡힌다.
    final _SpyShareRepository share =
        _SpyShareRepository(expiredKinds: <String, bool>{'482913': false});
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter, linkToken: null);

    await tester.enterText(find.byType(TextField), '482913');
    await tapCta(tester);

    expect(find.textContaining('만료된 초대 링크'), findsOneWidget);
    expect(find.textContaining('링크 재발급'), findsOneWidget);
    // 코드 재발급을 안내하면 안 된다 — 코드를 받아 와도 만료된 링크는 그대로다.
    expect(find.textContaining('만료된 초대코드'), findsNothing);
    expect(find.textContaining('새 코드를 요청'), findsNothing);
  });

  testWidgets('입력값의 앞뒤 공백은 잘라서 보낸다', (WidgetTester tester) async {
    // 붙여넣기는 공백을 달고 온다. 안 자르면 '없는 코드'로 거부된다.
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter, linkToken: null);

    await tester.enterText(find.byType(TextField), '  482913  ');
    await tapCta(tester);

    expect(share.requestedTokens, <String>['482913']);
  });

  testWidgets('만료가 아닌 실패는 만료라고 말하지 않는다', (WidgetTester tester) async {
    // 반대 방향도 고정한다 — "없는 코드"를 "만료됐다"고 말하면 존재한 적 없는
    // 그룹을 기다리게 만든다.
    final _SpyShareRepository share = _SpyShareRepository(fail: true);
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tapCta(tester);

    expect(find.textContaining('만료'), findsNothing);
  });

  testWidgets('코드 입력 전환은 실패한 뒤에만 나타난다', (WidgetTester tester) async {
    // 성공 경로는 버튼 하나로 둔다. 만료된 링크로 거절당한 사람이 방장에게 6자리
    // 코드를 불러 받는 것이 정상 경로라, 갈아탈 길은 **실패한 뒤에** 필요해진다.
    final _SpyShareRepository share =
        _SpyShareRepository(expiredKinds: <String, bool>{'TOKEN123': false});
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    expect(find.text('초대코드로 참여하기'), findsNothing);

    await tapCta(tester);

    expect(find.text('초대코드로 참여하기'), findsOneWidget);
  });

  testWidgets('전환하면 입력한 코드가 링크 토큰 대신 자격증명이 된다', (WidgetTester tester) async {
    // 링크는 링크로, 코드는 코드로 답한다 — 한 시트가 두 종류를 차례로 보내는
    // 유일한 경로라, 안내 문구도 함께 갈아타는지 여기서 본다.
    final _SpyShareRepository share = _SpyShareRepository(
      expiredKinds: <String, bool>{'TOKEN123': false, '482913': true},
    );
    final _SpyErrorReporter reporter = _SpyErrorReporter();
    await pumpSheet(tester, share, reporter);

    await tapCta(tester); // 링크 토큰으로 실패 → 전환 버튼 노출.
    await tester.tap(find.text('초대코드로 참여하기'));
    await tester.pumpAndSettle();

    // 입력란은 비어 있다 — 코드를 넣으려고 갈아탄 사람에게 토큰을 다시 내밀지 않는다.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('TOKEN123'), findsNothing);

    await tester.enterText(find.byType(TextField), '482913');
    await tapCta(tester);

    // 두 번째 요청은 **입력값**으로 나간다(토큰이 아니다).
    expect(share.requestedTokens, <String>['TOKEN123', '482913']);
    expect(find.textContaining('만료된 초대코드'), findsOneWidget);
  });
}
