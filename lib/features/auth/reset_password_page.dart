/// 비밀번호 찾기 페이지 — [AuthRepository.sendPasswordReset]로 재설정 메일을 발송한다.
///
/// 레이아웃(위→아래): 뒤로가기 + 타이틀 → 안내문구 → 이메일 → 재설정 링크 보내기.
/// route: [LoginPage]에서 Navigator.push로 진입(뒤로가기로 복귀).
///
/// 안내에 **스팸함**을 명시한다 — Firebase 기본 발신자로 나간 메일이 스팸으로
/// 격리되면 사용자에게는 "메일이 안 왔다"로 보인다(경위·근본 대응은 PR 본문).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/repositories.dart';
import '../../shared/repositories/auth_repository.dart';
import '../../shared/theme/theme_tokens.dart';
import 'auth_error_message.dart';

/// 비밀번호 재설정 화면.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final TextEditingController _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  /// 재설정 메일 발송. 성공 시 안내 후 로그인 화면으로 복귀한다.
  Future<void> _sendReset() async {
    if (_loading) return;
    final String email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _snack('이메일을 입력해 주세요.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email: email);
      if (!mounted) return;
      _snack('재설정 링크를 보냈어요. 스팸함도 확인해 주세요.');
      Navigator.of(context).maybePop();
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
                '가입한 이메일 주소를 입력하면\n비밀번호 재설정 링크를 보내드립니다.\n'
                '메일이 안 보이면 스팸함도 확인해 주세요.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),

              // ── 이메일 ──
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 24),

              // ── 재설정 링크 보내기 ──
              ElevatedButton(
                onPressed: _loading ? null : _sendReset,
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
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
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
