/// share 페이지 — 인라인 에러 배너(표시 + 수동 재시도).
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
///   (`StateError.message` 등 영문·raw id는 share 페이지 규약상 사용자에게 노출하지 않는다).
/// - [onRetry]가 null이면 재시도 버튼을 숨기고, 대신 복구 안내 접미(연결 확인 후 앱
///   재시작)를 **배너가 스스로** 문구에 덧붙인다 — **재시도 경로가 실제로 없는 원천**
///   에서 동작하지 않는 버튼을 보여 주지 않되 사용자가 취할 수 있는 행동은 알리기
///   위한 것이다. 호출부는 기본 문구만 넘긴다(접미를 각자 조립하면 누락·모순이
///   컴파일러에 안 잡힌 채 갈라진다).
///   ℹ️ **현재 share에는 null 사이트가 없다(규약은 휴면 상태).** 마지막 남아 있던
///   원천인 내 그룹 목록이 계약 재시도 훅(`retryMyGroups` — `lib/shared`)을 갖게 되면서
///   모든 배너가 실제 재시도를 넘긴다. 그래도 이 분기를 지우지 않는 이유는, 아래 승격
///   대상인 main·scan에 재시도 경로가 없는 에러 지점이 남아 있어 **승격 시 안전망**이
///   필요하기 때문이다(경로 없는 곳에서 죽은 버튼이 부활하지 않게 한다).
///
/// ## 승격(늦게 승격 규칙)
/// 지금은 share 전용이라 페이지 폴더에 둔다. main 목록·scan 타일에서 **두 번째 소비자**가
/// 생기면 그때 `contract-architect`에게 `lib/shared/widgets/`로의 승격을 요청한다
/// (투기적 승격 금지 — CLAUDE.md 승격 워크플로 ③). 예정된 첫 후보: main에는 raw 예외를
/// 그대로 노출하는 에러 UI(`main_page.dart`의 `'$e'` 표시, `auth_gate.dart` 동일)가 있어
/// 그 교체 작업이 사실상 두 번째 소비자다 — main 담당은 새 배너를 만들지 말고 승격을 요청할 것.
library;

import 'package:flutter/material.dart';

import '../../../shared/theme/theme_tokens.dart';

/// 목록/섹션 위에 얹는 인라인 에러 배너.
///
/// 색은 전부 `Theme.of(context).colorScheme`(error 계열)에서 오고 라운드는 [AppRadii]를
/// 쓴다 — 하드코딩 색·raw 반경 없음(공유 테마 SSOT 규약).
class ShareErrorBanner extends StatelessWidget {
  const ShareErrorBanner({
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
