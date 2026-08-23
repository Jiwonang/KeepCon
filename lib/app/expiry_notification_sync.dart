/// KeepCon 앱 조립부 — 만료 임박 알림 예약을 기프티콘 목록에 맞춰 유지한다.
///
/// **왜 조립부인가.** 예약은 특정 화면의 관심사가 아니다. 스캔이 추가하든 공유가 사용
/// 동기화를 하든 목록이 바뀌면 예약도 바뀌어야 하는데, 이걸 각 페이지에 심으면 한 곳만
/// 빠뜨려도 예약이 조용히 뒤처진다. 목록 스트림([rawGifticonsProvider]) 하나만 지켜보면
/// 모든 변경 경로가 여기로 모인다.
///
/// **왜 로그인 이후에만 있는가.** [AuthGate]가 로그인 상태에서만 이 위젯을 마운트한다.
/// 로그아웃하면 dispose에서 예약을 전부 지운다 — 계정을 바꿨는데 이전 사용자의 기프티콘
/// 알림이 뜨면 안 되기 때문이다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/providers/raw_gifticons_provider.dart';
import '../shared/deeplink/app_destination.dart';
import '../shared/models/gifticon.dart';
import '../shared/notifications/expiry_notification_scheduler.dart';
import '../shared/providers/deep_link_providers.dart';
import '../shared/providers/notification_providers.dart';

/// 기프티콘 목록 변화를 만료 임박 알림 예약에 반영하는 래퍼.
class ExpiryNotificationSync extends ConsumerStatefulWidget {
  /// [child]를 그대로 그리며, 알림 예약 동기화만 곁들인다.
  const ExpiryNotificationSync({super.key, required this.child});

  /// 감싸는 화면(로그인 이후의 앱 셸).
  final Widget child;

  @override
  ConsumerState<ExpiryNotificationSync> createState() =>
      _ExpiryNotificationSyncState();
}

class _ExpiryNotificationSyncState
    extends ConsumerState<ExpiryNotificationSync> {
  /// 동기화가 진행 중인지. 목록이 연달아 방출될 때 예약을 겹쳐 쓰지 않기 위함이다.
  bool _syncing = false;

  /// 동기화 중에 도착한 최신 목록. 끝나면 이것으로 한 번 더 돌린다(latest-wins).
  List<Gifticon>? _queued;

  /// 권한 요청은 세션당 한 번만 — 거부한 사용자에게 목록이 바뀔 때마다 다시 묻지 않는다.
  bool _permissionAsked = false;

  /// 이 위젯이 폐기됐는지(로그아웃/계정 전환).
  ///
  /// 없으면 이런 순서가 가능하다: 예약이 진행 중 → 로그아웃 → [dispose]가 취소를 걸음
  /// → 진행 중이던 예약이 끝나며 대기열([_queued])로 **다시 예약** → 결국 이전 사용자의
  /// 기프티콘 이름이 알림에 뜬다. 폐기 후에는 어떤 예약도 새로 시작하지 않는다.
  bool _disposed = false;

  /// 스케줄러를 미리 붙잡아 둔다.
  ///
  /// [dispose]에서 `ref.read`를 부르면 riverpod이 "Cannot use ref after the widget was
  /// disposed"로 던진다 — 정작 예약을 지워야 할 시점(로그아웃)에 지우지 못한다.
  /// provider는 앱 수명 동안 같은 인스턴스를 주므로 미리 읽어 두는 것이 안전하다.
  late final ExpiryNotificationScheduler _scheduler;

  /// 알림 탭 구독. 앱이 떠 있을 때 탭한 경우를 받는다.
  StreamSubscription<String>? _tapSubscription;

  @override
  void initState() {
    super.initState();
    _scheduler = ref.read(expiryNotificationSchedulerProvider);
    // 첫 프레임 이후에 묻는다. 로그인 직후 화면이 그려지기도 전에 시스템 권한
    // 다이얼로그가 뜨면 사용자가 맥락 없이 거부하기 쉽다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _askPermissionOnce());

    // 알림 탭 → 목적지 버스. 딥링크와 **같은 통로**를 쓴다 — 수신 경로마다 화면을
    // 직접 조작하면 어느 경로로 들어왔느냐에 따라 동작이 갈린다.
    _tapSubscription = _scheduler.notificationTaps.listen(
      _publishTap,
      onError: (Object e) => debugPrint('KeepCon: 알림 탭 수신 오류 — $e'),
    );
    unawaited(_consumeLaunchPayload());
  }

  /// 앱이 알림으로 처음 열린 경우(콜드 스타트). 스트림이 구독되기 전에 이벤트가
  /// 지나가므로 따로 받아야 한다 — 딥링크의 `getInitialLink`와 같은 구조다.
  Future<void> _consumeLaunchPayload() async {
    await _guard('실행 payload 확인', () async {
      final String? gifticonId = await _scheduler.takeLaunchPayload();
      if (gifticonId != null) _publishTap(gifticonId);
    });
  }

  void _publishTap(String gifticonId) {
    if (!mounted) return;
    ref.read(pendingDestinationProvider.notifier).state =
        GifticonHighlightDestination(gifticonId);
  }

  /// 알림 관련 호출을 감싸 실패를 삼킨다.
  ///
  /// 알림이 안 오는 것은 불편이지만, 목록 화면이 못 뜨거나 로그아웃이 막히는 것은
  /// 기능 상실이다. 플러그인이 없는 환경(위젯 테스트·미지원 플랫폼)에서도 앱이
  /// 정상 동작해야 한다.
  Future<void> _guard(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('KeepCon: 만료 알림 $what 실패 — $e');
    }
  }

  Future<void> _askPermissionOnce() async {
    if (_permissionAsked || !mounted) return;
    _permissionAsked = true;

    await _guard('권한 확인', () async {
      // 이미 허용돼 있으면 다이얼로그를 띄우지 않는다.
      final NotificationPermissionStatus current =
          await _scheduler.currentPermission();
      if (current == NotificationPermissionStatus.granted ||
          current == NotificationPermissionStatus.unsupported) {
        return;
      }
      await _scheduler.requestPermission();

      // 방금 허용됐다면 현재 목록으로 즉시 예약한다 — 다음에 목록이 바뀔 때까지
      // 기다리면, 목록이 안정된 사용자는 알림을 영영 못 받는다.
      if (!mounted) return;
      final List<Gifticon>? list = ref.read(rawGifticonsProvider).valueOrNull;
      if (list != null) unawaited(_sync(list));
    });
  }

  Future<void> _sync(List<Gifticon> gifticons) async {
    if (_disposed) return;
    if (_syncing) {
      _queued = gifticons;
      return;
    }
    _syncing = true;
    try {
      await _guard('예약', () => _scheduler.sync(gifticons));
    } finally {
      _syncing = false;
      final List<Gifticon>? next = _queued;
      _queued = null;
      if (next != null && !_disposed) unawaited(_sync(next));
    }
  }

  @override
  void dispose() {
    // 로그아웃/계정 전환 — 이전 사용자의 기프티콘 알림이 남으면 안 된다.
    //
    // 순서가 중요하다: 먼저 재진입을 막고 대기열을 비운 **뒤에** 취소를 건다. 스케줄러가
    // sync·cancelAll을 직렬 큐로 처리하므로, 진행 중인 예약이 있어도 취소가 그 뒤에
    // 실행된다(= 취소가 마지막 상태로 남는다).
    _disposed = true;
    _queued = null;
    unawaited(_tapSubscription?.cancel());
    unawaited(_guard('취소', _scheduler.cancelAll));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Gifticon>>>(
      rawGifticonsProvider,
      (AsyncValue<List<Gifticon>>? previous, AsyncValue<List<Gifticon>> next) {
        final List<Gifticon>? list = next.valueOrNull;
        // 로딩·에러에서는 손대지 않는다. 순단으로 빈 목록이 오는 순간 예약을 전부
        // 지워버리면, 네트워크가 잠깐 끊긴 것만으로 알림이 사라진다.
        if (list == null || next.isLoading || next.hasError) return;
        unawaited(_sync(list));
      },
    );
    return widget.child;
  }
}
