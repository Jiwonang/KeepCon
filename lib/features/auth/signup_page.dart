/// 회원가입 페이지 — rough 스캐폴드 (하드코딩, 실제 가입 없음).
///
/// ⚠️ 자리표시: 닉네임·이메일·비밀번호·비밀번호확인 입력과 버튼만 갖춘 rough 버전.
/// 유효성 검증/가입 로직은 팀원이 [AuthRepository]/`signUp` 계약으로 붙인다.
///
/// route: LoginPage에서 Navigator.push로 진입.
library;

import 'package:flutter/material.dart';

/// 회원가입 화면. rough 스캐폴드.
class SignupPage extends StatelessWidget {
  const SignupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TextField(
                decoration: InputDecoration(
                  hintText: '닉네임',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '비밀번호',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                  hintText: '비밀번호 확인',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // TODO(auth): 유효성 검증 후 AuthRepository.signUp(...) 연동 →
                  //   성공 시 세션 시작하거나 로그인 화면으로 복귀.
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('가입하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
