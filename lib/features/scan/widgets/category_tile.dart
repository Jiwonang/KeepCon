/// scan — 기프티콘 **카테고리** 선택(격자 타일 + 목록 enum).
///
/// `scan_page.dart`에서 떼어냈다. 옮기면서 이름을 바로잡았다 — 예전 이름은
/// `_GifticonGroup`·`_GroupTile`이었는데, 이 저장소에서 `Group`은 **공유 도메인
/// 모델**(`lib/shared/models/group.dart`)이라 그대로 공개하면 그룹 공유 기능의
/// 위젯으로 오해된다. 이 값이 흘러가는 곳도 `setCategory`다.
library;

import 'package:flutter/material.dart';

enum GifticonCategory {
  cafe(label: '카페/음료', emoji: '☕', icon: null),
  chicken(label: '치킨/피자', emoji: '🍗', icon: null),
  convenience(label: '편의점', emoji: '🏪', icon: null),
  bakery(label: '베이커리', emoji: '🥐', icon: null),
  voucher(label: '상품권/금액권', emoji: '💳', icon: null),
  etc(label: '기타', emoji: null, icon: Icons.more_horiz_rounded);

  const GifticonCategory({
    required this.label,
    required this.emoji,
    required this.icon,
  });

  final String label;
  final String? emoji;
  final IconData? icon;
}

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final GifticonCategory data;
  final bool selected;
  final VoidCallback onTap;

  // 타일 내용은 **높이가 고정이다** — 아이콘 칸, 간격, 한 줄 라벨, 위아래 여백.
  // 그리드가 높이를 폭에서 끌어오면(childAspectRatio) 좁은 화면에서 타일이 이
  // 높이보다 낮아져 내용이 넘친다. 값을 여기 모아 두고 [minExtentFor]가 같은
  // 값을 쓰게 해, 한쪽만 바뀌어 계산이 어긋나는 일을 막는다.
  static const double _padV = 20;
  static const double _iconBox = 34;
  static const double _emojiSize = 30;
  static const double _gap = 12;
  static const double _labelSize = 15;
  static const double _selectedBorder = 2;

  /// 내용이 넘치지 않으려면 타일이 최소한 가져야 하는 높이.
  ///
  /// 라벨 높이는 **어림하지 않고 실제로 잰다.** 행간 계수를 곱해 추정했더니
  /// 360px에서 5.5px 모자랐다 — 이유가 둘이고 둘 다 상수로는 못 맞춘다:
  ///
  /// - `치킨/피자`처럼 `/`가 섞인 라벨은 폰트 폴백이 일어나 2px 더 높다. 타일
  ///   높이는 하나뿐이므로 **가장 높은 라벨**을 기준으로 잡아야 한다.
  /// - 테두리가 안쪽 높이를 먹는다. 가장 두꺼운 경우인 **선택 상태**(위아래 각
  ///   [_selectedBorder] = 총 4px)를 기준으로 잡아야 한다. 비선택과의 '차이'인
  ///   2px으로 잡았다가 선택된 타일만 딱 그만큼 넘쳤다.
  ///
  /// [TextScaler]를 함께 넘겨 글자 확대 설정도 반영된다.
  static double minExtentFor(BuildContext context) {
    final TextStyle? labelStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontSize: _labelSize, fontWeight: FontWeight.w700);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    double tallestLabel = 0;
    for (final GifticonCategory group in GifticonCategory.values) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: group.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.height > tallestLabel) tallestLabel = painter.height;
      painter.dispose();
    }

    // 테두리도 안쪽 높이를 먹는다 — Flutter는 CSS와 달리 [BoxDecoration]의
    // 테두리 두께를 Container의 padding에 더한다. 가장 두꺼운 경우(선택 상태,
    // 위아래 각 [_selectedBorder])를 기준으로 잡아야 선택된 타일에서만 넘치는
    // 일이 없다 — 비선택과의 '차이'로 잡았다가 딱 그만큼 2px 모자랐다.
    //
    // 끝의 1px은 반올림 여유다 — 위 계산은 필요한 높이와 **정확히** 같아져서
    // 서브픽셀 반올림 한 번이면 다시 넘친다. 1px 남는 것은 눈에 띄지 않지만
    // 모자라면 오버플로로 드러난다.
    return _padV * 2 +
        _selectedBorder * 2 +
        _iconExtentFor(scaler) +
        _gap +
        tallestLabel +
        1;
  }

  /// 아이콘 칸의 높이.
  ///
  /// 칸에 든 이모지는 [Icon]이 아니라 **[Text]라서 글자 확대 설정을 따라 커진다**
  /// (`Icon`은 `applyTextScaling` 기본값이 false라 그대로다 — 그래서 '기타'
  /// 타일만 멀쩡했다). 칸을 상수 [_iconBox]로 고정하면 배율이 오를 때 이모지가
  /// 칸을 넘어 아래 라벨을 덮는다 — 2.0배에서 자연 높이 60px, [_gap] 12px을
  /// 넘어 13px이 라벨 위로 내려온다.
  ///
  /// ⚠️ 이 결함은 **오버플로 예외를 던지지 않는다.** `SizedBox`가 tight 제약이라
  /// 렌더 객체는 자기 크기를 34로 보고하고 이모지는 그냥 칸 밖에 그려진다.
  /// 그래서 폭·배율 전수 스윕으로도 잡히지 않았다 — 눈으로 봐야 보인다.
  ///
  /// 확대분이 [_iconBox]를 넘을 때만 칸을 넓혀 기본 배율의 모양은 그대로 둔다.
  static double _iconExtentFor(TextScaler scaler) {
    final double emoji = scaler.scale(_emojiSize);
    return emoji > _iconBox ? emoji : _iconBox;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color fg = selected ? scheme.primary : scheme.onSurface;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: _padV,
            horizontal: 10,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: 0.25),
              width: selected ? _selectedBorder : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _iconExtentFor(MediaQuery.textScalerOf(context)),
                child: Center(
                  child: data.icon != null
                      ? Icon(data.icon, color: fg, size: 32)
                      : Text(
                          data.emoji!,
                          style: const TextStyle(
                            fontSize: _emojiSize,
                            height: 1,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: _gap),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: _labelSize,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
