/// main 페이지 — 임시 설정 시트(다크모드 토글).
///
/// ⚠️ 자리표시(placeholder): 이 시트는 정식 '마이(설정)' 페이지가 생기기 전까지의
/// 임시 설정 진입점이다. 추후 auth/설정 담당의 '마이' 페이지로 대체될 자리다.
/// (여기서 '마이' 페이지 자체를 만들지 않는다.)
///
/// 다크모드 스위치는 공유 계약 [themeModeProvider]를 소비한다:
/// - 현재값: `ref.watch(themeModeProvider)` (== [ThemeMode.dark] 여부)
/// - 토글  : `ref.read(themeModeProvider.notifier).setDark(bool)`
/// 페이지 내부에 ThemeMode 상태를 재선언하지 않는다(설정 SSOT와 갈라짐 방지).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/theme_mode_provider.dart';

/// 설정 시트를 모달 바텀시트로 연다.
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final bool isDark = mode == ThemeMode.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('설정', style: theme.textTheme.titleLarge),
            ),
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
            // TODO(후속): 정식 '마이' 페이지로 이전 — 계정/알림/그룹 등 설정 항목 추가 예정.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '더 많은 설정은 곧 마이 페이지에서 제공됩니다',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
