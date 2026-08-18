/// main 페이지 — 정렬/필터 컨트롤 바.
///
/// 계약 enum([SortOption], [FilterOption], [GifticonStatus])만으로 선택지를 구성한다.
/// 선택 결과는 [sortOptionProvider]/[filterProvider]에 반영되고, 목록 파생 provider가
/// 자동 재계산한다.
library;

import 'package:flutter/material.dart';
import '../../../shared/theme/theme_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../state/gifticon_filter.dart';
import '../state/gifticon_list_providers.dart';
import 'gifticon_status_label.dart';

class SortFilterBar extends ConsumerWidget {
  const SortFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SortOption sort = ref.watch(sortOptionProvider);
    final GifticonFilter filter = ref.watch(filterProvider);
    final List<String> categories = ref.watch(availableCategoriesProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 정렬 — SortOption enum 전체를 선택지로.
          _SortDropdown(
            value: sort,
            onChanged: (SortOption? next) {
              if (next != null) {
                ref.read(sortOptionProvider.notifier).state = next;
              }
            },
          ),
          const SizedBox(width: 12),
          // 상태 필터 — FilterOption.status / GifticonStatus enum.
          _StatusFilterDropdown(
            value: filter.statusFilter,
            onChanged: (GifticonStatus? next) {
              ref.read(filterProvider.notifier).state = filter.withStatus(next);
            },
          ),
          const SizedBox(width: 12),
          // 카테고리 필터 — FilterOption.category / Gifticon.category 값.
          _CategoryFilterDropdown(
            value: filter.categoryFilter,
            categories: categories,
            onChanged: (String? next) {
              ref.read(filterProvider.notifier).state =
                  filter.withCategory(next);
            },
          ),
        ],
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final SortOption value;
  final ValueChanged<SortOption?> onChanged;
  const _SortDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _LabeledDropdown<SortOption>(
      icon: Icons.sort,
      value: value,
      items: [
        for (final SortOption o in SortOption.values)
          DropdownMenuItem<SortOption>(
            value: o,
            child: Text(sortOptionLabel(o)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _StatusFilterDropdown extends StatelessWidget {
  final GifticonStatus? value;
  final ValueChanged<GifticonStatus?> onChanged;
  const _StatusFilterDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _LabeledDropdown<GifticonStatus?>(
      icon: Icons.filter_alt_outlined,
      value: value,
      items: [
        const DropdownMenuItem<GifticonStatus?>(
          value: null,
          child: Text('상태 전체'),
        ),
        for (final GifticonStatus s in GifticonStatus.values)
          DropdownMenuItem<GifticonStatus?>(
            value: s,
            child: Text(gifticonStatusLabel(s)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _CategoryFilterDropdown extends StatelessWidget {
  final String? value;
  final List<String> categories;
  final ValueChanged<String?> onChanged;
  const _CategoryFilterDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 선택지에 없는 값을 [DropdownButton]에 주면 "value에 해당하는 item이 정확히 하나"
    // 단언이 터져 **컨트롤 자리에 렌더 에러가 뜬다**. 상태·정렬은 enum 전체가 늘 선택지에
    // 있어 이 문제가 없지만, 카테고리 선택지는 사용자의 기프티콘에서 파생되므로
    // 필터에 담긴 값이 목록에서 사라질 수 있다(계정 전환, 원천이 아직 로딩 중이라 빈
    // 목록으로 접히는 프레임).
    //
    // 그래서 선택지에 없으면 "전체"로 접어 그린다. 필터 상태 자체를 여기서 고치지는
    // 않는다 — 그리는 위젯이 상태를 되돌리면 build가 부작용을 갖게 된다. 되돌리는 일은
    // 계정 전환 시점에 [filterProvider]가 스스로 한다.
    final bool valueIsSelectable = value == null || categories.contains(value);

    return _LabeledDropdown<String?>(
      icon: Icons.category_outlined,
      value: valueIsSelectable ? value : null,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('카테고리 전체'),
        ),
        for (final String c in categories)
          DropdownMenuItem<String?>(value: c, child: Text(c)),
      ],
      onChanged: onChanged,
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  final IconData icon;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _LabeledDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(AppRadii.sheet),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
