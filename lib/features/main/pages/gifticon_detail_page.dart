/// main 페이지 — 내 기프티콘 상세.
///
/// 목록 카드를 탭하면 열린다. 매장에서 실제로 쓰는 화면이므로 **바코드가 주인공**이고,
/// 그 아래 사용 완료 처리를 둔다. 상태 전이는 계약 [GifticonRepository.updateStatus]에
/// 위임하며(전이 규칙은 [GifticonStatusTransition]이 SSOT), 이 화면은 판정하지 않고
/// 노출 여부만 고른다.
///
/// ## 이미지를 싣지 않는 이유
/// [Gifticon.imagePath]는 로컬 파일 경로(`image_picker`가 준 값)라 표시하려면 `dart:io`가
/// 필요한데, 이 앱은 web도 지원 대상이라 `dart:io`를 조건부 import로 감싸야 한다. 그
/// 추상화는 별도 관심사라 이번 범위에서 뺐다 — 바코드 번호가 있으면 아래 [_BarcodeCard]가
/// 스캔 가능한 심볼을 직접 그리므로 매장 사용에는 지장이 없다.
library;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/diagnostics/report_handled_failure.dart';
import '../../../shared/models/gifticon.dart';
import '../../../shared/models/share.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
import '../../../shared/providers/shared_gifticons_provider.dart';
import '../../../shared/theme/brand_palette.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/widgets/gifticon_detail_widgets.dart';
import '../../../shared/util/date_format.dart' show formatYmdDot;
import '../../../shared/util/expiry_policy.dart';
import '../../../shared/util/korean_particle.dart';
import '../../../shared/util/money_format.dart' show formatWon;
import '../state/gifticon_list_providers.dart';
import '../../../shared/providers/now_provider.dart';
import '../widgets/extend_expiry_dialog.dart';
import '../widgets/format.dart';
import '../widgets/gifticon_status_label.dart';

/// 기프티콘 상세 화면. 목록에서 `MaterialPageRoute`로 push한다.
class GifticonDetailPage extends ConsumerWidget {
  const GifticonDetailPage({super.key, required this.gifticon});

  /// 진입 시점의 스냅샷. 저장소 최신값을 못 찾을 때의 폴백으로만 쓴다.
  final Gifticon gifticon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 저장소 최신값을 우선한다 — 사용 완료 처리 후 이 화면의 상태 뱃지·버튼이 즉시
    // 따라가야 하기 때문이다. 목록에서 사라졌을 때만 진입 스냅샷으로 떨어진다(계정
    // 전환·스트림 순단). 그 경우 화면은 옛 값을 보여주지만 조작은 저장소 가드가 막고
    // 스낵바로 알린다 — 빈 화면을 띄우는 것보다 낫다.
    final Gifticon g = ref.watch(gifticonByIdProvider(gifticon.id)) ?? gifticon;

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final BrandStyle brand = BrandPalette.of(g.brand);

    // 시각은 [nowProvider] 정본에서 받는다 — 여기서 따로 [DateTime.now]를 읽으면 자정을
    // 넘기는 순간 목록의 D-day와 상세의 D-day가 갈린다(목록은 이미 정본을 소비한다).
    final DateTime now = ref.watch(nowProvider);
    final int daysLeft = daysUntilExpiry(g.expiryDate, now: now);
    final bool expiredByDate = isExpiredByDate(g.expiryDate, now: now);
    final bool used = g.status == GifticonStatus.used;

    // 공유 여부는 계약 정본 [sharedGifticonIdsProvider]에 묻는다.
    //
    // **[Gifticon.targetGroupId]를 보면 안 된다.** 그 필드는 scan이 *등록 시점에* 그룹을
    // 지정한 경우에만 채워진다 — 흔한 경로인 "이미 등록한 기프티콘을 공유 탭에서 공유"는
    // [ShareRepository.shareGifticon]이 [SharedGifticon] 레코드만 만들고 원본을 건드리지
    // 않아 끝까지 null이고, Firestore 매핑은 이 필드를 읽지도 쓰지도 않아 dev/prod에서는
    // 항상 null이다. 그걸로 판정하면 가드가 죽은 채 통과한다(코드리뷰에서 검출).
    final AsyncValue<Set<String>> sharedIdsAsync =
        ref.watch(sharedGifticonIdsProvider);
    final Set<String>? sharedIds = sharedIdsAsync.valueOrNull;
    final bool shared = sharedIds?.contains(g.id) ?? false;

    // 사용 완료 버튼 노출 조건.
    //
    // ① 상태가 available일 때만 — used/expired는 terminal 전이라 호출하면 StateError다.
    // ② 공유 여부가 **확정된 뒤에만**(`sharedIds != null`). 로딩을 "공유 안 됨"으로 접으면
    //    가드가 fail-open 한다 — 그룹 목록이 도착하기 전 몇 프레임 버튼이 열리고, 그 창에서
    //    누르면 원본만 used가 된다.
    // ③ 공유 중이 아닐 때만. 공유 중인데 여기서 [GifticonRepository.updateStatus]를 부르면
    //    원본만 used가 되고 그룹의 [SharedGifticon]은 '사용 가능'으로 남는다 — 계약의
    //    동기화는 공유→원본 한 방향뿐이다([ShareRepository.markUsed]). 그 상태로 두면 다른
    //    멤버가 이미 쓴 기프티콘을 매장에서 꺼내게 된다. 양방향 동기화는 계약 변경이라
    //    별건으로 다루고, 여기서는 이미 완비된 공유 탭 경로로 보낸다.
    //
    // 날짜상 만료(expiredByDate)는 **막지 않는다.** status를 expired로 옮기는 주체가 아직
    // 없어(만료 판정은 날짜 기준 표시일 뿐) 여기서 가리면 만료일이 지난 기프티콘은 영영
    // 사용 완료로 정리하지 못하고 목록에 남는다.
    final bool canMarkUsed =
        g.status == GifticonStatus.available && sharedIds != null && !shared;

    // 유효기간 연장 버튼 노출 조건.
    //
    // ① 만료됐을 때만 — 아직 쓸 수 있는 기프티콘에까지 버튼을 두면 상세 화면의 주된
    //    행동(바코드 제시·사용 완료)에서 시선을 나눠 간다. 날짜 만료(expiredByDate)와
    //    저장된 `expired`를 모두 받는다: 만료 판정의 실질 정본은 날짜이고, 저장된 상태는
    //    레거시·데모 시드에만 있지만 그것도 사용자에게는 똑같이 '만료'로 보인다.
    // ② 사용 완료가 아닐 때 — 이미 쓴 기프티콘은 기간을 늘려도 쓸 수 없다(계약도 거부).
    // ③ 등록한 본인일 때 — 요구사항이 "최초 등록자만". main은 자기 목록만 보므로 사실상
    //    항상 참이지만, 진입 스냅샷 폴백으로 남의 것이 표시될 여지를 여기서 닫는다.
    // ④ 공유 경로가 **확정된 뒤에만**([sharedItemForGifticonProvider] — fail-closed).
    //    공유 중인데 개인 경로로 연장하면 그룹 스냅샷만 옛 날짜로 남고, 그 어긋남은 어느
    //    화면에도 보이지 않는다.
    final AsyncValue<SharedGifticon?> sharedItemAsync =
        ref.watch(sharedItemForGifticonProvider(g.id));
    final String? myUserId = ref.watch(
        sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id));
    final bool expiredNow = expiredByDate || g.status == GifticonStatus.expired;
    final bool mine = myUserId != null && g.ownerId == myUserId;
    // ⑤ 공유 항목이 아직 소진되지 않았을 때만. 다른 멤버가 내 공유분을 사용해도 **내
    //    원본은 available로 남는다** — `gifticons`는 소유자만 쓸 수 있어 그쪽의 원본
    //    동기화가 권한으로 건너뛰기 때문이다(계약이 명시한 best-effort). 그래서
    //    `!used`만으로는 이 상태가 걸러지지 않고, 그대로 두면 눌러도 계약 가드가
    //    반드시 거부하는 버튼이 남는다.
    final bool canExtend = expiredNow &&
        !used &&
        mine &&
        sharedItemAsync.hasValue &&
        sharedItemAsync.value?.status != ShareStatus.used;

    // 공유 여부가 확정되기 전까지 함께 막히는 두 행동. 배너 하나로 안내한다.
    final bool markUsedBlocked =
        !used && g.status == GifticonStatus.available && sharedIds == null;
    final bool extendBlocked =
        !used && expiredNow && mine && !sharedItemAsync.hasValue;
    final bool blockedByShareState = markUsedBlocked || extendBlocked;
    final String blockedActionLabel = markUsedBlocked && extendBlocked
        ? '사용 완료와 기간 연장'
        : (extendBlocked ? '기간 연장' : '사용 완료');

    // 하단 액션 버튼들의 공용 스타일. 연장과 사용 완료는 같은 자리의 같은 무게라 모양이
    // 갈리면 안 되고, 사본을 두면 한쪽만 고쳐져 갈라진다(CodeRabbit 지적).
    //
    // ⚠️ `theme.textTheme.labelLarge`를 소비하지 않는다 — 이 앱의 [TextTheme]은 그 슬롯을
    //    **정의하지 않아서**(app_theme.dart는 headline/title/body/labelMedium만 채운다)
    //    Material 기본값(height 1.43 · letterSpacing 0.1 · fontFamily Roboto)이 딸려 들어와
    //    이 PR과 무관한 기존 '사용 완료' 버튼이 **52 → 56px로 자란다**(측정값. 지배적인
    //    것은 자간이 아니라 행높이다). 색만은 `foregroundColor`가 덮으므로 무관하다.
    //    버튼 타이포를 토큰화하려면 테마에 슬롯을 먼저 정의해야 하고, `labelLarge`는 M3에서
    //    모든 버튼의 기본 스타일이라 앱 전역 변경이다 — 이 PR의 범위가 아니다.
    final ButtonStyle actionButtonStyle = ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    );

    // 목록 카드는 날짜 만료도 '만료'로 칠하는데(`_DDayBadge`), 뱃지가 status만 보면 목록에서
    // '만료'인 카드를 눌렀는데 상세 헤더는 '사용가능'이라고 답한다. 같은 기프티콘을 두고 두
    // 화면이 다른 말을 하지 않도록 표시용 상태를 맞춘다(저장된 status는 건드리지 않는다).
    final GifticonStatus displayStatus =
        g.status == GifticonStatus.available && expiredByDate
            ? GifticonStatus.expired
            : g.status;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('기프티콘', style: context.navTitleStyle),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          children: <Widget>[
            BrandHero(brand: brand, brandName: g.brand),
            const SizedBox(height: 22),

            // 브랜드 · 상품명 · 상태 뱃지.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        g.brand,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(g.productName, style: context.heroProductStyle),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _StatusBadge(status: displayStatus),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 금액 · 카테고리 · 유효기간.
            GifticonMetaRow(
              icon: Icons.account_balance_wallet_outlined,
              text: g.price > 0 ? '${formatWon(g.price)}원' : '금액 미입력',
            ),
            const SizedBox(height: 8),
            GifticonMetaRow(icon: Icons.sell_outlined, text: g.category),
            const SizedBox(height: 8),
            GifticonMetaRow(
              icon: Icons.schedule,
              // 사용 완료한 것에까지 만료를 빨갛게 칠하면 처리할 일이 남은 것처럼 읽힌다.
              emphasize: !used &&
                  (expiredByDate || isExpiringSoon(g.expiryDate, now: now)),
              text: '${formatYmdDot(g.expiryDate)} 만료'
                  '${used ? '' : '  ·  ${formatDDay(daysLeft)}'}',
            ),
            const SizedBox(height: 22),

            _BarcodeCard(barcode: g.barcode),
            const SizedBox(height: 22),

            if (used)
              const DetailInfoBanner(
                icon: Icons.check_circle_outline,
                text: '이미 사용 완료한 기프티콘이에요.',
              ),
            if (!used && g.status == GifticonStatus.expired)
              const DetailInfoBanner(
                icon: Icons.event_busy_outlined,
                text: '만료 처리된 기프티콘이에요.',
              ),
            if (shared && !used)
              const DetailInfoBanner(
                icon: Icons.group_outlined,
                text: '그룹에 공유 중이에요. 사용 완료 처리는 공유 탭에서 해주세요.',
              ),
            // 공유 여부가 아직 확정되지 않아 버튼을 막아 둔 상태. 이유를 적지 않으면
            // 사용자는 버튼이 왜 없는지 알 수 없다(고장으로 읽힌다).
            //
            // **배너는 하나다.** 사용 완료와 기간 연장은 같은 이유로 함께 막히므로
            // (둘 다 공유 여부에 따라 경로가 갈린다) 따로 띄우면 같은 문장이 두 번 뜬다.
            // 대신 무엇이 막혔는지는 상황에 맞게 적는다.
            if (blockedByShareState)
              DetailInfoBanner(
                icon: sharedIdsAsync.hasError
                    ? Icons.error_outline
                    : Icons.hourglass_empty,
                text: sharedIdsAsync.hasError
                    ? '공유 상태를 확인하지 못해 '
                        '$blockedActionLabel${blockedActionLabel.eulReul} '
                        '잠시 막아 뒀어요.'
                    : '공유 상태를 확인하는 중이에요…',
                // 에러일 때 **반드시** 되살릴 길을 준다. 스트림 provider는 스스로
                // 재구독하지 않으므로 화면이 보고 있는 동안 실패한 에러는 캐시된 채
                // 남는다 — 버튼이 없으면 통신이 회복돼도 이 화면에서는 사용 완료가
                // 계속 막힌다(코드리뷰 검출). share 탭의 keepAlive 파생이 같은
                // 인스턴스를 붙잡고 있으면 상세를 나갔다 들어와도 풀리지 않는다.
                onRetry: sharedIdsAsync.hasError
                    ? () => retrySharedGifticonIds(ref)
                    : null,
              ),

            if (canExtend)
              ElevatedButton.icon(
                onPressed: () => _extendExpiry(context, ref, g, now: now),
                icon: const Icon(Icons.event_repeat_outlined, size: 20),
                label: const Text('기프티콘 기간 연장하기'),
                style: actionButtonStyle,
              ),
            // 두 버튼은 함께 뜬다(만료됐고·아직 사용 전이고·공유 중이 아닌 기프티콘이
            // 흔한 경우다). 사이 여백이 없으면 맞닿아 그려지고 오탭도 생긴다.
            if (canExtend && canMarkUsed) const SizedBox(height: 12),
            if (canMarkUsed)
              ElevatedButton.icon(
                onPressed: () => _confirmAndMarkUsed(context, ref, g),
                icon: const Icon(Icons.check, size: 20),
                label: const Text('사용 완료'),
                style: actionButtonStyle,
              ),
          ],
        ),
      ),
    );
  }

  /// 새 만료일 선택 → 계약의 연장 경로 호출.
  ///
  /// **경로가 둘이고, 고르는 기준은 공유 여부다.** 공유 중이면
  /// [ShareRepository.extendSharedExpiry]가 그룹 스냅샷과 원본을 함께 옮기고,
  /// 공유 중이 아니면 [GifticonRepository.extendExpiry]가 원본만 옮긴다. 공유 중인데
  /// 개인 경로를 부르면 스냅샷이 옛 날짜로 남아 그룹 화면과 내 목록이 **같은 기프티콘을
  /// 두고 다른 만료일**을 말한다(계약 dartdoc의 경고).
  ///
  /// **판정은 날짜를 확정한 뒤에 읽는다.** 빌드 시점 값을 클로저에 담아 두면 날짜
  /// 선택기가 열려 있는 동안(모달이라 몇 초에서 몇 분) 공유 상태가 바뀌어도 그대로
  /// 쓰게 되고, 그 창에서 fail-closed 가드가 **fail-open** 한다 — 다른 기기가 그 사이
  /// 그룹에 공유하면 개인 경로가 호출되어 그룹 스냅샷만 옛 날짜로 남는다.
  Future<void> _extendExpiry(
    BuildContext context,
    WidgetRef ref,
    Gifticon g, {
    required DateTime now,
  }) async {
    final ExtendDatePick pick = await pickExtendedExpiryDate(
      context,
      currentExpiry: g.expiryDate,
      now: now,
    );
    if (pick is ExtendDateCancelled || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (pick is ExtendDateUnavailable) {
      // 고를 수 있는 날이 없다 — 선택기를 못 연 이유를 말해 준다. 여기서 조용히
      // 돌아가면 버튼이 먹통인 것과 구별되지 않는다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${formatYmdDot(pick.limit)}까지만 연장할 수 있어요.'),
        ));
      return;
    }
    final DateTime picked = (pick as ExtendDatePicked).date;

    // 공유 판정을 **여기서 다시 읽는다**(위 dartdoc 참조 — 선택기가 열려 있던 창).
    // 확정되지 않았으면 어느 경로도 부르지 않는다: 둘 중 하나를 추측해 부르는 것이
    // 정확히 이 화면이 막으려는 것이다.
    final AsyncValue<SharedGifticon?> fresh =
        ref.read(sharedItemForGifticonProvider(g.id));
    if (!fresh.hasValue) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('공유 상태를 확인하는 중이에요. 잠시 후 다시 시도해 주세요.'),
        ));
      return;
    }
    final SharedGifticon? sharedItem = fresh.value;

    try {
      if (sharedItem != null) {
        await ref
            .read(shareRepositoryProvider)
            .extendSharedExpiry(sharedItem.id, picked);
      } else {
        await ref.read(gifticonRepositoryProvider).extendExpiry(g.id, picked);
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${formatYmdDot(picked)}까지로 연장했어요.'),
        ));
    } on StateError catch (e, st) {
      reportHandledFailure(ref, e, st,
          context: 'GifticonDetailPage.extendExpiry(guard)');
      // 계약 가드에 막혔다 — 화면을 열어 둔 사이 다른 경로가 상태를 옮긴 경우다
      // (그룹에서 누군가 사용 완료했거나, 다른 기기가 먼저 더 뒤로 연장했거나).
      // 다시 눌러도 같은 결과라 재시도를 권하지 않는다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 기간을 연장할 수 없어요.')));
    } catch (e, st) {
      // 사용 완료 경로와 같은 규약 — 로그를 남기고(진짜 결함이 "연결 확인"으로 위장되지
      // 않도록), 문구는 "지금 안 될 뿐"으로 재시도를 권한다. 연장도 트랜잭션이라 오프라인
      // 큐잉이 되지 않는다.
      reportHandledFailure(ref, e, st,
          context: 'GifticonDetailPage.extendExpiry');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('연장하지 못했어요. 연결을 확인하고 다시 시도해 주세요.')),
        );
    }
  }

  /// 사용 완료 확인 → 계약 [GifticonRepository.updateStatus] 호출.
  ///
  /// 되돌릴 수 없는 전이(used는 terminal)라 확인을 한 번 받는다. 버튼 노출 조건이 이미
  /// 걸러 주지만 최종 판정은 저장소 가드다 — 화면을 열어 둔 사이 다른 경로(공유 사용
  /// 동기화)가 먼저 상태를 옮겼을 수 있어, [StateError]를 안내로 바꿔 받는다.
  Future<void> _confirmAndMarkUsed(
    BuildContext context,
    WidgetRef ref,
    Gifticon g,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('사용 완료'),
        content: Text(
          '${g.productName}${g.productName.eulReul} 사용 완료로 바꿀까요?\n'
          '되돌릴 수 없어요.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('사용 완료'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(gifticonRepositoryProvider)
          .updateStatus(g.id, GifticonStatus.used);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('사용 완료로 변경했어요.')));
    } on StateError catch (e, st) {
      reportHandledFailure(ref, e, st,
          context: 'GifticonDetailPage.updateStatus(guard)');
      // 계약 위반(terminal 상태에서의 전이 등) — 다시 눌러도 결과가 같다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 사용 완료할 수 없어요.')));
    } catch (e, st) {
      // **로그를 반드시 남긴다.** 이 catch는 통신 실패를 겨냥한 것이지만 문법상 모든
      // 예외를 삼키므로, 매핑 버그 같은 진짜 결함까지 "연결을 확인하세요"로 위장시킨다.
      // 그때 콘솔에 아무것도 없으면 사용자도 개발자도 둘을 구분할 방법이 없다.
      reportHandledFailure(ref, e, st,
          context: 'GifticonDetailPage.updateStatus');
      // 그 외 실패는 사실상 전부 통신 문제다. `updateStatus`는 Firestore
      // `runTransaction`을 쓰는데 **트랜잭션은 오프라인 큐잉이 안 되므로**, 망이 끊기면
      // `FirebaseException(unavailable)`로 떨어진다 — 지하철·엘리베이터, 그리고 하필
      // 매장 계산대 앞에서 흔한 상황이다.
      //
      // 이걸 안 잡으면 예외가 삼켜진다: 호출부가 `onPressed: () => _confirm…()`이라
      // 반환된 Future가 버려져 unhandled async error가 되고, 화면에는 **아무 일도
      // 일어나지 않는다.** 사용자는 버튼이 먹통이라 여겨 여러 번 누르거나, 반대로
      // 됐으려니 하고 매장을 나선다.
      //
      // StateError와 문구를 나누는 이유: 위는 "이미 끝난 일"(재시도 무의미)이고
      // 이쪽은 "지금 안 될 뿐"(재시도하면 된다)이다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('처리하지 못했어요. 연결을 확인하고 다시 시도해 주세요.')),
        );
    }
  }
}

/// 바코드 카드 — 번호를 실제 스캔 가능한 심볼로 그린다.
///
/// ## 왜 항상 흰 바탕에 검은 바인가
/// 테마 색(`scheme.onSurface` 등)을 쓰면 다크 모드에서 **밝은 바탕에 어두운 바**라는
/// 스캐너의 전제가 뒤집힌다. 화면에서는 멀쩡해 보이는데 매장 리더기가 못 읽는, 확인하기
/// 어려운 실패다. 그래서 이 카드만은 테마를 따르지 않고 흑백을 고정한다.
///
/// ## 왜 Code128인가
/// 국내 기프티콘 바코드는 대부분 Code128이고, 이 심볼은 숫자·영문·기호를 모두 담아
/// 입력값을 가리지 않는다. 그래도 인코딩은 실패할 수 있어([BarcodeWidget.errorBuilder])
/// 번호 텍스트로 떨어진다 — **번호만 보이면 점원이 수동 입력할 수 있으므로** 심볼을 못
/// 그리는 것이 곧 사용 불가는 아니다.
class _BarcodeCard extends StatelessWidget {
  const _BarcodeCard({required this.barcode});

  final String? barcode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? value = barcode?.trim();
    final bool hasValue = value != null && value.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: hasValue ? Colors.white : scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: hasValue
          ? Column(
              children: <Widget>[
                BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: value,
                  height: 96,
                  // 번호는 아래에 **위젯으로** 따로 쓴다. [BarcodeWidget]의 drawText는
                  // 캔버스에 직접 그리는 것이라 스크린리더가 읽지 못하고 복사도 안 된다.
                  // 리더기가 못 읽을 때 번호를 부르거나 수동 입력하는 경로가 이 텍스트다.
                  drawText: false,
                  color: Colors.black,
                  backgroundColor: Colors.white,
                  // 심볼을 못 그려도 번호는 아래에 남으므로, 여기서는 자리만 비운다.
                  errorBuilder: (BuildContext context, String error) =>
                      const SizedBox.shrink(),
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          : Column(
              children: <Widget>[
                Icon(
                  Icons.qr_code_2,
                  size: 72,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  '바코드 번호가 없어요.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}

/// 상태 뱃지 — 라벨·색은 목록 카드와 같은 정본([gifticonStatusLabel])을 쓴다.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final GifticonStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = gifticonStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.badge),
      ),
      child: Text(
        gifticonStatusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
