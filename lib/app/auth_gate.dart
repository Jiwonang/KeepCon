/// KeepCon 인증 게이트 — 세션 상태에 따라 로그인/앱 셸을 라우팅한다.
///
/// 앱 조립부(assembly) 소유. 세션 스트림 정본 [sessionUserProvider]를 구독해:
/// - 세션 확인 중([AsyncLoading]) → 스플래시(진행 표시)
/// - 미로그인 확정([AsyncData]`(null)`) → [LoginPage]
/// - 로그인([AsyncData]`(user)`) → [KeepConShell]
/// - 세션 조회 실패([AsyncError]) → 안내 화면
/// 로그인/회원가입/로그아웃은 **세션만 바꾸면** 이 게이트가 화면을 전환한다
/// (페이지가 직접 셸로 내비게이션하지 않는다 — 세션이 단일 진실).
///
/// 게이트는 자체 세션 구독을 열지 않는다 — `watchCurrentUser()`를 다시 조립하면
/// 정본과 별개 인스턴스가 생겨 계정 전환 프레임에서 화면마다 세션이 한 프레임
/// 어긋나고, 실패 시 캐시된 에러가 소스마다 따로 남는다(매트릭스 #13).
/// 정본은 `autoDispose`지만 이 게이트가 앱 `home`으로 루트에서 상시 `watch` 하므로
/// 앱 수명 동안 구독이 유지된다(= 세션 스트림 구독 1개의 앵커).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/login_page.dart';
import '../shared/models/user.dart';
import '../shared/providers/session_provider.dart';
import 'keepcon_shell.dart';

/// 인증 게이트. 앱의 `home`으로 사용한다.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(sessionUserProvider).when(
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
