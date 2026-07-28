/// share 페이지 — 그룹 상세(전체 화면, KeepCon 틀 재디자인).
///
/// 그룹 카드(이모지·방장·멤버 수) + 멤버 목록(방장 뱃지) + 그룹 공유 기프티콘 목록 +
/// 하단 고정 액션 바(멤버 초대 / 나가기 / 방장이면 그룹 삭제). 방장이 나갈 때 소유권 이전 UI.
/// 색 하드코딩 없음(공유 팔레트·테마 토큰 소비). 상태 변경은 계약 [ShareRepository]에 반영된다.
///
/// UI 게이팅은 모델 predicate([Group.isOwnedBy]/[Group.canInvite])로 사전 판정하고,
/// 저장소 호출부는 가드 위반 시 [StateError]를 던지므로 try/catch로 스낵바 처리한다(이중 방어).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/group.dart';
import '../../../shared/models/share.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/theme/brand_palette.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../state/share_providers.dart';
import '../widgets/share_common.dart';
import '../widgets/share_format.dart';
import '../widgets/share_sheets.dart';
import 'member_invite_page.dart';
import 'shared_gifticon_detail_page.dart';

/// 그룹 상세 화면. 공유 메인의 그룹 카드에서 push 한다.
class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({super.key, required this.groupId});

  /// 표시할 그룹 id.
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(groupByIdProvider(groupId)).when(
          // 세션/그룹 로딩 중엔 pop 하지 않고 대기(스피너).
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, StackTrace _) => const Scaffold(
            body: Center(child: Text('그룹을 불러오지 못했어요.')),
          ),
          data: (Group? group) {
            if (group == null) {
              // 로딩이 끝났는데도 그룹이 없다 = 나가기/삭제/이전으로 멤버십 소멸 → 복귀.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) Navigator.of(context).maybePop();
              });
              return const Scaffold(body: SizedBox.shrink());
            }
            return _GroupDetailBody(group: group);
          },
        );
  }
}

class _GroupDetailBody extends ConsumerWidget {
  const _GroupDetailBody({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? uid = ref.watch(shareCurrentUserProvider).value?.id;
    final MemberNames names = ref.watch(memberNamesProvider);
    final List<SharedGifticon> shared =
        ref.watch(sharedGifticonsProvider(group.id)).value ??
            const <SharedGifticon>[];
    // 초대 권한(방장 한정 정책 반영) — 없으면 초대 진입점을 숨긴다.
    final bool canInvite = uid != null && group.canInvite(uid);
    final bool iAmOwner = uid != null && group.isOwnedBy(uid);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          group.name,
          style: context.navTitleStyle,
        ),
        actions: <Widget>[
          if (canInvite)
            IconButton(
              onPressed: () => _openInvite(context),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: '멤버 초대',
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          children: <Widget>[
            // ── 그룹 카드 ──
            _CardShell(
              child: Row(
                children: <Widget>[
                  _EmojiCircle(emoji: group.emoji, size: 66),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          group.name,
                          style: context.cardTitleStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '방장 ${group.owner.displayName} · 멤버 '
                          '${group.memberCount}/${group.maxMembers}명',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 멤버 목록 ──
            Text(
              '멤버 ${group.memberCount}/${group.maxMembers}명'
              '${group.isFull ? ' · 정원 마감' : ''}',
              style: context.sectionTitleStyle,
            ),
            const SizedBox(height: 12),
            _CardShell(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < group.members.length; i++) ...<Widget>[
                    if (i > 0) const _RowDivider(),
                    _MemberRow(
                      member: group.members[i],
                      isMe: uid != null && group.members[i].userId == uid,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 공유 기프티콘 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('공유 기프티콘 ${shared.length}개',
                    style: context.sectionTitleStyle),
                _SharePill(
                    onTap: () => showShareGifticonSheet(context, group.id)),
              ],
            ),
            const SizedBox(height: 12),
            if (shared.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('아직 공유된 기프티콘이 없어요.',
                      style: theme.textTheme.bodySmall),
                ),
              )
            else
              _CardShell(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < shared.length; i++) ...<Widget>[
                      if (i > 0) const _RowDivider(),
                      _SharedRow(
                        item: shared[i],
                        names: names,
                        currentUserId: uid,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SharedGifticonDetailPage(itemId: shared[i].id),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      // ── 하단 고정 액션 바 ──
      bottomNavigationBar: _ActionBar(
        canInvite: canInvite,
        iAmOwner: iAmOwner,
        onInvite: () => _openInvite(context),
        onLeave: () => _onLeave(context, ref, uid, iAmOwner),
        onDelete: () => _onDelete(context, ref),
      ),
    );
  }

  void _openInvite(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberInvitePage(groupId: group.id),
      ),
    );
  }

  Future<void> _onLeave(
    BuildContext context,
    WidgetRef ref,
    String? uid,
    bool iAmOwner,
  ) async {
    final repo = ref.read(shareRepositoryProvider);
    // 방장이 나갈 땐 소유권 이전이 먼저다.
    if (iAmOwner && group.memberCount > 1) {
      final GroupMember? newOwner = await _pickNewOwner(context, uid);
      if (newOwner == null || !context.mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      try {
        await repo.transferOwnershipAndLeave(
          groupId: group.id,
          newOwnerUserId: newOwner.userId,
        );
        // 이전 성공 시 그룹은 남지만 내 멤버십은 사라진다 → 상세를 명시적으로 닫는다.
        navigator.pop();
        _snack(messenger, '그룹에서 나갔어요.');
      } on StateError {
        _snack(messenger, '지금은 나갈 수 없어요.');
      }
      return;
    }

    final bool confirmed =
        await _confirm(context, '그룹 나가기', '"${group.name}"에서 나갈까요?');
    if (!confirmed || !context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await repo.leaveGroup(group.id);
      _snack(messenger, '그룹에서 나갔어요.');
    } on StateError {
      _snack(messenger, '지금은 나갈 수 없어요.');
    }
  }

  Future<void> _onDelete(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await _confirm(
        context, '그룹 삭제', '"${group.name}" 그룹을 삭제할까요? 되돌릴 수 없어요.');
    if (!confirmed || !context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shareRepositoryProvider).deleteGroup(group.id);
      _snack(messenger, '그룹을 삭제했어요.');
    } on StateError {
      _snack(messenger, '방장만 삭제할 수 있어요.');
    }
  }

  /// 소유권 이전 대상 멤버 선택 바텀시트.
  Future<GroupMember?> _pickNewOwner(BuildContext context, String? uid) {
    final List<GroupMember> candidates = <GroupMember>[
      for (final GroupMember m in group.members)
        if (m.userId != uid) m,
    ];
    return showModalBottomSheet<GroupMember>(
      context: context,
      builder: (BuildContext ctx) {
        final ThemeData theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('소유권 이전', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('방장은 나가기 전에 다른 멤버에게 방장을 넘겨야 해요.',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                for (final GroupMember m in candidates)
                  ListTile(
                    leading: EmojiAvatar(emoji: m.avatarEmoji, size: 40),
                    title:
                        Text(m.displayName, style: theme.textTheme.titleMedium),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(ctx).pop(m),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _snack(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('닫기')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('확인')),
        ],
      ),
    );
    return ok ?? false;
  }
}

// ─────────────────────────── 공통 조각 ───────────────────────────

/// 보더 + 소프트 섀도 카드 껍데기(#25 softCard 소비).
class _CardShell extends StatelessWidget {
  const _CardShell(
      {required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: AppDecorations.softCard(scheme),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 그룹 카드/멤버 목록 내부 구분선(좌우 인셋).
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
    );
  }
}

/// 이모지 원형 타일(연한 서피스 배경). 그룹/멤버 아바타 공용.
class _EmojiCircle extends StatelessWidget {
  const _EmojiCircle({required this.emoji, required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// '공유' 초록 아웃라인 pill 버튼.
class _SharePill extends StatelessWidget {
  const _SharePill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add, size: 16),
      label: const Text('공유'),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 멤버 한 줄 — 아바타 + 이름 + (방장 뱃지) + 셰브론.
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.isMe});

  final GroupMember member;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          // 본인은 brand 원 + 이니셜, 그 외는 서피스 원 + 이모지.
          if (isMe)
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: Text(
                member.displayName.characters.first.toUpperCase(),
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            )
          else
            _EmojiCircle(emoji: member.avatarEmoji, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isMe ? '${member.displayName} (나)' : member.displayName,
              style: context.rowTitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.isOwner) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadii.dot),
              ),
              child: Text(
                '방장',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// 공유 기프티콘 한 줄(그룹 상세 목록용, 컴팩트) — 브랜드 타일 + 정보 + 상태 뱃지 + 셰브론.
class _SharedRow extends StatelessWidget {
  const _SharedRow({
    required this.item,
    required this.names,
    required this.currentUserId,
    required this.onTap,
  });

  final SharedGifticon item;
  final MemberNames names;
  final String? currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BrandStyle brand = BrandPalette.of(item.brand);
    final bool locked = item.isLockedFor(currentUserId ?? '');
    final bool dimmed = locked || item.isUsed;
    final String sharer = names.isMe(item.sharedByUserId)
        ? '내가 공유'
        : '${names.labelFor(item.sharedByUserId)}님이 공유';

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brand.background,
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: Text(
                  brand.label,
                  style: TextStyle(
                    color: brand.foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(item.brand,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      item.productName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$sharer · ${formatExpiryLabel(item.expiryDate)}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShareStatusBadge(status: item.status, locked: locked),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 하단 고정 액션 바 — 멤버 초대(brand) / 그룹 나가기(error) / 그룹 삭제(error, 방장).
///
/// 노출 규칙: 초대는 [canInvite], 삭제는 [iAmOwner]일 때만. 나가기는 항상.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.canInvite,
    required this.iAmOwner,
    required this.onInvite,
    required this.onLeave,
    required this.onDelete,
  });

  final bool canInvite;
  final bool iAmOwner;
  final VoidCallback onInvite;
  final VoidCallback onLeave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.15)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: <Widget>[
              if (canInvite) ...<Widget>[
                Expanded(
                  child: _ActionButton(
                    icon: Icons.person_add_alt_1_outlined,
                    label: '멤버 초대',
                    color: scheme.primary,
                    onTap: onInvite,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _ActionButton(
                  icon: Icons.logout,
                  label: '그룹 나가기',
                  color: scheme.error,
                  onTap: onLeave,
                ),
              ),
              if (iAmOwner) ...<Widget>[
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.delete_outline,
                    label: '그룹 삭제',
                    color: scheme.error,
                    onTap: onDelete,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 액션 바 버튼 한 칸 — 세로 아이콘+라벨, 색상 아웃라인.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.action)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
