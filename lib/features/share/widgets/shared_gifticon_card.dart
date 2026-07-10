/// share 페이지 — 공유 기프티콘 카드(그룹 상세·공유 메인 공용).
///
/// 계약 [SharedGifticon]을 소비한다. 표시 이름(공유자/찜)은 [SharedGifticon]이 userId만
/// 담으므로 상위에서 [MemberNames]로 해석해 넘긴다. 잠김/사용완료 판정은 모델 predicate로.
/// 색/라운드는 전부 `Theme.of(context)`에서 온다. 하드코딩 색 없음.
library;

import 'package:flutter/material.dart';

import '../../../shared/models/share.dart';
import '../state/share_providers.dart';
import 'share_common.dart';

/// 그룹에 공유된 기프티콘 한 개 카드. 탭하면 상세로 이동한다.
///
/// 잠김(다른 멤버 사용중)이면 흐리게 + 잠김 뱃지, 찜이면 찜 뱃지를 표시한다.
class SharedGifticonCard extends StatelessWidget {
  const SharedGifticonCard({
    super.key,
    required this.item,
    required this.names,
    required this.currentUserId,
    required this.onTap,
  });

  /// 표시할 공유 기프티콘.
  final SharedGifticon item;

  /// userId→표시 이름 해석기.
  final MemberNames names;

  /// 현재 사용자 id(잠김/찜 판정 기준). 미로그인이면 null.
  final String? currentUserId;

  /// 카드 탭 콜백(상세 이동).
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String uid = currentUserId ?? '';
    final bool locked = item.isLockedFor(uid);
    final bool dimmed = locked || item.isUsed;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Opacity(
          opacity: dimmed ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      Icon(Icons.card_giftcard, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.brand,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.productName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Icon(Icons.person_outline,
                              size: 13, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${names.labelFor(item.sharedByUserId)}님이 공유',
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (item.reservedByUserId != null) ...<Widget>[
                        const SizedBox(height: 6),
                        ReservedBadge(
                            name: names.labelFor(item.reservedByUserId!)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ShareStatusBadge(status: item.status, locked: locked),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
