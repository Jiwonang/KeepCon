/// main 페이지 — 기프티콘 카드(2열 그리드용).
///
/// 계약 [Gifticon]의 필드를 표시한다: 이미지 top + D-day 뱃지 + 브랜드(muted) +
/// 상품명(볼드) + 가격(볼드, 원) + 만료일(시계, 임박 시 danger).
///
/// 색·라운드·타이포는 전부 테마 토큰(`Theme.of(context)` / 공유 팔레트 어댑터)에서
/// 온다. 하드코딩 색 없음. 상태 전이는 계약 Repository.updateStatus로 위임(카드는 표시만).
library;

import 'package:flutter/material.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/util/date_format.dart' show formatYmdDot;
import '../../../shared/util/expiry_policy.dart';
import '../../../shared/util/money_format.dart' show formatWon;
import 'format.dart';

/// 2열 그리드에 놓이는 기프티콘 카드.
class GifticonGridCard extends StatelessWidget {
  final Gifticon gifticon;

  /// 카드 탭 콜백(상세/사용 진입 자리표시). null이면 비활성.
  final VoidCallback? onTap;

  const GifticonGridCard({super.key, required this.gifticon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final DateTime now = DateTime.now();
    final int daysLeft = daysUntilExpiry(gifticon.expiryDate, now: now);

    // 만료됐거나 임박했으면 만료일 텍스트를 danger로. 이미 지난 것도 빨갛게 두는 게
    // 자연스러우므로 [isExpiringSoon](하한 0)이 아니라 상한만 본다.
    final bool soon = daysLeft <= expirySoonDays;
    final Color dateColor = soon ? scheme.error : scheme.onSurfaceVariant;

    // 가격 예외 처리 (0 이하일 경우 '-' 표기, 불필요한 null 비교 제거)
    final int price = gifticon.price;
    final bool hasPrice = price > 0;
    final String priceText = hasPrice ? '${formatWon(price)}원' : '-';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 이미지 top + D-day 뱃지 오버레이.
            AspectRatio(
              aspectRatio: 16 / 11,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CardImage(gifticon: gifticon),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _DDayBadge(daysLeft: daysLeft),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 브랜드(muted).
                  Text(
                    gifticon.brand,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // 상품명(볼드).
                  Text(
                    gifticon.productName,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // 가격(볼드, 금액 없으면 '-').
                  Text(
                    priceText,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // 만료일(시계, 임박 시 danger).
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: dateColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          formatYmdDot(gifticon.expiryDate),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: dateColor,
                            fontWeight:
                                soon ? FontWeight.w700 : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 이미지 영역 — imagePath 있으면 이미지, 없으면 카테고리색 placeholder 블록.
class _CardImage extends StatelessWidget {
  final Gifticon gifticon;
  const _CardImage({required this.gifticon});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? path = gifticon.imagePath;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return Image.network(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(scheme),
        );
      }
    }
    return _placeholder(scheme);
  }

  Widget _placeholder(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.card_giftcard,
        size: 34,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// D-day 뱃지(pill). 어두운 강조면(darkSurface) + 온다크 텍스트.
class _DDayBadge extends StatelessWidget {
  final int daysLeft;
  const _DDayBadge({required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.darkSurface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        formatDDay(daysLeft),
        style: TextStyle(
          color: context.onDarkSurface,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
