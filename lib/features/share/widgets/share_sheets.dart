/// share 페이지 — 짧은 입력용 바텀시트 모음.
///
/// 그룹 생성 / 그룹 참여 / 기프티콘 공유처럼 입력이 짧은 흐름은 전체 화면 push 대신
/// [showModalBottomSheet]로 처리한다. 색/라운드는 전부 `Theme.of(context)`에서 온다.
library;

import 'package:flutter/material.dart';

import '../data/korean_particle.dart';
import '../data/share_models.dart';
import '../data/share_store.dart';
import 'share_common.dart';

/// 바텀시트 공통 컨테이너 — 키보드 인셋·핸들·패딩을 통일한다.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// 그룹 생성 바텀시트 — 그룹명 + 이모지 선택. 생성 시 [ShareStore]에 반영한다.
Future<void> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (BuildContext ctx) => const _CreateGroupSheet(),
  );
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet();

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  static const List<String> _emojis = <String>[
    '🏠',
    '👥',
    '💼',
    '🎓',
    '🎁',
    '⚽',
    '🍻',
    '✈️',
  ];
  final TextEditingController _nameCtrl = TextEditingController();
  String _emoji = _emojis.first;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    ShareStore.instance.createGroup(name: name, emoji: _emoji);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('"$name" 그룹을 만들었어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _SheetScaffold(
      title: '그룹 만들기',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('아이콘', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final String e in _emojis)
                GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _emoji == e
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 20)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('그룹 이름', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: '예) 우리 가족'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _submit, child: const Text('만들기')),
        ],
      ),
    );
  }
}

/// 그룹 참여 바텀시트 — 초대코드 입력. 참여 시 [ShareStore]에 반영한다.
Future<void> showJoinGroupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => const _JoinGroupSheet(),
  );
}

class _JoinGroupSheet extends StatefulWidget {
  const _JoinGroupSheet();

  @override
  State<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends State<_JoinGroupSheet> {
  final TextEditingController _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final String code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    ShareStore.instance.joinGroup(code);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('그룹에 참여했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _SheetScaffold(
      title: '그룹 참여하기',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('초대코드', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: '6자리 코드 입력'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _submit, child: const Text('참여하기')),
        ],
      ),
    );
  }
}

/// 기프티콘 공유 바텀시트 — 내 기프티콘 중 하나를 골라 [groupId] 그룹에 공유한다.
Future<void> showShareGifticonSheet(BuildContext context, String groupId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _ShareGifticonSheet(groupId: groupId),
  );
}

class _ShareGifticonSheet extends StatelessWidget {
  const _ShareGifticonSheet({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<MyGifticon> mine = ShareStore.instance.myGifticons;

    return _SheetScaffold(
      title: '기프티콘 공유',
      child: mine.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '공유할 수 있는 기프티콘이 없어요.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ★ TODO(contract): 내 기프티콘 목록은 GifticonRepository에서 온다(현재 하드코딩).
                Text('내 기프티콘에서 선택', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: mine.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext ctx, int i) {
                      final MyGifticon g = mine[i];
                      return Card(
                        child: ListTile(
                          leading: const EmojiAvatar(emoji: '🎁', size: 40),
                          title: Text(g.product,
                              style: theme.textTheme.titleMedium),
                          subtitle: Text('${g.brand} · ${g.expiryLabel}',
                              style: theme.textTheme.bodySmall),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () {
                            ShareStore.instance
                                .shareGifticon(groupId: groupId, g: g);
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                  content: Text(
                                      '${g.product}${g.product.eulReul} 공유했어요.')));
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
