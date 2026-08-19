/// KeepCon 공유 계약 — [ErrorReporter] provider (단일 정본 / SSOT).
///
/// ⚠️ 이 파일이 리포터 인스턴스를 제공하는 **유일한 정본**이다. 페이지 안에서
/// `final _reporter = DebugPrintErrorReporter()` 같은 사본을 만들지 마라 — 조립부에서
/// 원격 수집으로 갈아끼울 때 그 사본만 옛 구현을 물고 남는다(승격 전 세션 provider가
/// 페이지마다 갈라졌던 것과 같은 사고다).
///
/// ## 소비 — 이 provider를 **직접 읽지 마라**
///
/// 잡는 자리에서는 항상 `reportHandledFailure`를 거친다. [WidgetRef.read]는 위젯이 폐기된 뒤
/// 호출되면 **던지는데**(assert가 아니라 무조건 `StateError` — release 포함), 이 진단이
/// 필요한 자리는 정확히 `await` 뒤의 catch라 그 사이 위젯이 사라지는 일이 흔하다. 그때
/// 보고가 던지면 **catch 블록의 나머지(사용자 안내)가 실행되지 않는다** — share 화면이
/// `catch (_)`까지 넓혀 가며 없앤 "아무 안내도 없이 버튼이 죽은 것처럼 보인다"가 되살아난다.
///
/// ```dart
/// try {
///   await ref.read(shareRepositoryProvider).leaveGroup(group.id);
/// } catch (e, s) {
///   reportHandledFailure(ref, e, s, context: 'GroupDetailPage.leaveGroup');
///   _snack(messenger, '지금은 나갈 수 없어요.');
///   return;
/// }
/// ```
///
/// 이 provider를 직접 읽는 곳은 그 래퍼 하나뿐이어야 한다.
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
