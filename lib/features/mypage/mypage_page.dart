/// 마이(설정) 페이지 — currentUser 연동 + 실제 로그아웃.
///
/// 프로필(이름/이메일)은 [AuthRepository.currentUser]를 반영한다(하드코딩 제거).
/// 로그아웃은 [AuthRepository.signOut] 호출 후 이전 스택을 모두 제거하고
/// [LoginPage]로 이동한다.
///
/// 다크 모드 스위치도 **실제 동작**한다 — 공유 계약 [themeModeProvider]를 소비:
/// - 현재값: `ref.watch(themeModeProvider)` (== [ThemeMode.dark] 여부)
/// - 토글  : `ref.read(themeModeProvider.notifier).setDark(bool)`
/// 페이지 내부에 ThemeMode 상태를 재선언하지 않는다(설정 SSOT와 갈라짐 방지).
///
/// 레이아웃(위→아래): 헤더(타이틀 + 알림벨) → 프로필 카드 → 설정 그룹 카드
/// (알림·계정·다크모드·사용이력·설정) → 로그아웃 카드.
/// 색/폰트/라운드는 `Theme.of(context)` 소비. 하드코딩 색 없음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/user.dart';
import '../../shared/providers/repositories.dart';
import '../../shared/providers/theme_mode_provider.dart';
import '../../shared/theme/theme_tokens.dart';
import '../auth/login_page.dart';

/// 마이 페이지 전용 currentUser 관찰 provider. `main`의 `currentUserProvider`,
/// `share`의 `shareCurrentUserProvider`와 동일 패턴(각 feature가 SSOT
/// [authRepositoryProvider]를 얇게 wrap) — SSOT provider 자체를 재선언하지 않는다.
final StreamProvider<User?> mypageCurrentUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).watchCurrentUser(),
);

/// 마이(설정) 화면. themeModeProvider/currentUser 소비를 위해 [ConsumerWidget].
class MyPage extends ConsumerWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ThemeMode mode = ref.watch(themeModeProvider);
    final bool isDark = mode == ThemeMode.dark;
    final User? user = ref.watch(mypageCurrentUserProvider).valueOrNull;
    final String displayName = user?.displayName ?? '로그인 필요';
    final String displayEmail = user?.email ?? '';
    final String initial = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : '?';

    return Scaffold(
      // 큰 타이틀은 본문 헤더로 두고, AppBar는 뒤로가기만 담당(투명).
      appBar: AppBar(toolbarHeight: 44),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: <Widget>[
            // ── 헤더 ──
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('마이', style: context.pageHeaderStyle),
                ),
                _BellIcon(),
              ],
            ),
            const SizedBox(height: 24),

            // ── 프로필 카드 ──
            _CardShell(
              onTap: () => _placeholder(context, '프로필 편집'),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          displayName,
                          style: context.navTitleStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(displayEmail, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── 설정 그룹 카드 ──
            _CardShell(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  _SettingsRow(
                    icon: Icons.notifications_none,
                    showDot: true,
                    title: '알림 설정',
                    onTap: () => _placeholder(context, '알림 설정'),
                  ),
                  const _RowDivider(),
                  _SettingsRow(
                    icon: Icons.manage_accounts_outlined,
                    title: '계정 관리',
                    onTap: () => _placeholder(context, '계정 관리'),
                  ),
                  const _RowDivider(),
                  // 다크 모드 — 실제 동작하는 유일한 기능.
                  _SettingsRow(
                    icon: Icons.dark_mode_outlined,
                    title: '다크 모드',
                    subtitle: '앱 전체 테마를 어둡게 전환합니다',
                    onTap: () =>
                        ref.read(themeModeProvider.notifier).setDark(!isDark),
                    trailing: Switch(
                      value: isDark,
                      onChanged: (bool v) =>
                          ref.read(themeModeProvider.notifier).setDark(v),
                    ),
                  ),
                  const _RowDivider(),
                  _SettingsRow(
                    icon: Icons.history,
                    title: '사용 이력',
                    // TODO(mypage): 공유 사용 이력(UsageLogPage) 연동 검토.
                    onTap: () => _placeholder(context, '사용 이력'),
                  ),
                  const _RowDivider(),
                  _SettingsRow(
                    icon: Icons.settings_outlined,
                    title: '설정',
                    onTap: () => _placeholder(context, '설정'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── 로그아웃 카드 ──
            _CardShell(
              onTap: () => _signOut(context, ref),
              child: Row(
                children: <Widget>[
                  Icon(Icons.logout, color: scheme.error, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '로그아웃',
                      style:
                          context.itemTitleStyle?.copyWith(color: scheme.error),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _placeholder(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 은(는) 준비 중입니다.')),
    );
  }

  /// [AuthRepository.signOut] 연동 — 세션 종료 후 이전 스택을 모두 제거하고
  /// [LoginPage]로 이동한다.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }
}

/// 알림 벨 아이콘 + 초록 뱃지 점(정적).
class _BellIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(Icons.notifications_none, color: scheme.onSurface),
          Positioned(
            top: 8,
            right: 8,
            child: _GreenDot(border: scheme.surface),
          ),
        ],
      ),
    );
  }
}

/// 초록 뱃지 점(서피스 테두리).
class _GreenDot extends StatelessWidget {
  const _GreenDot({required this.border});

  final Color border;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
    );
  }
}

/// 보더 + 소프트 섀도 카드 껍데기. onTap이 있으면 InkWell로 감싼다.
class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(AppRadii.card);

    return Material(
      color: scheme.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: AppDecorations.softCard(scheme),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 설정 그룹 카드 내부 구분선(좌우 인셋).
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 20,
      endIndent: 20,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
    );
  }
}

/// 설정 항목 한 줄. 아이콘 + 제목(+부제) + 트레일링(기본 셰브론).
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.showDot = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? trailing;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(icon, size: 24, color: scheme.onSurface),
                  if (showDot)
                    Positioned(
                      top: -1,
                      right: -1,
                      child: _GreenDot(border: scheme.surface),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ??
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
