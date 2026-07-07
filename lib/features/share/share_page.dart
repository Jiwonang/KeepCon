/// share 페이지 — 하단 탭의 '공유' 화면 (rough 스캐폴드).
///
/// **이 파일은 하드코딩 UI 스캐폴드다.** 화면 구조(내 그룹 / 공유 기프티콘 /
/// 최근 사용 이력)만 잡아두고, 실제 로직·계약 소비는 아직 하지 않는다:
/// - 공유 모델(Group, GroupMember, SharedGifticon, UsageLog 등)을 재정의하거나
///   `lib/shared`에 새로 만들지 않는다. 데이터는 화면 내부 로컬 상수/레코드다.
/// - Repository/Provider 호출, 상태 전이, 라우트 상수 사용이 없다.
/// - 버튼·탭은 동작 없이 스낵바만 띄운다(자리표시).
///
/// 실제 기능(그룹 관리·멤버 초대·공유 기프티콘·사용 이력·사용 동기화·공유 취소)은
/// 계약 v1 확정 후 이 구조 위에 증분 구현한다.
///
/// 색/폰트/라운드/그림자는 전부 `Theme.of(context)` / 공유 팔레트 어댑터에서 온다.
/// 하드코딩 색 없음.
library;

import 'package:flutter/material.dart';

import 'widgets/share_tokens.dart';

/// 하단 탭에서 '공유' 탭 콘텐츠로 렌더링되는 화면.
///
/// 하드코딩 스캐폴드라 상태·Repository 호출이 없어 [StatelessWidget]으로 둔다.
/// 기능 구현 시 계약 소비가 필요해지면 `ConsumerWidget`으로 전환한다.
class SharePage extends StatelessWidget {
  const SharePage({super.key});

  // ── 하드코딩 rough 데이터 (로컬 레코드) ──────────────────────────

  /// 내 그룹 목록(rough). 실제로는 GroupRepository에서 온다.
  static const List<({String emoji, String name, int members, int shared})>
      _groups = [
    (emoji: '🏠', name: '가족', members: 4, shared: 12),
    (emoji: '👥', name: '친구 모임', members: 6, shared: 5),
    (emoji: '💼', name: '회사 동기', members: 3, shared: 2),
  ];

  /// 그룹 공유 기프티콘 목록(rough). 실제로는 ShareRepository에서 온다.
  static const List<
      ({
        String brand,
        String product,
        String sharedBy,
        String status,
        bool available,
      })> _sharedGifticons = [
    (
      brand: '스타벅스',
      product: '아메리카노 T',
      sharedBy: '엄마',
      status: '사용 가능',
      available: true,
    ),
    (
      brand: 'BBQ',
      product: '황금올리브 세트',
      sharedBy: '홍길동',
      status: '사용 가능',
      available: true,
    ),
    (
      brand: 'CU',
      product: '5,000원 금액권',
      sharedBy: '김철수',
      status: '사용 완료',
      available: false,
    ),
  ];

  /// 최근 사용 이력(rough). 실제로는 UsageLog 목록에서 온다.
  static const List<({String who, String what, String when})> _usageLogs = [
    (who: '홍길동', what: '스타벅스 아메리카노', when: '2일 전'),
    (who: '엄마', what: 'CU 5,000원 금액권', when: '4일 전'),
    (who: '김철수', what: '올리브영 1만원권', when: '1주 전'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('공유'),
        actions: [
          // '그룹 만들기' 진입점(자리표시).
          IconButton(
            onPressed: () => _todo(context, '그룹 만들기'),
            icon: const Icon(Icons.group_add_outlined),
            tooltip: '그룹 만들기',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // ── 1. 내 그룹 ──
            const _SectionHeader(title: '내 그룹'),
            const SizedBox(height: 12),
            for (int i = 0; i < _groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _GroupCard(group: _groups[i]),
            ],
            const SizedBox(height: 16),
            const _GroupActionButtons(),

            const SizedBox(height: 28),

            // ── 2. 공유 기프티콘 ──
            const _SectionHeader(title: '공유 기프티콘'),
            const SizedBox(height: 12),
            for (int i = 0; i < _sharedGifticons.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _SharedGifticonCard(item: _sharedGifticons[i]),
            ],

            const SizedBox(height: 28),

            // ── 3. 최근 사용 이력 ──
            const _SectionHeader(title: '최근 사용 이력'),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < _usageLogs.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    _UsageLogTile(log: _usageLogs[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 아직 동작하지 않는 자리표시 액션 — 스낵바로 안내.
  static void _todo(BuildContext context, String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$label 기능은 준비 중입니다.')),
      );
  }
}

// ─────────────────────────── 섹션 헤더 ───────────────────────────

/// 섹션 제목(볼드) 헤더. main 페이지의 섹션 헤더 톤과 맞춘다.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

// ─────────────────────────── 1. 그룹 카드 ───────────────────────────

/// 그룹 한 개를 표현하는 카드(rough). 이모지 아바타 + 이름 + 멤버·공유 수.
class _GroupCard extends StatelessWidget {
  final ({String emoji, String name, int members, int shared}) group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => SharePage._todo(context, '그룹 정보'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 이모지 아바타(darkSurface 원).
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.darkSurface,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  group.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '멤버 ${group.members}명 · 공유 ${group.shared}개',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// '그룹 만들기' / '그룹 참여하기' 액션 버튼 행(자리표시).
class _GroupActionButtons extends StatelessWidget {
  const _GroupActionButtons();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => SharePage._todo(context, '그룹 만들기'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('그룹 만들기'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => SharePage._todo(context, '그룹 참여하기'),
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

// ─────────────────────── 2. 공유 기프티콘 카드 ───────────────────────

/// 그룹에 공유된 기프티콘 한 개(rough). 브랜드·상품명·공유자 + 상태 뱃지.
class _SharedGifticonCard extends StatelessWidget {
  final ({
    String brand,
    String product,
    String sharedBy,
    String status,
    bool available,
  }) item;
  const _SharedGifticonCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // 썸네일 placeholder 블록.
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.card_giftcard,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.brand,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.product,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${item.sharedBy}님이 공유',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(label: item.status, available: item.available),
          ],
        ),
      ),
    );
  }
}

/// 공유 기프티콘 상태 뱃지(rough). 사용 가능=brand 톤, 사용 완료=muted 톤.
///
/// 실제 구현에서는 계약의 `ShareStatus` enum을 소비한다(현재는 하드코딩 라벨).
class _StatusBadge extends StatelessWidget {
  final String label;
  final bool available;
  const _StatusBadge({required this.label, required this.available});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fg = available ? scheme.primary : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────── 3. 사용 이력 타일 ───────────────────────

/// 최근 사용 이력 한 줄(rough). "OOO님이 △△ 사용 · N일 전".
class _UsageLogTile extends StatelessWidget {
  final ({String who, String what, String when}) log;
  const _UsageLogTile({required this.log});

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
          children: [
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
      subtitle: Text(log.when, style: theme.textTheme.bodySmall),
    );
  }
}
