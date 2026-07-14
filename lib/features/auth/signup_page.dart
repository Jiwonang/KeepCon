/// 회원가입 페이지 — KeepCon 틀 재디자인 (rough 스캐폴드, 실제 가입 없음).
///
/// ⚠️ 자리표시: 닉네임·이메일·비밀번호·비밀번호확인 입력과 버튼만 갖춘 rough 버전.
/// 유효성 검증/가입 로직은 팀원이 [AuthRepository]/`signUp` 계약으로 붙인다.
///
/// 레이아웃(위→아래): 뒤로가기 + 타이틀 → Google 가입 → 구분선 →
/// 닉네임/이메일/비밀번호/비밀번호 확인 → 가입하기.
///
/// route: [LoginPage]에서 Navigator.push로 진입(뒤로가기로 복귀).
/// 색/폰트/라운드는 `Theme.of(context)` 소비. Google 브랜드색만 페이지 로컬 상수.
///
/// NOTE: Google 버튼·구분선은 [LoginPage]와 동일 패턴이다. 로그인/회원가입/비번찾기가
///   모두 머지된 뒤 `lib/features/auth/widgets`의 공용 위젯으로 추출·통합 예정(follow-up).
library;

import 'package:flutter/material.dart';

/// 회원가입 화면. rough 스캐폴드.
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  bool _obscurePw = true;
  bool _obscurePwConfirm = true;

  /// 데모 가입 — 실제 가입/검증 없이 이전(로그인) 화면으로 복귀한다.
  ///
  /// TODO(auth): 유효성 검증 후 AuthRepository.signUp(...) / Google OAuth 연동 →
  ///   성공 시 세션 시작하거나 로그인 화면으로 복귀.
  void _demoSignup() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 26),

              // ── Google 가입 ──
              _GoogleButton(label: 'Google로 가입하기', onPressed: _demoSignup),
              const SizedBox(height: 26),

              // ── 구분선 ──
              const _OrDivider(label: '또는 이메일로 가입'),
              const SizedBox(height: 24),

              // ── 닉네임 ──
              const TextField(
                decoration: InputDecoration(
                  hintText: '닉네임',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),

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
                onPressed: _demoSignup,
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
                child: const Text('가입하기'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
