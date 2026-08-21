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
      final ThemeData t = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          '보낸 참여 요청을 불러오지 못했어요.',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.error),
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
            for (final JoinRequest r in visible) _JoinRequestRow(request: r),
          ],
        ),
      ),
    );
  }
}

class _JoinRequestRow extends ConsumerWidget {
  const _JoinRequestRow({required this.request});

  final JoinRequest request;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // try는 저장소 호출만 감싼다 — 취소는 됐는데 스낵바에서 예외가 나면 실패 안내가 떠
    // 사용자가 취소에 실패했다고 오해한다.
    try {
      await ref.read(shareRepositoryProvider).cancelJoinRequest(request.id);
    } catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: 'MyJoinRequestsCard.cancelJoinRequest');
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
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool pending = request.status == JoinRequestStatus.pending;
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
          Expanded(child: Text(request.status.label)),
          if (pending)
            TextButton(
              onPressed: () => _cancel(context, ref),
              child: const Text('취소'),
            ),
        ],
      ),
    );
  }
}
