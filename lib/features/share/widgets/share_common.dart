/// share 페이지 — 공통 UI 조각(뱃지·아바타 등).
///
/// 색/라운드는 전부 `Theme.of(context)` + [ShareThemeTokens]에서 온다. 하드코딩 색 없음.
library;

import 'package:flutter/material.dart';

import '../../../shared/models/share.dart';
import 'share_tokens.dart';

/// 이모지 아바타 원(darkSurface 강조면). 그룹/멤버 공용.
class EmojiAvatar extends StatelessWidget {
  const EmojiAvatar({super.key, required this.emoji, this.size = 48});

  /// 표시 이모지.
  final String emoji;

  /// 원 지름.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.darkSurface,
        shape: BoxShape.circle,
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.46)),
    );
  }
}

/// 공유 기프티콘 상태 뱃지. [ShareStatus] enum을 소비한다(매직 스트링 금지).
///
/// - [locked] 이 true면 잠김(다른 멤버 사용중) 톤으로 표시한다.
class ShareStatusBadge extends StatelessWidget {
  const ShareStatusBadge({
    super.key,
    required this.status,
    this.locked = false,
  });

  /// 표시할 상태.
  final ShareStatus status;

  /// 다른 멤버가 사용중이라 나에게 잠긴 상태인지.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    late final Color fg;
    late final String label;
    late final IconData? icon;
    // 잠김(다른 멤버 사용중)은 [locked] 또는 [ShareStatus.inUse]가 모두 커버하므로,
    // 나머지 분기는 available/used만 다룬다.
    if (locked || status == ShareStatus.inUse) {
      fg = scheme.error;
      label = '잠김';
      icon = Icons.lock_outline;
    } else if (status == ShareStatus.used) {
      fg = scheme.onSurfaceVariant;
      label = ShareStatus.used.label;
      icon = Icons.check;
    } else {
      fg = scheme.primary;
      label = ShareStatus.available.label;
      icon = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 찜(사용 예정) 뱃지 — 본인은 "내가 찜", 타인은 "OO님 찜".
class ReservedBadge extends StatelessWidget {
  const ReservedBadge({super.key, required this.name, this.isMe = false});

  /// 찜한 사람 표시 이름(타인일 때 사용).
  final String name;

  /// 찜한 주체가 현재 사용자(나)인지 — 참이면 "내가 찜"으로 표시(어색한 "나님 찜" 방지).
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bookmark, size: 12, color: scheme.secondary),
          const SizedBox(width: 3),
          Text(
            isMe ? '내가 찜' : '$name님 찜',
            style: TextStyle(
              color: scheme.secondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
