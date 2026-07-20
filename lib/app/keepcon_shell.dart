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

import '../features/main/main_page.dart';
import '../features/scan/scan_page.dart';
import '../features/share/share_page.dart';

/// 하단 내비게이션 셸. 앱의 홈으로 사용한다.
class KeepConShell extends StatefulWidget {
  const KeepConShell({super.key});

  @override
  State<KeepConShell> createState() => _KeepConShellState();
}

class _KeepConShellState extends State<KeepConShell> {
  // 탭: 홈(0) · 공유(1). 스캔(추가)은 탭이 아니라 중앙 +로 push한다.
  int _index = 0;

  static const List<Widget> _tabs = <Widget>[
    MainPage(),
    SharePage(),
  ];

  Future<void> _openAdd() async {
    // 중앙 + = 기프티콘 추가. 스캔 플로우를 전체화면으로 push한다.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ScanPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _NavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: '홈',
              selected: _index == 0,
              onTap: () => setState(() => _index = 0),
            ),
            const SizedBox(width: 48), // 중앙 FAB 노치 공간
            _NavItem(
              icon: Icons.group_outlined,
              selectedIcon: Icons.group,
              label: '공유',
              selected: _index == 1,
              onTap: () => setState(() => _index = 1),
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
    return Expanded(
      child: InkWell(
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
      ),
    );
  }
}
