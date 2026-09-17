/// `ScanPage._openForm` — **인식 도중 화면이 사라져도** 실패의 진단이 남는가.
///
/// 이 catch는 `mounted`를 검사한다 — 촬영·인식·폼 왕복 중 화면이 사라질 수 있다는
/// 뜻이다. 그때 `reportHandledFailure(ref, …)`로 보고하면 죽은 `ref`에서 던져 조용히
/// 아무것도 남지 않으므로, 리포터를 `await` 전에 잡아 `reportHandledFailureTo`로
/// 보낸다(`report_handled_failure.dart` 머리말 기준). 이 파일은 그 전환을 고정한다.
///
/// ## 플러그인 뒤의 catch에 어떻게 닿는가
///
/// 기존 스캔 테스트들은 "`_openForm`은 플러그인을 타서 위젯 테스트로 통째로 지날 수
/// 없다"고 적었는데, **갤러리 경로는 두 플러그인 모두 기본 MethodChannel 구현을
/// 탄다**(image_picker의 `plugins.flutter.io/image_picker`, ML Kit의
/// `google_mlkit_text_recognizer`·`google_mlkit_barcode_scanning`). 그래서
/// `setMockMethodCallHandler`로 막을 수 있다 — 텍스트 인식을 게이트로 붙잡아 두고,
/// 그 사이 페이지를 내린 뒤 실패시킨다.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/features/scan/scan_page.dart';
import 'package:keepcon/shared/diagnostics/error_reporter.dart';
import 'package:keepcon/shared/providers/error_reporter_provider.dart';
import 'package:keepcon/shared/providers/now_provider.dart';
import 'package:keepcon/shared/providers/repositories.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';

/// 보고된 라벨을 기록하고, 첫 보고가 들어오면 [reported]를 완료한다.
class _SpyErrorReporter implements ErrorReporter {
  final List<String> contexts = <String>[];

  /// 첫 보고 도착 신호 — 고정 지연 대신 이것을 기다린다.
  final Completer<void> reported = Completer<void>();

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    contexts.add(context);
    if (!reported.isCompleted) reported.complete();
  }
}

void main() {
  const MethodChannel picker = MethodChannel('plugins.flutter.io/image_picker');
  const MethodChannel text = MethodChannel('google_mlkit_text_recognizer');
  const MethodChannel barcode = MethodChannel('google_mlkit_barcode_scanning');

  testWidgets('인식 도중 화면을 떠나도 _openForm 실패의 진단이 남는다',
      (WidgetTester tester) async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      for (final MethodChannel c in <MethodChannel>[picker, text, barcode]) {
        messenger.setMockMethodCallHandler(c, null);
      }
    });

    // 갤러리가 돌려줄 파일 — 내용은 상관없다(인식이 실패하도록 막는다).
    final Directory dir = Directory.systemTemp.createTempSync('kc_scan');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File img = File('${dir.path}/x.jpg')..writeAsBytesSync(<int>[0]);

    final Completer<void> gate = Completer<void>();
    messenger.setMockMethodCallHandler(picker, (_) async => img.path);
    messenger.setMockMethodCallHandler(text, (MethodCall c) async {
      if (c.method.contains('start')) {
        await gate.future; // 인식은 공중에 떠 있다 — 그 사이 화면을 내린다.
        throw PlatformException(code: 'boom');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      barcode,
      (MethodCall c) async => c.method.contains('start') ? <Object>[] : null,
    );

    final InMemoryGifticonRepository gifticons = InMemoryGifticonRepository();
    final InMemoryAuthRepository auth = InMemoryAuthRepository();
    addTearDown(() {
      gifticons.dispose();
      auth.dispose();
    });
    final _SpyErrorReporter spy = _SpyErrorReporter();
    // 같은 스코프를 유지한 채 **페이지만** 내린다(실제 화면 이탈과 같은 조건).
    final List<Override> overrides = <Override>[
      gifticonRepositoryProvider.overrideWithValue(gifticons),
      authRepositoryProvider.overrideWithValue(auth),
      nowProvider.overrideWithValue(DateTime(2029, 5, 15, 12)),
      errorReporterProvider.overrideWithValue(spy),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: ScanPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('갤러리'));
    await tester.pump(); // 갤러리 pick
    await tester.pump(); // 인식 시작(게이트에서 멈춘다)

    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: SizedBox()),
    ));
    await tester.pump();
    expect(find.byType(ScanPage), findsNothing, reason: '화면이 내려간 것이 이 테스트의 전제');

    // 플러그인 채널 응답은 실제 비동기라 가짜 시계 밖에서 풀어 준다. 고정 지연은
    // 느린 CI에서 보고보다 먼저 끝날 수 있으므로(CodeRabbit) 보고 도착을 기다린다.
    // 타임아웃은 조용히 넘긴다 — 회귀가 나면 아래 단언이 Expected/Actual로 말하게
    // 두는 편이 `TimeoutException` 한 줄보다 진단이 쉽다.
    await tester.runAsync(() async {
      gate.complete();
      await spy.reported.future
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    });
    await tester.pumpAndSettle();

    expect(spy.contexts, <String>['ScanPage._openForm']);
  });
}
