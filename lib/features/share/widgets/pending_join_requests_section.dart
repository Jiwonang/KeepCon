/// 그룹 상세 — 방장이 보는 참여 요청 대기 목록.
///
/// **방장만 읽는다.** 일반 멤버에게도 열지 않는다 — 아직 멤버가 아닌 사람들의 이름이고,
/// 보안 규칙도 같은 선을 긋는다(계약 참조). 호출부가 `iAmOwner`로 게이팅한다.
///
/// 이 스트림이 **방장에게 요청 도착을 알리는 유일한 신호**다. 알림 문서로 알리려면
/// 비멤버가 `notifications`에 써야 하는데 규칙이 막고, 서버로 대신 쓰려면 유료 플랜이
/// 필요하다 — 대기 목록이 같은 정보를 이미 갖고 있으니 둘 다 치르지 않는다.
///
/// 정원은 **승인 시점**에 검사된다(계약) — 대기자가 자리를 선점하면 방장이 정작 받고 싶은
/// 사람을 못 넣기 때문이다. 그래서 정원이 찬 그룹에도 요청은 쌓이고, 승인만 거부된다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/diagnostics/report_handled_failure.dart';
import '../../../shared/models/join_request.dart';
import '../../../shared/providers/repositories.dart';
import '../state/share_providers.dart';

/// [groupId] 그룹의 대기 중 참여 요청 목록(방장 전용).
class PendingJoinRequestsSection extends ConsumerWidget {
  /// 섹션을 생성한다.
  const PendingJoinRequestsSection({super.key, required this.groupId});

  /// 대상 그룹 id.
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return ref.watch(pendingJoinRequestsProvider(groupId)).when(
          // 로딩·에러를 빈 목록으로 접지 않는다 — "요청 없음"과 구분되지 않으면 방장이
          // 대기자를 못 보고 지나간다(이 스트림이 유일한 신호다).
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, StackTrace _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '참여 요청을 불러오지 못했어요.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
          data: (List<JoinRequest> requests) {
            if (requests.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 24),
                Row(
                  children: <Widget>[
                    Text('참여 요청', style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Badge(label: Text('${requests.length}')),
                  ],
                ),
                const SizedBox(height: 8),
                // ⚠️ key가 없으면 목록이 [A,B]→[B]로 줄 때 Flutter가 index 0의 State를
                //    재사용해 **B가 A의 `_busy = true`를 물려받는다** — 남은 요청의
                //    버튼이 영구히 잠긴다(실측 재현). 요청 id는 계약상 유일하다.
                for (final JoinRequest r in requests)
                  _PendingRow(key: ValueKey<String>(r.id), request: r),
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
    setState(() => _busy = true);
    try {
      final shareRepo = ref.read(shareRepositoryProvider);
      if (approve) {
        await shareRepo.approveJoinRequest(widget.request.id);
      } else {
        await shareRepo.rejectJoinRequest(widget.request.id);
      }
    } catch (e, s) {
      reportHandledFailure(ref, e, s,
          context: approve
              ? 'PendingJoinRequests.approveJoinRequest'
              : 'PendingJoinRequests.rejectJoinRequest');
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
          Text(r.avatarEmoji, style: const TextStyle(fontSize: 22)),
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
