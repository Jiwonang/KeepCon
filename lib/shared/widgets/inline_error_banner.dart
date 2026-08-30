/// 공유 위젯 — 인라인 에러 배너(표시 + 수동 재시도).
///
/// ## 왜 필요한가
/// 이 앱의 화면들은 [AsyncValue]를 `valueOrNull ?? []`로 접어(폴딩) 크래시를 막는다
/// (크로스페이지 주의점 #13 — `.value`의 rethrow 함정 회피). 대가로 **에러가 빈 상태와
/// 구분되지 않는다**: 알림 스트림이 실패하면 "알림이 없어요", 사용 이력이 실패하면
/// "이력이 없어요"로 보인다(감사 화면에서는 특히 위험). 이 배너는 그 폴딩을 **바꾸지 않고**,
/// 원천 provider의 `hasError`를 함께 관찰해 화면 위에 얹는 얇은 표시 계층이다.
///
/// ## 규약
/// - **자동 재시도 금지.** 장애 중 전 화면이 동시에 재구독하면 retry storm이 된다(#13).
///   재시도는 사용자가 [onRetry]를 누를 때만 일어나고, 구현은 해당 **원천** provider의
///   `ref.invalidate`다(폴딩된 파생은 에러 정보가 이미 없어 재시도 지점이 될 수 없다).
/// - **내부 에러 메시지 비노출.** [message]에는 한국어 중립 문구만 넣는다
///   (`StateError.message` 등 영문·raw id는 사용자에게 노출하지 않는다 — share 페이지에서
///   출발한 규약이고, 승격 후에는 이 배너를 쓰는 모든 페이지에 적용된다).
/// - [onRetry]가 null이면 재시도 버튼을 숨기고, 대신 복구 안내 접미(연결 확인 후 앱
///   재시작)를 **배너가 스스로** 문구에 덧붙인다 — **재시도 경로가 실제로 없는 원천**
///   에서 동작하지 않는 버튼을 보여 주지 않되 사용자가 취할 수 있는 행동은 알리기
///   위한 것이다. 호출부는 기본 문구만 넘긴다(접미를 각자 조립하면 누락·모순이
///   컴파일러에 안 잡힌 채 갈라진다).
///   ℹ️ **현재 이 저장소에 null 사이트는 없다(규약은 휴면 상태).** share의 마지막 남아
///   있던 원천인 내 그룹 목록이 계약 재시도 훅(`retryMyGroups` — `lib/shared`)을 갖게
///   되면서 share의 모든 배너가 실제 재시도를 넘기고, 아래 **남은 소비 후보**(scan·main·
///   auth)도 조사해 보면 셋 다 재시도 훅이 이미 계약에 있다. 그래도 이 분기를 지우지 않는
///   이유는 **지금 그런 사이트가 남아 있어서가 아니라**, 재시도 경로가 없는 원천이 앞으로
///   생겼을 때의 **안전망**이기 때문이다(경로 없는 곳에서 죽은 버튼이 부활하지 않게 한다).
///
/// ## 승격 이력 — 완료됨(2026-08-30)
/// 원래 위치는 share 페이지 폴더(`lib/features/share/widgets/`)였고 이름에도 `Share`
/// 접두가 붙어 있었다 — 두 번째 소비자가 생길 때까지 페이지 안에 두는 규칙을 따른 것이다
/// (투기적 승격 금지 — CLAUDE.md 승격 워크플로 ③). **PR #137이 scan에 그룹 선택 타일을
/// 넣으면서 두 번째 소비 지점이 확정되어** `lib/shared/widgets/`로 옮기고
/// `InlineErrorBanner`로 개명했다 — 공유 도메인 전용이 아니게 되어 옛 접두가 사실과
/// 어긋나기 때문이다.
///
/// ⚠️ **배선은 아직이다 — 현재 실소비자는 share 하나뿐이다.** `lib/features/scan`에 이
/// 위젯 참조는 0건이고, scan·main·auth 연결은 각 담당의 후속 PR이다(아래 "남은 소비
/// 후보"). 즉 규칙 ③이 말하는 "실제 두 번째 소비자"가 이미 생긴 상태는 아니며, 소비
/// **지점**이 확정됐고 그 사이에 사본이 생기는 것을 막으려고 앞당긴 승격이다
/// (`tool/check_ssot.sh` 등록이 그 게이트다).
///
/// 옛 이름(`ShareErrorBanner`·`share_error_banner`)은 **`lib`·`test`에 0건**이다(주석 포함).
/// 저장소 전체로는 `_workspace/qa_report.md`에 4곳 남아 있으나 **의도적으로 남긴 것이며
/// 개명하지 않는다** — 날짜가 박힌 과거 QA 스냅샷 기록이라 당시 이름 그대로 두는 것이
/// 맞다(누락으로 읽고 덮어쓰지 말 것).
///
/// ## 남은 소비 후보(아직 교체되지 않았다 — 이 목록을 지우지 말 것)
/// - **scan** — `scanTargetGroupsProvider`가 로딩·미로그인·에러를 **모두 빈 목록으로 접어**
///   "그룹을 못 불러옴"과 "그룹 없음"이 구분되지 않는다. 재시도 훅은 계약에 이미 있다
///   (`retryMyGroups`). 승격을 촉발한 지점이지만 배선은 별도 PR(scan 담당)이다.
///   ⚠️ 이 이름의 선언이 **둘**이다 — 배선 대상은 화면이 실제로 읽는
///   `lib/features/scan/state/scan_target_group_state.dart`(`Provider.autoDispose`)이고,
///   `lib/features/share/state/share_providers.dart`의 동명 선언(`Provider`, 참조 0건)이
///   아니다. 본문은 같지만 수명이 다르다. 두 선언의 정리는 scan·share 담당의 별도 작업.
/// - **main·auth** — `lib/features/main/main_page.dart`와 `lib/app/auth_gate.dart`가 raw
///   예외를 `'$e'`로 그대로 노출한다(내부 메시지 비노출 규약 위반). 둘 다 에러 원천이
///   `sessionUserProvider`이고 그 재시도 훅은 **계약에 이미 있다** —
///   `retrySessionIfFailed(WidgetRef)`(`lib/shared/providers/session_provider.dart`).
///   따라서 `onRetry: null`이 아니라 `onRetry: () => retrySessionIfFailed(ref)`로
///   배선한다(버튼 없는 배너 + 앱 재시작 안내는 제자리 복구가 가능한 지점에서 틀린
///   처방이다). 배선은 각 담당의 별도 PR이다.
///
/// 새 배너를 만들지 말고 이 위젯을 소비할 것. 문구·색·레이아웃을 바꿔야 하면
/// `contract-architect`에게 요청한다(`lib/shared`는 `CODEOWNERS` 대상).
library;

import 'package:flutter/material.dart';

import '../theme/theme_tokens.dart';

/// 목록/섹션 위에 얹는 인라인 에러 배너.
///
/// 색은 전부 `Theme.of(context).colorScheme`(error 계열)에서 오고 라운드는 [AppRadii]를
/// 쓴다 — 하드코딩 색·raw 반경 없음(공유 테마 SSOT 규약).
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
  });

  /// 재시도 불가 배너([onRetry] == null)에 자동으로 붙는 복구 안내 접미.
  static const String retryUnavailableGuide = '연결 상태를 확인한 뒤 앱을 다시 열어 주세요.';

  /// 사용자에게 보여 줄 한국어 중립 문구(내부 예외 메시지 금지). 접미 없이 기본
  /// 문구만 — 재시도 불가 안내는 배너가 붙인다([retryUnavailableGuide]).
  final String message;

  /// 재시도 콜백. null이면 버튼을 숨기고 [retryUnavailableGuide]를 문구에 덧붙인다.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String text =
        onRetry == null ? '$message $retryUnavailableGuide' : message;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, 12, onRetry == null ? 14 : 6, 12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: scheme.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_outlined, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
              style: TextButton.styleFrom(
                foregroundColor: scheme.error,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
