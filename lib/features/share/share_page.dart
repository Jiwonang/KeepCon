/// share 페이지 — 하단 탭의 '공유' 화면.
///
/// 3섹션(내 그룹 / 공유 기프티콘 / 최근 사용 이력)을 유지하되, 버튼·카드가 실제
/// 화면(그룹 상세·공유 기프티콘 상세·사용 이력·알림)으로 이동하도록 배선한다.
///
/// **계약 소비.** 그룹/공유 도메인은 `lib/shared`의 계약(SSOT)을 소비한다:
/// - 상태 구독 = [ShareRepository]의 watch 스트림([allSharedProvider]/[usageLogsProvider])
///   — Riverpod `ref.watch`.
/// - 내 그룹 목록 = 계약 정본 [myGroupsProvider](`lib/shared/providers/my_groups_provider.dart`).
///   scan 페이지도 같은 정본을 보므로 `watchGroups` 구독이 하나로 합쳐진다.
/// - 행위자/멤버 식별 = 세션 정본 `sessionUserProvider`를 통과시키는
///   [shareCurrentUserProvider](share 별칭 — 자체 구독 없음).
/// - 공유 후보(내 기프티콘)는 [GifticonRepository.watchGifticons]로 원본 [Gifticon]을 받는다.
///
/// 색/폰트/라운드/그림자는 전부 `Theme.of(context)`에서 오고, 공유 기프티콘 카드의
/// 브랜드 타일은 공유 `BrandPalette`를 소비한다. 하드코딩 색 없음. 라이트/다크 양쪽 대응.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/group.dart';
import '../../shared/models/share.dart';
import '../../shared/models/user.dart';
import '../../shared/providers/my_groups_provider.dart'
    show myGroupsProvider, retryMyGroups;
import '../../shared/theme/theme_tokens.dart';
import 'pages/group_detail_page.dart';
import 'pages/group_notifications_page.dart';
import 'pages/shared_gifticon_detail_page.dart';
import 'pages/usage_log_page.dart';
import 'state/share_providers.dart';
import 'widgets/share_error_banner.dart';
import 'widgets/share_format.dart';
import 'widgets/share_sheets.dart';
import 'widgets/shared_gifticon_card.dart';

/// 하단 탭에서 '공유' 탭 콘텐츠로 렌더링되는 화면.
///
/// [ShareRepository]의 watch 스트림을 [ref]로 구독해, 다른 화면에서 일어난 그룹/공유/사용
/// 변경이 이 화면에 즉시 반영되게 한다(리액티브 계약 소비).
class SharePage extends ConsumerWidget {
  const SharePage({super.key});

  static void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 폴딩(#13)은 그대로 두고, 섹션별로 원천의 hasError를 함께 관찰해 배너를 얹는다.
    final AsyncValue<List<Group>> groupsAsync = ref.watch(myGroupsProvider);
    final List<Group> groups = groupsAsync.valueOrNull ?? const <Group>[];
    // "값도 없는 에러"만 배너 대상이다(단일 판정점 provider와 같은 규칙) — 이전 값을
    // 보존한 순단 에러는 목록이 계속 표시·조회되므로, 사용자가 할 일이 없는 배너를
    // 멀쩡한 목록 위에 얹지 않는다(재시도 훅 도착 후에도 유지된 판단 — #13/v2.6).
    final bool groupsUnavailable = ref.watch(myGroupListUnavailableProvider);
    // 첫 방출 전(값 없는 로딩)은 "없음"이 아직 확정이 아니다 — 빈 안내 게이트용.
    final bool groupsPending = groupsAsync.isLoading && !groupsAsync.hasValue;
    final List<SharedGifticon> shared = ref.watch(allSharedProvider);
    final bool sharedHaveError = ref.watch(sharedGifticonsHaveErrorProvider);
    final bool sharedPending = ref.watch(sharedGifticonsPendingProvider);
    final AsyncValue<List<UsageLog>> logsAsync = ref.watch(usageLogsProvider);
    final List<UsageLog> logs = logsAsync.valueOrNull ?? const <UsageLog>[];
    final bool logsHaveError = logsAsync.hasError;
    final bool logsPending = logsAsync.isLoading && !logsAsync.hasValue;
    final MemberNames names = ref.watch(memberNamesProvider);
    final User? user = ref.watch(shareCurrentUserProvider).valueOrNull;
    final int unreadNotifications = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: <Widget>[
            // ── 헤더(큰 타이틀 + 알림벨 + 그룹 추가) ──
            _ShareHeader(
              unreadCount: unreadNotifications,
              onNotifications: () =>
                  _push(context, const GroupNotificationsPage()),
              onCreate: () => showCreateGroupSheet(context),
            ),
            const SizedBox(height: 26),

            // ── 1. 내 그룹 ──
            const _SectionHeader(title: '내 그룹'),
            const SizedBox(height: 12),
            if (groupsUnavailable) ...<Widget>[
              // 재시도는 계약 정본의 훅으로 한다 — 그룹 목록의 에러는 정본이 watch하는
              // **private 체인**(lib/shared)에 캐시돼 페이지의
              // `invalidate(myGroupsProvider)`로는 되살릴 수 없기 때문이다(#13 실측).
              // `retryMyGroups`가 세션·그룹 두 계층 중 에러인 것만 재구독한다.
              ShareErrorBanner(
                message: '그룹 목록을 불러오지 못했어요.',
                onRetry: () => retryMyGroups(ref),
              ),
              if (groups.isNotEmpty) const SizedBox(height: 12),
            ],
            if (groups.isEmpty && !groupsUnavailable && !groupsPending)
              const _EmptyHint(
                text: '아직 참여한 그룹이 없어요.\n그룹을 만들거나 초대코드로 참여해 보세요.',
              )
            else if (groups.isNotEmpty)
              for (int i = 0; i < groups.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 12),
                _GroupCard(
                  group: groups[i],
                  onTap: () =>
                      _push(context, GroupDetailPage(groupId: groups[i].id)),
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
            if (sharedHaveError) ...<Widget>[
              ShareErrorBanner(
                message: '공유 기프티콘을 불러오지 못했어요.',
                onRetry: () => retrySharedGifticons(ref),
              ),
              if (shared.isNotEmpty) const SizedBox(height: 12),
            ],
            // `sharedGifticonsHaveErrorProvider`는 배너 중복을 피하려 그룹 목록 에러를
            // 일부러 제외한다. 그래서 그룹 목록이 실패하면 순회할 그룹이 0개라
            // `sharedHaveError`가 false가 되고, 여기서 "공유된 기프티콘이 없어요"라는
            // false-empty가 되살아난다 — 이번 변경이 없애려던 바로 그 위장이다.
            // 빈 안내를 그룹 사용 불가에도, 첫 방출 전 로딩에도 게이트해 막는다
            // (에러는 위 배너들이 설명하고, 로딩은 곧 실제 상태로 바뀐다).
            if (shared.isEmpty &&
                !sharedHaveError &&
                !groupsUnavailable &&
                !sharedPending)
              const _EmptyHint(text: '공유된 기프티콘이 없어요.')
            else if (shared.isNotEmpty)
              for (int i = 0; i < shared.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 12),
                SharedGifticonCard(
                  item: shared[i],
                  names: names,
                  currentUserId: user?.id,
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
            if (logsHaveError) ...<Widget>[
              ShareErrorBanner(
                message: '사용 이력을 불러오지 못했어요.',
                onRetry: () => retryUsageLogs(ref),
              ),
              if (logs.isNotEmpty) const SizedBox(height: 12),
            ],
            if (logs.isEmpty && !logsHaveError && !logsPending)
              const _EmptyHint(text: '사용 이력이 없어요.')
            else if (logs.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < logs.length && i < 3; i++) ...<Widget>[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      _UsageLogTile(log: logs[i], names: names),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── 헤더 ───────────────────────────

/// 상단 헤더 — 큰 타이틀 "공유" + 알림벨(안읽음 뱃지) + 그룹 추가. 홈/스캔과 동일 톤.
class _ShareHeader extends StatelessWidget {
  const _ShareHeader({
    required this.unreadCount,
    required this.onNotifications,
    required this.onCreate,
  });

  /// 안읽음 알림 개수. 0이면 뱃지를 숨긴다.
  final int unreadCount;
  final VoidCallback onNotifications;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '공유',
            style: context.pageHeaderStyle,
          ),
        ),
        // 알림 벨 + 안읽음 카운트 뱃지(있을 때만) → 그룹 알림.
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            onPressed: onNotifications,
            tooltip: '그룹 알림',
            icon: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(Icons.notifications_none, color: scheme.onSurface),
                if (unreadCount > 0)
                  Positioned(
                    top: -4,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(color: scheme.surface, width: 1.5),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: TextStyle(
                          color: scheme.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: onCreate,
          tooltip: '그룹 만들기',
          icon: const Icon(Icons.person_add_alt_1_outlined),
        ),
      ],
    );
  }
}

// ─────────────────────────── 섹션 헤더 ───────────────────────────

/// 섹션 제목(볼드) 헤더. 스캔의 섹션 헤더 톤(18·w800)과 맞춘다.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: context.sectionTitleStyle,
    );
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
        borderRadius: BorderRadius.circular(AppRadii.tile),
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
class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group, required this.onTap});

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int sharedCount =
        ref.watch(sharedGifticonsProvider(group.id)).valueOrNull?.length ?? 0;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Ink(
          decoration: AppDecorations.softCard(scheme),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                // 이모지 타일(연한 서피스 라운드 스퀘어).
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadii.panel),
                  ),
                  child:
                      Text(group.emoji, style: const TextStyle(fontSize: 30)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        group.name,
                        style: context.navTitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
    final RoundedRectangleBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.tile),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('그룹 만들기'),
            style: ElevatedButton.styleFrom(
              shape: shape,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
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
              shape: shape,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── 3. 사용 이력 타일 ───────────────────────

/// 최근 사용 이력 한 줄. "OOO님이 △△ 사용 · N일 전".
class _UsageLogTile extends ConsumerWidget {
  const _UsageLogTile({required this.log, required this.names});

  final UsageLog log;
  final MemberNames names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String groupName =
        ref.watch(groupByIdProvider(log.groupId)).valueOrNull?.name ?? '그룹';

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
              text: '${names.labelFor(log.userId)}님',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: '이 '),
            TextSpan(text: '${log.brand} ${log.productName}'),
            const TextSpan(text: ' 사용'),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$groupName · ${formatRelativeKo(log.usedAt)}',
          style: theme.textTheme.bodySmall),
    );
  }
}
