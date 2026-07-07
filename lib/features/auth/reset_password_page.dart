/// 비밀번호 찾기 페이지 — rough 스캐폴드 (하드코딩, 실제 재설정 없음).
///
/// ⚠️ 자리표시: 이메일 입력 + 안내문구 + 버튼만 갖춘 rough 버전.
/// 재설정 링크 발송 로직은 팀원이 [AuthRepository]/`resetPassword` 계약으로 붙인다.
///
/// route: LoginPage에서 Navigator.push로 진입.
library;

import 'package:flutter/material.dart';

/// 비밀번호 재설정 화면. rough 스캐폴드.
class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 찾기')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '가입한 이메일 주소를 입력하면\n비밀번호 재설정 링크를 보내드립니다.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              const TextField(
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // TODO(auth): AuthRepository.resetPassword(email) 연동 →
                  //   발송 성공 안내 후 로그인 화면으로 복귀.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('재설정 링크 발송은 준비 중입니다.'),
                    ),
                  );
                },
                child: const Text('재설정 링크 보내기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
