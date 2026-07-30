/// share 페이지 — 그룹 알림(전체 화면, KeepCon 틀 재디자인).
///
/// 등록/만료임박/사용완료 유형별 아이콘·문구를 카드 목록으로 보여준다. 공유/사용완료가
/// 일어날 때마다 계약 [ShareRepository]에 알림이 쌓이고 이 화면이 [notificationsProvider]
/// 구독으로 동기화된다. 상대 시각 포맷은 소비자(UI) 책임. 색 하드코딩 없음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/share.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../state/share_providers.dart';
import '../widgets/share_format.dart';

/// 그룹 알림 화면. 공유 메인 헤더의 알림 아이콘에서 push 한다.
///
/// 진입 시 [ShareRepository.markNotificationsRead]를 호출해 안읽음을 해소한다(뱃지 클리어).
class GroupNotificationsPage extends ConsumerStatefulWidget {
  const GroupNotificationsPage({super.key});

  @override
  ConsumerState<GroupNotificationsPage> createState() =>
      _GroupNotificationsPageState();
}

class _GroupNotificationsPageState
    extends ConsumerState<GroupNotificationsPage> {
  @override
  void initState() {
    super.initState();
    // 진입 즉시 모두 읽음 처리. 세션이 없으면(StateError) 조용히 무시한다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(shareRepositoryProvider).markNotificationsRead();
      } on StateError {
        // 미로그인 상태에선 표시할 알림도 없으므로 무시.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<GroupNotification> items =
        ref.watch(notificationsProvider).value ?? const <GroupNotification>[];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('그룹 알림', style: context.navTitleStyle),
      ),
      body: SafeArea(
        top: false,
        child: items.isEmpty
            ? Center(
                child: Text('알림이 없어요.',
                    style: Theme.of(context).textTheme.bodySmall),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (BuildContext context, int i) =>
                    _NotificationCard(item: items[i]),
              ),
      ),
    );
  }
}

/// 알림 카드 — 유형별 원형 아이콘 + 제목/시간/본문 + 셰브론.
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
        icon = Icons.card_giftcard;
        tint = scheme.primary;
      case GroupNotificationType.expiringSoon:
        icon = Icons.schedule;
        tint = scheme.error;
      case GroupNotificationType.used:
        icon = Icons.check_circle_outline;
        tint = scheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.softCard(scheme),
      child: Row(
        children: <Widget>[
          // 유형별 원형 아이콘(연한 틴트 배경).
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tint, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.title,
                        style: context.sectionTitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(formatRelativeKo(item.createdAt),
                        style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.message,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
