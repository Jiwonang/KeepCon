/// 설정('마이') — 알림 설정 화면.
///
/// 앱 내부에 on/off 토글을 두지 않는다. 끄기는 **시스템 알림 설정**이 이미 제공하며,
/// 앱에 토글을 하나 더 두면 "앱에서는 켜져 있는데 안 온다"(=OS에서 꺼둠) 같은 상태가
/// 생겨 사용자가 어디를 봐야 할지 알 수 없게 된다. 대신 이 화면은 **지금 어느 상태이고
/// 언제 알림이 오는지**를 보여주고, 권한이 없으면 요청한다.
///
/// (앱 내부 토글을 도입하려면 설정을 기기에 저장할 계층이 필요한데, 이 프로젝트에는
/// 아직 없다 — 테마 모드도 같은 이유로 재시작하면 초기화된다.)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/notifications/expiry_notification_scheduler.dart';
import '../../shared/providers/notification_providers.dart';
import '../../shared/util/expiry_policy.dart';

/// 알림 설정 화면.
class NotificationSettingsPage extends ConsumerStatefulWidget {
  /// NotificationSettingsPage 인스턴스를 생성한다.
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  NotificationPermissionStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final NotificationPermissionStatus s =
        await ref.read(expiryNotificationSchedulerProvider).currentPermission();
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    final NotificationPermissionStatus s =
        await ref.read(expiryNotificationSchedulerProvider).requestPermission();
    if (!mounted) return;
    setState(() {
      _status = s;
      _busy = false;
    });

    if (s == NotificationPermissionStatus.denied && mounted) {
      // 두 번째 요청부터 안드로이드는 다이얼로그를 띄우지 않고 즉시 거부한다.
      // 그러면 버튼이 아무 반응도 없는 것처럼 보이므로, 어디로 가야 하는지 알려준다.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('휴대폰 설정 > 앱 > KeepCon > 알림에서 켤 수 있어요.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _StatusCard(status: _status, busy: _busy, onRequest: _request),
          const SizedBox(height: 20),
          Text('만료 임박 알림', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '보관 중인 기프티콘의 유효기간이 다가오면 알려드려요. '
            '만료 ${expiryNotifyLeadDays.join('일 · ')}일 전 '
            '오전 $expiryNotifyHour시에 알림이 옵니다.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            '이 알림은 휴대폰 안에서 예약돼요. 인터넷에 연결돼 있지 않아도, '
            '앱이 꺼져 있어도 뜹니다. 사용 완료했거나 이미 만료된 기프티콘은 알리지 않아요.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 현재 권한 상태 카드.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.busy,
    required this.onRequest,
  });

  final NotificationPermissionStatus? status;
  final bool busy;
  final Future<void> Function() onRequest;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final (IconData, Color, String, String?) view = switch (status) {
      null => (
          Icons.hourglass_empty,
          scheme.onSurfaceVariant,
          '확인 중…',
          null,
        ),
      NotificationPermissionStatus.granted => (
          Icons.notifications_active,
          scheme.primary,
          '알림이 켜져 있어요',
          '만료가 다가오면 알려드릴게요.',
        ),
      NotificationPermissionStatus.denied => (
          Icons.notifications_off,
          scheme.error,
          '알림이 꺼져 있어요',
          '권한을 허용해야 만료 임박 알림을 받을 수 있어요.',
        ),
      NotificationPermissionStatus.unsupported => (
          Icons.desktop_access_disabled,
          scheme.onSurfaceVariant,
          '이 환경에서는 알림을 지원하지 않아요',
          '안드로이드 앱에서 이용할 수 있어요.',
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(view.$1, color: view.$2),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(view.$3, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            if (view.$4 != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                view.$4!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (status == NotificationPermissionStatus.denied) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : () => onRequest(),
                child: Text(busy ? '요청 중…' : '알림 허용하기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
