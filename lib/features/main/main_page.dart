/// main 페이지 — 나의 기프티콘 보관 현황 (KeepCon 틀 재디자인).
///
/// 레이아웃(위→아래): 인사 헤더 → 검색바+필터 → 만료 알림 배너 →
/// 요약 통계 3카드 → 섹션 헤더(전체 N개 / 정렬) → 기프티콘 세로 리치 카드 리스트
/// (좌 브랜드 타일 + 정보 + 우 썸네일 + D-day 뱃지).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/gifticon.dart';
import '../../shared/models/user.dart';
import '../../shared/providers/session_provider.dart';
import '../../shared/theme/brand_palette.dart';
import '../../shared/theme/theme_tokens.dart';
import '../../shared/util/date_format.dart' show formatYmdDot;
import '../../shared/util/expiry_policy.dart';
import '../../shared/util/money_format.dart' show formatWon;
import '../mypage/mypage_page.dart';
import '../scan/scan_page.dart';
import 'state/gifticon_filter.dart';
import 'state/gifticon_list_providers.dart';
import 'state/gifticon_stats.dart';
import 'state/now_provider.dart';
import 'widgets/format.dart';
import 'widgets/gifticon_status_label.dart';

/// 메인(홈) 화면. [AppRoutes.main]에 등록해 사용한다.
class MainPage extends ConsumerWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<User?> userAsync = ref.watch(sessionUserProvider);

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
    final GifticonFilter filter = ref.watch(filterProvider);

    // 배너용 목록은 **원천 기준**(필터 무관)이다 — 필터를 걸었다고 "곧 만료되는 것이
    // 없다"고 알리면 안 된다.
    final List<Gifticon> expiringSoon =
        ref.watch(expiringSoonGifticonsProvider);

    final List<Gifticon> list = visibleAsync.valueOrNull ?? const <Gifticon>[];

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
              // 임박한 것이 없으면 배너째로 뺀다. 뒤따르는 간격도 함께 빼야
              // 빈 자리가 남지 않는다.
              if (expiringSoon.isNotEmpty) ...<Widget>[
                _ExpiryBanner(expiringSoon: expiringSoon),
                const SizedBox(height: 16),
              ],
              _StatsRow(stats: stats),
              const SizedBox(height: 20),
              _SectionHeader(count: list.length, sort: sort, filter: filter),
              const SizedBox(height: 12),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: _GifticonList(gifticons: list),
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
    final String displayName = user?.displayName ?? '';
    final String initial = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
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
              Text(
                '우리집 기프티콘',
                style: context.pageHeaderStyle,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScanPage()),
            );
          },
          icon: const Icon(Icons.add_circle_outline),
          tooltip: '기프티콘 추가',
        ),
        const SizedBox(width: 4),
        const _NotificationBell(),
        const SizedBox(width: 8),
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
        IconButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyPage()),
            );
          },
          icon: const Icon(Icons.settings_outlined),
          tooltip: '마이',
        ),
      ],
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

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
        InkResponse(
          onTap: () {},
          radius: 28,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.darkSurface,
              borderRadius: BorderRadius.circular(AppRadii.panel),
            ),
            child: Icon(Icons.tune, color: context.onDarkSurface),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── 3. 만료 알림 배너 ───────────────────────

/// 만료 임박 알림 배너.
///
/// [expiringSoon]은 **비어 있지 않다고 가정한다** — 0개일 때 이 위젯은 아예 만들어지지
/// 않는다(호출부 [_HomeBody]에서 걸러낸다). "임박 없음" 상태를 배너로 알리지 않는 것은
/// 의도된 선택이다: 알릴 것이 없을 때 자리를 차지하지 않는 편이 낫다.
///
/// 개수·대표 항목을 **한 목록에서** 파생시킨다. 예전에는 개수를 원천 통계에서, 대표
/// 브랜드를 화면 표시 목록(필터·정렬 적용본)에서 각각 가져와, 필터를 걸면 "3개 만료"인데
/// 제목은 폴백 '기프티콘'이 뜨는 불일치가 났다.
class _ExpiryBanner extends ConsumerWidget {
  final List<Gifticon> expiringSoon;

  const _ExpiryBanner({required this.expiringSoon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color onDark = context.onDarkSurface;

    final GifticonFilter filter = ref.watch(filterProvider);
    final bool isFiltered = filter.expiringSoonOnly;
    final DateTime now = ref.watch(nowProvider);

    // 목록은 만료 임박순 정렬본이므로 first가 "가장 급한 것"이다.
    final Gifticon soonest = expiringSoon.first;
    final int others = expiringSoon.length - 1;

    // 이 항목을 목록에 넣은 판정과 **같은 시각**으로 D-day를 센다. 여기서 시계를 새로
    // 읽으면(`now:` 생략) 자정 직후 리빌드에서 "-1일 뒤 만료"처럼 목록 판정과 어긋난
    // 값이 찍힌다. `<= 0` 하한도 그 방어의 일부다.
    final int daysLeft = daysUntilExpiry(soonest.expiryDate, now: now);
    final String whenLabel = daysLeft <= 0 ? '오늘 만료' : '$daysLeft일 뒤 만료';

    final String title = others == 0
        ? '${soonest.brand} 곧 만료!'
        : '${soonest.brand} 외 $others개 곧 만료!';
    final String subTitle = others == 0
        ? '${soonest.productName} · $whenLabel'
        : '${expiringSoon.length}개의 기프티콘이 $expirySoonDays일 내 만료됩니다';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.darkSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadii.thumb),
            ),
            child: Icon(Icons.schedule, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: onDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subTitle,
                  style: TextStyle(
                    color: onDark.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ConfirmPill(
            // 토글이다 — 적용만 되고 풀 방법이 없으면 목록이 잠긴 것처럼 보인다.
            // (홈에는 아직 필터 컨트롤 UI가 없어 이 버튼이 유일한 해제 수단이다.)
            label: isFiltered ? '해제' : '확인',
            onTap: () {
              ref.read(filterProvider.notifier).state =
                  filter.withExpiringSoonOnly(!isFiltered);
            },
          ),
        ],
      ),
    );
  }
}

class _ConfirmPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ConfirmPill({required this.label, required this.onTap});

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
            label,
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
    final bool hasPrice = stats.totalPrice > 0;
    final String priceText = hasPrice ? '${formatWon(stats.totalPrice)}원' : '-';

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
            emphasize: stats.expiringSoonCount > 0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: '총금액',
            value: priceText,
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

/// 목록 섹션 헤더 — 표시 개수 + 활성 필터 표시 + 정렬.
///
/// 필터가 걸려 있으면 "전체"라고 쓰지 않는다. 걸러진 목록을 전체라고 부르면 사용자는
/// 기프티콘이 사라졌다고 읽는다 — 특히 만료 임박 필터는 배너 버튼 한 번으로 켜지므로
/// 어디서 켜졌는지 모른 채 마주치기 쉽다.
class _SectionHeader extends ConsumerWidget {
  final int count;
  final SortOption sort;
  final GifticonFilter filter;
  const _SectionHeader({
    required this.count,
    required this.sort,
    required this.filter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final String countLabel = filter.expiringSoonOnly
        ? '만료 임박 $count개'
        : (filter.isAnyActive ? '$count개 · 필터 적용' : '전체 $count개');

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  countLabel,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (filter.isAnyActive) ...<Widget>[
                const SizedBox(width: 6),
                InkResponse(
                  onTap: () => ref.read(filterProvider.notifier).state =
                      GifticonFilter.none,
                  radius: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
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

// ─────────────────────── 6. 기프티콘 세로 리치 카드 리스트 ───────────────────────

class _GifticonList extends StatelessWidget {
  final List<Gifticon> gifticons;
  const _GifticonList({required this.gifticons});

  @override
  Widget build(BuildContext context) {
    if (gifticons.isEmpty) {
      return const SliverToBoxAdapter(
        child: _CenterMessage(
          text: '표시할 기프티콘이 없습니다.\n새 기프티콘을 추가해 보세요.',
        ),
      );
    }
    return SliverList.separated(
      itemCount: gifticons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) => _RichGifticonCard(gifticon: gifticons[i]),
    );
  }
}

/// 기프티콘 한 장 — 좌 브랜드 타일 + 중앙 정보 + 우 썸네일 + 우상단 D-day 뱃지.
class _RichGifticonCard extends StatelessWidget {
  final Gifticon gifticon;
  const _RichGifticonCard({required this.gifticon});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BrandStyle brand = BrandPalette.of(gifticon.brand);

    final DateTime nowDate = DateTime.now();
    final int daysLeft = daysUntilExpiry(gifticon.expiryDate, now: nowDate);
    final bool used = gifticon.status == GifticonStatus.used;
    final bool expired = gifticon.status == GifticonStatus.expired ||
        isExpiredByDate(gifticon.expiryDate, now: nowDate);

    final bool hasPrice = gifticon.price > 0;
    final String priceText = hasPrice ? '${formatWon(gifticon.price)}원' : '-';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.softCard(scheme, shadowOpacity: 0.05),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 84,
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
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gifticon.brand,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      gifticon.productName,
                      style: context.itemTitleStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceText,
                      style: context.rowTitleStyle,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.schedule,
                            size: 14,
                            color:
                                used ? scheme.onSurfaceVariant : scheme.error),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${formatYmdDot(gifticon.expiryDate)} 만료',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  used ? scheme.onSurfaceVariant : scheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 56,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brand.background.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadii.thumb),
                ),
                child: Icon(Icons.card_giftcard,
                    color: brand.background.withValues(alpha: 0.55), size: 24),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _DDayBadge(used: used, expired: expired, daysLeft: daysLeft),
          ),
        ],
      ),
    );
  }
}

/// D-day 뱃지(빨강 pill). 사용완료=회색 '완료', 만료=빨강 '만료'.
class _DDayBadge extends StatelessWidget {
  final bool used;
  final bool expired;
  final int daysLeft;
  const _DDayBadge(
      {required this.used, required this.expired, required this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final String text;
    if (used) {
      bg = scheme.onSurface.withValues(alpha: 0.08);
      fg = scheme.onSurfaceVariant;
      text = '완료';
    } else if (expired) {
      bg = scheme.error.withValues(alpha: 0.12);
      fg = scheme.error;
      text = '만료';
    } else {
      bg = scheme.error.withValues(alpha: 0.12);
      fg = scheme.error;
      text = formatDDay(daysLeft);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(AppRadii.dot)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12),
      ),
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
