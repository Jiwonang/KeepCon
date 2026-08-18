/// KeepCon 앱 셸 — 하단 내비게이션 (홈 · 중앙 추가(+) · 공유).
///
/// 앱 조립부(orchestrator/assembly) 소유. 틀 이미지의 하단 구조를 따른다:
/// - 좌: 홈([MainPage]) · 우: 공유([SharePage]) — [IndexedStack]으로 탭 상태 보존
/// - 중앙: 다크 원형 FAB(+) = 기프티콘 추가 → [ScanPage]를 push(추가 플로우)
///
/// 각 페이지는 자체 [Scaffold]/AppBar를 가지므로 셸의 [Scaffold]는 본문 + 하단바만 담당.
/// 색/셰이프는 공유 테마(FAB=darkSurface, 선택색=primary)를 그대로 소비한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/main/main_page.dart';
import '../features/main/state/highlighted_gifticon.dart';
import '../features/scan/scan_page.dart';
import '../features/share/share_page.dart';
import '../features/share/widgets/share_sheets.dart';
import '../shared/deeplink/app_destination.dart';
import '../shared/providers/deep_link_providers.dart';

/// 하단 내비게이션 셸. 앱의 홈으로 사용한다.
class KeepConShell extends ConsumerStatefulWidget {
  const KeepConShell({super.key});

  @override
  ConsumerState<KeepConShell> createState() => _KeepConShellState();
}

class _KeepConShellState extends ConsumerState<KeepConShell> {
  // 탭: 홈(0) · 공유(1). 스캔(추가)은 탭이 아니라 중앙 +로 push한다.
  int _index = 0;

  static const List<Widget> _tabs = <Widget>[
    MainPage(),
    SharePage(),
  ];

  @override
  void initState() {
    super.initState();
    // 로그인 후 셸이 뜨는 시점에 대기 중인 딥링크 목적지가 있으면 처리한다.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _consumePendingDestination());
  }

  /// 대기 중인 목적지를 소비해 해당 화면으로 이동한다.
  ///
  /// 1회성 — 소비 즉시 버스를 비워 탭을 오갈 때 같은 시트가 다시 뜨는 것을 막는다.
  /// `switch`가 [AppDestination]에 대해 **exhaustive**라, 목적지가 추가되면 여기서
  /// 컴파일 에러가 난다(처리를 빠뜨려 조용히 아무 일도 안 일어나는 것을 막는다).
  void _consumePendingDestination() {
    final AppDestination? destination = ref.read(pendingDestinationProvider);
    if (destination == null || !mounted) return;
    ref.read(pendingDestinationProvider.notifier).state = null;

    switch (destination) {
      case InviteDestination(:final String inviteToken):
        setState(() => _index = 1); // 공유 탭.
        showJoinGroupSheet(context, initialToken: inviteToken);

      case GifticonHighlightDestination(:final String gifticonId):
        setState(() => _index = 0); // 홈 탭.
        // 강조를 어떻게 보이고 언제 거둘지는 main 페이지의 상태가 정한다.
        ref.read(highlightedGifticonIdProvider.notifier).highlight(gifticonId);
    }
  }

  Future<void> _openAdd() async {
    // 중앙 + = 기프티콘 추가. 스캔 플로우를 전체화면으로 push한다.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScanPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 앱이 **이미 떠 있을 때** 도착한 링크(웜 스타트)도 소비한다. initState의 post-frame
    // 한 번만으로는 그 경우가 통째로 죽는다 — 버스에는 목적지가 쌓이는데 읽는 사람이
    // 없어, 링크를 눌러 앱이 앞으로 나와도 아무 일도 일어나지 않는다.
    ref.listen<AppDestination?>(pendingDestinationProvider,
        (AppDestination? previous, AppDestination? next) {
      // 소비 직후 버스를 비우면서 오는 null 통지는 무시한다.
      if (next == null) return;
      // 빌드 중에는 시트를 열 수 없으므로 프레임 뒤로 미룬다.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _consumePendingDestination());
    });

    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        // 기본 내부 패딩(세로 12)을 제거 — 내비 아이템이 자체 패딩(세로 8)을 가져
        // 좁은 높이에서 아이콘+라벨 컬럼이 2px 넘치던 것을 해소한다.
        padding: EdgeInsets.zero,
        child: Row(
          children: <Widget>[
            Expanded(
              child: _NavItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: '홈',
                selected: _index == 0,
                onTap: () => setState(() => _index = 0),
              ),
            ),
            const SizedBox(width: 48), // 중앙 FAB 노치 공간
            Expanded(
              child: _NavItem(
                icon: Icons.group_outlined,
                selectedIcon: Icons.group,
                label: '공유',
                selected: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 하단바 좌/우 내비 아이템. 선택 시 primary(민트그린), 비선택 시 muted.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(selected ? selectedIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
