/// 마이(설정) 페이지 — rough 스캐폴드.
///
/// ⚠️ 자리표시: 프로필/설정 화면 틀만 갖춘 rough 버전이다. 프로필 데이터는 하드코딩이며,
/// 실제 조회/수정/로그아웃 로직은 팀원이 [AuthRepository]/`currentUser` 계약으로 붙인다.
///
/// 다크 모드 스위치만 **실제 동작**한다 — 공유 계약 [themeModeProvider]를 소비:
/// - 현재값: `ref.watch(themeModeProvider)` (== [ThemeMode.dark] 여부)
/// - 토글  : `ref.read(themeModeProvider.notifier).setDark(bool)`
/// 페이지 내부에 ThemeMode 상태를 재선언하지 않는다(설정 SSOT와 갈라짐 방지).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/theme_mode_provider.dart';
import '../auth/login_page.dart';

/// 마이(설정) 화면. themeModeProvider 소비를 위해 [ConsumerWidget].
class MyPage extends ConsumerWidget {
  const MyPage({super.key});

  // 프로필 하드코딩 값 (rough — 실제 currentUser는 후속 연동).
  static const String _name = 'KeepCon Tester';
  static const String _email = 'tester@keepcon.app';
  static const String _initial = 'K';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final bool isDark = mode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('마이')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 프로필 카드 (하드코딩).
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        _initial,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(_email, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 다크 모드 — 실제 동작하는 유일한 기능.
            SwitchListTile(
              value: isDark,
              onChanged: (bool v) =>
                  ref.read(themeModeProvider.notifier).setDark(v),
              secondary: Icon(
                isDark ? Icons.dark_mode : Icons.light_mode,
                color: theme.colorScheme.primary,
              ),
              title: const Text('다크 모드'),
              subtitle: const Text('앱 전체 테마를 어둡게 전환합니다'),
            ),
            const Divider(),

            // 자리표시 항목 (탭 시 스낵바만).
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('알림 설정'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _placeholder(context, '알림 설정'),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('계정 관리'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _placeholder(context, '계정 관리'),
            ),
            const Divider(),

            // 로그아웃 — LoginPage로 push(자리표시 흐름).
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                '로그아웃',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () {
                // TODO(auth): AuthRepository.signOut() 연동 후 세션 종료 →
                //   로그인 화면으로 대체 이동(현재는 rough push).
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LoginPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _placeholder(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 은(는) 준비 중입니다.')),
    );
  }
}
