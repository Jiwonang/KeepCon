// 초대 딥링크 진입 → 참여 시트 자동 오픈 위젯 테스트 (P3).
//
// pendingInviteCodeProvider에 초대코드가 있으면, 로그인된 셸이 뜰 때
// 공유 탭으로 전환하고 참여 바텀시트를 코드로 미리 채워 연다.
// 기본 세션(InMemoryAuthRepository.defaultUser)은 로그인 상태라 셸이 바로 렌더된다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepcon/app/keepcon_shell.dart';
import 'package:keepcon/features/share/state/share_providers.dart';

void main() {
  testWidgets('딥링크 초대코드가 있으면 참여 시트가 코드와 함께 열린다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          pendingInviteCodeProvider.overrideWith((ref) => 'ABC123'),
        ],
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pumpAndSettle();

    // 참여 시트가 열리고(고유 CTA '참여하기') 코드가 미리 채워져 있어야 한다.
    // ('그룹 참여하기'는 공유 탭 버튼과 겹치므로 시트 고유 표식으로 검증한다.)
    expect(find.widgetWithText(ElevatedButton, '참여하기'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
  });

  testWidgets('대기 초대코드가 없으면 참여 시트가 열리지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          pendingInviteCodeProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pumpAndSettle();

    // 참여 시트가 열리지 않았어야 한다(시트 고유 CTA 부재로 검증).
    expect(find.widgetWithText(ElevatedButton, '참여하기'), findsNothing);
  });
}
