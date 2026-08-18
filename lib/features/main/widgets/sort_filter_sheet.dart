/// main 페이지 — 정렬/필터 바텀시트.
///
/// 홈에는 컨트롤을 상시 노출할 자리가 없다(인사 헤더·검색바·만료 배너·통계 3카드가
/// 이미 첫 화면을 채운다). 그래서 정렬/필터는 시트로 접어 두고, 검색바 옆 필터 버튼과
/// 섹션 헤더의 정렬 라벨 **두 진입점이 같은 시트**를 연다.
///
/// 시트 내용은 기존 [SortFilterBar]를 그대로 마운트한다 — 정렬·상태·카테고리 선택지
/// 구성과 provider 반영이 이미 계약 enum만으로 구현돼 있어, 시트용으로 다시 쓰면
/// 같은 로직이 두 벌이 된다.
library;

import 'package:flutter/material.dart';

import 'sort_filter_bar.dart';

/// 정렬/필터 시트를 띄운다. 선택은 provider에 즉시 반영되므로 반환값은 없다.
Future<void> showSortFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => const _SortFilterSheet(),
  );
}

class _SortFilterSheet extends StatelessWidget {
  const _SortFilterSheet();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      // 드래그 핸들이 위쪽 여백을 이미 만들므로 top은 0으로 둔다.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('정렬 · 필터', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '조건은 모두 함께 적용됩니다.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // [SortFilterBar]는 좌우로 스크롤되는 컨트롤 줄이다. 좁은 화면에서 세 개가
            // 다 안 들어가면 가로로 밀어서 고른다.
            const SortFilterBar(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('완료'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
