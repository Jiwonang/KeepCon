/// KeepCon 공유 계약 — **처리된 실패**의 진단 경로 (단일 정본 / SSOT).
///
/// ## 왜 필요한가
///
/// share 화면의 쓰기 액션은 실패 원인과 무관하게 사용자에게 안내를 띄운다
/// (`catch (_)` — PR #96). 그 넓은 그물이 필요한 이유는 명확하다: `on StateError`로 좁히면
/// 백엔드 예외가 그대로 빠져나가 **아무 안내 없이 버튼이 죽은 것처럼 보인다.**
///
/// 그런데 넓게 잡으면 반대 대가가 생긴다 — Dart의 `catch (_)`는 [Exception]뿐 아니라
/// [Error](예: [TypeError])까지 삼킨다. 즉 **프로그래밍 결함이 사용자용 문구 한 줄로 바뀌어
/// 조용히 사라진다.** 화면에는 "지금은 나갈 수 없어요"만 남고, 개발자에게는 아무것도
/// 남지 않는다.
///
/// 이 계약은 그 둘을 동시에 만족시킨다 — **사용자에게는 안내, 개발자에게는 원본.**
/// 잡은 자리에서 원본 예외와 스택을 [ErrorReporter]에 넘기고, 사용자에게는 하던 대로
/// 상황에 맞는 문구를 띄운다.
///
/// ## 왜 인터페이스인가 (원격 수집을 지금 붙이지 않는 이유)
///
/// 기본 구현([DebugPrintErrorReporter])은 콘솔에만 남긴다. 원격 수집(Crashlytics·Sentry)은
/// **의존성과 플랫폼 설정이 걸린 별도 결정**이라 여기서 하지 않는다. 특히 Crashlytics는
/// Android에서 `com.google.gms.google-services` Gradle 플러그인을 요구하는데, KeepCon은 그
/// 플러그인을 **일부러 제거했다** — 네이티브가 `[DEFAULT] FirebaseApp`을 먼저 만들어 버려
/// emulator/dev/prod를 실행 시 고르는 구조가 깨지기 때문이다(팀 기본 경로인 에뮬레이터 포함).
///
/// 그래서 지금은 **이음매만** 만든다. 나중에 백엔드를 정하면 [ErrorReporter] 구현 하나를
/// 더하고 조립부에서 provider를 갈아끼우면 되며, **잡는 자리는 손대지 않는다.**
///
/// ## 잔여 소비자 (아직 이 정본을 안 쓰는 곳)
///
/// 이 계약은 share 화면과 `GifticonDetailPage.updateStatus`를 덮는다. 아래는 같은 부류인데
/// 아직 배선되지 않았다 — 다음 사람이 "정본이 이미 전부 덮는다"고 오해하지 않도록 적어 둔다.
///
/// - `lib/features/scan/state/gifticon_form_state.dart` — 원시 예외를 **사용자 문구에 직접**
///   넣는다(`'저장에 실패했습니다: $e'`). 진단도 안 남는다. 문구 정리와 함께 별도로 다룬다.
/// - `lib/features/scan/scan_page.dart` / `gifticon_ocr_parser.dart` — 광폭 catch, 진단 없음.
///
/// 인증(`features/auth`)·마이 페이지는 `on AuthException`으로 좁혀 잡으므로 이 부류가 아니다.
library;

import 'package:flutter/foundation.dart';

/// 처리된 실패를 개발자에게 남기는 계약.
///
/// "처리된(handled)"은 **사용자에게 이미 안내가 나갔다**는 뜻이다. 앱을 죽이지 않으므로
/// 구현은 절대 예외를 던지지 말아야 한다 — 리포터가 터지면 원래 실패를 가린다.
abstract class ErrorReporter {
  /// [error]와 [stack]을 남긴다.
  ///
  /// [context]는 **어디서 났는지**를 사람이 읽을 수 있게 적은 라벨이다
  /// (예: `'GroupDetailPage.leaveGroup'`). 로그에서 grep 되도록 호출부마다 고정 문자열을
  /// 쓰고, 사용자 데이터(이름·토큰·기프티콘 내용)는 넣지 않는다 — 로그는 남고 퍼진다.
  void report(Object error, StackTrace stack, {required String context});
}

/// 기본 구현 — 콘솔에 남긴다.
///
/// [debugPrint]는 release 빌드에서도 플랫폼 로그로 나가므로, 원격 수집이 없는 지금도
/// 기기 로그(`adb logcat` 등)로는 진단할 수 있다. 저장소의 기존 관행(`KeepCon: …` 접두)을
/// 따라 한 줄로 시작해, 스택은 그 아래에 붙인다.
class DebugPrintErrorReporter implements ErrorReporter {
  /// 상수 생성자 — provider가 인스턴스를 한 벌만 들고 있으면 충분하다.
  ///
  /// [includeMessage]가 참이면 예외 메시지를 그대로 찍고, 거짓이면 **타입만** 남긴다.
  /// 기본값이 [kDebugMode]인 이유는 아래 [report] 참조.
  const DebugPrintErrorReporter({this.includeMessage = kDebugMode});

  /// 예외 메시지를 로그에 실을지 여부.
  final bool includeMessage;

  @override
  void report(Object error, StackTrace stack, {required String context}) {
    // 리포터는 절대 던지지 않는다 — 여기서 터지면 원래 실패를 가린다.
    try {
      // release 로그에는 **타입만** 남긴다. 저장소 예외 메시지에는 식별자가 그대로 실려
      // 있고(`Invite token expired: $inviteToken`, `Not a member of group: $groupId`),
      // [debugPrint]는 release에서도 플랫폼 로그로 나간다 — 진단하려고 만든 경로가
      // 유출 경로가 되면 안 된다. 초대 토큰은 유출되면 그대로 참여 경로다.
      //
      // 타입과 라벨만으로도 "어느 화면의 어느 액션이 어떤 부류로 실패했는가"는 남으므로
      // 분류에는 충분하다. 값이 필요한 재현은 debug 빌드에서 한다.
      final String what =
          includeMessage ? '$error' : error.runtimeType.toString();
      debugPrint('KeepCon: [$context] 처리된 실패 — $what');
      // 스택에는 파일·줄만 들어가므로 그대로 남긴다(진단의 핵심이다).
      debugPrint('$stack');
    } catch (_) {
      // 로깅 실패는 삼킨다(할 수 있는 것이 없다).
    }
  }
}

/// 아무것도 하지 않는 구현 — 테스트에서 소음을 없앨 때 쓴다.
///
/// ⚠️ 앱 조립부에서 쓰지 마라. 이 계약이 존재하는 이유(진단 경로 확보)를 정면으로 무효화한다.
class SilentErrorReporter implements ErrorReporter {
  /// 상수 생성자.
  const SilentErrorReporter();

  @override
  void report(Object error, StackTrace stack, {required String context}) {}
}
