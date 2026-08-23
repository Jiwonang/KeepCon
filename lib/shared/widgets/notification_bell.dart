/// KeepCon 공유 위젯 — 안읽음 수 뱃지가 붙은 알림 벨.
///
/// 벨은 홈 헤더·공유 탭 헤더 두 곳에 있고 둘이 같은 숫자를 보여야 한다. 화면마다 벨을
/// 따로 그리면 뱃지 임계값·표기(`9+`)·색이 갈라지고, 실제로 홈 벨은 **점이 하드코딩**돼
/// 안읽음이 0이어도 켜져 있었다(#55에서 공유 탭·마이페이지만 실연동으로 고치고 홈이 빠짐).
/// 그래서 표시와 안읽음 구독을 이 위젯 하나로 모은다.
///
/// **목적지는 받지 않고 [onPressed]로 위임한다.** 알림 화면은 `lib/features/share`에 있어
/// 여기서 직접 import하면 계약(`lib/shared`)이 페이지를 향해 거꾸로 의존한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/group_notifications_provider.dart';
import '../theme/theme_tokens.dart';

/// 안읽음 수 뱃지가 붙은 알림 벨 버튼.
///
/// 안읽음 수는 계약 정본 [unreadNotificationCountProvider]를 구독한다 — 한 화면에서
/// 읽음 처리하면 다른 화면의 뱃지도 함께 꺼진다.
class NotificationBell extends ConsumerWidget {
  /// NotificationBell 인스턴스를 생성한다.
  const NotificationBell({
    required this.onPressed,
    this.tooltip = '알림',
    super.key,
  });

  /// 벨을 눌렀을 때의 동작(보통 알림 목록 화면으로 이동).
  final VoidCallback onPressed;

  /// 길게 눌렀을 때의 안내 문구. 화면마다 부르는 이름이 달라 주입받는다.
  final String tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int unreadCount = ref.watch(unreadNotificationCountProvider);

    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Icon(Icons.notifications_none, color: scheme.onSurface),
            // 0이면 뱃지를 아예 그리지 않는다 — "안읽음 없음"과 "0건"은 같은 말이라
            // 빈 뱃지가 붙어 있으면 읽을 것이 남았다고 오독된다.
            if (unreadCount > 0)
              Positioned(
                top: -4,
                right: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                  // 두 자리를 넘으면 뱃지가 아이콘을 덮으므로 `9+`로 접는다.
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: TextStyle(
                      color: scheme.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
