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
  /// 공유·사용), 여기서 다시 조회해 화면을 바꾸지는 않는다 — 팝업이 스스로 사라지면
  /// 사용자는 자기 탭이 먹힌 줄 알고 다시 누른다. 그 사이의 변화는 저장소가 실패로
  /// 돌려주고 호출부가 안내로 바꿔 받는다.
  ///
  /// ⚠️ **저장소가 막는 축은 셋뿐이다 — 그룹 없음·비멤버·이중 공유.** 두 구현
  /// (`InMemoryShareRepository`·`FirebaseShareRepository`의 `shareGifticon`) 모두 원본
  /// [Gifticon]의 상태는 보지 않으므로, 팝업이 떠 있는 사이 다른 기기가 원본을 '사용
  /// 완료'로 처리해도 공유는 그대로 성공한다(코드리뷰에서 실측). 탭 즉시 공유였을 때도
  /// 있던 창이지만 이 팝업이 사람이 읽는 시간만큼 넓힌다. 닫으려면 계약
  /// `ShareRepository.shareGifticon`에 원본 status 축을 더해야 하고, 그것은 두 구현·보안
  /// 규칙·규칙 검증을 함께 건드리는 별건이다.
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
    final int daysLeft = daysUntilExpiry(g.expiryDate, now: now);
    final bool expired = isExpiredByDate(g.expiryDate, now: now);
    final bool soon = isExpiringSoon(g.expiryDate, now: now);

    final String? barcode = g.barcode?.trim();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      // 라우트 이름 — `scopesRoute`는 `DialogRoute`가 이미 주지만 **이름은 아무도 채우지
      // 않는다**(`AlertDialog`은 title로 채운다). 없으면 스크린리더가 무엇이 열렸는지
      // 알리지 못한 채 포커스만 본문 조각으로 옮겨 간다.
      child: Semantics(
        namesRoute: true,
        // `AlertDialog`과 같은 조합으로 맞춰 둔다. ⚠️ **지금 구조에서는 이 값이 없어도
        // 트리가 같다** — `Semantics`는 `MergeSemantics`가 아니라서 자손이 만든 노드를
        // 삼키지 않는다(코드리뷰가 두 상태의 트리를 덤프해 대조: 동일). 그래도 남기는
        // 이유는 여기에 `MergeSemantics`나 라벨 없는 래퍼가 끼어드는 순간 갈리기
        // 때문이고, 그 갈림은 아래 회귀 테스트가 잡는다.
        explicitChildNodes: true,
        label: '기프티콘 공유 확인',
        child: ConstrainedBox(
          // 태블릿·웹에서 팝업이 화면 너비만큼 늘어나면 상세가 아니라 페이지처럼 읽힌다.
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 스크롤 밖에 고정으로 남기는 것은 **결정 버튼 한 줄뿐**이다(표준
              // `AlertDialog`과 같은 배치). 질문·배너까지 고정으로 두면 세로가 짧은
              // 화면(가로 모드·분할 화면)이나 큰 글꼴에서 고정분이 가용 높이를 넘겨
              // **버튼이 화면 밖으로 나간다** — 배리어 탭으로 닫을 수만 있고 공유는
              // 완료할 수 없는 상태다(720x360dp·글꼴 1.5배·만료 배너에서 위젯 테스트로
              // 28px 오버플로 재현).
              //
              // ⚠️ **그렇다고 배너·질문을 스크롤 아래쪽에 두어도 안 된다.** 첫 화면 밖으로
              // 밀려 사용자가 무엇을 묻는지도 만료 경고도 못 본 채 '예/아니오'만 보게
              // 되는데, 오버플로 예외가 나지 않아 **조용히** 지나간다(실측: 360x640dp
              // 기본 글꼴에서 질문이, 360x800dp 1.5배에서 배너까지 가려졌다). 그래서
              // 질문·부제·배너를 스크롤 **맨 위**에 둔다 — 스크롤 시작 지점이라 어떤
              // 화면 높이에서도 첫 화면에 들어온다.
              //
              // 그 대가로 [DetailInfoBanner]의 "액션 바로 위" 규약에서 벗어난다. 그 규약의
              // 목적은 "버튼이 없거나 눌리지 않는 이유를 그 자리에서 설명"하는 것인데, 여기
              // 배너는 버튼을 막지 않고 **항목**을 경고하므로 인접보다 **보이는 것**이 앞선다.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
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
                      const SizedBox(height: 16),

                      // 만료·임박은 **말로** 알린다. 후보 목록은 상태만 보고 날짜는 보지
                      // 않아(`unsharedGifticonsProvider`) 만료일이 지났거나 코앞인
                      // 기프티콘도 그대로 후보에 뜨는데, 그것을 붉은 글씨 한 줄로만
                      // 암시하면 이 팝업이 막으려던 바로 그 실수(못 쓰는 것을 공유)가
                      // 그대로 통과한다.
                      if (expired)
                        const DetailInfoBanner(
                          icon: Icons.event_busy_outlined,
                          text: '만료일이 지난 기프티콘이에요. 그래도 공유할까요?',
                        )
                      // 임박은 실수가 아니라 정보다 — 캐묻지 않고 남은 기간만 알린다.
                      else if (soon)
                        DetailInfoBanner(
                          icon: Icons.schedule,
                          text: daysLeft == 0
                              ? '오늘 만료되는 기프티콘이에요.'
                              : '만료까지 $daysLeft일 남은 기프티콘이에요.',
                        ),

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

                      // 금액 · 카테고리 · 유효기간 — 상세 화면과 같은 줄. 다만 만료 줄에
                      // 상세가 붙이는 `· D-N` 접미는 없다(`formatDDay`는 main 고유 표현이라
                      // 승격 대상에서 빠져 있다 — `features/main/widgets/format.dart`).
                      // 그 자리는 아래 임박 배너가 문장으로 대신한다.
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
                        emphasize: expired || soon,
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

              // ── 결정 ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant),
                      // 보이는 글자는 '아니오'지만 읽히는 이름에는 무엇에 대한
                      // 아니오인지까지 담는다 — 포커스가 버튼으로 바로 간 사용자에게는
                      // 질문이 들리지 않는다. 보이는 라벨을 접두로 포함해 '라벨 속 이름'
                      // 규칙은 지킨다.
                      child: const Text('아니오', semanticsLabel: '아니오, 공유하지 않기'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('예', semanticsLabel: '예, 공유하기'),
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
