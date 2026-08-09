/// KeepCon 조립부 — 에뮬레이터 미기동 안내 화면.
///
/// 기본 실행(플래그 없음)은 로컬 에뮬레이터에 붙는데, 에뮬레이터는 **별도 터미널에서
/// 사람이 띄워야** 한다. 안 띄운 채 실행하면 SDK는 요청을 localhost로 보내고 아무도
/// 응답하지 않으므로 화면이 영원히 로딩 상태가 된다 — 앱은 멀쩡해 보이는데 아무것도
/// 안 되는, 원인을 못 찾는 상황이다.
///
/// 그래서 조립부가 `isEmulatorReachable()`로 먼저 확인하고, 닿지 않으면 앱 대신
/// 이 화면을 띄운다. **무엇을 해야 하는지 화면에서 바로 알 수 있어야** 한다.
///
/// ## 화면에서 다시 확인할 수 있어야 하는 이유
/// 이 화면이 뜨는 가장 흔한 상황은 "에뮬레이터를 아직 안 띄웠다"가 아니라
/// **"띄웠는데 아직 다 안 떴다"** 이다 — Firestore 에뮬레이터는 별도 Java 프로세스라
/// CLI가 뜬 뒤에도 수십 초 더 걸린다. 재확인 수단이 없으면 그 사이에 실행한 사람은
/// 앱을 통째로 다시 띄우는 수밖에 없고, 콜드 빌드가 붙으면 그게 제일 비싼 단계가 된다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/firebase/firebase_bootstrap.dart';
import '../shared/theme/app_theme.dart';

/// 에뮬레이터에 닿지 못했을 때 앱 대신 실행하는 최소 앱.
///
/// Repository provider를 조립하지 않는다 — 백엔드가 없는 상태이므로 화면 하나만 띄운다.
class EmulatorUnavailableApp extends StatelessWidget {
  const EmulatorUnavailableApp({super.key, required this.onRetrySucceeded});

  /// 재확인에서 에뮬레이터에 닿았을 때 호출한다. 조립부가 본 앱으로 교체한다.
  ///
  /// 이 화면이 직접 본 앱을 띄우지 않는 이유는 provider override 목록을 조립부만
  /// 알고 있기 때문이다 — 화면은 "닿았다"는 사실만 알리고 조립은 조립부에 맡긴다.
  final VoidCallback onRetrySucceeded;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeepCon',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _EmulatorUnavailablePage(onRetrySucceeded: onRetrySucceeded),
    );
  }
}

class _EmulatorUnavailablePage extends StatefulWidget {
  const _EmulatorUnavailablePage({required this.onRetrySucceeded});

  final VoidCallback onRetrySucceeded;

  @override
  State<_EmulatorUnavailablePage> createState() =>
      _EmulatorUnavailablePageState();
}

class _EmulatorUnavailablePageState extends State<_EmulatorUnavailablePage> {
  /// 셸별 실행 명령. cmd/PowerShell에서 `bash tool/emulators.sh`를 치면 Git Bash가
  /// 아니라 WSL이 실행되어 실패하므로, 두 명령을 나란히 보여 준다.
  static const List<(String, String)> _commands = <(String, String)>[
    ('Git Bash · macOS · Linux', 'bash tool/emulators.sh'),
    ('cmd · PowerShell', 'tool\\emulators.cmd'),
  ];

  /// 재확인이 진행 중인지. 버튼 연타로 프로브가 겹치는 것을 막는다.
  bool _checking = false;

  Future<void> _recheck() async {
    setState(() => _checking = true);
    final bool reachable = await isEmulatorReachable();
    if (!mounted) return;
    if (reachable) {
      widget.onRetrySucceeded();
      return;
    }
    setState(() => _checking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('아직 닿지 않습니다. 터미널에 All emulators ready! 가 뜬 뒤 다시 눌러 보세요.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  '에뮬레이터가 떠 있지 않습니다',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'KeepCon은 기본으로 내 PC의 Firebase 에뮬레이터에 연결합니다. '
                  '에뮬레이터는 별도 터미널에서 먼저 띄워야 합니다.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                for (final (String shell, String command) in _commands)
                  _CommandTile(shell: shell, command: command),
                const SizedBox(height: 20),
                Text(
                  '띄운 뒤 아래 버튼을 누르면 앱을 다시 실행하지 않아도 됩니다.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _checking ? null : _recheck,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_checking ? '확인 중…' : '다시 확인'),
                ),
                const SizedBox(height: 20),
                Divider(color: theme.dividerColor),
                const SizedBox(height: 12),
                Text(
                  '에뮬레이터 없이 실행하려면',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '• 화면·UI 작업만 할 때\n'
                  '    --dart-define=USE_DEMO=true  (시드 데이터, 백엔드 없음)\n'
                  '• 팀원과 같은 그룹에 들어가 공유를 검증할 때\n'
                  '    --dart-define=USE_FIREBASE=true  (팀 공유 dev 서버)',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.7),
                ),
                const SizedBox(height: 8),
                Text(
                  '⚠️ dev 서버는 팀 공유입니다. 그룹 삭제·공유 취소 같은 파괴적 '
                  '테스트는 남의 작업까지 지우므로 에뮬레이터에서 하세요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 셸 이름 + 복사 가능한 명령 한 줄.
class _CommandTile extends StatelessWidget {
  const _CommandTile({required this.shell, required this.command});

  final String shell;
  final String command;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(shell, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SelectableText(
                    command,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: '복사',
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: command));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('명령을 복사했습니다')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
