/// 앱 복귀 시 **시계 정본이 되살아나는지** 고정하는 테스트.
///
/// [nowProvider]는 의존성이 없어 컨테이너 수명 동안 한 번만 계산된다. 아무도 무효화하지
/// 않으면 앱이 살아 있는 내내 첫 계산 시각에 머물고, 날짜 파생이 전부 늙는다 — 알림
/// 센터는 "이미 울린 만료 알림"을 계산으로 복원하므로 그 사이 발송된 알림이 목록에 아예
/// 안 뜬다(푸시를 받고 앱으로 돌아와 벨을 눌렀는데 비어 있는 경로).
///
/// ⚠️ 이 테스트가 덮는 것은 **복귀(resumed)** 경로뿐이다. 앱을 포그라운드에 켜 둔 채
/// 시각을 넘기는 경우는 타이머 소유 구조가 필요해 별도 작업으로 남아 있다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/app/keepcon_shell.dart';
import 'package:keepcon/features/main/state/highlighted_gifticon.dart';
import 'package:keepcon/shared/providers/now_provider.dart';

void main() {
  testWidgets('앱이 앞으로 돌아오면 nowProvider가 다시 계산된다', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pump();

    final DateTime first = container.read(nowProvider);
    // 캐시 확인 — 무효화 없이는 몇 번을 읽어도 같은 값이다(이 provider가 늙는 이유).
    expect(container.read(nowProvider), first);

    // 백그라운드 → 복귀. 실제 앱에서 푸시를 보고 돌아오는 경로다.
    // 전이는 실제 순서를 따라야 한다 — 프레임워크가 건너뛴 전이를 assertion으로 막는다
    // (resumed → inactive → hidden → paused, 복귀는 그 역순).
    for (final AppLifecycleState s in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();

    expect(container.read(nowProvider), isNot(first),
        reason: '복귀에도 시계가 그대로면 날짜 파생이 늙은 채 남는다');

    // 남은 강조 타이머가 있으면 흘려보낸다(pending timer 방지).
    await tester.pump(highlightDuration + const Duration(seconds: 1));
  });

  testWidgets('복귀가 아닌 상태 변화에는 시계를 건드리지 않는다', (WidgetTester tester) async {
    // 멀쩡한 시계를 매 전이마다 무효화하면 날짜 파생 전체가 불필요하게 재계산된다.
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KeepConShell()),
      ),
    );
    await tester.pump();

    final DateTime first = container.read(nowProvider);
    for (final AppLifecycleState s in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();

    expect(container.read(nowProvider), first);

    await tester.pump(highlightDuration + const Duration(seconds: 1));
  });
}
