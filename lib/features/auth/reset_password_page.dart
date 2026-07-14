/// 비밀번호 찾기 페이지 — KeepCon 틀 재디자인 (rough 스캐폴드, 실제 재설정 없음).
///
/// ⚠️ 자리표시: 이메일 입력 + 안내문구 + 버튼만 갖춘 rough 버전.
/// 재설정 링크 발송 로직은 팀원이 [AuthRepository]/`resetPassword` 계약으로 붙인다.
///
/// 레이아웃(위→아래): 뒤로가기 + 타이틀 → 안내문구 → 이메일 → 재설정 링크 보내기.
///
/// route: [LoginPage]에서 Navigator.push로 진입(뒤로가기로 복귀).
/// 색/폰트/라운드는 `Theme.of(context)` 소비. 하드코딩 색 없음.
library;

import 'package:flutter/material.dart';
import '../../shared/theme/theme_tokens.dart';

/// 비밀번호 재설정 화면. rough 스캐폴드.
class ResetPasswordPage extends StatelessWidget {
  const ResetPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      // 큰 타이틀은 본문 헤더로 두고, AppBar는 뒤로가기만 담당(투명).
      appBar: AppBar(toolbarHeight: 44),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '비밀번호 찾기',
                style: context.resetTitleStyle,
              ),
              const SizedBox(height: 20),
              Text(
                '가입한 이메일 주소를 입력하면\n비밀번호 재설정 링크를 보내드립니다.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),

              // ── 이메일 ──
              const TextField(
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 24),

              // ── 재설정 링크 보내기 ──
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
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('재설정 링크 보내기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
