/// share 페이지 — 그룹 상세(전체 화면).
///
/// 그룹명·방장·멤버 수 헤더 + 멤버 목록(방장 뱃지) + 그룹 공유 기프티콘 목록 +
/// 하단 액션(멤버 초대 / 나가기 / 방장이면 그룹 삭제). 방장이 나갈 때 소유권 이전 UI.
/// 색 하드코딩 없음. 상태 변경은 계약 [ShareRepository]에 반영된다.
///
/// UI 게이팅은 모델 predicate([Group.isOwnedBy]/[Group.canInvite])로 사전 판정하고,
/// 저장소 호출부는 가드 위반 시 [StateError]를 던지므로 try/catch로 스낵바 처리한다(이중 방어).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/group.dart';
import '../../../shared/models/share.dart';
import '../../../shared/providers/repositories.dart';
import '../state/share_providers.dart';
import '../widgets/share_common.dart';
import '../widgets/share_sheets.dart';
import '../widgets/shared_gifticon_card.dart';
import 'member_invite_page.dart';
import 'shared_gifticon_detail_page.dart';

/// 그룹 상세 화면. 공유 메인의 그룹 카드에서 push 한다.
class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({super.key, required this.groupId});

  /// 표시할 그룹 id.
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Group? group = ref.watch(groupByIdProvider(groupId));
    if (group == null) {
      // 나가기/삭제/이전 후 내 멤버십이 사라지면 이전 화면으로 복귀.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return _GroupDetailBody(group: group);
  }
}

class _GroupDetailBody extends ConsumerWidget {
  const _GroupDetailBody({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
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
        title: Text(group.name),
        actions: <Widget>[
          if (canInvite)
            IconButton(
              onPressed: () => _openInvite(context),
              icon: const Icon(Icons.person_add_outlined),
              tooltip: '멤버 초대',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: <Widget>[
            // 헤더.
            Row(
              children: <Widget>[
                EmojiAvatar(emoji: group.emoji, size: 60),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(group.name, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        '방장 ${group.owner.displayName} · 멤버 ${group.memberCount}명',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 멤버 목록.
            Text('멤버 ${group.memberCount}명', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < group.members.length; i++) ...<Widget>[
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    _MemberTile(
                      member: group.members[i],
                      isMe: uid != null && group.members[i].userId == uid,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 공유 기프티콘.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('공유 기프티콘 ${shared.length}개',
                    style: theme.textTheme.titleLarge),
                TextButton.icon(
                  onPressed: () => showShareGifticonSheet(context, group.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('공유'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (shared.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('아직 공유된 기프티콘이 없어요.',
                      style: theme.textTheme.bodySmall),
                ),
              )
            else
              for (int i = 0; i < shared.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 12),
                SharedGifticonCard(
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

            const SizedBox(height: 28),

            // 하단 액션.
            if (canInvite) ...<Widget>[
              OutlinedButton.icon(
                onPressed: () => _openInvite(context),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('멤버 초대'),
              ),
              const SizedBox(height: 10),
            ],
            _DangerAction(
              icon: Icons.logout,
              label: '그룹 나가기',
              onTap: () => _onLeave(context, ref, uid, iAmOwner),
            ),
            if (iAmOwner) ...<Widget>[
              const SizedBox(height: 10),
              _DangerAction(
                icon: Icons.delete_outline,
                label: '그룹 삭제',
                onTap: () => _onDelete(context, ref),
              ),
            ],
          ],
        ),
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

/// 멤버 한 줄 타일 — 아바타 + 이름 + (방장/나) 뱃지.
class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.isMe});

  final GroupMember member;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ListTile(
      leading: EmojiAvatar(emoji: member.avatarEmoji, size: 40),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              isMe ? '${member.displayName} (나)' : member.displayName,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.isOwner) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '방장',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 위험 액션 버튼(나가기/삭제) — error 톤 아웃라인.
class _DangerAction extends StatelessWidget {
  const _DangerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.error,
        side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
