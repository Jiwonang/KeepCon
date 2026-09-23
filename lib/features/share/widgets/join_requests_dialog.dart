/// share 페이지 — 승인요청목록(방장이 보는 참여 요청 대기 목록, **모달 팝업**).
///
/// **방장만 읽는다.** 일반 멤버에게도 열지 않는다 — 아직 멤버가 아닌 사람들의 이름이고,
/// 보안 규칙도 같은 선을 긋는다(계약 참조). 진입점(그룹 상세의 '승인요청목록' 버튼)이
/// `iAmOwner`로 게이팅하고, 이 팝업도 [_OwnerOnlyNotice]로 한 겹 더 막는다.
///
/// 이 스트림이 **방장에게 요청 도착을 알리는 유일한 신호**다. 알림 문서로 알리려면
/// 비멤버가 `notifications`에 써야 하는데 규칙이 막고, 서버로 대신 쓰려면 유료 플랜이
/// 필요하다 — 대기 목록이 같은 정보를 이미 갖고 있으니 둘 다 치르지 않는다.
/// 그래서 **로딩·에러를 빈 목록으로 접지 않는다**(그러면 "요청 없음"과 구분되지 않아
/// 방장이 대기자를 못 보고 지나간다). 진입점 버튼의 뱃지도 같은 규약을 따른다.
///
/// 정원은 **승인 시점**에 검사된다(계약) — 대기자가 자리를 선점하면 방장이 정작 받고 싶은
/// 사람을 못 넣기 때문이다. 그래서 정원이 찬 그룹에도 요청은 쌓이고, 승인만 거부된다.
///
/// ## 이력 — 인라인 섹션 → 전용 화면 → 모달 팝업
/// ① 처음에는 그룹 상세 안에 인라인으로 펼쳐지던 `PendingJoinRequestsSection`이었다.
///    목록이 상세 화면의 세로 길이를 요청 수만큼 늘려 아래의 공유 기프티콘 섹션을
///    밀어냈고, 0건이면 통째로 사라져 방장이 "요청이 없다"는 것조차 확인할 수 없었다.
///    진입점(버튼)과 목록을 분리해 둘 다 해소했다.
/// ② 그다음에는 전용 화면(옛 이름 `JoinRequestsPage` — 지금은 없다)을
///    `MaterialPageRoute`로 push했다. 그런데
///    승인·거절은 **그룹 상세에 머문 채 곁에서 처리하는 일**이지 다른 화면으로 떠나는
///    일이 아닌데, 전체 화면 push는 그룹 상세를 통째로 덮어 맥락을 지웠다.
/// ③ 그래서 지금은 스크림 위에 뜨는 모달 팝업이다 — 뒤의 그룹 상세가 어두워진 채 계속
///    보이므로 "이 그룹의 대기자를 처리하는 중"이라는 맥락이 유지된다.
///
/// ## 결정 피드백은 스낵바가 아니라 **팝업 안**이다(실측 근거)
/// ②였을 때는 `ScaffoldMessenger`로 스낵바를 띄웠다. 팝업이 되면서 그 경로가 깨진다 —
/// 스낵바는 아래 `Scaffold`에 붙어 그려지는데 모달 배리어가 그 위에 덮이기 때문이다.
/// 위젯 테스트로 스낵바 영역의 **가장 밝은 픽셀**을 재 보면 배리어가 있을 때
/// `(117,117,117)`, 없을 때 `(255,255,255)`였다(본문 대비 18.5:1 → 4.3:1). 사라지지는
/// 않지만 눈에 띄게 바래고, 하필 그 문구가 실패("정원이 찼거나…")를 알리는 유일한
/// 수단이라 **방장이 실패한 줄도 모르는** 상태가 된다.
///
/// 그래서 결정 결과를 팝업 **안**([_DecisionBanner])에서 알린다. 배리어 위에 있으니
/// 구조적으로 가려질 수 없고, 저절로 사라지지 않아 놓칠 수도 없다. 다만 요청이 도는
/// 동안 팝업이 닫힐 수 있으므로(`barrierDismissible`), 그때는 **스낵바로 떨어뜨린다** —
/// 팝업이 없으면 배리어도 없어 가려지지 않는다. 두 경로 모두 성공·실패를 함께 나른다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/diagnostics/error_reporter.dart';
import '../../../shared/diagnostics/report_handled_failure.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/join_request.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/error_reporter_provider.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/widgets/inline_error_banner.dart';
import '../state/share_providers.dart';

/// 팝업 가로 상한. 형제 [showShareGifticonConfirmDialog]와 같은 값이다 —
/// 이 저장소는 웹으로도 뜨는데, 상한이 없으면 데스크톱 폭에서 가로로 늘어나 팝업이
/// 아니라 페이지처럼 읽힌다.
const double _kMaxWidth = 400;

/// 팝업 세로 상한(화면 높이 대비 비율).
///
/// 높이를 내용에 맡기되([MainAxisSize.min]) 여기서 끊고 목록만 스크롤시킨다. 0.7인
/// 이유는 **위아래로 스크림이 보여야 모달로 읽히기** 때문이다 — 남는 30%가 여백이 된다.
/// 1에 가까울수록 전체 화면 push(=이 변경이 걷어낸 것)와 구분되지 않는다.
const double _kMaxHeightFactor = 0.7;

/// 좌우/상하 바깥 여백. 좌우 24는 형제 팝업과 같고, 360dp 폭에서 양쪽에 24dp씩
/// 스크림이 드러나 "뒤에 화면이 있다"는 것이 보인다.
const EdgeInsets _kInsetPadding = EdgeInsets.symmetric(
  horizontal: 24,
  vertical: 32,
);

/// 승인요청목록을 **모달 팝업**으로 띄운다. 그룹 상세의 '승인요청목록' 버튼이 호출한다.
///
/// 전체 화면 push가 아니라 팝업인 이유는 뒤의 그룹 상세를 지우지 않기 위해서다
/// (머리말 이력 ③). 반환값은 없다 — 승인·거절의 결과는 팝업 안에서 알리고, 목록은
/// 계약 스트림이 스스로 갱신한다.
Future<void> showJoinRequestsDialog(BuildContext context, String groupId) {
  return showDialog<void>(
    context: context,
    // ⚠️ **`barrierColor`를 넘기지 않는 것이 의도다.** 기본값(`Colors.black54`)이 뒤의
    //    그룹 상세를 어둡게 덮는 스크림이고, 그것이 이 변경의 핵심이다. 앱 테마가 이
    //    기본값을 덮어쓰지 않는 것을 확인했다 — `lib/`에 `barrierColor`·`DialogTheme`
    //    선언이 0건이고, `AppTheme.light`로 실제 렌더한 배리어 색이
    //    `Color(alpha: 0.5412, …, 0,0,0)` = `black54`였다(위젯 테스트로 실측).
    //    아래 `join_requests_dialog_test`가 그 값을 못박는다.
    barrierDismissible: true,
    builder: (BuildContext ctx) => JoinRequestsDialog(groupId: groupId),
  );
}

/// 승인요청목록 팝업 본체. 띄우는 것은 [showJoinRequestsDialog]가 한다.
class JoinRequestsDialog extends ConsumerStatefulWidget {
  /// 팝업을 생성한다.
  const JoinRequestsDialog({super.key, required this.groupId});

  /// 대상 그룹 id.
  final String groupId;

  @override
  ConsumerState<JoinRequestsDialog> createState() => _JoinRequestsDialogState();
}

class _JoinRequestsDialogState extends ConsumerState<JoinRequestsDialog> {
  /// 가장 최근 결정의 결과. null이면 배너를 그리지 않는다.
  ///
  /// 다음 결정이 덮어쓰고, 팝업을 닫으면 사라진다. 타이머로 지우지 않는 이유는
  /// 스낵바를 걷어낸 이유와 같다 — 저절로 사라지면 놓친다.
  _DecisionResult? _result;

  /// 행이 결정 결과를 올려보내는 지점. **표시했으면 `true`** 를 돌려준다.
  ///
  /// `false`면 팝업이 이미 닫힌 것이므로 호출한 행이 스낵바로 떨어뜨린다(머리말).
  bool _report(_DecisionResult result) {
    if (!mounted) return false;
    setState(() => _result = result);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 방장 여부를 **긍정적으로 아는 경우에만** 막는다.
    //
    // 비방장이 어떻게든 이 팝업에 닿으면 대기 목록 스트림은 보안 규칙에 막혀 에러가 되고,
    // 화면은 "불러오지 못했어요 · 다시 시도"를 띄운다 — 재시도가 영원히 성공할 수 없는
    // 지점에서 틀린 처방이다([InlineErrorBanner] 규약과 같은 판단). 그래서 원인을 아는
    // 자리에서 먼저 설명한다.
    //
    // 반대로 그룹을 **모르는** 경우(아직 로딩 중이거나, 삭제·탈퇴로 내 그룹에서 빠진 경우)는
    // 막지 않고 통과시킨다. 그 상태를 '권한 없음'으로 단정하면 로딩 한 프레임에 잘못된
    // 안내가 번쩍이고, 삭제된 그룹에는 사실이 아닌 이유를 대게 된다.
    final Group? group =
        ref.watch(groupByIdProvider(widget.groupId)).valueOrNull;
    final String? uid = ref.watch(
      sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
    );
    final bool knownNonOwner =
        group != null && uid != null && !group.isOwnedBy(uid);

    return Dialog(
      insetPadding: _kInsetPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      // 라우트 이름 — `scopesRoute`는 `DialogRoute`가 이미 주지만 **이름은 아무도 채우지
      // 않는다**(`AlertDialog`은 title로 채운다). 없으면 스크린리더가 무엇이 열렸는지
      // 알리지 못한 채 포커스만 본문 조각으로 옮겨 간다. 형제 팝업
      // (`share_gifticon_confirm_dialog.dart`)과 같은 조합으로 맞춰 둔다.
      child: Semantics(
        namesRoute: true,
        explicitChildNodes: true,
        label: '승인요청목록',
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _kMaxWidth,
            maxHeight: MediaQuery.sizeOf(context).height * _kMaxHeightFactor,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ── 헤더(고정) ──
              // 목록이 길어 스크롤해도 제목과 닫기 버튼은 남는다.
              _DialogHeader(onClose: () => Navigator.of(context).pop()),

              // ── 결정 피드백(고정) ──
              // 스크롤 밖에 둔다 — 목록 안에 있으면 12건 스크롤 중에 결과가
              // 화면 밖으로 밀려 스낵바를 걷어낸 이유가 그대로 되살아난다.
              if (_result != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: _DecisionBanner(result: _result!),
                ),

              // ── 본문 ──
              // `Flexible`(loose) + 각 갈래의 `shrinkWrap` 스크롤 뷰 = **내용만큼만
              // 차지하고 상한에서 스크롤**. `Flexible`만으로는 안 된다 — 늘어나려는
              // 스크롤 뷰가 0건에도 상한까지 차올라 빈 팝업이 화면의 70%를 먹는다.
              Flexible(
                child: knownNonOwner
                    ? const _OwnerOnlyNotice()
                    : _PendingList(groupId: widget.groupId, onResult: _report),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// 팝업 헤더 — 제목 + 닫기(X).
///
/// 배리어 탭(`barrierDismissible: true`)과 뒤로가기(Android back / 브라우저 back —
/// `DialogRoute`가 기본으로 pop된다. 막는 `PopScope`를 두지 않는 것이 의도다)에 더해
/// **눈에 보이는 닫기 경로**를 하나 둔다. 배리어 탭은 마우스·데스크톱 웹에서 발견하기
/// 어렵고, 뒤로가기는 웹에서 앱 전체를 벗어난 것처럼 느껴진다.
class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        children: <Widget>[
          // 형제 팝업(`share_gifticon_confirm_dialog.dart`)과 같은 제목 규격을 쓴다.
          Expanded(child: Text('승인요청목록', style: context.itemTitleStyle)),
          IconButton(
            onPressed: onClose,
            tooltip: '닫기',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// 승인·거절 한 건의 결과 — 문구와 실패 여부.
@immutable
class _DecisionResult {
  const _DecisionResult.ok(this.message) : failed = false;

  const _DecisionResult.failed(this.message) : failed = true;

  /// 사용자에게 보여 줄 한국어 문구(내부 예외 메시지 금지 — [InlineErrorBanner] 규약).
  final String message;

  /// 실패면 `true` — 배너 톤과 아이콘을 가른다.
  final bool failed;
}

/// 팝업 안에서 결정 결과를 알리는 배너(스낵바 대체 — 머리말의 실측 근거).
///
/// [InlineErrorBanner]를 쓰지 않는다. 그 배너는 **원천 스트림 로드 실패** 전용이고,
/// `onRetry: null`이면 "연결 상태를 확인한 뒤 앱을 다시 열어 주세요."를 스스로 덧붙이는데,
/// 여기 실패의 흔한 원인(정원이 찼다·이미 처리됐다)에는 틀린 처방이다.
class _DecisionBanner extends StatelessWidget {
  const _DecisionBanner({required this.result});

  final _DecisionResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // 성공은 차분하게(표면 톤), 실패는 error 계열로 — 색은 전부 스킴에서 온다.
    final Color tone = result.failed ? scheme.error : scheme.primary;

    // ⚠️ `liveRegion` — 걷어낸 `SnackBar`가 프레임워크에서 공짜로 받던 것이다
    //    (Flutter SDK `snack_bar.dart`가 본문을 `Semantics(container: true,
    //    liveRegion: true)`로 감싼다). 없으면 결과가 스크린리더에 전혀 통지되지 않는데,
    //    결정을 누른 버튼은 그 행과 함께 사라지므로 포커스로 되짚어 갈 수도 없다.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadii.tile),
          border: Border.all(color: tone.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              result.failed ? Icons.error_outline : Icons.check_circle_outline,
              size: 20,
              color: tone,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.message,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 방장이 아닌 사람이 닿았을 때의 안내(이중 방어).
class _OwnerOnlyNotice extends StatelessWidget {
  const _OwnerOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _BodyScroll(
      children: <Widget>[
        Text(
          '참여 요청은 방장만 볼 수 있어요.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 본문 공통 스크롤 뷰 — **내용만큼만 높이를 차지하고**, 상한을 넘으면 스크롤한다.
///
/// `shrinkWrap: true`가 그 "내용만큼만"을 만든다. 없으면 0건·1건에도 팝업이 상한
/// 높이까지 차올라 아래가 텅 빈다.
class _BodyScroll extends StatelessWidget {
  const _BodyScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      children: children,
    );
  }
}

/// 대기 중 참여 요청 목록 본문 — 로딩·에러·빈 상태·목록 네 갈래.
class _PendingList extends ConsumerWidget {
  const _PendingList({required this.groupId, required this.onResult});

  final String groupId;

  /// 결정 결과를 팝업에 올린다. 표시됐으면 `true`.
  final _ResultSink onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return ref.watch(pendingJoinRequestsProvider(groupId)).when(
          // 로딩·에러를 빈 목록으로 접지 않는다 — "요청 없음"과 구분되지 않으면 방장이
          // 대기자를 못 보고 지나간다(이 스트림이 유일한 신호다).
          //
          // `heightFactor: 1`이 없으면 `Center`가 남은 높이를 다 먹어 스피너 하나에
          // 팝업이 상한까지 늘어난다.
          loading: () => const _BodyScroll(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child:
                    Center(heightFactor: 1, child: CircularProgressIndicator()),
              ),
            ],
          ),
          // 이 스트림이 요청 도착의 유일한 신호다 — 재진입(autoDispose 해제) 말고도
          // 그 자리에서 되살릴 수단을 준다. 되살리는 범위(이 그룹 인스턴스만)와 세션
          // 계층 처리는 훅이 소유한다 — 그룹 상세의 공유 기프티콘 배너가 쓰는
          // `retrySharedGifticons(groupId:)`와 같은 형태다.
          error: (Object e, StackTrace _) => _BodyScroll(
            children: <Widget>[
              InlineErrorBanner(
                message: '참여 요청을 불러오지 못했어요.',
                onRetry: () => retryPendingJoinRequests(ref, groupId),
              ),
            ],
          ),
          data: (List<JoinRequest> requests) {
            if (requests.isEmpty) {
              // ⚠️ **0건이 되어도 팝업을 자동으로 닫지 않는다.**
              //
              // 마지막 요청을 처리하면 스트림이 빈 목록을 내보내는데, 그때 닫으면
              // ① 방금 띄운 결과 배너("○○님을 그룹에 추가했어요")가 **함께 사라져**
              //    스낵바를 걷어낸 이유가 그대로 되살아나고,
              // ② "닫힘"이 방장의 행동이 아니라 데이터 변화가 되어, 다른 기기가 마지막
              //    요청을 처리하거나 요청자가 취소해도 팝업이 제멋대로 사라진다.
              // 닫는 것은 방장이다(X·배리어·뒤로가기 셋 다 열려 있다).
              return _BodyScroll(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      heightFactor: 1,
                      child: Text('대기 중인 참여 요청이 없어요.',
                          style: theme.textTheme.bodySmall),
                    ),
                  ),
                ],
              );
            }
            return _BodyScroll(
              children: <Widget>[
                Text('대기 중 ${requests.length}명',
                    style: context.sectionTitleStyle),
                const SizedBox(height: 4),
                // ⚠️ key가 없으면 목록이 [A,B]→[B]로 줄 때 Flutter가 index 0의
                //    State를 재사용해 **B가 A의 `_busy = true`를 물려받는다** —
                //    남은 요청의 버튼이 영구히 잠긴다(실측 재현).
                //    요청 id는 계약상 유일하다.
                //
                // 카드 장식(`AppDecorations.softCard`)은 두지 않는다 — 팝업 표면이
                // 이미 카드다. 겹쳐 두면 카드 안의 카드가 된다.
                for (final JoinRequest r in requests)
                  _PendingRow(
                    key: ValueKey<String>(r.id),
                    request: r,
                    onResult: onResult,
                  ),
              ],
            );
          },
        );
  }
}

/// 결정 결과를 팝업에 올리는 콜백. **표시됐으면 `true`**(팝업이 닫혔으면 `false`).
typedef _ResultSink = bool Function(_DecisionResult result);

class _PendingRow extends ConsumerStatefulWidget {
  const _PendingRow({super.key, required this.request, required this.onResult});

  final JoinRequest request;
  final _ResultSink onResult;

  @override
  ConsumerState<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends ConsumerState<_PendingRow> {
  /// 처리 중 — 승인·거절 버튼을 함께 잠근다(중복 탭 → 같은 결정을 두 번 보낸다).
  bool _busy = false;

  /// 결과를 사용자에게 전달한다. 팝업이 살아 있으면 팝업 안 배너, 닫혔으면 스낵바.
  ///
  /// 스낵바가 **닫힌 뒤에만** 쓰이는 것이 중요하다 — 팝업이 떠 있는 동안 스낵바는
  /// 배리어에 덮여 바랜다(머리말의 픽셀 실측). 닫힌 뒤에는 덮을 배리어가 없다.
  void _deliver(
    _ResultSink sink,
    ScaffoldMessengerState messenger,
    _DecisionResult result,
  ) {
    if (sink(result)) return;
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _decide({required bool approve}) async {
    if (_busy) return;
    // 이 행은 대기 목록 스트림의 한 칸이라, 왕복 중 다른 기기의 결정·요청자 취소로
    // 목록에서 빠질 수 있다(아래 catch의 `mounted` 검사가 그것을 가정한다). 그래서
    // **`await` 전에** 안내 수단을 잡아 둔다 — 행이 죽어도 결과는 알려야 한다.
    // 팝업 쪽 경로(`onResult`)는 이 행이 아니라 팝업 State가 소유하므로 행이 죽어도
    // 살아 있고, 스낵바 경로는 팝업까지 닫힌 경우의 대비다.
    final _ResultSink sink = widget.onResult;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // 리포터도 `await` 전에 잡는다(`reportHandledFailure` 머리말 기준).
    final ErrorReporter reporter = ref.read(errorReporterProvider);
    final String displayName = widget.request.displayName;
    setState(() => _busy = true);
    try {
      final shareRepo = ref.read(shareRepositoryProvider);
      if (approve) {
        await shareRepo.approveJoinRequest(widget.request.id);
      } else {
        await shareRepo.rejectJoinRequest(widget.request.id);
      }
    } catch (e, s) {
      reportHandledFailureTo(reporter, e, s,
          context: approve
              ? 'JoinRequestsDialog.approveJoinRequest'
              : 'JoinRequestsDialog.rejectJoinRequest');
      if (mounted) setState(() => _busy = false);
      // 승인 실패의 흔한 원인이 정원이다 — 계약상 정원은 이 시점에 검사된다.
      _deliver(
        sink,
        messenger,
        _DecisionResult.failed(approve
            ? '승인하지 못했어요. 정원이 찼거나 요청이 이미 처리됐을 수 있어요.'
            : '거절하지 못했어요. 다시 시도해 주세요.'),
      );
      return;
    }
    // 성공하면 스트림에서 이 행이 사라지므로 setState로 되돌릴 필요가 없다.
    _deliver(
      sink,
      messenger,
      _DecisionResult.ok(
          approve ? '$displayName님을 그룹에 추가했어요.' : '참여 요청을 거절했어요.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final JoinRequest r = widget.request;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          // ⚠️ `titleLarge`가 아니다 — 이 앱의 AppTheme은 그것을 18/w700로 덮어써서
          //    아바타가 22 → 18로 줄어든다. `headlineSmall`이 22다. 테스트는 맨
          //    MaterialApp이라 이 차이를 못 보므로 여기에 적어 둔다.
          Text(r.avatarEmoji, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 12),
          Expanded(child: Text(r.displayName)),
          // 승인이 왼쪽, 거절이 오른쪽. Material 관례(주 동작을 오른쪽 끝에)와는
          // 반대이지만 화면 주인의 지시다. 순서를 되돌리면 **같은 자리를 누르던 손이
          // 반대 결정을 보낸다** — 둘 다 되돌리기 쉽지 않은 결정이라(승인은 멤버 추가,
          // 거절은 요청자에게 남는 기록) 테스트로 순서를 못박아 둔다.
          FilledButton(
            onPressed: _busy ? null : () => _decide(approve: true),
            child: const Text('승인'),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: _busy ? null : () => _decide(approve: false),
            child: const Text('거절'),
          ),
        ],
      ),
    );
  }
}
