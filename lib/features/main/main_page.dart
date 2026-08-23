/// main 페이지 — 나의 기프티콘 보관 현황 (KeepCon 틀 재디자인).
///
/// 레이아웃(위→아래): 인사 헤더 → 검색바+필터 → 만료 알림 배너 →
/// 요약 통계 3카드 → 섹션 헤더(전체 N개 / 정렬) → 기프티콘 세로 리치 카드 리스트
/// (좌 브랜드 타일 + 정보 + 우 썸네일 + D-day 뱃지).
library;

import 'dart:async';

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
import '../../shared/widgets/notification_bell.dart';
import '../mypage/mypage_page.dart';
import '../scan/scan_page.dart';
import '../share/pages/notification_center_page.dart';
import 'pages/gifticon_detail_page.dart';
import 'state/gifticon_filter.dart';
import 'state/gifticon_list_providers.dart';
import 'state/gifticon_stats.dart';
import 'state/highlighted_gifticon.dart';
import '../../shared/providers/now_provider.dart';
import 'widgets/format.dart';
import 'widgets/gifticon_status_label.dart';
import 'widgets/sort_filter_sheet.dart';

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
        NotificationBell(
          tooltip: '알림',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NotificationCenterPage(),
            ),
          ),
        ),
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

// ─────────────────────── 2. 검색바 + 필터 버튼 ───────────────────────

/// 검색바 + 필터 버튼.
///
/// 입력은 [filterProvider]의 검색어에 **즉시** 반영한다. 디바운스를 두지 않는 이유:
/// 필터링이 이미 받아 둔 목록 위에서 메모리로 끝나기 때문이다(Firestore 재질의가 아니다).
/// 늦출 비용이 없는 곳에 지연을 넣으면 타이핑이 굼떠 보이기만 한다.
class _SearchRow extends ConsumerStatefulWidget {
  const _SearchRow();

  @override
  ConsumerState<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends ConsumerState<_SearchRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // 위젯이 다시 만들어져도(탭 전환 등) 걸려 있던 검색어를 이어서 보여준다. 필터 상태는
    // provider에 남아 목록에 계속 적용되고 있으므로, 입력창만 비면 둘이 어긋난다.
    _controller = TextEditingController(
      text: ref.read(filterProvider).searchQuery,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 입력 원문을 필터에 반영한다. 정규화는 [GifticonFilter.withSearchQuery]가 한다.
  void _applyQuery(String raw) {
    final GifticonFilter current = ref.read(filterProvider);
    final GifticonFilter next = current.withSearchQuery(raw);
    // 정규화 결과가 같으면(예: 끝에 공백만 더 쳤다) 상태를 건드리지 않는다.
    if (next != current) {
      ref.read(filterProvider.notifier).state = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    // **역방향 동기화** — 섹션 헤더의 해제(×)는 필터를 통째로 [GifticonFilter.none]으로
    // 되돌린다. 그때 이 컨트롤러를 같이 비우지 않으면 목록은 전체로 돌아갔는데 검색창에는
    // 글자가 남아, 사용자는 "검색 중인데 왜 다 보이지"를 만난다.
    //
    // **비어질 때만** 따라간다. 반대 방향까지 밀어 넣으면(필터 값 → 컨트롤러) 정규화된
    // 소문자가 입력창으로 되돌아와 타이핑 중 대문자가 뭉개진다.
    ref.listen<String>(
      filterProvider.select((GifticonFilter f) => f.searchQuery),
      (String? previous, String next) {
        if (next.isEmpty && _controller.text.isNotEmpty) _controller.clear();
      },
    );

    return Row(
      children: [
        Expanded(
          // 지우기(×) 버튼은 입력 **원문**이 비었는지로 판단한다. 필터의 검색어로 보면
          // 공백만 친 상태에서 버튼이 사라져 지울 방법이 없어진다.
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (BuildContext context, TextEditingValue value, _) {
              return TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: _applyQuery,
                decoration: InputDecoration(
                  hintText: '브랜드, 상품명 검색',
                  prefixIcon:
                      Icon(Icons.search, color: scheme.onSurfaceVariant),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          color: scheme.onSurfaceVariant,
                          tooltip: '검색어 지우기',
                          onPressed: () {
                            _controller.clear();
                            _applyQuery('');
                          },
                        ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        InkResponse(
          onTap: () => showSortFilterSheet(context),
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
            // (정렬/필터 시트에는 만료 임박 항목이 없다. 저장된 상태가 아니라 날짜에서
            // 파생되는 조건이라서다 — 푸는 길은 이 버튼과 섹션 헤더의 해제(×) 둘뿐이다.)
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
/// 어디서 켜졌는지 모른 채 마주치기 쉽다. 검색어도 같은 이유로 이 계산에 넣는다.
///
/// 정렬 라벨은 [showSortFilterSheet]를 여는 버튼이다(검색바 옆 필터 버튼과 같은 시트).
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

    // 검색·만료 임박·상태·카테고리는 모두 AND로 결합한다. 그래서 둘 이상 겹치면 count는
    // 어느 한 조건의 전부가 아니라 그 교집합이다 — "만료 임박 N개"라고만 쓰면 더 좁은
    // 숫자를 임박 전체인 것처럼 보여주고, 다른 조건이 걸려 있다는 사실도 숨긴다.
    //
    // 그래서 앞머리에는 **가장 눈에 띄는 조건 하나만** 이름 붙이고(검색 > 만료 임박 >
    // 그 외), 거기서 이름을 얻지 못한 조건이 더 남아 있으면 '· 필터 적용'을 덧붙인다.
    // 검색을 맨 앞에 두는 것은 사용자가 방금 직접 친 조건이라 가장 먼저 확인하기 때문이다.
    final String base = filter.hasSearchQuery
        ? '검색 결과 $count개'
        : filter.expiringSoonOnly
            ? '만료 임박 $count개'
            : filter.hasOptionFilter
                ? '$count개'
                : '전체 $count개';
    final bool hasUnnamed = filter.hasOptionFilter ||
        (filter.hasSearchQuery && filter.expiringSoonOnly);
    final String countLabel = hasUnnamed ? '$base · 필터 적용' : base;

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
        // 화살표까지 그려 놓고 눌리지 않으면 고장으로 읽힌다. 검색바 옆 필터 버튼과
        // **같은 시트**를 연다 — 정렬도 그 시트 안에 있으므로 진입점만 둘인 셈이다.
        InkWell(
          onTap: () => showSortFilterSheet(context),
          borderRadius: BorderRadius.circular(AppRadii.dot),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sortOptionLabel(sort),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down,
                    size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── 6. 기프티콘 세로 리치 카드 리스트 ───────────────────────

class _GifticonList extends ConsumerStatefulWidget {
  final List<Gifticon> gifticons;
  const _GifticonList({required this.gifticons});

  @override
  ConsumerState<_GifticonList> createState() => _GifticonListState();
}

class _GifticonListState extends ConsumerState<_GifticonList> {
  /// 강조 대상 카드에 붙이는 키. 스크롤해 보여주려면 그 카드의 [BuildContext]가 필요하다.
  final GlobalKey _highlightKey = GlobalKey();

  /// 이미 스크롤을 마친 강조 id. 같은 강조에 대해 두 번 움직이지 않기 위함이다.
  String? _scrolledFor;

  /// 강조 대상이 생기면 화면 안으로 스크롤한다. 성공할 때까지 빌드마다 재시도한다.
  ///
  /// 강조를 **거두는** 일은 하지 않는다 — 그건 상태(HighlightedGifticonController)가
  /// 스스로 한다. 목록이 화면에 없을 때 탭한 경우에도 같은 시간에 끝나야 하기 때문이다.
  void _scrollToHighlighted(String? id) {
    if (id == null || id == _scrolledFor) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 대상 카드가 아직 만들어지지 않았을 수 있다. 세 경우다:
      //  ① 목록이 아직 도착하지 않았다(위 didUpdateWidget이 다시 시도한다).
      //  ② 필터가 걸려 목록에서 아예 빠졌다(예: 상태 필터).
      //  ③ [SliverList]가 지연 생성이라 화면에서 멀리 떨어진 항목은 빌드되지 않았다.
      // 셋 다 키의 currentContext가 null이다. **여기서 _scrolledFor를 세우지 않는 것이
      // 핵심** — 세워 버리면 ①에서 목록이 도착해도 재시도가 막힌다.
      //
      // ③의 도달 범위는 넓지 않다. 헤더(인사·검색·배너·통계)가 화면을 많이 차지해
      // 한 화면에 만들어지는 카드가 몇 장뿐이고, 그보다 아래 항목은 스크롤 대상이 되지
      // 못한다. 기본 정렬이 만료임박순([SortOption.expiryAsc])이라 알림이 온 기프티콘이
      // 대개 앞쪽에 오는 것으로 상당 부분 상쇄되지만, **먼 항목은 강조만 되고 스크롤은
      // 되지 않는다.** 이걸 제대로 풀려면 인덱스 기반 스크롤(예: scrollable_positioned_list)
      // 이 필요한데, 홈 화면 전체를 sliver 구조에서 들어내야 해서 이득보다 비용이 크다.
      final BuildContext? target = _highlightKey.currentContext;
      if (target == null) return;

      _scrolledFor = id;
      unawaited(Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.2,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? highlightedId = ref.watch(highlightedGifticonIdProvider);

    // 목록이 비었을 때 뭐라고 안내할지 가르는 데 쓴다(아래 빈 상태 분기). 조건부로
    // watch하면 목록이 찼다 비었다 할 때 구독이 붙었다 떨어져, 여기서 미리 읽는다.
    final GifticonFilter filter = ref.watch(filterProvider);

    // 강조가 거둬지면 다음 강조가 다시 스크롤할 수 있게 기록을 비운다.
    if (highlightedId == null) _scrolledFor = null;

    // **빌드마다 시도한다**(성공하면 `_scrolledFor`가 막는다). `ref.listen`으로 강조가
    // 바뀌는 순간에만 시도하면 **강조가 목록보다 먼저 걸리는 경우**가 빠진다 — 알림으로
    // 앱이 열리면 강조가 먼저 걸리고 목록은 저장소에서 나중에 오는데, 그때 이 위젯은
    // 아직 마운트되지도 않았거나 대상 카드가 없어 스크롤을 건너뛴다. 강조 id는 그대로라
    // 리스너는 다시 울리지 않고, 카드는 강조된 채 화면 밖에 남는다.
    _scrollToHighlighted(highlightedId);

    if (widget.gifticons.isEmpty) {
      // 하나도 안 가진 것과, 걸러져서 안 보이는 것은 다른 상황이다. 후자에 "새 기프티콘을
      // 추가해 보세요"라고 하면 가지고 있는 것이 사라졌다고 읽는다 — 그때 필요한 안내는
      // 추가가 아니라 조건을 풀라는 쪽이다.
      return SliverToBoxAdapter(
        child: _CenterMessage(
          text: filter.isAnyActive
              ? '조건에 맞는 기프티콘이 없습니다.\n검색어나 필터를 바꿔 보세요.'
              : '표시할 기프티콘이 없습니다.\n새 기프티콘을 추가해 보세요.',
        ),
      );
    }
    return SliverList.separated(
      itemCount: widget.gifticons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (BuildContext context, int i) {
        final Gifticon g = widget.gifticons[i];
        final bool highlighted = g.id == highlightedId;
        return _RichGifticonCard(
          key: highlighted ? _highlightKey : null,
          gifticon: g,
          highlighted: highlighted,
          // 셸의 push 패턴을 따른다(앱 전역이 MaterialPageRoute 직접 push — AppRoutes는
          // 탭 라우트 문서용이라 실제 내비게이션에 쓰이지 않는다).
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => GifticonDetailPage(gifticon: g),
            ),
          ),
        );
      },
    );
  }
}

/// 기프티콘 한 장 — 좌 브랜드 타일 + 중앙 정보 + 우 썸네일 + 우상단 D-day 뱃지.
class _RichGifticonCard extends StatelessWidget {
  final Gifticon gifticon;

  /// 알림을 타고 들어와 잠시 짚어 보여주는 중인지. 테두리로 표시한다.
  final bool highlighted;

  /// 카드 탭 — 상세 화면 진입. null이면 비활성(잉크 반응도 없다).
  final VoidCallback? onTap;

  const _RichGifticonCard({
    super.key,
    required this.gifticon,
    this.highlighted = false,
    this.onTap,
  });

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

    // 강조는 **테두리만** 더한다. 배경색을 바꾸면 브랜드 색·D-day 뱃지와 경쟁해
    // 오히려 무엇을 봐야 할지 흐려진다.
    final BoxDecoration base =
        AppDecorations.softCard(scheme, shadowOpacity: 0.05);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: highlighted
          ? base.copyWith(
              border: Border.all(color: scheme.primary, width: 2),
            )
          : base,
      // 잉크(리플)가 카드 배경 **위에** 그려지도록 [InkWell]을 컨테이너 안쪽에 둔다.
      // 바깥에 두면 불투명한 surface 배경에 가려 눌린 반응이 보이지 않는다. 리플이
      // 라운드 모서리 밖으로 번지지 않게 클립도 데코와 같은 반경으로 건다.
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                                  color: used
                                      ? scheme.onSurfaceVariant
                                      : scheme.error),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${formatYmdDot(gifticon.expiryDate)} 만료',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: used
                                        ? scheme.onSurfaceVariant
                                        : scheme.error,
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
                          color: brand.background.withValues(alpha: 0.55),
                          size: 24),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: _DDayBadge(
                      used: used, expired: expired, daysLeft: daysLeft),
                ),
              ],
            ),
          ),
        ),
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
