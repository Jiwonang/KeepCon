/// 스캔/추가 페이지 (KeepCon 틀 재디자인).
///
/// 카메라 스캔 / 갤러리 불러오기 / 수동 입력 세 경로를 리치 카드로 제공한다. 세 경로
/// 모두 최종적으로 편집 가능한 [GifticonForm]으로 수렴해 하나의 [Gifticon]을 생성한다.
///
/// 레이아웃(위→아래): 헤더(타이틀 + 알림벨 + 아바타) → 입력 경로 3카드 →
/// AI 안내 배너 → 저장할 그룹 선택 그리드.
///
/// 셸의 중앙 +(FAB)에서 push되는 전체화면이라, 뒤로가기용 투명 AppBar만 두고
/// 큰 타이틀은 홈과 동일하게 본문 헤더로 노출한다.
///
/// 색/폰트/라운드는 전부 `Theme.of(context)`/공유 팔레트 소비. 소스 구분 액센트만
/// 페이지 로컬 [ScanAccents]. AI 배너·그룹 선택은 디자인 스캐폴드(동작은 정적 자리표시).
///
/// route: [AppRoutes.scan].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/routes.dart';
import '../../shared/theme/app_colors.dart';
import 'state/gifticon_form_state.dart';
import 'widgets/gifticon_form.dart';
import 'widgets/scan_tokens.dart';

/// 스캔/추가 진입 화면. 세 입력 경로 선택 → 폼 화면으로 이동.
class ScanPage extends ConsumerWidget {
  const ScanPage({super.key});

  /// route 등록용 상수(계약 [AppRoutes.scan]와 일치).
  static const String routeName = AppRoutes.scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // 큰 타이틀은 본문 헤더로 두고, AppBar는 뒤로가기만 담당(투명).
      appBar: AppBar(toolbarHeight: 44),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ScanHeader(),
              const SizedBox(height: 26),
              _SourceCard(
                icon: Icons.photo_camera_outlined,
                accent: Theme.of(context).colorScheme.primary,
                title: '카메라로 스캔',
                subtitle: '바코드 또는 QR 코드를 스캔해요',
                onTap: () => _openForm(context, ref, ScanSource.camera),
              ),
              const SizedBox(height: 16),
              _SourceCard(
                icon: Icons.image_outlined,
                accent: ScanAccents.gallery,
                title: '갤러리에서 불러오기',
                subtitle: '저장된 이미지에서 불러와요',
                onTap: () => _openForm(context, ref, ScanSource.gallery),
              ),
              const SizedBox(height: 16),
              _SourceCard(
                icon: Icons.edit_outlined,
                accent: ScanAccents.manual,
                title: '직접 입력',
                subtitle: '코드 번호를 직접 입력해요',
                onTap: () => _openForm(context, ref, ScanSource.manual),
              ),
              const SizedBox(height: 16),
              const _AiBanner(),
              const SizedBox(height: 26),
              const _GroupSelector(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    ScanSource source,
  ) async {
    // 폼 컨트롤러를 선택 경로로 초기화한다.
    ref.read(gifticonFormControllerProvider.notifier).startWith(source);

    // 카메라/갤러리 경로: 실제 플러그인 연동은 후속 작업.
    // TODO(scan): image_picker/camera + 바코드·OCR 플러그인으로 이미지 획득 후
    //   prefillFromRecognition(...)로 인식 결과를 폼에 채운다. 인식 실패 필드는
    //   비워 두어 사용자가 수동 편집으로 폴백하도록 한다(현재 구조가 이미 폴백).
    if (source != ScanSource.manual) {
      _showPlaceholderNotice(context, source);
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _GifticonFormScreen(),
      ),
    );
  }

  void _showPlaceholderNotice(BuildContext context, ScanSource source) {
    final name = source == ScanSource.camera ? '카메라' : '갤러리';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name 인식은 준비 중입니다. 아래 폼에서 직접 입력/수정하세요.'),
      ),
    );
  }
}

// ─────────────────────────── 헤더 ───────────────────────────

/// 상단 헤더 — 큰 타이틀 + 알림벨 + 아바타(홈과 동일 톤). 벨/아바타는 정적 자리표시.
class _ScanHeader extends StatelessWidget {
  const _ScanHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // 아바타 원은 홈과 동일하게 darkSurface(어두운 강조면) 토큰을 소비 —
    // scheme.onSurface는 다크 모드에서 밝은색이라 원이 뒤집힌다.
    final Color darkSurface = theme.brightness == Brightness.dark
        ? AppColorsDark.darkSurface
        : AppColorsLight.darkSurface;

    return Row(
      children: [
        Expanded(
          child: Text(
            '기프티콘 추가',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
        // 알림 벨 + 초록 뱃지 점.
        SizedBox(
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
        ),
        const SizedBox(width: 10),
        // 아바타(다크서피스 배경, 이니셜) — 정적.
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: darkSurface,
            shape: BoxShape.circle,
          ),
          child: const Text(
            'K',
            style: TextStyle(
              color: AppColorsCommon.onDark,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── 입력 경로 리치 카드 ───────────────────────

/// 입력 경로 한 장 — 좌 액센트 아이콘 타일 + 제목·부제 + 우 셰브론.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: scheme.onSurface.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 액센트 아이콘 타일.
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: ScanAccents.tileTintAlpha),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── AI 안내 배너 (정적) ───────────────────────

/// 이미지 자동 인식 안내 배너 — 연한 brand 틴트. 동작은 정적 자리표시.
class _AiBanner extends StatelessWidget {
  const _AiBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: scheme.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '이미지에서 브랜드와 만료일을\n자동으로 정리해요',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

// ─────────────────────── 저장할 그룹 선택 (정적 스캐폴드) ───────────────────────

/// 저장 대상 그룹 선택 그리드. 현재는 로컬 선택 상태만 가진 디자인 스캐폴드.
///
/// TODO(scan): 실제 그룹 연동 — 공유 계약 ShareRepository.watchGroups(...)로
///   사용자의 그룹을 로드해 타일을 구성하고, 선택 그룹을 폼 저장 대상으로 전달한다.
///   (지금은 홈의 검색/필터처럼 정적 자리표시.)
class _GroupSelector extends StatefulWidget {
  const _GroupSelector();

  @override
  State<_GroupSelector> createState() => _GroupSelectorState();
}

class _GroupSelectorState extends State<_GroupSelector> {
  int _selected = 0;

  static const List<_GroupTileData> _groups = <_GroupTileData>[
    _GroupTileData(icon: Icons.account_balance_wallet_outlined, label: '내 지갑'),
    _GroupTileData(emoji: '🏡', label: '가족'),
    _GroupTileData(emoji: '👬', label: '친구 모임'),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '저장할 그룹 선택',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (int i = 0; i < _groups.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: _GroupTile(
                  data: _groups[i],
                  selected: i == _selected,
                  onTap: () => setState(() => _selected = i),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 그룹 타일의 표시 데이터(아이콘 또는 이모지 + 라벨).
class _GroupTileData {
  const _GroupTileData({this.icon, this.emoji, required this.label})
      : assert(icon != null || emoji != null, 'icon 또는 emoji 중 하나는 필요');

  final IconData? icon;
  final String? emoji;
  final String label;
}

/// 그룹 선택 타일 한 칸. 선택 시 brand 테두리·전경.
class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _GroupTileData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color fg = selected ? scheme.primary : scheme.onSurface;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outline.withValues(alpha: 0.25),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 34,
                child: Center(
                  child: data.icon != null
                      ? Icon(data.icon, color: fg, size: 32)
                      : Text(data.emoji!,
                          style: const TextStyle(fontSize: 30, height: 1)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 폼 화면. 세 경로 공통으로 이 화면에서 [Gifticon]을 완성해 저장한다.
class _GifticonFormScreen extends ConsumerWidget {
  const _GifticonFormScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(
      gifticonFormControllerProvider.select((s) => s.source),
    );
    final title = switch (source) {
      ScanSource.camera => '카메라 스캔 결과 확인',
      ScanSource.gallery => '갤러리 인식 결과 확인',
      ScanSource.manual => '기프티콘 직접 입력',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const GifticonForm(),
    );
  }
}
