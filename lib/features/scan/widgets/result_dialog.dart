/// scan — 저장 결과 다이얼로그(한도 도달·중복 등록)의 **공유 배치 규약.**
///
/// `scan_page.dart`에서 떼어냈다. 값과 근거는 그대로다.
library;

import 'package:flutter/material.dart';

/// 저장 결과 안내 다이얼로그(한도 도달·중복 등록)가 **공유하는 배치 규약.**
///
/// 둘은 같은 화면군에서 같은 역할을 하는 형제다. 값을 각자 들고 있으면 한쪽만
/// 고쳐졌을 때 여백·행간이 어긋나 폭이 들쭉날쭉해 보인다 — 한곳에 두어 그
/// 비대칭이 생길 여지를 없앤다.
abstract final class ScanResultDialog {
  /// 좁은 화면일수록 좌우 여백이 본문 폭을 크게 깎는다 — 375px에서 기본
  /// 여백(40)이면 글자가 쓸 수 있는 폭이 250px 남짓이라 짧은 문장도 두 줄로
  /// 접힌다. 여백을 줄여 폭을 돌려주면 줄 수가 줄고, 줄 수가 줄면 읽기 쉽다.
  ///
  /// 넓은 화면에서는 기본값을 유지한다 — 거기서는 폭이 모자라지 않고, 문단이
  /// 지나치게 길어지면 오히려 시선이 줄을 놓친다.
  static EdgeInsets insetPadding(BuildContext context) => EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 400 ? 16 : 40,
        vertical: 24,
      );

  /// 흐린 보조 안내 스타일.
  ///
  /// 좁은 폭에서 두 줄로 접히는데, bodySmall 기본 행간으로는 접힌 두 줄이 서로
  /// 붙어 **어디까지가 한 문장인지** 보이지 않는다. 글자 크기는 그대로 두고
  /// 행간만 넓힌다.
  static TextStyle? mutedStyle(ThemeData theme) =>
      theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.45,
      );
}
