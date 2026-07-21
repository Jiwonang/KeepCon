/// KeepCon 인증 게이트 — 세션 상태에 따라 로그인/앱 셸을 라우팅한다.
///
/// 앱 조립부(assembly) 소유. `AuthRepository.watchCurrentUser()`를 구독해:
/// - 미로그인(null) → [LoginPage]
/// - 로그인 → [KeepConShell]
/// 로그인/회원가입/로그아웃은 **세션만 바꾸면** 이 게이트가 화면을 전환한다
/// (페이지가 직접 셸로 내비게이션하지 않는다 — 세션이 단일 진실).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/login_page.dart';
import '../shared/models/user.dart';
import '../shared/providers/repositories.dart';
import 'keepcon_shell.dart';

/// 앱 게이트용 현재 세션 사용자 스트림. SSOT [authRepositoryProvider]를 구독한다.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// 인증 게이트. 앱의 `home`으로 사용한다.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authStateProvider).when(
          data: (User? user) =>
              user == null ? const LoginPage() : const KeepConShell(),
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, StackTrace _) => Scaffold(
            body: Center(child: Text('세션을 불러오지 못했어요.\n$e')),
          ),
        );
  }
}
