/// 마이(설정) 페이지 — KeepCon 틀 재디자인.
///
/// 프로필(이름·이메일·이니셜)은 [mypageCurrentUserProvider](세션 스트림)를 반응형으로
/// 표시하고, 로그아웃은 [AuthRepository.signOut]으로 세션을 종료해 `AuthGate`가
/// 로그인 화면으로 전환한다.
///
/// **실동작 항목**:
/// - 프로필 편집(프로필 카드 탭): [AuthRepository.updateDisplayName]으로 표시 이름 변경
/// - 계정 관리: [AuthRepository.deleteAccount] — 비밀번호 재확인 후 계정 삭제
/// - 다크 모드 토글, 로그아웃
/// 알림 설정·사용 이력·설정 항목은 자리표시(준비 중).
///
/// 다크 모드 스위치는 공유 계약 [themeModeProvider]를 소비한다:
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
import '../../shared/repositories/auth_repository.dart';
import '../../shared/theme/theme_tokens.dart';
import '../auth/auth_error_message.dart';

/// 마이페이지용 현재 사용자 스트림. SSOT [authRepositoryProvider]를 구독한다.
/// (main의 `currentUserProvider`, share의 `shareCurrentUserProvider`와 동일 패턴 —
/// 각 feature가 자기 래퍼를 선언하고 저장소 provider는 계약 정본을 소비한다.)
final mypageCurrentUserProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// 마이(설정) 화면. themeModeProvider 소비를 위해 [ConsumerWidget].
class MyPage extends ConsumerWidget {
  const MyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ThemeMode mode = ref.watch(themeModeProvider);
    final bool isDark = mode == ThemeMode.dark;

    // 현재 세션 사용자를 반응형으로 표시(로그인 상태에서만 진입) —
    // updateDisplayName 등 프로필 갱신 방출 시 자동 리빌드된다.
    // (스트림 첫 방출 전 첫 프레임은 동기 접근점으로 폴백해 깜빡임을 막는다.)
    final User? user = ref.watch(mypageCurrentUserProvider).valueOrNull ??
        ref.read(authRepositoryProvider).currentUser;
    final String name =
        (user?.displayName.isNotEmpty ?? false) ? user!.displayName : 'KeepCon';
    final String email = user?.email ?? '';
    final String initial =
        name.isNotEmpty ? name.characters.first.toUpperCase() : 'K';

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
              onTap:
                  user == null ? null : () => _editProfile(context, ref, user),
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
                          name,
                          style: context.navTitleStyle,
                        ),
                        const SizedBox(height: 4),
                        Text(email, style: theme.textTheme.bodySmall),
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
                    onTap: () => _manageAccount(context, ref),
                  ),
                  const _RowDivider(),
                  // 다크 모드 토글.
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
              onTap: () async {
                // 세션 종료 → AuthGate가 로그인 화면으로 전환. 위에 쌓인 화면(마이 등)을
                // 정리해 홈(게이트)으로 돌려보낸다. (context 교차 방지: navigator 선캡처.)
                final NavigatorState navigator = Navigator.of(context);
                await ref.read(authRepositoryProvider).signOut();
                navigator.popUntil((Route<dynamic> r) => r.isFirst);
              },
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

  /// 프로필 편집 — 표시 이름을 다이얼로그로 받아
  /// [AuthRepository.updateDisplayName]을 호출한다.
  ///
  /// 성공 시 [mypageCurrentUserProvider]가 갱신된 사용자를 방출해 카드가
  /// 자동으로 새 이름을 표시한다. 실패([AuthException])는 스낵바로 안내한다.
  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) async {
    final String? submitted = await showDialog<String>(
      context: context,
      builder: (_) => _EditNameDialog(initialName: user.displayName),
    );

    if (submitted == null) return; // 취소.
    final String name = submitted.trim();
    if (!context.mounted) return;
    if (name.isEmpty) {
      _snack(context, '이름을 입력해 주세요.');
      return;
    }
    if (name == user.displayName) return; // 변경 없음.

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .updateDisplayName(displayName: name);
      messenger.showSnackBar(
        const SnackBar(content: Text('표시 이름을 변경했어요.')),
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
    }
  }

  /// 계정 관리 — 비밀번호 재확인 후 [AuthRepository.deleteAccount]를 호출한다.
  ///
  /// 성공 시 세션이 종료되어 `AuthGate`가 로그인 화면으로 전환하므로, 위에 쌓인
  /// 화면(마이 등)을 정리해 홈(게이트)으로 돌려보낸다(로그아웃 카드와 동일 패턴).
  Future<void> _manageAccount(BuildContext context, WidgetRef ref) async {
    final String? password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (password == null || password.isEmpty) return; // 취소/미입력.
    if (!context.mounted) return;

    // context 교차 방지: navigator/messenger 선캡처(로그아웃 카드와 동일 패턴).
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).deleteAccount(password: password);
      messenger.showSnackBar(
        const SnackBar(content: Text('계정이 삭제됐어요.')),
      );
      navigator.popUntil((Route<dynamic> r) => r.isFirst);
    } on AuthException catch (e) {
      // 삭제 맥락에선 '이메일 또는 비밀번호…' 대신 비밀번호만 짚어 안내한다.
      messenger.showSnackBar(SnackBar(
        content: Text(e.code == AuthErrorCode.invalidCredential
            ? '비밀번호가 올바르지 않아요.'
            : authErrorMessage(e)),
      ));
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// 프로필 편집 다이얼로그 — 표시 이름을 입력받아 `Navigator.pop(값)`으로 반환한다.
///
/// [TextEditingController] 수명을 State가 소유한다 — 호출부에서 컨트롤러를 만들고
/// showDialog 직후 dispose하면 다이얼로그 퇴장 애니메이션 중 TextField가 죽은
/// 컨트롤러를 참조하는 사고가 나므로, 라우트 제거 후 불리는 State.dispose에 맡긴다.
class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('프로필 편집'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(
          labelText: '표시 이름',
          hintText: '앱에서 보여질 이름',
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (String v) => Navigator.of(context).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 계정 삭제 확인 다이얼로그 — 비밀번호를 입력받아 `Navigator.pop(값)`으로 반환한다.
/// 컨트롤러 수명 규칙은 [_EditNameDialog]와 동일.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('계정 삭제'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('계정과 프로필이 삭제되며 되돌릴 수 없어요.\n'
              '계속하려면 비밀번호를 입력해 주세요.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호'),
            textInputAction: TextInputAction.done,
            onSubmitted: (String v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('삭제'),
        ),
      ],
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
