/// 비밀번호 찾기 페이지 — 실제 재설정 요청 연동.
///
/// [AuthRepository.sendPasswordReset]를 호출하고, 성공 시 안내 후 로그인 화면으로
/// 복귀한다.
///
/// 레이아웃(위→아래): 뒤로가기 + 타이틀 → 안내문구 → 이메일 → 재설정 링크 보내기.
///
/// route: [LoginPage]에서 Navigator.push로 진입(뒤로가기로 복귀).
/// 색/폰트/라운드는 `Theme.of(context)` 소비. 하드코딩 색 없음.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/theme_tokens.dart';
import '../../shared/providers/repositories.dart';
import '../../shared/repositories/auth_repository.dart';

import 'auth_error_messages.dart';

/// 비밀번호 재설정 화면.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('이메일을 입력해주세요.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email: email);
      if (!mounted) return;
      _showMessage('재설정 링크를 보냈습니다. 메일함을 확인해주세요.');
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      _showMessage(authErrorMessage(e.code));
    } catch (_) {
      _showMessage('요청 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 24),

              // ── 재설정 링크 보내기 ──
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
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
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('재설정 링크 보내기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
