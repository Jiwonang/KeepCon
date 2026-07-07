/// share 페이지 — 하단 탭의 '공유' 자리표시(placeholder).
///
/// 이 파일은 자리표시 전용이다. 그룹/공유/알림 계약(Group, SharedGifticon,
/// GroupRepository, ShareRepository 등)을 아직 **소비하지 않는다**:
/// - 공유 모델을 재정의하거나 임의 생성하지 않는다.
/// - Repository/Provider 호출, 상태 전이, 라우트 상수 사용이 없다.
/// 실제 기능(그룹 관리·멤버 초대·공유 기프티콘·사용 이력·동기화)은
/// 계약 v1 확정 후 증분 구현한다.
library;

import 'package:flutter/material.dart';

/// 하단 탭에서 '공유' 탭 콘텐츠로 렌더링되는 자리표시 화면.
///
/// 상태·로직·Repository 호출을 포함하지 않으므로 [StatelessWidget]으로 둔다.
/// 기능 구현 시 계약 소비가 필요해지면 `ConsumerWidget`으로 전환한다.
class SharePage extends StatelessWidget {
  const SharePage({super.key});

  /// 앞으로 제공될 기능 안내 항목.
  static const List<({IconData icon, String title, String subtitle})>
      _upcomingFeatures = [
    (
      icon: Icons.groups_outlined,
      title: '그룹 관리',
      subtitle: '그룹을 만들고 인원을 정해 함께 관리해요',
    ),
    (
      icon: Icons.person_add_alt_1_outlined,
      title: '멤버 초대',
      subtitle: '초대 코드나 링크로 가족·친구를 초대해요',
    ),
    (
      icon: Icons.card_giftcard_outlined,
      title: '그룹 공유 기프티콘',
      subtitle: '기프티콘을 그룹에 공유하고 함께 사용해요',
    ),
    (
      icon: Icons.history_outlined,
      title: '사용 이력',
      subtitle: '누가 언제 사용했는지 기록을 확인해요',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('공유'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.group,
                  size: 72,
                  color: colors.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  '공유 기능 준비 중입니다',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '가족·친구와 기프티콘을 함께 관리하고 사용할 수 있어요.\n곧 아래 기능이 제공됩니다.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (int i = 0; i < _upcomingFeatures.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        _FeatureTile(feature: _upcomingFeatures[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 준비 중 기능 한 줄을 표현하는 안내 타일.
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.feature});

  final ({IconData icon, String title, String subtitle}) feature;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Icon(feature.icon),
      ),
      title: Text(feature.title),
      subtitle: Text(feature.subtitle),
      trailing: Chip(
        label: const Text('준비 중'),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: colors.outlineVariant),
      ),
    );
  }
}
