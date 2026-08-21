// 그룹 만들기 시트 — **중복 제출 잠금** 회귀 고정.
//
// 이 시트는 진입점이 둘이다: '만들기' 버튼과 입력란의 `onSubmitted`(키보드 Done).
// 잠금이 없으면 두 번 들어와 `createGroup`이 두 번 불리고, **같은 이름의 그룹이 두 개**
// 만들어진다(Firebase 구현에서는 `inviteTokens` 문서도 두 벌). 사용자는 되돌릴 방법이 없다.
//
// 형제인 참여 시트(`_JoinGroupSheetState._sending`)와 참여 요청 행들에는 같은 잠금이
// 있었는데 이 시트만 빠져 있었다 — "형제를 안 셌다"의 사례라 여기에 못을 박는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/features/share/widgets/share_sheets.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// `createGroup` 호출만 세는 스텁. 완료 시점을 테스트가 제어한다.
class _SpyShareRepository implements ShareRepository {
  final List<String> created = <String>[];
  final Completer<void> gate = Completer<void>();

  @override
  Future<Group> createGroup({
    required String name,
    required String emoji,
    int maxMembers = Group.defaultMaxMembers,
  }) async {
    created.add(name);
    await gate.future;
    return Group(
      id: 'g1',
      name: name,
      emoji: emoji,
      inviteToken: 'TOKEN',
      members: const <GroupMember>[
        GroupMember(
          userId: 'u1',
          displayName: '나',
          avatarEmoji: '🙂',
          role: MemberRole.owner,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('기대하지 않은 호출: ${invocation.memberName}');
}

class _SpyErrorReporter implements ErrorReporter {
  final List<String> contexts = <String>[];

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    contexts.add(context);
  }
}

void main() {
  testWidgets('만들기를 두 번 눌러도 createGroup은 한 번만 불린다',
      (WidgetTester tester) async {
    final _SpyShareRepository share = _SpyShareRepository();
    final _SpyErrorReporter reporter = _SpyErrorReporter();

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
                  onPressed: () => showCreateGroupSheet(context),
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

    await tester.enterText(find.byType(TextField), '우리집');
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, '만들기'));
    await tester.pump();

    // 첫 탭으로 호출 1회. 버튼은 잠겨 있어야 두 번째 탭이 무시된다.
    expect(share.created, <String>['우리집']);
    final ElevatedButton btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '만드는 중…'),
    );
    expect(btn.onPressed, isNull,
        reason: '생성 중인데 버튼이 열려 있다 — 같은 그룹이 두 개 만들어진다');

    share.gate.complete();
    await tester.pumpAndSettle();
    expect(share.created, hasLength(1));
  });
}
