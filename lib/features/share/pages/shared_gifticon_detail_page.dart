/// share 페이지 — 공유 기프티콘 상세(전체 화면, KeepCon 틀 재디자인).
///
/// 브랜드 히어로(쿠폰 배너) + 상태(잠김/찜/사용완료) + QR/바코드 + 액션(찜·사용완료·공유취소).
/// 상태 변경은 계약 [ShareRepository]에 반영되고 목록/뱃지가 동기화된다. 사용 완료 시
/// 원본 [Gifticon]도 `GifticonStatus.used`로 동기화되어 메인 목록에 반영된다(계약 경계면).
/// 색 하드코딩 없음(공유 [BrandPalette]·테마 토큰 소비).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/share.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
import '../../../shared/theme/brand_palette.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/util/korean_particle.dart';
import '../../../shared/widgets/gifticon_detail_widgets.dart';
import '../state/share_providers.dart';
import '../widgets/share_common.dart';
import '../widgets/share_error_banner.dart';
import '../widgets/share_format.dart';

/// 공유 기프티콘 상세 화면. 셸의 push 패턴으로 전체화면 이동한다.
class SharedGifticonDetailPage extends ConsumerWidget {
  const SharedGifticonDetailPage({super.key, required this.itemId});

  /// 표시할 공유 기프티콘 id.
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 항상 최신 항목을 조회. 공유취소 등으로 사라지면 안내를 표시한다.
    final SharedGifticon? item = ref.watch(sharedItemByIdProvider(itemId));
    if (item == null) {
      // null의 원인이 둘이다 — ① 정말 사라짐(공유취소·그룹 이탈) ② 조회 실패(스트림 에러).
      // 폴딩된 [sharedItemByIdProvider]만 보면 구분이 안 되므로, 원천 에러 여부를
      // 함께 관찰해 "찾을 수 없어요"(확정)와 "불러오지 못했어요"(재시도 가능)를 나눈다.
      final bool hasError = ref.watch(sharedItemLookupHasErrorProvider);
      // 에러의 출처가 둘(내 그룹 목록 / 그룹별 공유 스트림)이므로 재시도도 두 축을
      // 함께 되살린다([retrySharedItemLookup] — 각 축은 에러인 계층만 재구독한다).
      // 예전엔 그룹 목록이 원인이면 되살릴 방법이 없어 버튼을 감췄지만(#13), 계약
      // 정본이 재시도 훅을 제공하면서 그 강등 분기가 사라졌다.
      // 세 번째 원인: 조회 경로가 아직 첫 방출 전(값 없는 로딩)이면 부재가 확정이
      // 아니다 — "찾을 수 없어요"로 위장하지 않고 스피너를 둔다. 현 진입 경로
      // (목록 타일 탭)에서는 캐시가 항상 따뜻해 닿지 않지만, 알림→상세 직행·딥링크
      // 같은 콜드 진입이 추가되는 순간 현실화되는 창이라 미리 막는다.
      final bool pending = ref.watch(sharedGifticonsPendingProvider);
      return Scaffold(
        appBar: AppBar(centerTitle: true, title: const Text('공유 기프티콘')),
        body: hasError
            ? Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ShareErrorBanner(
                    message: '공유 기프티콘 정보를 불러오지 못했어요.',
                    onRetry: () => retrySharedItemLookup(ref),
                  ),
                ),
              )
            : pending
                ? const Center(child: CircularProgressIndicator())
                : const Center(child: Text('기프티콘을 찾을 수 없어요.')),
      );
    }
    return _DetailBody(item: item);
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.item});

  final SharedGifticon item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // 세션 정본 직접 소비 — 쓰는 값이 id 뿐이라 `select`로 좁힌다.
    final String? uid = ref.watch(
      sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
    );
    final MemberNames names = ref.watch(memberNamesProvider);
    final String actorId = uid ?? '';
    final BrandStyle brand = BrandPalette.of(item.brand);

    final bool locked = item.isLockedFor(actorId);
    final bool reservedByMe = uid != null && item.reservedByUserId == uid;
    // 다른 멤버가 이미 찜한 상태(내 찜 아님) — 찜 버튼 비활성.
    final bool reservedByOther = item.isReservedByOther(actorId);
    // 내가 공유한 기프티콘만 회수(공유 취소)할 수 있다.
    final bool iShared = uid != null && item.sharedByUserId == uid;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('공유 기프티콘', style: context.navTitleStyle),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          children: <Widget>[
            // 브랜드 히어로(쿠폰 배너).
            BrandHero(brand: brand, brandName: item.brand),
            const SizedBox(height: 22),

            // 브랜드·상품·상태.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.brand,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text(
                        item.productName,
                        style: context.heroProductStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ShareStatusBadge(status: item.status, locked: locked),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 공유자 · 유효기간.
            Row(
              children: <Widget>[
                Icon(Icons.person_outline,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${names.isMe(item.sharedByUserId) ? '내가' : '${names.labelFor(item.sharedByUserId)}님이'} 공유'
                    '  ·  유효기간 ${formatExpiryLabel(item.expiryDate)}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (item.reservedByUserId != null) ...<Widget>[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ReservedBadge(
                  name: names.labelFor(item.reservedByUserId!),
                  isMe: names.isMe(item.reservedByUserId!),
                ),
              ),
            ],
            const SizedBox(height: 22),

            // QR/바코드 카드.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border:
                    Border.all(color: scheme.outline.withValues(alpha: 0.18)),
              ),
              child: Column(
                children: <Widget>[
                  Icon(Icons.qr_code_2, size: 120, color: scheme.onSurface),
                  const SizedBox(height: 16),
                  Text(item.barcode ?? '바코드 정보 없음',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 잠김/사용완료 안내.
            if (locked)
              DetailInfoBanner(
                icon: Icons.lock_outline,
                text: item.lockedByUserId != null
                    ? '${names.labelFor(item.lockedByUserId!)}님이 사용 중이라 지금은 사용할 수 없어요.'
                    : '다른 멤버가 사용 중이라 지금은 사용할 수 없어요.',
              ),
            if (item.isUsed)
              const DetailInfoBanner(
                icon: Icons.check_circle_outline,
                text: '이미 사용 완료된 기프티콘이에요.',
              ),

            // 액션 — 사용 완료·잠김(다른 멤버 사용중) 상태에선 노출하지 않는다.
            if (!item.isUsed && !locked) ...<Widget>[
              OutlinedButton.icon(
                // 다른 멤버가 이미 찜했으면 비활성(남의 찜을 덮어쓰지 않음).
                onPressed:
                    reservedByOther ? null : () => _toggleReserve(context, ref),
                icon:
                    Icon(reservedByMe ? Icons.bookmark : Icons.bookmark_border),
                label: Text(reservedByMe ? '찜 해제' : '찜하기 (사용 예정)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.primary,
                  side:
                      BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.tile)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _markUsed(context, ref),
                icon: const Icon(Icons.check, size: 20),
                label: const Text('사용 완료'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.tile)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              // 공유 취소(회수)는 내가 공유한 항목만 가능.
              if (iShared) ...<Widget>[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _confirmCancel(context, ref),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  icon: const Icon(Icons.undo),
                  label: const Text('공유 취소 (회수)'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReserve(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shareRepositoryProvider).toggleReservation(item.id);
    } on StateError {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 찜할 수 없어요.')));
    }
  }

  Future<void> _markUsed(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shareRepositoryProvider).markUsed(item.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('사용 완료 처리했어요.')));
    } on StateError {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 사용 완료할 수 없어요.')));
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('공유 취소'),
        content:
            Text('${item.productName}${item.productName.eulReul} 그룹에서 회수할까요?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('닫기')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('회수')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // 버튼은 이미 공유자·미사용중일 때만 노출되지만, 저장소 가드가 최종 판정한다.
    try {
      await ref.read(shareRepositoryProvider).cancelShare(item.id);
      navigator.pop();
    } on StateError {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 회수할 수 없어요.')));
    }
  }
}
