/// main 페이지 — GifticonStatus / SortOption 의 표시용 라벨.
///
/// 표시 문자열은 UI 전용이며, 비교/저장에는 절대 쓰지 않는다(계약 enum으로만 비교).
library;

import 'package:flutter/material.dart';

import '../../../shared/models/gifticon.dart';

/// [GifticonStatus]의 한국어 표시 라벨.
String gifticonStatusLabel(GifticonStatus status) {
  switch (status) {
    case GifticonStatus.available:
      return '사용가능';
    case GifticonStatus.used:
      return '사용완료';
    case GifticonStatus.expired:
      return '만료';
  }
}

/// [GifticonStatus]별 배지 색.
Color gifticonStatusColor(GifticonStatus status) {
  switch (status) {
    case GifticonStatus.available:
      return const Color(0xFF2E7D32); // green 800
    case GifticonStatus.used:
      return const Color(0xFF616161); // grey 700
    case GifticonStatus.expired:
      return const Color(0xFFC62828); // red 800
  }
}

/// [SortOption]의 한국어 표시 라벨.
String sortOptionLabel(SortOption option) {
  switch (option) {
    case SortOption.expiryAsc:
      return '만료임박순';
    case SortOption.registeredDesc:
      return '최신 등록순';
    case SortOption.brandAsc:
      return '브랜드명순';
  }
}
