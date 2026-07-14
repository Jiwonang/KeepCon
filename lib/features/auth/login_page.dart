/// 로그인 페이지 — KeepCon 틀 재디자인 (rough 스캐폴드, 실제 인증 없음).
///
/// ⚠️ 자리표시: 화면 틀만 갖춘 rough 버전이다. 실제 인증/세션/자동 로그인 로직은
/// 팀원(auth 담당)이 이 위에 [AuthRepository]/`currentUser` 계약을 붙여 구현한다.
/// 여기서는 계약에 없는 공유 타입을 만들지 않고, 데이터는 화면 내부 로컬로만 둔다.
///
/// 레이아웃(위→아래): 로고+타이틀 → Google 로그인 → 구분선 → 이메일/비밀번호 →
/// 로그인 버튼 → 회원가입·비밀번호 찾기 링크.
///
/// 이동: 회원가입 → [SignupPage], 비밀번호 찾기 → [ResetPasswordPage],
/// 로그인/Google → 데모로 [KeepConShell]로 진입(실제 인증은 후속 TODO).
/// 색/폰트/라운드는 `Theme.of(context)` 소비. Google 브랜드색만 페이지 로컬 상수.
library;

import 'package:flutter/material.dart';

import '../../app/keepcon_shell.dart';
import 'reset_password_page.dart';
import 'signup_page.dart';

/// 로그인 진입 화면. rough 스캐폴드.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscure = true;

  /// 데모 로그인 — 실제 인증 없이 인증 스택을 제거하고 홈으로 진입한다.
  ///
  /// TODO(auth): AuthRepository.signIn(email, password) / Google OAuth 연동 →
  ///   성공 시 세션 시작(currentUser 노출) 후 홈으로 이동.
  void _demoSignIn() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const KeepConShell()),
      (route) => false,
    );
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
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
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

                // ── Google 로그인 ──
                _GoogleButton(onPressed: _demoSignIn),
                const SizedBox(height: 30),

                // ── 구분선 ──
                const _OrDivider(label: '또는 이메일로 로그인'),
                const SizedBox(height: 22),

                // ── 이메일 ──
                const TextField(
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: '이메일',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 14),

                // ── 비밀번호(가시성 토글) ──
                TextField(
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
                  onPressed: _demoSignIn,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('로그인'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
