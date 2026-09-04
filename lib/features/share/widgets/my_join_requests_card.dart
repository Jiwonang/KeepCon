/// 공유 탭 — 내가 보낸 참여 요청 카드.
///
/// **승인 전에는 어느 그룹인지 보여주지 않는다.** 초대 링크는 유출될 수 있고, 링크를 쥔
/// 사람이 그룹 이름·멤버 수를 알 수 있게 되면 승인제를 넣은 의미가 절반 사라진다. 계약의
/// [JoinRequest]가 그룹 표시 정보를 담지 않는 것과 같은 이유이며, 여기서 `groupId`로
/// 그룹을 되조회해 이름을 붙이면 그 계약을 화면이 우회하는 셈이 된다.
///
/// 거절도 목록에 남긴다 — 비멤버는 그룹 알림을 못 읽으므로 **요청자가 결과를 알 유일한
/// 경로**다(계약). 취소는 상태가 아니라 삭제라 목록에서 사라진다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/diagnostics/report_handled_failure.dart';
import '../../../shared/models/join_request.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/widgets/inline_error_banner.dart';
import '../state/share_providers.dart';

/// 내가 보낸 참여 요청 목록. 요청이 없으면 아무것도 그리지 않는다.
class MyJoinRequestsCard extends ConsumerWidget {
  /// 카드를 생성한다.
  const MyJoinRequestsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JoinRequest>> async = ref.watch(joinRequestsProvider);
    // 에러를 빈 목록으로 접지 않는다 — 이 카드가 **거절 통보의 유일한 경로**라
    // (비멤버는 그룹 알림을 못 읽는다), 조용히 사라지면 요청자는 결과를 영영 모른다.
    // 형제인 PendingJoinRequestsSection과 같은 규약이다.
    if (async.hasError) {
      // 재시도는 원천 family를 되살리는 계약 훅으로 — 이 축의 family는 keepAlive
      // 래퍼(joinRequestsProvider)가 붙잡고 있어 로그아웃 전에는 스스로 해제되지
      // 않으므로, 로그아웃 없이 죽은 스트림은 이 버튼이 유일한 제자리 복구 경로다.
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: InlineErrorBanner(
          message: '보낸 참여 요청을 불러오지 못했어요.',
          onRetry: () => retryJoinRequests(ref),
        ),
      );
    }
    final List<JoinRequest> requests =
        async.valueOrNull ?? const <JoinRequest>[];
    // 승인된 요청은 그룹 목록에 이미 그룹으로 나타나므로 여기서 중복 표시하지 않는다.
    final List<JoinRequest> visible = requests
        .where((JoinRequest r) => r.status != JoinRequestStatus.approved)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('보낸 참여 요청', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '방장이 승인하기 전까지는 그룹에 들어갈 수 없어요.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // key 없이 나열하면 목록이 줄 때 State가 재사용돼 남은 행이 앞 행의
            // `_busy`를 물려받는다 — `_PendingRow`에서 실측으로 확인한 사고다.
            for (final JoinRequest r in visible)
              _JoinRequestRow(key: ValueKey<String>(r.id), request: r),
          ],
        ),
      ),
    );
  }
}

class _JoinRequestRow extends ConsumerStatefulWidget {
  const _JoinRequestRow({super.key, required this.request});

  final JoinRequest request;

  @override
  ConsumerState<_JoinRequestRow> createState() => _JoinRequestRowState();
}

class _JoinRequestRowState extends ConsumerState<_JoinRequestRow> {
  /// 취소 중 — 버튼을 잠근다. 두 번 누르면 `cancelJoinRequest`가 두 번 불리고,
  /// 첫 호출이 성공한 뒤 두 번째가 실패해 **취소됐는데 실패 안내**가 뜬다.
  /// (형제 `_PendingRow`가 승인·거절에 **같은 잠금 규약**을 쓴다 — 라벨 전환은 여기만.)
  bool _busy = false;

  Future<void> _cancel() async {
    if (_busy) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    // try는 저장소 호출만 감싼다 — 취소는 됐는데 스낵바에서 예외가 나면 실패 안내가 떠
    // 사용자가 취소에 실패했다고 오해한다.
    try {
      await ref
          .read(shareRepositoryProvider)
          .cancelJoinRequest(widget.request.id);
    } catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: 'MyJoinRequestsCard.cancelJoinRequest');
      if (mounted) setState(() => _busy = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('요청을 취소하지 못했어요. 다시 시도해 주세요.')),
        );
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('참여 요청을 취소했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool pending = widget.request.status == JoinRequestStatus.pending;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(
            pending ? Icons.hourglass_top : Icons.do_not_disturb_on_outlined,
            size: 20,
            color: pending
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          // 그룹을 특정하지 않는다 — 상태 라벨은 계약(JoinRequestStatus)이 정본이다.
          Expanded(child: Text(widget.request.status.label)),
          if (pending)
            TextButton(
              onPressed: _busy ? null : _cancel,
              child: Text(_busy ? '취소 중…' : '취소'),
            ),
        ],
      ),
    );
  }
}
