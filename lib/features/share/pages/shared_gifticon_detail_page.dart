/// share 페이지 — 공유 기프티콘 상세(전체 화면).
///
/// 바코드/이미지 placeholder + 상태(잠김/찜/사용완료) + 액션(찜·사용완료·공유취소).
/// 상태 변경은 [ShareStore]에 반영되고 목록/뱃지가 동기화된다. 색 하드코딩 없음.
library;

import 'package:flutter/material.dart';

import '../data/korean_particle.dart';
import '../data/share_models.dart';
import '../data/share_store.dart';
import '../widgets/share_common.dart';

/// 공유 기프티콘 상세 화면. 셸의 push 패턴으로 전체화면 이동한다.
class SharedGifticonDetailPage extends StatelessWidget {
  const SharedGifticonDetailPage({super.key, required this.itemId});

  /// 표시할 공유 기프티콘 id.
  final String itemId;

  @override
  Widget build(BuildContext context) {
    final ShareStore store = ShareStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (BuildContext context, _) {
        // 스토어에서 항상 최신 항목을 조회. 공유취소 등으로 사라지면 이전 화면으로 복귀.
        SharedGifticon? item;
        for (final Group g in store.groups) {
          for (final SharedGifticon s in store.sharedOf(g.id)) {
            if (s.id == itemId) item = s;
          }
        }
        if (item == null) {
          return const Scaffold(
            body: Center(child: Text('기프티콘을 찾을 수 없어요.')),
          );
        }
        return _DetailBody(item: item);
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item});

  final SharedGifticon item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ShareStore store = ShareStore.instance;
    final bool locked = store.isLockedForMe(item);
    final bool reservedByMe = item.reservedByName == ShareStore.myName;
    // 다른 멤버가 이미 찜한 상태(내 찜 아님) — 찜 버튼 비활성.
    final bool reservedByOther = item.reservedByName != null && !reservedByMe;
    // 내가 공유한 기프티콘만 회수(공유 취소)할 수 있다.
    final bool iShared = item.sharedByName == ShareStore.myName;

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
                      Text(item.product, style: theme.textTheme.headlineSmall),
                    ],
                  ),
                ),
                ShareStatusBadge(status: item.status, locked: locked),
              ],
            ),
            const SizedBox(height: 8),
            Text('${item.sharedByName}님이 공유 · 유효기간 ${item.expiryLabel}',
                style: theme.textTheme.bodySmall),
            if (item.reservedByName != null) ...<Widget>[
              const SizedBox(height: 10),
              ReservedBadge(name: item.reservedByName!),
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
                    Text(item.barcode, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 잠김 안내.
            if (locked)
              _InfoBanner(
                icon: Icons.lock_outline,
                text: '${item.lockedByName}님이 사용 중이라 지금은 사용할 수 없어요.',
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
                onPressed: reservedByOther
                    ? null
                    : () => store.toggleReservation(item),
                icon:
                    Icon(reservedByMe ? Icons.bookmark : Icons.bookmark_border),
                label: Text(reservedByMe ? '찜 해제' : '찜하기 (사용 예정)'),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  if (store.markUsed(item)) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                          const SnackBar(content: Text('사용 완료 처리했어요.')));
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('사용 완료'),
              ),
              // 공유 취소(회수)는 내가 공유한 항목만 가능.
              if (iShared) ...<Widget>[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _confirmCancel(context, store, item),
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

  Future<void> _confirmCancel(
      BuildContext context, ShareStore store, SharedGifticon item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('공유 취소'),
        content: Text('${item.product}${item.product.eulReul} 그룹에서 회수할까요?'),
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
    if (ok == true && context.mounted) {
      store.cancelShare(item);
      Navigator.of(context).pop();
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
