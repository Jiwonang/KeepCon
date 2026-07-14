/// scan 페이지 — 입력 경로별 액센트 색 (페이지 로컬 토큰).
///
/// 카메라 경로는 brand(그린)라 테마 `colorScheme.primary`를 그대로 쓴다. 갤러리(블루)·
/// 직접입력(퍼플)은 **이 페이지에서만** 쓰는 소스 구분색이라 공유 팔레트에 올리지 않고
/// 여기 로컬 상수로 둔다.
///
/// 왜 lib/shared로 승격하지 않나 (CLAUDE.md '늦게 승격'):
/// - 지금은 소비자가 스캔 페이지 하나뿐이다. 두 번째 소비자가 실제로 생기면 그때
///   `contract-architect`에게 공유 승격을 요청한다. 투기적 승격은 금한다.
/// - 하드코딩 산발을 막기 위해 인라인 hex 대신 이름 있는 상수로 모아둔다.
library;

import 'package:flutter/material.dart';

/// 스캔 입력 경로 타일의 액센트 색.
abstract final class ScanAccents {
  /// 갤러리 경로(블루).
  static const Color gallery = Color(0xFF3B82F6);

  /// 직접 입력 경로(퍼플).
  static const Color manual = Color(0xFF7C5CE0);

  /// 아이콘 타일 배경(액센트의 연한 틴트) 불투명도.
  static const double tileTintAlpha = 0.12;
}
