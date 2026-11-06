/// KeepCon 공유 계약 — 기프티콘 카테고리 선택지.
///
/// `Gifticon.category`에 저장되는 문자열은 [GifticonCategory.label]이다(홈 필터가 저장된
/// 문자열을 그대로 비교한다). 등록(scan)과 수정(main) 두 화면이 같은 선택지를 내므로
/// scan에서 승격했다(CLAUDE.md 승격 규칙 ③ — 실제 두 번째 소비자가 생겼을 때).
///
/// ⚠️ 저장된 값이 이 목록 안에 있다는 보장은 없다 — 레거시·시드 문서에는 `카페` 같은 옛
/// 값이 있다. 수정 화면은 그런 값을 선택지에 함께 보여 주어 저장만으로 값이 바뀌지 않게 한다.
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
