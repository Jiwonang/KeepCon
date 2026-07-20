/// 로그인 페이지 — 이메일/비밀번호 로그인.
///
/// [AuthRepository.signIn]으로 인증한다. 성공 시 세션이 바뀌어 `AuthGate`가 앱 셸로
/// 전환하므로 이 화면은 직접 내비게이션하지 않는다(세션이 단일 진실). 실패는
/// [AuthException] 메시지로 안내한다.
///
/// 레이아웃(위→아래): 로고+타이틀 → Google 로그인(준비 중) → 구분선 → 이메일/비밀번호 →
/// 로그인 버튼 → 회원가입·비밀번호 찾기 링크.
///
/// 이동: 회원가입 → [SignupPage], 비밀번호 찾기 → [ResetPasswordPage].
/// Google 로그인은 아직 미구현(안내만). 색/폰트/라운드는 `Theme.of(context)` 소비.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/repositories.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/theme/theme_tokens.dart';
import 'auth_error_message.dart';
import 'reset_password_page.dart';
import 'signup_page.dart';

/// 로그인 진입 화면. [AuthRepository]로 이메일/비밀번호 로그인한다.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  /// 이메일/비밀번호로 로그인. 성공 시 세션이 바뀌어 `AuthGate`가 앱 셸로 전환하므로
  /// 여기서 직접 내비게이션하지 않는다. 실패는 [AuthException] 메시지로 안내한다.
  Future<void> _signIn() async {
    if (_loading) return;
    final String email = _emailCtrl.text.trim();
    final String pw = _pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      _snack('이메일과 비밀번호를 입력해 주세요.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signIn(email: email, password: pw);
      // 성공 → AuthGate가 세션 변화를 받아 셸로 전환(별도 내비게이션 불필요).
    } on AuthException catch (e) {
      _snack(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _notReady() => _snack('Google 로그인은 준비 중이에요. 이메일로 로그인해 주세요.');

  void _openSignup() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SignupPage()),
      );

  void _openReset() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ResetPasswordPage()),
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ── 로고 + 타이틀 + 슬로건 ──
                Icon(Icons.card_giftcard, size: 64, color: scheme.primary),
                const SizedBox(height: 14),
                Text(
                  'KeepCon',
                  textAlign: TextAlign.center,
                  style: context.logoTitleStyle,
                ),
                const SizedBox(height: 10),
                Text(
                  '흩어진 기프티콘을 한 곳에서',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 48),

                // ── Google 로그인 (준비 중) ──
                _GoogleButton(onPressed: _notReady),
                const SizedBox(height: 30),

                // ── 구분선 ──
                const _OrDivider(label: '또는 이메일로 로그인'),
                const SizedBox(height: 22),

                // ── 이메일 ──
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: '이메일',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 14),

                // ── 비밀번호(가시성 토글) ──
                TextField(
                  controller: _pwCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: '비밀번호',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      tooltip: _obscure ? '비밀번호 표시' : '비밀번호 숨기기',
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── 로그인 버튼 ──
                ElevatedButton(
                  onPressed: _loading ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('로그인'),
                ),
                const SizedBox(height: 24),

                // ── 회원가입 · 비밀번호 찾기 ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    TextButton(
                      onPressed: _openSignup,
                      child: const Text('회원가입'),
                    ),
                    Text('|',
                        style: TextStyle(
                            color: scheme.outline.withValues(alpha: 0.6))),
                    TextButton(
                      onPressed: _openReset,
                      child: const Text('비밀번호 찾기'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google 로그인 버튼(아웃라인). 실제 OAuth는 후속 — 지금은 데모 진입.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _GoogleMark(),
          SizedBox(width: 12),
          Text('Google로 로그인'),
        ],
      ),
    );
  }
}

/// Google 로고 자리표시 마크. 3rd-party 브랜드색이라 테마가 아닌 페이지 로컬 상수.
///
/// TODO(auth): 실제 Google Sign-In 연동 시 공식 로고 에셋으로 교체(브랜드 가이드 준수).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  /// Google 브랜드 블루(공식 로고 색). KeepCon 테마 토큰이 아님(3rd-party 아이덴티티).
  static const Color _googleBlue = Color(0xFF4285F4);

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        color: _googleBlue,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

/// "또는 …" 좌우 라인 구분선.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color line = theme.colorScheme.outline.withValues(alpha: 0.4);
    return Row(
      children: <Widget>[
        Expanded(child: Divider(color: line, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(child: Divider(color: line, thickness: 1)),
      ],
    );
  }
}
