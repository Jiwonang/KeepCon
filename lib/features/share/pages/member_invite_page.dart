/// share 페이지 — 멤버 초대(전체 화면).
///
/// 초대 URL + 초대코드(각 복사 버튼), 만료시간 선택, "방장만 초대" 권한 토글(UI만).
/// 색 하드코딩 없음. 실제 초대 발송/권한 저장은 계약 이관 시 연동한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/korean_particle.dart';
import '../data/share_models.dart';

/// 멤버 초대 화면. 그룹 상세에서 push 한다.
class MemberInvitePage extends StatefulWidget {
  const MemberInvitePage({super.key, required this.group});

  /// 초대 대상 그룹.
  final Group group;

  @override
  State<MemberInvitePage> createState() => _MemberInvitePageState();
}

class _MemberInvitePageState extends State<MemberInvitePage> {
  InviteExpiry _expiry = InviteExpiry.oneDay;
  bool _ownerOnly = false;

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label${label.eulReul} 복사했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Group g = widget.group;

    return Scaffold(
      appBar: AppBar(title: const Text('멤버 초대')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: <Widget>[
            Text('"${g.name}" 그룹으로 초대', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('아래 링크나 코드를 공유하세요.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            _CopyField(label: '초대 링크', value: g.inviteUrl, onCopy: _copy),
            const SizedBox(height: 12),
            _CopyField(label: '초대코드', value: g.inviteCode, onCopy: _copy),
            const SizedBox(height: 24),
            Text('초대코드 만료', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final InviteExpiry e in InviteExpiry.values)
                  ChoiceChip(
                    label: Text(e.label),
                    selected: _expiry == e,
                    onSelected: (_) => setState(() => _expiry = e),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                value: _ownerOnly,
                onChanged: (bool v) => setState(() => _ownerOnly = v),
                title: const Text('방장만 초대 가능'),
                subtitle: Text('켜면 방장 외 멤버는 초대할 수 없어요.',
                    style: theme.textTheme.bodySmall),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _copy(g.inviteUrl, '초대 링크'),
              icon: const Icon(Icons.share_outlined),
              label: const Text('초대 링크 공유'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 라벨 + 값 + 복사 버튼 필드.
class _CopyField extends StatelessWidget {
  const _CopyField({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final void Function(String value, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => onCopy(value, label),
              icon: const Icon(Icons.copy_outlined),
              tooltip: '복사',
            ),
          ],
        ),
      ),
    );
  }
}
