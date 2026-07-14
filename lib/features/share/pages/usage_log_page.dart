/// share 페이지 — 사용 이력 로그(전체 화면, KeepCon 틀 재디자인).
///
/// "누가 · 무엇을 · 언제" 타임라인 + 그룹 필터. 사용 완료 처리가 일어날 때마다 계약
/// [ShareRepository]에 이력이 쌓이고 이 화면이 [usageLogsProvider] 구독으로 동기화된다.
/// userId→이름·시각 포맷은 소비자(UI) 책임. 좌측 브랜드 타일은 공유 [BrandPalette] 소비.
/// 색 하드코딩 없음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/group.dart';
import '../../../shared/models/share.dart';
import '../../../shared/theme/brand_palette.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../state/share_providers.dart';
import '../widgets/share_format.dart';

/// 사용 이력 로그 화면. 공유 메인의 '최근 사용 이력'에서 push 한다.
class UsageLogPage extends ConsumerStatefulWidget {
  const UsageLogPage({super.key});

  @override
  ConsumerState<UsageLogPage> createState() => _UsageLogPageState();
}

class _UsageLogPageState extends ConsumerState<UsageLogPage> {
  /// 선택된 그룹 필터. null이면 전체.
  String? _groupFilter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<UsageLog> all =
        ref.watch(usageLogsProvider).value ?? const <UsageLog>[];
    final List<Group> groups =
        ref.watch(myGroupsProvider).value ?? const <Group>[];
    final MemberNames names = ref.watch(memberNamesProvider);

    // 선택된 그룹이 사라졌으면(나가기 등) 전체로 폴백.
    final bool filterValid =
        _groupFilter == null || groups.any((Group g) => g.id == _groupFilter);
    final String? activeFilter = filterValid ? _groupFilter : null;
    final List<UsageLog> logs = activeFilter == null
        ? all
        : all.where((UsageLog l) => l.groupId == activeFilter).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        titleSpacing: 0,
        title: Text('사용 이력', style: context.pageHeaderStyle),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 그룹 필터 칩(전체 + 내 그룹들).
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                children: <Widget>[
                  _FilterChip(
                    label: '전체',
                    selected: activeFilter == null,
                    onTap: () => setState(() => _groupFilter = null),
                  ),
                  for (final Group g in groups) ...<Widget>[
                    const SizedBox(width: 10),
                    _FilterChip(
                      label: g.name,
                      selected: activeFilter == g.id,
                      onTap: () => setState(() => _groupFilter = g.id),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Text('아직 사용 이력이 없어요.',
                          style: theme.textTheme.bodySmall),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: logs.length,
                      itemBuilder: (BuildContext context, int i) => _LogRow(
                        log: logs[i],
                        names: names,
                        isLast: i == logs.length - 1,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 그룹 필터 칩 — 선택 시 brand 채움.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bg = selected ? scheme.primary : scheme.surfaceContainerHighest;
    final Color fg = selected ? scheme.onPrimary : scheme.onSurfaceVariant;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 타임라인 한 줄 — 좌측 점·선 + 브랜드 타일 + 내용.
class _LogRow extends ConsumerWidget {
  const _LogRow({
    required this.log,
    required this.names,
    required this.isLast,
  });

  final UsageLog log;
  final MemberNames names;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BrandStyle brand = BrandPalette.of(log.brand);
    final String groupName =
        ref.watch(groupByIdProvider(log.groupId)).value?.name ?? '그룹';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 타임라인 점 + 연결선.
          Column(
            children: <Widget>[
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 24),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 3),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.22),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 18),
          // 브랜드 타일 + 텍스트.
          Expanded(
            child: Container(
              padding: EdgeInsets.only(top: 18, bottom: isLast ? 0 : 22),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(
                        bottom: BorderSide(
                          color: scheme.outline.withValues(alpha: 0.15),
                        ),
                      ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brand.background,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      brand.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: brand.foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text.rich(
                          TextSpan(
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                            children: <InlineSpan>[
                              TextSpan(
                                  text: '${names.labelFor(log.userId)}님이 '),
                              TextSpan(text: '${log.brand} ${log.productName}'),
                              const TextSpan(text: ' 사용'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('$groupName · ${formatRelativeKo(log.usedAt)}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
