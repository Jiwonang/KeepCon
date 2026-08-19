/// KeepCon 공유 계약 — [ErrorReporter] provider (단일 정본 / SSOT).
///
/// ⚠️ 이 파일이 리포터 인스턴스를 제공하는 **유일한 정본**이다. 페이지 안에서
/// `final _reporter = DebugPrintErrorReporter()` 같은 사본을 만들지 마라 — 조립부에서
/// 원격 수집으로 갈아끼울 때 그 사본만 옛 구현을 물고 남는다(승격 전 세션 provider가
/// 페이지마다 갈라졌던 것과 같은 사고다).
///
/// ## 소비
///
/// 실패를 잡는 자리에서 원본과 스택을 넘긴다. 사용자 안내는 하던 대로 띄운다.
///
/// ```dart
/// try {
///   await ref.read(shareRepositoryProvider).leaveGroup(group.id);
/// } catch (e, s) {
///   ref.read(errorReporterProvider).report(e, s, context: 'GroupDetailPage.leaveGroup');
///   _snack(messenger, '지금은 나갈 수 없어요.');
///   return;
/// }
/// ```
///
/// ## 원격 수집으로 갈아끼우기
///
/// 백엔드를 정하면 [ErrorReporter] 구현을 하나 더하고 **조립부에서 이 provider만**
/// override한다. 잡는 자리는 손대지 않는다.
///
/// ```dart
/// ProviderScope(
///   overrides: <Override>[
///     errorReporterProvider.overrideWithValue(CrashlyticsErrorReporter()),
///   ],
///   child: const KeepConApp(),
/// );
/// ```
///
/// ## 테스트
///
/// 기본 구현은 콘솔에 쓰므로 테스트에서는 소음이 된다. 무엇이 보고됐는지 단언하려면
/// 스파이를, 소음만 없애려면 [SilentErrorReporter]를 override 한다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/error_reporter.dart';

/// 처리된 실패의 진단 경로. 기본은 콘솔 출력([DebugPrintErrorReporter]).
final Provider<ErrorReporter> errorReporterProvider = Provider<ErrorReporter>(
  (Ref ref) => const DebugPrintErrorReporter(),
);
