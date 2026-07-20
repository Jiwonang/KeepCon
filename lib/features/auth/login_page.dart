/// 로그인 페이지 — 이메일/비밀번호 실제 인증 연동.
///
/// [AuthRepository.signIn]으로 로그인하고, 성공 시 세션이 시작되어 [KeepConShell]로
/// 이동한다. Google 로그인은 패키지가 아직 없어 안내만 표시한다(TODO(auth): google_sign_in
/// 도입 후 실연동).
///
/// 레이아웃(위→아래): 로고+타이틀 → Google 로그인(준비 중) → 구분선 → 이메일/비밀번호 →
/// 로그인 버튼 → 회원가입·비밀번호 찾기 링크.
///
/// 이동: 회원가입 → [SignupPage], 비밀번호 찾기 → [ResetPasswordPage],
/// 로그인 성공 → [KeepConShell](이전 스택 제거).
/// 색/폰트/라운드는 `Theme.of(context)` 소비. Google 브랜드색만 페이지 로컬 상수.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/theme_tokens.dart';
import '../../shared/providers/repositories.dart';
import '../../shared/repositories/auth_repository.dart';

import '../../app/keepcon_shell.dart';
import 'auth_error_messages.dart';
import 'reset_password_page.dart';
import 'signup_page.dart';

/// 로그인 진입 화면.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 실제 로그인 — [AuthRepository.signIn] 연동.
  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showMessage('이메일과 비밀번호를 입력해주세요.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: email, password: password);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const KeepConShell()),
        (route) => false,
      );
    } on AuthException catch (e) {
      _showMessage(authErrorMessage(e.code));
    } catch (_) {
      _showMessage('로그인 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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

                // ── Google 로그인(준비 중) ──
                _GoogleButton(
                  onPressed: () => _showMessage('Google 로그인은 준비 중입니다.'),
                ),
                const SizedBox(height: 30),

                // ── 구분선 ──
                const _OrDivider(label: '또는 이메일로 로그인'),
                const SizedBox(height: 22),

                // ── 이메일 ──
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: '이메일',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 14),

                // ── 비밀번호(가시성 토글) ──
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
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
                  onPressed: _submitting ? null : _submit,
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
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
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
