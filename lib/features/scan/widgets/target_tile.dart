/// scan — '저장할 그룹 선택'의 타일 하나('내 지갑'과 그룹이 같은 모양을 쓴다).
///
/// `scan_page.dart`에서 떼어냈다.
library;

import 'package:flutter/material.dart';

import 'package:keepcon/shared/theme/theme_tokens.dart';

/// '저장할 그룹 선택'의 타일 하나 — '내 지갑'과 그룹이 같은 모양을 쓴다.
///
/// 둘을 한 위젯으로 두는 이유는 **선택 상태의 시각 언어가 갈라지지 않게** 하기
/// 위해서다. 예전에는 '내 지갑' 타일만 인라인으로 있었고, 그룹 타일을 따로 짜면
/// 테두리 두께·색·체크 아이콘이 조용히 어긋난다.
class TargetTile extends StatelessWidget {
  /// 그룹 이모지 글자 크기. 형제 `CategoryTile`(`widgets/category_tile.dart`)의
  /// `_emojiSize`(30)와 다른 값이다 — 저쪽은 격자 카드, 이쪽은 한 줄짜리 목록
  /// 타일이라 시각 무게가 다르다.
  ///
  /// 대괄호 링크로 두지 않는 이유: 이 파일은 `category_tile.dart`를 import하지
  /// 않으므로 `[CategoryTile]`이 스코프 밖이라 해석되지 않는다. doc 전용 import는
  /// 이 저장소 설정에서 `unused_import` 경고가 된다.
  static const double _emojiSize = 22;

  const TargetTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
  });

  /// 이모지가 없을 때 쓰는 대체 아이콘.
  final IconData icon;

  /// 그룹 이모지. 그룹이 설정해 두지 않았으면 null이고 [icon]으로 떨어진다.
  final String? emoji;

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? trimmedEmoji = emoji?.trim();
    final bool hasEmoji = trimmedEmoji != null && trimmedEmoji.isNotEmpty;

    return InkWell(
      onTap: onTap,
      // `AppRadii.panel`(16) — 토큰 doc이 용도로 '이모지 타일'을 명시한다.
      // 값은 리터럴 16과 같아 모양은 그대로다.
      borderRadius: BorderRadius.circular(AppRadii.panel),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            // 이모지는 [Text]라 글자 확대 설정을 따라 커지는데 [Icon]은
            // `applyTextScaling` 기본값이 false라 그대로다. 그냥 두면 '내 지갑'
            // 타일과 그룹 타일의 높이가 **모든 배율에서 어긋난다**(실측: 1.0배
            // 64 vs 69, 2.0배 88 vs 101). 형제 [CategoryTile]이 같은 함정을 겪고
            // doc에 적어 뒀다 — 오버플로 예외를 던지지 않아 눈으로만 보인다.
            //
            // 저쪽은 격자라 칸을 넓히는 쪽으로 풀었지만(`_iconExtentFor`), 여기는
            // 유연한 Row라 **아이콘도 함께 확대**시키는 편이 단순하고, 라벨이
            // 이미 확대되므로 셋의 배율이 한 축으로 모인다.
            if (hasEmoji)
              // height: 1 — 없으면 기본 줄높이가 붙어 아이콘 갈래보다 크다.
              Text(
                trimmedEmoji,
                style: const TextStyle(fontSize: _emojiSize, height: 1),
              )
            else
              Icon(
                icon,
                applyTextScaling: true,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                // 그룹 이름은 사용자가 짓는 값이라 길 수 있다. '내 지갑'과 달리
                // 폭을 가정할 수 없어 한 줄로 잘라 낸다.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (selected) ...<Widget>[
              const SizedBox(width: 8),
              Icon(Icons.check_circle_rounded, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}
