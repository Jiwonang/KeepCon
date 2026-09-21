/// share 페이지 — 승인요청목록(방장이 보는 참여 요청 대기 목록, 전체 화면).
///
/// **방장만 읽는다.** 일반 멤버에게도 열지 않는다 — 아직 멤버가 아닌 사람들의 이름이고,
/// 보안 규칙도 같은 선을 긋는다(계약 참조). 진입점(그룹 상세의 '승인요청목록' 버튼)이
/// `iAmOwner`로 게이팅하고, 이 화면도 [_OwnerOnlyNotice]로 한 겹 더 막는다.
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
/// 이력: 원래는 그룹 상세 안에 인라인으로 펼쳐지던 `PendingJoinRequestsSection`이었다.
/// 목록이 상세 화면의 세로 길이를 요청 수만큼 늘려 아래의 공유 기프티콘 섹션을 밀어냈고,
/// 0건이면 통째로 사라져 방장이 "요청이 없다"는 것조차 확인할 수 없었다. 진입점(버튼)과
/// 목록(이 화면)을 분리해 둘 다 해소한다.
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

/// 승인요청목록 화면. 그룹 상세의 '승인요청목록' 버튼에서 push 한다.
class JoinRequestsPage extends ConsumerWidget {
  /// 화면을 생성한다.
  const JoinRequestsPage({super.key, required this.groupId});

  /// 대상 그룹 id.
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 방장 여부를 **긍정적으로 아는 경우에만** 막는다.
    //
    // 비방장이 어떻게든 이 화면에 닿으면 대기 목록 스트림은 보안 규칙에 막혀 에러가 되고,
    // 화면은 "불러오지 못했어요 · 다시 시도"를 띄운다 — 재시도가 영원히 성공할 수 없는
    // 지점에서 틀린 처방이다([InlineErrorBanner] 규약과 같은 판단). 그래서 원인을 아는
    // 자리에서 먼저 설명한다.
    //
    // 반대로 그룹을 **모르는** 경우(아직 로딩 중이거나, 삭제·탈퇴로 내 그룹에서 빠진 경우)는
    // 막지 않고 통과시킨다. 그 상태를 '권한 없음'으로 단정하면 로딩 한 프레임에 잘못된
    // 안내가 번쩍이고, 삭제된 그룹에는 사실이 아닌 이유를 대게 된다.
    final Group? group = ref.watch(groupByIdProvider(groupId)).valueOrNull;
    final String? uid = ref.watch(
      sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
    );
    final bool knownNonOwner =
        group != null && uid != null && !group.isOwnedBy(uid);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('승인요청목록', style: context.navTitleStyle),
      ),
      body: SafeArea(
        top: false,
        child: knownNonOwner
            ? const _OwnerOnlyNotice()
            : _PendingList(groupId: groupId),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Center(
        child: Text(
          '참여 요청은 방장만 볼 수 있어요.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// 대기 중 참여 요청 목록 본문 — 로딩·에러·빈 상태·목록 네 갈래.
class _PendingList extends ConsumerWidget {
  const _PendingList({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ref.watch(pendingJoinRequestsProvider(groupId)).when(
          // 로딩·에러를 빈 목록으로 접지 않는다 — "요청 없음"과 구분되지 않으면 방장이
          // 대기자를 못 보고 지나간다(이 스트림이 유일한 신호다).
          loading: () => const Center(child: CircularProgressIndicator()),
          // 이 스트림이 요청 도착의 유일한 신호다 — 재진입(autoDispose 해제) 말고도
          // 그 자리에서 되살릴 수단을 준다. 되살리는 범위(이 그룹 인스턴스만)와 세션
          // 계층 처리는 훅이 소유한다 — 그룹 상세의 공유 기프티콘 배너가 쓰는
          // `retrySharedGifticons(groupId:)`와 같은 형태다.
          error: (Object e, StackTrace _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: <Widget>[
              InlineErrorBanner(
                message: '참여 요청을 불러오지 못했어요.',
                onRetry: () => retryPendingJoinRequests(ref, groupId),
              ),
            ],
          ),
          data: (List<JoinRequest> requests) {
            if (requests.isEmpty) {
              // 인라인 섹션이던 시절에는 0건이면 통째로 사라졌다. 여기는 사용자가
              // 스스로 들어온 전용 화면이라, 사라지면 빈 화면만 남는다.
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                child: Center(
                  child: Text('대기 중인 참여 요청이 없어요.',
                      style: theme.textTheme.bodySmall),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: <Widget>[
                Text('대기 중 ${requests.length}명',
                    style: context.sectionTitleStyle),
                const SizedBox(height: 12),
                Container(
                  decoration: AppDecorations.softCard(scheme),
                  clipBehavior: Clip.antiAlias,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: <Widget>[
                      // ⚠️ key가 없으면 목록이 [A,B]→[B]로 줄 때 Flutter가 index 0의
                      //    State를 재사용해 **B가 A의 `_busy = true`를 물려받는다** —
                      //    남은 요청의 버튼이 영구히 잠긴다(실측 재현).
                      //    요청 id는 계약상 유일하다.
                      for (final JoinRequest r in requests)
                        _PendingRow(key: ValueKey<String>(r.id), request: r),
                    ],
                  ),
                ),
              ],
            );
          },
        );
  }
}

class _PendingRow extends ConsumerStatefulWidget {
  const _PendingRow({super.key, required this.request});

  final JoinRequest request;

  @override
  ConsumerState<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends ConsumerState<_PendingRow> {
  /// 처리 중 — 승인·거절 버튼을 함께 잠근다(중복 탭 → 같은 결정을 두 번 보낸다).
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    if (_busy) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // 이 행은 대기 목록 스트림의 한 칸이라, 왕복 중 다른 기기의 결정·요청자 취소로
    // 목록에서 빠질 수 있다(아래 catch의 `mounted` 검사가 그것을 가정한다). 리포터도
    // `await` 전에 잡는다(`reportHandledFailure` 머리말 기준).
    final ErrorReporter reporter = ref.read(errorReporterProvider);
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
              ? 'JoinRequestsPage.approveJoinRequest'
              : 'JoinRequestsPage.rejectJoinRequest');
      if (mounted) setState(() => _busy = false);
      // 승인 실패의 흔한 원인이 정원이다 — 계약상 정원은 이 시점에 검사된다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(approve
              ? '승인하지 못했어요. 정원이 찼거나 요청이 이미 처리됐을 수 있어요.'
              : '거절하지 못했어요. 다시 시도해 주세요.'),
        ));
      return;
    }
    // 성공하면 스트림에서 이 행이 사라지므로 setState로 되돌릴 필요가 없다.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(approve
            ? '${widget.request.displayName}님을 그룹에 추가했어요.'
            : '참여 요청을 거절했어요.'),
      ));
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
          TextButton(
            onPressed: _busy ? null : () => _decide(approve: false),
            child: const Text('거절'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _busy ? null : () => _decide(approve: true),
            child: const Text('승인'),
          ),
        ],
      ),
    );
  }
}
