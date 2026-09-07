/// KeepCon 공유 계약 — 기프티콘 상세 화면 공용 위젯 (단일 정본 / SSOT).
///
/// 개인 기프티콘 상세(`lib/features/main/pages/gifticon_detail_page.dart`)와 공유 기프티콘
/// 상세(`lib/features/share/pages/shared_gifticon_detail_page.dart`)는 **같은 상세 화면
/// 언어**를 쓴다 — 같은 히어로·같은 메타 줄·같은 배너를 쓴다. 다만 **배치는 화면 종류를
/// 따른다**: 전체 화면 상세 두 곳은 히어로가 위·배너가 액션 바로 위지만, 공유 확인 팝업은
/// 뷰포트가 좁아 그 순서를 쓰지 못한다(아래 [DetailInfoBanner] 규약의 예외 참조).
/// 두 페이지가 각자 사본을 두면 한쪽만 손볼 때 조용히 갈라진다(승격 전 실제로 세 클래스가
/// 바이트 단위로 같은 복사본이었고, `tool/check_ssot.sh`는 private 위젯 복제를 잡지 못해
/// CI도 통과했다 — 코드리뷰에서 검출).
///
/// 세 번째 소비자는 공유 확인 팝업(`lib/features/share/widgets/share_gifticon_confirm_dialog.dart`)
/// 이다 — 공유 직전 "이 기프티콘이 맞는지" 대조받는 자리라, 사용자가 메인에서 본 상세와
/// **같은 모양**이어야 대조가 성립한다.
///
/// 시각 값(높이·노치 크기·라운드)은 승격 전 목업 값을 **그대로 보존**한다(픽셀 무변경).
library;

import 'package:flutter/material.dart';

import '../theme/brand_palette.dart';
import '../theme/theme_tokens.dart';

/// 브랜드 히어로 — 브랜드 색 쿠폰 배너(좌우 티켓 노치 + 중앙 로고 자리 + 우상단 브랜드명).
class BrandHero extends StatelessWidget {
  const BrandHero({super.key, required this.brand, required this.brandName});

  /// 브랜드 색·라벨. 정본은 [BrandPalette].
  final BrandStyle brand;

  /// 우상단에 적는 브랜드명 원문.
  final String brandName;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const double height = 180;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.hero),
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: brand.background)),
            // 좌우 티켓 노치(배경색 원이 가장자리를 파고든다).
            Positioned(
              left: -11,
              top: height / 2 - 11,
              child: _Notch(color: scheme.surface),
            ),
            Positioned(
              right: -11,
              top: height / 2 - 11,
              child: _Notch(color: scheme.surface),
            ),
            Positioned(
              top: 20,
              right: 24,
              child: Text(
                brandName,
                style: TextStyle(
                  color: brand.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Center(
              child: Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brand.foreground.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  brand.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: brand.background,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 티켓 노치(작은 원). [BrandHero] 전용이라 공개하지 않는다.
class _Notch extends StatelessWidget {
  const _Notch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 상세 화면 상태 안내 배너(잠김·사용완료·만료·공유중 등).
///
/// 액션 버튼 **바로 위**에 놓는 것이 규약이다 — 버튼이 없거나 눌리지 않는 이유를 그 자리에서
/// 설명해야 사용자가 고장으로 읽지 않는다.
///
/// **예외 — 배너가 버튼이 아니라 항목을 경고할 때.** 공유 확인 팝업
/// (`features/share/widgets/share_gifticon_confirm_dialog.dart`)의 만료·임박 배너가 그렇다.
/// 버튼을 막지 않으므로 인접보다 **첫 화면 가시성**이 앞서고, 팝업의 스크롤 영역이 좁아
/// 액션 옆에 두면 짧은 화면에서 통째로 가려진다(실측: 360x640dp 기본 글꼴에서 미노출).
/// 예외를 여기 적어 두는 이유는 호출부 주석에만 두면 다음 사람이 ①이탈을 규약 위반으로
/// 읽고 되돌리거나 ②이 정본만 읽고 새 소비자에 잘못 적용하기 때문이다.
class DetailInfoBanner extends StatelessWidget {
  const DetailInfoBanner({
    super.key,
    required this.icon,
    required this.text,
    this.onRetry,
  });

  final IconData icon;
  final String text;

  /// 재시도 콜백. null이면 버튼을 그리지 않는다.
  ///
  /// **실패를 알리는 배너에는 반드시 넘길 것.** 이 앱의 스트림 provider들은 스스로
  /// 재구독하지 않으므로, 소비자(화면·keepAlive 파생)가 붙잡고 있는 동안 캐시된 에러는
  /// 그대로다 — 되살릴 버튼이 없으면 통신이 회복돼도 그 화면에서는 막힌 상태가
  /// 유지된다. 자동 재시도는 금지(#13 — 장애 중 retry storm).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          if (onRetry != null) ...<Widget>[
            const SizedBox(width: 8),
            // 탭 영역을 줄이지 않는다(`minimumSize: Size.zero` + `shrinkWrap` 금지).
            // 이 버튼은 fail-closed 가드를 푸는 **유일한 경로**라, 누르기 어려우면
            // 사용자는 화면이 고장났다고 읽는다. 기본값이 Material 권장 48dp를 만족하므로
            // 좌우 여백만 조정하고 나머지는 건드리지 않는다.
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 상세 화면 메타 한 줄 — 아이콘 + 텍스트(금액·카테고리·유효기간·바코드 번호).
///
/// 개인 상세(`main`)와 공유 확인 팝업(`share`)이 **같은 줄 언어**를 써야 한다. 확인 팝업의
/// 역할이 "메인에서 본 그 기프티콘이 맞는지" 대조하는 것이라, 두 화면이 같은 값을 다른
/// 모양으로 적으면 대조가 성립하지 않는다. 그래서 사본을 두지 않고 이 정본을 소비한다
/// (승격 전에는 `main` 상세의 private `_MetaRow`였고, 두 번째 소비자가 실제로 생긴
/// 시점에 승격했다 — CLAUDE.md 승격 규칙 ③ "늦게 승격").
class GifticonMetaRow extends StatelessWidget {
  const GifticonMetaRow({
    super.key,
    required this.icon,
    required this.text,
    this.emphasize = false,
  });

  final IconData icon;
  final String text;

  /// 만료 임박/경과를 error 색으로 강조할지.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color color = emphasize ? scheme.error : scheme.onSurfaceVariant;

    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
