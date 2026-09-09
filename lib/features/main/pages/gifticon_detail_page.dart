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
import '../../../shared/providers/repositories.dart';
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
// 연장 피커의 상한은 scan의 등록 피커와 같은 정본을 소비한다(재사용 우선 —
// 값을 여기 다시 적으면 두 피커의 상한이 조용히 갈라진다). 소비자가 둘이 된
// 시점이므로 lib/shared 승격 대상이다 — contract-architect 요청은 PR에 기록.
import '../../scan/util/expiry_date_range.dart' show expirySelectableTo;
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

    // 기간 연장 버튼 노출 조건.
    //
    // ① 만료로 보이는 것에만 — 계약의 목적이 "만료돼 못 쓰게 된 것을 되살리는 경로"다
    //    (저장된 expired든 날짜상 만료든. 만료 전 연장도 계약 가드는 허용하지만, 그
    //    확장은 실사용 요구가 확인되면 그때 연다 — 버튼이 늘 떠 있으면 주 동선인
    //    바코드 제시를 밀어낸다).
    // ② used 제외 — 계약 가드가 StateError로 거부한다(이미 쓴 것은 기간을 늘려도
    //    쓸 수 없다).
    // ③ 공유 가드는 사용 완료와 동일(확정 전 fail-closed + 공유 중 차단) — 계약이
    //    "공유 중인 기프티콘에 직접 부르지 마라"고 못박는다(스냅샷이 안 따라온다).
    //    공유본의 연장 경로(extendSharedExpiry)는 그룹 상세 몫이라 여기서는 열지
    //    않고, 안내도 하지 않는다 — 그 화면의 버튼은 아직 후속 PR이라, 있지도 않은
    //    경로를 가리키면 틀린 안내가 된다.
    final bool canExtend = !used &&
        (g.status == GifticonStatus.expired || expiredByDate) &&
        sharedIds != null &&
        !shared;

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
            if (!used &&
                g.status == GifticonStatus.available &&
                sharedIds == null)
              DetailInfoBanner(
                icon: sharedIdsAsync.hasError
                    ? Icons.error_outline
                    : Icons.hourglass_empty,
                text: sharedIdsAsync.hasError
                    ? '공유 상태를 확인하지 못해 사용 완료를 잠시 막아 뒀어요.'
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

            if (canMarkUsed)
              ElevatedButton.icon(
                onPressed: () => _confirmAndMarkUsed(context, ref, g),
                icon: const Icon(Icons.check, size: 20),
                label: const Text('사용 완료'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

            // 날짜상 만료인데 아직 available이면 두 버튼이 공존한다 — 위(사용 완료)는
            // 정리, 아래(연장)는 되살리기. 저장된 expired에는 연장만 남는다.
            if (canExtend) ...<Widget>[
              if (canMarkUsed) const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _pickAndExtendExpiry(context, ref, g),
                icon: const Icon(Icons.event_repeat, size: 20),
                label: const Text('기프티콘 기간 연장하기'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  /// 새 만료일 선택 → 확인 → 계약 [GifticonRepository.extendExpiry] 호출.
  ///
  /// 실제 연장은 브랜드사가 해 주는 것이고 이 화면은 그 결과를 기록한다(계약 doc).
  /// 확인을 한 번 받는 이유: 계약이 만료일을 **뒤로만** 옮기므로, 잘못 고른 날짜를
  /// 앞당겨 되돌릴 수 없다 — 사용 완료의 "되돌릴 수 없어요"와 같은 계열이다.
  Future<void> _pickAndExtendExpiry(
    BuildContext context,
    WidgetRef ref,
    Gifticon g,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // 시각은 정본에서 — 여기서 DateTime.now()를 직접 읽으면 자정 경계에서 이
    // 화면의 D-day 판정과 피커 시작 위치가 서로 다른 "오늘"을 본다.
    final DateTime today = DateUtils.dateOnly(ref.read(nowProvider));
    // 계약 하한 — 현재 만료일의 **다음 달력일**부터가 연장이다(판정 정본
    // [isLaterExpiryDate]가 달력 일 단위라, 같은 날은 연장이 아니다).
    final DateTime contractFloor =
        DateUtils.addDaysToDate(DateUtils.dateOnly(g.expiryDate), 1);
    // 화면 하한은 계약 하한과 **오늘** 중 나중 — 오늘 이전 날짜를 고르면 계약
    // 가드는 통과하지만 여전히 날짜상 만료라, "연장했어요" 안내가 사용자가
    // 얻지 못한 상태(되살아남)를 주장하게 된다(에이전트 리뷰 검출). 버튼이
    // 만료 건에만 열리므로 대부분 오늘이 이기고, 저장된 expired인데 만료일이
    // 미래인 건에서만 계약 하한이 이긴다.
    final DateTime firstDate =
        today.isAfter(contractFloor) ? today : contractFloor;

    // 만료일이 이미 선택 상한이면 피커를 열 수 없다 — [showDatePicker]는
    // initialDate가 범위 밖이면 assert로 죽는다(scan 등록 상한까지 등록된
    // 기프티콘에서 실제로 도달 가능한 상태다).
    if (firstDate.isAfter(expirySelectableTo)) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('더 연장할 수 있는 날짜가 없어요.')),
        );
      return;
    }

    // 위 가드가 firstDate ≤ 상한을 보장하므로 시작 위치는 하한 그대로다.
    final DateTime initialDate = firstDate;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: expirySelectableTo,
    );
    if (picked == null || !context.mounted) return;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('기간 연장'),
        content: Text(
          '유효기간을 ${formatYmdDot(picked)}까지로 연장할까요?\n'
          '연장한 날짜를 앞당길 수는 없어요.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('연장하기'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(gifticonRepositoryProvider).extendExpiry(g.id, picked);
      // 화면 갱신은 저장소 스트림이 한다 — 이 페이지가 gifticonByIdProvider를
      // watch하므로 만료일·상태 뱃지(expired → available)가 함께 따라온다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('유효기간을 ${formatYmdDot(picked)}까지로 연장했어요.')),
        );
    } on StateError catch (e, st) {
      reportHandledFailure(ref, e, st,
          context: 'GifticonDetailPage.extendExpiry(guard)');
      // 계약 가드 위반(이미 사용 완료·앞당기기 등) — 화면을 열어 둔 사이 다른
      // 경로가 상태를 옮겼을 수 있다. 다시 눌러도 결과가 같다.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('지금은 연장할 수 없어요.')));
    } catch (e, st) {
      // 사용 완료 핸들러와 같은 이유의 광역 캐치 — 통신 실패를 침묵시키지 않되
      // 진짜 결함도 로그에 남긴다(위 [_confirmAndMarkUsed] 주석 참조).
      reportHandledFailure(ref, e, st,
          context: 'GifticonDetailPage.extendExpiry');
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
