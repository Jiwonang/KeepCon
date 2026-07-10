/// share 페이지 — 사용 이력 로그(전체 화면).
///
/// "누가 · 무엇을 · 언제" 타임라인. 사용 완료 처리가 일어날 때마다 계약
/// [ShareRepository]에 이력이 쌓이고 이 화면이 [usageLogsProvider] 구독으로 동기화된다.
/// userId→이름·시각 포맷은 소비자(UI) 책임. 색 하드코딩 없음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/share.dart';
import '../state/share_providers.dart';
import '../widgets/share_format.dart';

/// 사용 이력 로그 화면. 공유 메인의 '최근 사용 이력'에서 push 한다.
class UsageLogPage extends ConsumerWidget {
  const UsageLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<UsageLog> logs =
        ref.watch(usageLogsProvider).value ?? const <UsageLog>[];
    final MemberNames names = ref.watch(memberNamesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('사용 이력')),
      body: SafeArea(
        child: logs.isEmpty
            ? Center(
                child: Text('아직 사용 이력이 없어요.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: logs.length,
                itemBuilder: (BuildContext context, int i) => _LogRow(
                  log: logs[i],
                  names: names,
                  isLast: i == logs.length - 1,
                ),
              ),
      ),
    );
  }
}

/// 타임라인 한 줄 — 좌측 점·선 + 내용.
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
    final String groupName =
        ref.watch(groupByIdProvider(log.groupId)).value?.name ?? '그룹';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: <InlineSpan>[
                        TextSpan(
                          text: '${names.labelFor(log.userId)}님',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: '이 '),
                        TextSpan(text: '${log.brand} ${log.productName}'),
                        const TextSpan(text: ' 사용'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$groupName · ${formatRelativeKo(log.usedAt)}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
