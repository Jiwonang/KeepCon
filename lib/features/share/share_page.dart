/// share 페이지 — 하단 탭의 '공유' 화면.
///
/// 3섹션(내 그룹 / 공유 기프티콘 / 최근 사용 이력)을 유지하되, 버튼·카드가 실제
/// 화면(그룹 상세·공유 기프티콘 상세·사용 이력·알림)으로 이동하도록 배선한다.
///
/// **데이터·상태는 프로토타입 하드코딩.** 그룹/공유 도메인은 아직 공유 계약(`lib/shared`)에
/// 없으므로, share 스코프 로컬 저장소([ShareStore])의 인메모리 상태를 소비한다. 계약 v1
/// 확정 후 GroupRepository/ShareRepository 소비 코드로 이관한다.
/// ★ TODO(contract): 내 기프티콘/원본 상태 동기화는 GifticonRepository 연동 지점.
///
/// 색/폰트/라운드/그림자는 전부 `Theme.of(context)` + [ShareThemeTokens]에서 온다.
/// 하드코딩 색 없음. 라이트/다크 양쪽 대응.
library;

import 'package:flutter/material.dart';

import 'data/share_models.dart';
import 'data/share_store.dart';
import 'pages/group_detail_page.dart';
import 'pages/group_notifications_page.dart';
import 'pages/shared_gifticon_detail_page.dart';
import 'pages/usage_log_page.dart';
import 'widgets/share_common.dart';
import 'widgets/share_sheets.dart';
import 'widgets/shared_gifticon_card.dart';

/// 하단 탭에서 '공유' 탭 콘텐츠로 렌더링되는 화면.
///
/// 로컬 저장소([ShareStore])를 [ListenableBuilder]로 구독해, 다른 화면에서 일어난
/// 그룹/공유/사용 변경이 이 화면에 즉시 반영되게 한다.
class SharePage extends StatelessWidget {
  const SharePage({super.key});

  static void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ShareStore store = ShareStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('공유'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _push(context, const GroupNotificationsPage()),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: '그룹 알림',
          ),
          IconButton(
            onPressed: () => showCreateGroupSheet(context),
            icon: const Icon(Icons.group_add_outlined),
            tooltip: '그룹 만들기',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (BuildContext context, _) {
            final List<Group> groups = store.groups;
            final List<SharedGifticon> shared = store.allShared;
            final List<UsageLog> logs = store.usageLogs;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: <Widget>[
                // ── 1. 내 그룹 ──
                const _SectionHeader(title: '내 그룹'),
                const SizedBox(height: 12),
                if (groups.isEmpty)
                  const _EmptyHint(
                    text: '아직 참여한 그룹이 없어요.\n그룹을 만들거나 초대코드로 참여해 보세요.',
                  )
                else
                  for (int i = 0; i < groups.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 12),
                    _GroupCard(
                      group: groups[i],
                      onTap: () => _push(
                          context, GroupDetailPage(groupId: groups[i].id)),
                    ),
                  ],
                const SizedBox(height: 16),
                _GroupActionButtons(
                  onCreate: () => showCreateGroupSheet(context),
                  onJoin: () => showJoinGroupSheet(context),
                ),

                const SizedBox(height: 28),

                // ── 2. 공유 기프티콘 ──
                const _SectionHeader(title: '공유 기프티콘'),
                const SizedBox(height: 12),
                if (shared.isEmpty)
                  const _EmptyHint(text: '공유된 기프티콘이 없어요.')
                else
                  for (int i = 0; i < shared.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 12),
                    SharedGifticonCard(
                      item: shared[i],
                      onTap: () => _push(
                        context,
                        SharedGifticonDetailPage(itemId: shared[i].id),
                      ),
                    ),
                  ],

                const SizedBox(height: 28),

                // ── 3. 최근 사용 이력 ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const _SectionHeader(title: '최근 사용 이력'),
                    TextButton(
                      onPressed: () => _push(context, const UsageLogPage()),
                      child: const Text('전체 보기'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (logs.isEmpty)
                  const _EmptyHint(text: '사용 이력이 없어요.')
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < logs.length && i < 3; i++) ...<Widget>[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          _UsageLogTile(log: logs[i]),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────── 섹션 헤더 ───────────────────────────

/// 섹션 제목(볼드) 헤더. main 페이지의 섹션 헤더 톤과 맞춘다.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

/// 비어 있는 섹션 안내.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

// ─────────────────────────── 1. 그룹 카드 ───────────────────────────

/// 그룹 한 개를 표현하는 카드. 이모지 아바타 + 이름 + 멤버·공유 수.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int sharedCount = ShareStore.instance.sharedOf(group.id).length;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              EmojiAvatar(emoji: group.emoji),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(group.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '멤버 ${group.memberCount}명 · 공유 $sharedCount개',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// '그룹 만들기' / '그룹 참여하기' 액션 버튼 행.
class _GroupActionButtons extends StatelessWidget {
  const _GroupActionButtons({required this.onCreate, required this.onJoin});

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('그룹 만들기'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.login, size: 18),
            label: const Text('그룹 참여하기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outline),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── 3. 사용 이력 타일 ───────────────────────

/// 최근 사용 이력 한 줄. "OOO님이 △△ 사용 · N일 전".
class _UsageLogTile extends StatelessWidget {
  const _UsageLogTile({required this.log});

  final UsageLog log;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.16),
        foregroundColor: scheme.primary,
        child: const Icon(Icons.check, size: 20),
      ),
      title: Text.rich(
        TextSpan(
          style: theme.textTheme.bodyMedium,
          children: <InlineSpan>[
            TextSpan(
              text: '${log.who}님',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: '이 '),
            TextSpan(text: log.what),
            const TextSpan(text: ' 사용'),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${log.groupName} · ${log.when}',
          style: theme.textTheme.bodySmall),
    );
  }
}
