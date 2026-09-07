/// share 페이지 — 기프티콘을 그룹에 공유하기 전 **상세를 보여주고 받는 확인 팝업**.
///
/// ## 왜 한 단계를 더 두는가
/// 공유 시트의 후보 타일은 상품명 한 줄과 `브랜드 · ~만료일` 한 줄이 전부라, 같은 브랜드
/// 기프티콘을 여러 장 가진 사용자에게는 **어느 것을 골랐는지 타일만으로 구분되지 않는다.**
/// 그런데 탭 한 번이 곧바로 쓰기였다 — 잘못 눌러도 되돌릴 여지가 없었다.
///
/// 잘못 고른 대가가 작지 않다. 공유하는 순간 ① 그룹 멤버 누구나 그 기프티콘을 쓸 수 있고
/// (찜·사용이 곧바로 가능하다) ② 원본은 다른 그룹의 공유 후보에서 빠지며
/// (`unsharedGifticonsProvider`) ③ 되돌리려면 공유 취소라는 **다른 화면의 다른 경로**를
/// 타야 하는데, 그 사이 다른 멤버가 이미 사용했다면 되돌릴 방법 자체가 없다.
///
/// 그래서 누른 기프티콘의 상세를 그대로 펼쳐 보이고 예/아니오를 받는다.
///
/// ## 왜 상세 화면과 같은 위젯을 쓰는가
/// 이 팝업의 역할은 "메인에서 보던 그 기프티콘이 맞는지" 대조받는 것이다. 대조는 두 화면이
/// **같은 모양으로 같은 값을 적을 때만** 성립하므로, 표현을 새로 짜지 않고 상세 화면 정본
/// 위젯([BrandHero]·[GifticonMetaRow])과 포맷 정본(`formatWon`·`formatYmdDot`)을 그대로
/// 소비한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/providers/now_provider.dart';
import '../../../shared/theme/brand_palette.dart';
import '../../../shared/theme/theme_tokens.dart';
import '../../../shared/util/date_format.dart' show formatYmdDot;
import '../../../shared/util/expiry_policy.dart';
import '../../../shared/util/money_format.dart' show formatWon;
import '../../../shared/widgets/gifticon_detail_widgets.dart';

/// [gifticon]의 상세를 팝업으로 보여주고 공유 여부를 받는다.
///
/// 반환값이 `true`일 때만 공유를 진행한다. 바깥 탭·뒤로가기로 닫혀 결과가 없는 경우
/// (`null`)는 **'아니오'와 같게 읽는다** — 공유는 되돌리기 비용이 큰 쓰기라, 불확실한
/// 닫힘을 승인으로 해석하지 않는다(fail-closed).
Future<bool> showShareGifticonConfirmDialog(
  BuildContext context,
  Gifticon gifticon,
) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) =>
        _ShareGifticonConfirmDialog(gifticon: gifticon),
  );
  return ok ?? false;
}

class _ShareGifticonConfirmDialog extends ConsumerWidget {
  const _ShareGifticonConfirmDialog({required this.gifticon});

  /// 확인 대상. 공유 시트가 목록에서 건네준 **스냅샷**이다.
  ///
  /// 팝업이 떠 있는 동안 이 기프티콘이 후보 자격을 잃을 수 있지만(다른 기기에서 먼저
  /// 공유·사용), 여기서 다시 조회해 화면을 바꾸지는 않는다 — 최종 판정은 저장소
  /// 가드([ShareRepository.shareGifticon]의 [StateError])이고 호출부가 그 실패를 안내로
  /// 바꿔 받는다. 팝업이 스스로 사라지면 사용자는 자기 탭이 먹힌 줄 알고 다시 누른다.
  final Gifticon gifticon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Gifticon g = gifticon;
    final BrandStyle brand = BrandPalette.of(g.brand);

    // 시각은 [nowProvider] 정본에서 받는다 — 상세 화면과 같은 규약이다. 여기서 따로
    // [DateTime.now]를 읽으면 자정 근처에서 목록·상세·이 팝업이 서로 다른 "오늘"로
    // 만료를 판정한다.
    final DateTime now = ref.watch(nowProvider);
    final bool expired = isExpiredByDate(g.expiryDate, now: now);
    final bool expiryEmphasis =
        expired || isExpiringSoon(g.expiryDate, now: now);

    final String? barcode = g.barcode?.trim();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      // 라우트 이름 — `AlertDialog`와 달리 맨 [Dialog]은 이것을 채우지 않는다. 없으면
      // 스크린리더가 "팝업이 열렸다"를 알리지 못한 채 포커스만 본문 조각으로 옮겨 간다.
      child: Semantics(
        namesRoute: true,
        label: '기프티콘 공유 확인',
        child: ConstrainedBox(
          // 태블릿·웹에서 팝업이 화면 너비만큼 늘어나면 상세가 아니라 페이지처럼 읽힌다.
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 상세 본문. 작은 화면·큰 글꼴에서도 질문과 버튼이 잘리지 않도록 본문만
              // 스크롤시킨다(`Flexible` + 스크롤뷰) — 팝업 전체를 스크롤시키면 결정
              // 버튼이 화면 밖으로 밀려 "닫을 수도 확인할 수도 없는" 상태가 된다.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      BrandHero(brand: brand, brandName: g.brand),
                      const SizedBox(height: 22),

                      // 브랜드 · 상품명.
                      Text(
                        g.brand,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(g.productName, style: context.heroProductStyle),
                      const SizedBox(height: 14),

                      // 금액 · 카테고리 · 유효기간 — 상세 화면과 같은 줄·같은 포맷.
                      GifticonMetaRow(
                        icon: Icons.account_balance_wallet_outlined,
                        text: g.price > 0 ? '${formatWon(g.price)}원' : '금액 미입력',
                      ),
                      const SizedBox(height: 8),
                      GifticonMetaRow(
                          icon: Icons.sell_outlined, text: g.category),
                      const SizedBox(height: 8),
                      GifticonMetaRow(
                        icon: Icons.schedule,
                        emphasize: expiryEmphasis,
                        text: '${formatYmdDot(g.expiryDate)} 만료',
                      ),
                      // 바코드 번호는 **같은 브랜드·같은 상품 두 장**을 가르는 마지막
                      // 단서라, 있으면 반드시 보여준다(없으면 줄 자체를 두지 않는다 —
                      // "번호 없음"은 대조에 아무 도움이 안 되면서 자리만 먹는다).
                      if (barcode != null && barcode.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        GifticonMetaRow(icon: Icons.qr_code_2, text: barcode),
                      ],
                    ],
                  ),
                ),
              ),

              // ── 질문 + 결정 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // 만료는 **말로** 알린다. 후보 목록은 상태만 보고 날짜는 보지 않아
                    // (`unsharedGifticonsProvider`) 만료일이 지난 기프티콘도 그대로 후보에
                    // 뜨는데, 그것을 붉은 글씨 한 줄로만 암시하면 이 팝업이 막으려던 바로 그
                    // 실수(못 쓰는 것을 공유)가 그대로 통과한다. 배너는 결정 버튼 바로 위에
                    // 둔다([DetailInfoBanner] 규약).
                    if (expired)
                      const DetailInfoBanner(
                        icon: Icons.event_busy_outlined,
                        text: '만료일이 지난 기프티콘이에요. 그래도 공유할까요?',
                      ),
                    Text(
                      '이 기프티콘을 공유할까요?',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '공유하면 그룹 멤버 누구나 사용할 수 있어요.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant),
                          child: const Text('아니오'),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('예'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
