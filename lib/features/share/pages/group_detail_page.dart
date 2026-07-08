/// share 페이지 — 그룹 상세(전체 화면).
///
/// 그룹명·방장·멤버 수 헤더 + 멤버 목록(방장 뱃지) + 그룹 공유 기프티콘 목록 +
/// 하단 액션(멤버 초대 / 나가기 / 방장이면 그룹 삭제). 방장이 나갈 때 소유권 이전 UI.
/// 색 하드코딩 없음. 상태 변경은 [ShareStore]에 반영된다.
library;

import 'package:flutter/material.dart';

import '../data/share_models.dart';
import '../data/share_store.dart';
import '../widgets/share_common.dart';
import '../widgets/share_sheets.dart';
import '../widgets/shared_gifticon_card.dart';
import 'member_invite_page.dart';
import 'shared_gifticon_detail_page.dart';

/// 그룹 상세 화면. 공유 메인의 그룹 카드에서 push 한다.
class GroupDetailPage extends StatelessWidget {
  const GroupDetailPage({super.key, required this.groupId});

  /// 표시할 그룹 id.
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final ShareStore store = ShareStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (BuildContext context, _) {
        final Group? group = store.groupById(groupId);
        if (group == null) {
          // 나가기/삭제 후 그룹이 사라지면 이전 화면으로 복귀.
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

class _GroupDetailBody extends StatelessWidget {
  const _GroupDetailBody({required this.group});

  final Group group;

  bool get _iAmOwner => group.owner.id == ShareStore.myId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ShareStore store = ShareStore.instance;
    final List<SharedGifticon> shared = store.sharedOf(group.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MemberInvitePage(group: group),
              ),
            ),
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
                        '방장 ${group.owner.name} · 멤버 ${group.memberCount}명',
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
                    _MemberTile(member: group.members[i]),
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
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemberInvitePage(group: group),
                ),
              ),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('멤버 초대'),
            ),
            const SizedBox(height: 10),
            _DangerAction(
              icon: Icons.logout,
              label: '그룹 나가기',
              onTap: () => _onLeave(context, store),
            ),
            if (_iAmOwner) ...<Widget>[
              const SizedBox(height: 10),
              _DangerAction(
                icon: Icons.delete_outline,
                label: '그룹 삭제',
                onTap: () => _onDelete(context, store),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onLeave(BuildContext context, ShareStore store) async {
    // 방장이 나갈 땐 소유권 이전이 먼저다.
    if (_iAmOwner && group.memberCount > 1) {
      final GroupMember? newOwner = await _pickNewOwner(context);
      if (newOwner == null) return;
      store.transferOwnershipAndLeave(
          groupId: group.id, newOwnerId: newOwner.id);
      if (context.mounted) _leftSnack(context);
      return;
    }
    final bool ok =
        await _confirm(context, '그룹 나가기', '"${group.name}"에서 나갈까요?');
    if (ok && context.mounted) {
      store.leaveGroup(group.id);
      _leftSnack(context);
    }
  }

  Future<void> _onDelete(BuildContext context, ShareStore store) async {
    final bool ok = await _confirm(
        context, '그룹 삭제', '"${group.name}" 그룹을 삭제할까요? 되돌릴 수 없어요.');
    if (ok && context.mounted) {
      store.deleteGroup(group.id);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('그룹을 삭제했어요.')));
    }
  }

  /// 소유권 이전 대상 멤버 선택 바텀시트.
  Future<GroupMember?> _pickNewOwner(BuildContext context) {
    final List<GroupMember> candidates = <GroupMember>[
      for (final GroupMember m in group.members)
        if (m.id != ShareStore.myId) m,
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
                    leading: EmojiAvatar(emoji: m.emoji, size: 40),
                    title: Text(m.name, style: theme.textTheme.titleMedium),
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

  void _leftSnack(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('그룹에서 나갔어요.')));
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
  const _MemberTile({required this.member});

  final GroupMember member;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isMe = member.id == ShareStore.myId;

    return ListTile(
      leading: EmojiAvatar(emoji: member.emoji, size: 40),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              isMe ? '${member.name} (나)' : member.name,
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
