/// main 페이지 — 나의 기프티콘 보관 현황 (KeepCon 틀 재디자인).
///
/// 레이아웃(위→아래): 인사 헤더 → 검색바+필터 → 만료 알림 배너 →
/// 요약 통계 3카드 → 섹션 헤더(전체 N개 / 정렬) → 기프티콘 2열 그리드.
///
/// 계약 소비:
/// - AuthRepository.watchCurrentUser() → 현재 사용자([currentUserProvider]).
/// - GifticonRepository.watchGifticons(ownerId) → 원천 목록([rawGifticonsProvider]).
/// - 정렬([SortOption])·필터는 main에서 수행([visibleGifticonsProvider]).
/// - 요약 통계는 원천 목록에서 계산([gifticonStatsProvider]).
/// - 설정(다크모드)은 공유 [themeModeProvider]를 설정 시트에서 소비.
///
/// 색/폰트/라운드는 전부 `Theme.of(context)`/공유 팔레트 어댑터. 하드코딩 색 없음.
/// 이 재디자인은 '디자인 스캐폴드' — 검색/필터 동작 일부는 정적 자리표시다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/gifticon.dart';
import '../../shared/models/user.dart';
import 'state/gifticon_list_providers.dart';
import 'state/gifticon_stats.dart';
import 'widgets/format.dart';
import 'widgets/gifticon_card.dart';
import 'widgets/gifticon_status_label.dart';
import 'widgets/main_tokens.dart';
import '../mypage/mypage_page.dart';

/// 메인(홈) 화면. [AppRoutes.main]에 등록해 사용한다.
class MainPage extends ConsumerWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<User?> userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _CenterMessage(text: '사용자 정보를 불러오지 못했습니다.\n$e'),
          data: (User? user) => _HomeBody(user: user),
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  final User? user;
  const _HomeBody({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Gifticon>> visibleAsync =
        ref.watch(visibleGifticonsProvider);
    final GifticonStats stats = ref.watch(gifticonStatsProvider);
    final SortOption sort = ref.watch(sortOptionProvider);

    final List<Gifticon> list = visibleAsync.value ?? const <Gifticon>[];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          sliver: SliverList.list(
            children: [
              _GreetingHeader(user: user),
              const SizedBox(height: 20),
              const _SearchRow(),
              const SizedBox(height: 16),
              const _ExpiryBanner(),
              const SizedBox(height: 16),
              _StatsRow(stats: stats),
              const SizedBox(height: 20),
              _SectionHeader(count: list.length, sort: sort),
              const SizedBox(height: 12),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: _GifticonGrid(gifticons: list),
        ),
      ],
    );
  }
}

// ─────────────────────────── 1. 인사 헤더 ───────────────────────────

class _GreetingHeader extends StatelessWidget {
  final User? user;
  const _GreetingHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial = (user?.displayName.isNotEmpty ?? false)
        ? user!.displayName.characters.first.toUpperCase()
        : 'K';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('안녕하세요 👋', style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text('내 기프티콘', style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
        // 알림 벨 + 초록 뱃지 점.
        _NotificationBell(),
        const SizedBox(width: 8),
        // 아바타(다크서피스 배경, 이니셜).
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.darkSurface,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: TextStyle(
              color: context.onDarkSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // 설정 기어 — 마이 페이지(프로필·다크모드·로그아웃) 진입점.
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyPage()),
          ),
          icon: const Icon(Icons.settings_outlined),
          tooltip: '마이',
        ),
      ],
    );
  }
}

class _NotificationBell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.notifications_none, color: scheme.onSurface),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── 2. 검색바 + 필터 버튼 ───────────────────────

class _SearchRow extends StatelessWidget {
  const _SearchRow();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        // 검색바(회색 pill) — 동작은 정적 자리표시.
        Expanded(
          child: TextField(
            enabled: false,
            decoration: InputDecoration(
              hintText: '브랜드, 상품명 검색',
              prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 필터 버튼(다크 원, 슬라이더 아이콘) — 정적 자리표시.
        InkResponse(
          onTap: () {},
          radius: 28,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.darkSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.tune, color: context.onDarkSurface),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── 3. 만료 알림 배너 ───────────────────────

class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color onDark = context.onDarkSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.darkSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          // 초록 시계 아이콘.
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.schedule, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '올리브영 곧 만료!',
                  style: TextStyle(
                    color: onDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '1개의 기프티콘이 7일 내 만료됩니다',
                  style: TextStyle(
                    color: onDark.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 확인 pill(초록).
          _ConfirmPill(onTap: () {}),
        ],
      ),
    );
  }
}

class _ConfirmPill extends StatelessWidget {
  final VoidCallback onTap;
  const _ConfirmPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '확인',
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── 4. 요약 통계 3카드 ───────────────────────

class _StatsRow extends StatelessWidget {
  final GifticonStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: '보유중',
            value: '${stats.holdingCount}',
            icon: Icons.card_giftcard,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: '만료 임박',
            value: '${stats.expiringSoonCount}',
            icon: Icons.schedule,
            emphasize: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: '총금액',
            value: '${formatWon(stats.totalPrice)}원',
            icon: Icons.account_balance_wallet_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool emphasize;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color valueColor = emphasize ? scheme.error : scheme.onSurface;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: 10),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(color: valueColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── 5. 섹션 헤더 ───────────────────────

class _SectionHeader extends StatelessWidget {
  final int count;
  final SortOption sort;
  const _SectionHeader({required this.count, required this.sort});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('전체 $count개', style: theme.textTheme.titleMedium),
        // 정렬 라벨(초록). 계약 SortOption enum 라벨을 표시(자리표시 — 정적).
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sortOptionLabel(sort),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, size: 18, color: scheme.primary),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────── 6. 기프티콘 2열 그리드 ───────────────────────

class _GifticonGrid extends StatelessWidget {
  final List<Gifticon> gifticons;
  const _GifticonGrid({required this.gifticons});

  @override
  Widget build(BuildContext context) {
    if (gifticons.isEmpty) {
      return const SliverToBoxAdapter(
        child: _CenterMessage(
          text: '표시할 기프티콘이 없습니다.\n새 기프티콘을 추가해 보세요.',
        ),
      );
    }
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.66,
      ),
      itemCount: gifticons.length,
      itemBuilder: (context, i) =>
          GifticonGridCard(gifticon: gifticons[i], onTap: () {}),
    );
  }
}

// ─────────────────────── 공통 ───────────────────────

class _CenterMessage extends StatelessWidget {
  final String text;
  const _CenterMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
