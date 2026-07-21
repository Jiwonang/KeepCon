/// 회원가입 페이지 — 이메일/비밀번호 가입.
///
/// [AuthRepository.signUp]으로 가입한다(닉네임=displayName). 비밀번호 확인 일치를
/// 검증하고, 성공 시 즉시 로그인 상태가 되어 `AuthGate`가 앱 셸로 전환하므로 이 화면을
/// 정리해 홈으로 돌려보낸다. 실패는 [AuthException] 메시지로 안내한다.
///
/// 레이아웃(위→아래): 뒤로가기 + 타이틀 → Google 가입(준비 중) → 구분선 →
/// 닉네임/이메일/비밀번호/비밀번호 확인 → 가입하기.
///
/// route: [LoginPage]에서 Navigator.push로 진입(뒤로가기로 복귀).
///
/// NOTE: Google 버튼·구분선은 [LoginPage]와 동일 패턴 — 공용 위젯 추출은 follow-up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/repositories.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/theme/theme_tokens.dart';
import 'auth_error_message.dart';

/// 회원가입 화면. [AuthRepository]로 이메일/비밀번호 가입한다.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final TextEditingController _nicknameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _pwCtrl = TextEditingController();
  final TextEditingController _pwConfirmCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _obscurePwConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  /// 이메일/비밀번호로 가입. 성공 시 즉시 로그인 상태가 되어 `AuthGate`가 셸로 전환하므로,
  /// 이 화면(및 위 스택)을 정리해 홈으로 돌려보낸다. 실패는 [AuthException] 메시지로 안내.
  Future<void> _signUp() async {
    if (_loading) return;
    final String email = _emailCtrl.text.trim();
    final String pw = _pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      _snack('이메일과 비밀번호를 입력해 주세요.');
      return;
    }
    if (pw != _pwConfirmCtrl.text) {
      _snack('비밀번호가 서로 달라요.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signUp(
            email: email,
            password: pw,
            displayName: _nicknameCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      }
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

  void _notReady() => _snack('Google 가입은 준비 중이에요. 이메일로 가입해 주세요.');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 큰 타이틀은 본문 헤더로 두고, AppBar는 뒤로가기만 담당(투명).
      appBar: AppBar(toolbarHeight: 44),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '회원가입',
                style: context.signupTitleStyle,
              ),
              const SizedBox(height: 26),

              // ── Google 가입 (준비 중) ──
              _GoogleButton(label: 'Google로 가입하기', onPressed: _notReady),
              const SizedBox(height: 26),

              // ── 구분선 ──
              const _OrDivider(label: '또는 이메일로 가입'),
              const SizedBox(height: 24),

              // ── 닉네임 ──
              TextField(
                controller: _nicknameCtrl,
                decoration: const InputDecoration(
                  hintText: '닉네임',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),

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
                obscureText: _obscurePw,
                decoration: InputDecoration(
                  hintText: '비밀번호',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: _VisibilityToggle(
                    obscured: _obscurePw,
                    onPressed: () => setState(() => _obscurePw = !_obscurePw),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── 비밀번호 확인(가시성 토글) ──
              TextField(
                controller: _pwConfirmCtrl,
                obscureText: _obscurePwConfirm,
                decoration: InputDecoration(
                  hintText: '비밀번호 확인',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: _VisibilityToggle(
                    obscured: _obscurePwConfirm,
                    onPressed: () =>
                        setState(() => _obscurePwConfirm = !_obscurePwConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 26),

              // ── 가입하기 ──
              ElevatedButton(
                onPressed: _loading ? null : _signUp,
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
                    : const Text('가입하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 비밀번호 가시성 토글(눈 아이콘). 입력 필드 suffix 공용.
class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      tooltip: obscured ? '비밀번호 표시' : '비밀번호 숨기기',
    );
  }
}

/// Google 가입 버튼(아웃라인). 실제 OAuth는 후속 — 지금은 데모.
///
/// NOTE: [LoginPage]의 동명 위젯과 동일 — 추후 공용 위젯으로 통합 예정.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.label, required this.onPressed});

  final String label;
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const _GoogleMark(),
          const SizedBox(width: 12),
          Text(label),
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
