/// share 페이지 — 공유 기프티콘 상세(전체 화면).
///
/// 바코드/이미지 placeholder + 상태(잠김/찜/사용완료) + 액션(찜·사용완료·공유취소).
/// 상태 변경은 계약 [ShareRepository]에 반영되고 목록/뱃지가 동기화된다. 사용 완료 시
/// 원본 [Gifticon]도 `GifticonStatus.used`로 동기화되어 메인 목록에 반영된다(계약 경계면).
/// 색 하드코딩 없음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/share.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/util/korean_particle.dart';
import '../state/share_providers.dart';
import '../widgets/share_common.dart';
import '../widgets/share_format.dart';

/// 공유 기프티콘 상세 화면. 셸의 push 패턴으로 전체화면 이동한다.
class SharedGifticonDetailPage extends ConsumerWidget {
  const SharedGifticonDetailPage({super.key, required this.itemId});

  /// 표시할 공유 기프티콘 id.
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 항상 최신 항목을 조회. 공유취소 등으로 사라지면 안내를 표시한다.
    final SharedGifticon? item = ref.watch(sharedItemByIdProvider(itemId));
    if (item == null) {
      return const Scaffold(
        body: Center(child: Text('기프티콘을 찾을 수 없어요.')),
      );
    }
    return _DetailBody(item: item);
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.item});

  final SharedGifticon item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? uid = ref.watch(shareCurrentUserProvider).value?.id;
    final MemberNames names = ref.watch(memberNamesProvider);
    final String actorId = uid ?? '';

    final bool locked = item.isLockedFor(actorId);
    final bool reservedByMe = uid != null && item.reservedByUserId == uid;
    // 다른 멤버가 이미 찜한 상태(내 찜 아님) — 찜 버튼 비활성.
    final bool reservedByOther = item.isReservedByOther(actorId);
    // 내가 공유한 기프티콘만 회수(공유 취소)할 수 있다.
    final bool iShared = uid != null && item.sharedByUserId == uid;

    return Scaffold(
      appBar: AppBar(title: const Text('공유 기프티콘')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: <Widget>[
            // 이미지 placeholder.
            AspectRatio(
              aspectRatio: 1.6,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.card_giftcard,
                    size: 64, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.brand, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(item.productName,
                          style: theme.textTheme.headlineSmall),
                    ],
                  ),
                ),
                ShareStatusBadge(status: item.status, locked: locked),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                '${names.isMe(item.sharedByUserId) ? '내가' : '${names.labelFor(item.sharedByUserId)}님이'} 공유 · '
                '유효기간 ${formatExpiryLabel(item.expiryDate)}',
                style: theme.textTheme.bodySmall),
            if (item.reservedByUserId != null) ...<Widget>[
              const SizedBox(height: 10),
              ReservedBadge(
                name: names.labelFor(item.reservedByUserId!),
                isMe: names.isMe(item.reservedByUserId!),
              ),
            ],
            const SizedBox(height: 20),

            // 바코드 placeholder.
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: <Widget>[
                    Icon(Icons.qr_code_2, size: 96, color: scheme.onSurface),
                    const SizedBox(height: 8),
                    Text(item.barcode ?? '바코드 정보 없음',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 잠김 안내.
            if (locked)
              _InfoBanner(
                icon: Icons.lock_outline,
                text: item.lockedByUserId != null
                    ? '${names.labelFor(item.lockedByUserId!)}님이 사용 중이라 지금은 사용할 수 없어요.'
                    : '다른 멤버가 사용 중이라 지금은 사용할 수 없어요.',
              ),
            if (item.isUsed)
              const _InfoBanner(
                icon: Icons.check_circle_outline,
                text: '이미 사용 완료된 기프티콘이에요.',
              ),

            // 액션 — 사용 완료·잠김(다른 멤버 사용중) 상태에선 노출하지 않는다.
            if (!item.isUsed && !locked) ...<Widget>[
              OutlinedButton.icon(
                // 다른 멤버가 이미 찜했으면 비활성(남의 찜을 덮어쓰지 않음).
                onPressed:
                    reservedByOther ? null : () => _toggleReserve(context, ref),
                icon:
                    Icon(reservedByMe ? Icons.bookmark : Icons.bookmark_border),
                label: Text(reservedByMe ? '찜 해제' : '찜하기 (사용 예정)'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _markUsed(context, ref),
                icon: const Icon(Icons.check),
                label: const Text('사용 완료'),
              ),
              // 공유 취소(회수)는 내가 공유한 항목만 가능.
              if (iShared) ...<Widget>[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _confirmCancel(context, ref),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  icon: const Icon(Icons.undo),
                  label: const Text('공유 취소 (회수)'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReserve(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shareRepositoryProvider).toggleReservation(item.id);
    } on StateError {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 찜할 수 없어요.')));
    }
  }

  Future<void> _markUsed(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shareRepositoryProvider).markUsed(item.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('사용 완료 처리했어요.')));
    } on StateError {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 사용 완료할 수 없어요.')));
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('공유 취소'),
        content:
            Text('${item.productName}${item.productName.eulReul} 그룹에서 회수할까요?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('닫기')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('회수')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // 버튼은 이미 공유자·미사용중일 때만 노출되지만, 저장소 가드가 최종 판정한다.
    try {
      await ref.read(shareRepositoryProvider).cancelShare(item.id);
      navigator.pop();
    } on StateError {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 회수할 수 없어요.')));
    }
  }
}

/// 상세 상단 안내 배너(잠김/사용완료).
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
