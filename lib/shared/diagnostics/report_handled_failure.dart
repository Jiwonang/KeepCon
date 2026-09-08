/// KeepCon 공유 계약 — 잡은 자리에서 [ErrorReporter]로 넘기는 **유일한 진입점**.
///
/// ## 왜 함수 하나를 더 두는가
///
/// `ref.read(errorReporterProvider).report(...)`를 catch 블록에 그대로 쓰면 안 된다.
/// [WidgetRef.read]는 위젯이 폐기된 뒤 호출되면 **던진다**(assert가 아니라 무조건
/// `StateError` — release 포함). 그런데 이 진단 경로가 필요한 자리는 정확히
/// **`await` 뒤의 catch 블록**이고, 그 사이에 위젯이 사라지는 일은 흔하다:
///
/// - 참여 시트는 `isDismissible` 기본값이라, 저장소 왕복 중 사용자가 스크림을 탭해 닫을 수 있다.
/// - 그룹 상세 본문은 그룹 스트림이 loading/error를 방출하면 unmount된다.
///
/// 그 상태에서 보고가 던지면 **catch 블록의 나머지가 실행되지 않는다** — 사용자 안내
/// 스낵바가 사라진다. 즉 "아무 안내도 없이 버튼이 죽은 것처럼 보인다"는, share 화면이
/// 없애려고 `catch (_)`까지 넓힌 바로 그 실패 양상이 **진단을 붙이다가 되살아난다.**
///
/// 그래서 보고는 항상 이 함수를 거친다. 여기서 한 번 감싸면 호출부마다 try를 중복하지
/// 않아도 되고, [ErrorReporter] 구현이 던지는 경우(원격 수집 SDK의 초기화 전 호출·플랫폼
/// 채널 부재 등)도 같은 그물에 걸린다.
///
/// **진단 경로는 원래 실패를 절대 가리지 않는다.** 이 파일의 존재 이유가 그 한 줄이다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/error_reporter_provider.dart';
import 'error_reporter.dart';

/// 처리된 실패를 [ErrorReporter]에 넘긴다 — 무슨 일이 있어도 던지지 않는다.
///
/// [context]는 **어디서 났는지**를 사람이 읽을 수 있게 적은 고정 라벨이다
/// (예: `'GroupDetailPage.leaveGroup'`). 로그에서 grep 되도록 호출부마다 리터럴을 쓰고,
/// 사용자 데이터(이름·토큰·기프티콘 내용)는 넣지 않는다 — 로그는 남고 퍼진다.
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
void reportHandledFailure(
  WidgetRef ref,
  Object error,
  StackTrace stack, {
  required String context,
}) {
  try {
    reportHandledFailureTo(
      ref.read(errorReporterProvider),
      error,
      stack,
      context: context,
    );
  } catch (_) {
    // 폐기된 ref·리포터 자체 실패 — 여기서 새어 나가면 원래 실패의 안내가 사라진다.
    // 진단을 못 남기는 것이 안내를 못 띄우는 것보다 낫다.
  }
}

/// `await` **이전에 읽어 둔** [reporter]로 보고한다 — 위젯이 사라진 뒤에도 남는다.
///
/// ## 왜 형제가 필요한가
/// [reportHandledFailure]는 `WidgetRef`를 쓰므로, 위젯이 폐기된 뒤에는 `ref.read`가
/// 던지고 그것이 위 `catch (_)`에 삼켜져 **아무것도 남지 않는다.** 사용자 안내는
/// 그 설계 덕에 지켜지지만(진단이 원래 실패를 가리지 않는다 — 이 파일의 존재 이유),
/// 진단 쪽은 조용히 비는 것이다.
///
/// 그런데 그 창이 **정상 경로**인 자리가 있다: 닫을 수 있는 시트의 `await` 뒤 catch.
/// 하필 거기가 원격 진단이 가장 필요한 표본이다 — 사용자가 화면을 떠난 뒤의 백엔드
/// 실패이고, 그것만 로그에서 빠지면 표본이 조용히 편향된다("시트를 안 닫은 실패"만
/// 모인다). 그런 자리는 리포터를 `await` 이전에 잡아 이쪽으로 보고한다.
///
/// ```dart
/// final ErrorReporter reporter = ref.read(errorReporterProvider);
/// try {
///   await ref.read(shareRepositoryProvider).requestToJoin(token);
/// } catch (e, s) {
///   reportHandledFailureTo(reporter, e, s, context: 'JoinGroupSheet.requestToJoin');
///   // …안내(사전 캡처한 navigator·messenger로)
/// }
/// ```
///
/// 보고 계약([context] 라벨 규약·던지지 않음)은 [reportHandledFailure]와 같다.
void reportHandledFailureTo(
  ErrorReporter reporter,
  Object error,
  StackTrace stack, {
  required String context,
}) {
  try {
    reporter.report(error, stack, context: context);
  } catch (_) {
    // 리포터 구현이 던지는 경우(원격 수집 SDK 초기화 전 호출·플랫폼 채널 부재 등).
    // 위와 같은 규약 — 진단 경로는 원래 실패를 절대 가리지 않는다.
  }
}
