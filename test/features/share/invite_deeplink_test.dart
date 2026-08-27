// 초대 딥링크 진입 → 참여 시트 자동 오픈 위젯 테스트 (P3).
//
// pendingDestinationProvider에 InviteDestination이 있으면, 로그인된 셸이 뜰 때
// 공유 탭으로 전환하고 참여 바텀시트를 코드로 미리 채워 연다.
// 기본 세션(InMemoryAuthRepository.defaultUser)은 로그인 상태라 셸이 바로 렌더된다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keepcon/app/keepcon_shell.dart';
import 'package:keepcon/shared/deeplink/app_destination.dart';
import 'package:keepcon/shared/providers/deep_link_providers.dart';

void main() {
  testWidgets('딥링크 링크 토큰이 있으면 참여 시트가 그 값과 함께 열린다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          pendingDestinationProvider
              .overrideWith((ref) => const InviteDestination('ABC123')),
        ],
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pumpAndSettle();

    // 참여 요청 시트가 열리고(고유 CTA '참여 요청 보내기') 토큰이 미리 채워져 있어야 한다.
    // ('그룹 참여하기'는 공유 탭 버튼과 겹치므로 시트 고유 표식으로 검증한다.)
    expect(find.widgetWithText(ElevatedButton, '참여 요청 보내기'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
  });

  testWidgets('대기 중인 링크 토큰이 없으면 참여 시트가 열리지 않는다', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          pendingDestinationProvider.overrideWith((ref) => null),
        ],
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pumpAndSettle();

    // 참여 시트가 열리지 않았어야 한다(시트 고유 CTA 부재로 검증).
    expect(find.widgetWithText(ElevatedButton, '참여 요청 보내기'), findsNothing);
  });

  testWidgets('앱이 떠 있는 중에 도착한 링크도 참여 시트를 연다', (WidgetTester tester) async {
    // 웜 스타트 경로. initState의 post-frame 한 번만으로는 이 경우가 통째로 죽는다 —
    // 버스에 목적지가 실려도 읽는 사람이 없어 아무 일도 일어나지 않는다.
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ElevatedButton, '참여 요청 보내기'), findsNothing);

    // 앱이 이미 떠 있는 상태에서 딥링크가 도착한다.
    container.read(pendingDestinationProvider.notifier).state =
        const InviteDestination('LATE99');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, '참여 요청 보내기'), findsOneWidget);
    expect(find.text('LATE99'), findsOneWidget);
  });
}
