/// 로그인 페이지 — rough 스캐폴드 (하드코딩, 실제 인증 없음).
///
/// ⚠️ 자리표시: 화면 틀만 갖춘 rough 버전이다. 실제 인증/세션/자동 로그인 로직은
/// 팀원(auth 담당)이 이 위에 [AuthRepository]/`currentUser` 계약을 붙여 구현한다.
/// 여기서는 계약에 없는 공유 타입을 만들지 않고, 데이터는 화면 내부 로컬로만 둔다.
///
/// 이동: 회원가입 → [SignupPage], 비밀번호 찾기 → [ResetPasswordPage]
/// (scan_page와 동일한 Navigator.push(MaterialPageRoute) 패턴).
library;

import 'package:flutter/material.dart';

import '../../app/keepcon_shell.dart';
import 'reset_password_page.dart';
import 'signup_page.dart';

/// 로그인 진입 화면. rough 스캐폴드.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 로고/타이틀 + 인사문구.
                Icon(
                  Icons.card_giftcard,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'KeepCon',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '흩어진 기프티콘을 한 곳에서.\n로그인하고 시작하세요.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 32),

                // 이메일 입력.
                const TextField(
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: '이메일',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 12),

                // 비밀번호 입력.
                const TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: '비밀번호',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 24),

                // 로그인 버튼 (자리표시 — 실제 인증 없이 이전 화면 pop).
                ElevatedButton(
                  onPressed: () {
                    // TODO(auth): AuthRepository.signIn(email, password) 연동 →
                    //   성공 시 세션 시작(currentUser 노출).
                    // 로그인 성공 → 메인(홈)으로 이동하고 인증 스택 제거.
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => const KeepConShell(),
                      ),
                      (route) => false,
                    );
                  },
                  child: const Text('로그인'),
                ),
                const SizedBox(height: 16),

                // 하단 텍스트 링크: 회원가입 · 비밀번호 찾기.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SignupPage(),
                        ),
                      ),
                      child: const Text('회원가입'),
                    ),
                    Text('·', style: theme.textTheme.bodySmall),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ResetPasswordPage(),
                        ),
                      ),
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
