/// [reportHandledFailure]의 **불변식** 테스트 — 진단 경로는 원래 실패를 절대 가리지 않는다.
///
/// 이 함수가 존재하는 이유가 그 한 줄이다. 잡는 자리에서 `ref.read(...)`를 직접 부르면
/// 두 갈래로 던질 수 있고, 그러면 **catch 블록의 나머지(사용자 안내)가 실행되지 않는다**:
///
/// - [WidgetRef.read]는 위젯이 폐기된 뒤 호출되면 던진다(assert가 아니라 무조건
///   `StateError` — release 포함). `await` 뒤의 catch에서 흔히 도달한다.
/// - [ErrorReporter] 구현 자체가 던질 수 있다(원격 수집 SDK의 초기화 전 호출 등).
///
/// 둘 다 "아무 안내도 없이 버튼이 죽은 것처럼 보인다"로 이어진다 — share 화면이 `catch (_)`
/// 까지 넓혀 가며 없앤 바로 그 실패 양상이다. 진단을 붙이다가 그것을 되살리면 본말전도다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/diagnostics/report_handled_failure.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';

/// 호출되면 던지는 리포터 — 원격 수집 SDK가 초기화 전에 터지는 상황의 대역.
class _ThrowingErrorReporter implements ErrorReporter {
  bool called = false;

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    called = true;
    throw StateError('reporter itself blew up');
  }
}

class _RecordingErrorReporter implements ErrorReporter {
  final List<String> contexts = <String>[];

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    contexts.add(context);
  }
}

void main() {
  /// `ref`를 밖으로 꺼내 주는 최소 위젯 — 폐기 후 호출을 재현하려면 element가 필요하다.
  Widget host(void Function(WidgetRef ref) onBuilt) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          onBuilt(ref);
          return const SizedBox.shrink();
        },
      );

  testWidgets('정상 경로 — 리포터로 그대로 전달된다', (WidgetTester tester) async {
    final _RecordingErrorReporter reporter = _RecordingErrorReporter();
    late WidgetRef captured;

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        errorReporterProvider.overrideWithValue(reporter),
      ],
      child: MaterialApp(home: host((WidgetRef r) => captured = r)),
    ));

    reportHandledFailure(captured, Exception('x'), StackTrace.current,
        context: 'Page.action');

    expect(reporter.contexts, <String>['Page.action']);
  });

  testWidgets('리포터가 던져도 호출부로 새지 않는다', (WidgetTester tester) async {
    final _ThrowingErrorReporter reporter = _ThrowingErrorReporter();
    late WidgetRef captured;

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        errorReporterProvider.overrideWithValue(reporter),
      ],
      child: MaterialApp(home: host((WidgetRef r) => captured = r)),
    ));

    expect(
      () => reportHandledFailure(captured, Exception('x'), StackTrace.current,
          context: 'Page.action'),
      returnsNormally,
    );
    expect(reporter.called, isTrue, reason: '실제로 리포터를 태운 뒤 삼켰는지 확인');
  });

  testWidgets('위젯이 폐기된 뒤 호출해도 던지지 않는다 — 사용자 안내가 사라지면 안 된다',
      (WidgetTester tester) async {
    final _RecordingErrorReporter reporter = _RecordingErrorReporter();
    late WidgetRef captured;

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        errorReporterProvider.overrideWithValue(reporter),
      ],
      child: MaterialApp(home: host((WidgetRef r) => captured = r)),
    ));

    // 같은 ProviderScope를 유지한 채 자식만 갈아끼워 위 Consumer element를 폐기한다
    // (시트를 닫거나 스트림 방출로 본문이 unmount되는 상황과 같다).
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        errorReporterProvider.overrideWithValue(reporter),
      ],
      child: const MaterialApp(home: SizedBox.shrink()),
    ));

    // 전제 확인 — 직접 부르면 실제로 던진다(이 테스트가 공허하지 않다는 근거).
    expect(
      () => captured.read(errorReporterProvider),
      throwsA(isA<StateError>()),
    );

    // 래퍼를 거치면 조용히 넘어간다.
    expect(
      () => reportHandledFailure(captured, Exception('x'), StackTrace.current,
          context: 'Page.action'),
      returnsNormally,
    );
    expect(reporter.contexts, isEmpty, reason: '폐기된 ref로는 보고할 수 없다(그래도 안 던진다)');
  });
}
