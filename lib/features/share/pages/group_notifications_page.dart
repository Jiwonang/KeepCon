/// share 페이지 — 그룹 알림(전체 화면).
///
/// 등록/만료임박/사용완료 유형별 아이콘·문구를 목록으로 보여준다. 공유/사용완료가
/// 일어날 때마다 계약 [ShareRepository]에 알림이 쌓이고 이 화면이 [notificationsProvider]
/// 구독으로 동기화된다. 상대 시각 포맷은 소비자(UI) 책임. 색 하드코딩 없음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/share.dart';
import '../state/share_providers.dart';
import '../widgets/share_format.dart';

/// 그룹 알림 화면. 공유 메인 앱바의 알림 아이콘에서 push 한다.
class GroupNotificationsPage extends ConsumerWidget {
  const GroupNotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<GroupNotification> items =
        ref.watch(notificationsProvider).value ?? const <GroupNotification>[];

    return Scaffold(
      appBar: AppBar(title: const Text('그룹 알림')),
      body: SafeArea(
        child: items.isEmpty
            ? Center(
                child: Text('알림이 없어요.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int i) =>
                    _NotificationCard(item: items[i]),
              ),
      ),
    );
  }
}

/// 알림 카드 — 유형별 아이콘·색 + 제목/본문/시간.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final GroupNotification item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    late final IconData icon;
    late final Color tint;
    switch (item.type) {
      case GroupNotificationType.registered:
        icon = Icons.add_circle_outline;
        tint = scheme.primary;
      case GroupNotificationType.expiringSoon:
        icon = Icons.schedule;
        tint = scheme.error;
      case GroupNotificationType.used:
        icon = Icons.check_circle_outline;
        tint = scheme.onSurfaceVariant;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              backgroundColor: tint.withValues(alpha: 0.16),
              foregroundColor: tint,
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(item.title,
                            style: theme.textTheme.titleMedium),
                      ),
                      Text(formatRelativeKo(item.createdAt),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.message, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
