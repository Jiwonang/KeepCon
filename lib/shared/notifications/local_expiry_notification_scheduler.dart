/// KeepCon — 만료 임박 알림 스케줄러의 로컬 알림 구현(안드로이드).
///
/// 서버가 없다. 만료일은 **내 기기가 이미 알고 있는 정보**라, 남의 행동을 기다릴 필요가
/// 없기 때문이다. 등록·수정 시점에 OS 알림 스케줄러에 걸어두면 앱이 꺼져 있어도 뜬다
/// (FCM과 달리 Cloud Functions·Blaze 결제·토큰 관리가 전부 필요 없다).
///
/// 그룹 이벤트 알림("누가 공유했다")은 이 방식으로 못 만든다 — 그건 남의 행동을 내 닫힌
/// 앱에 전달하는 것이라 중계 서버가 있어야 한다. 두 알림은 요구사항이 다르므로 분리한다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/gifticon.dart';
import 'expiry_notification_plan.dart';
import 'expiry_notification_scheduler.dart';

/// 만료 임박 알림 채널 id. 사용자가 시스템 설정에서 이 채널만 끌 수 있다.
const String expiryChannelId = 'keepcon_expiry_reminder';

/// 채널 표시 이름(시스템 알림 설정에 노출된다).
const String expiryChannelName = '만료 임박 알림';

/// 채널 설명(시스템 알림 설정에 노출된다).
const String expiryChannelDescription = '보관 중인 기프티콘의 유효기간이 다가오면 알려줍니다.';

/// 로컬 알림 기반 스케줄러.
class LocalExpiryNotificationScheduler implements ExpiryNotificationScheduler {
  /// [plugin]을 주입하면 테스트에서 교체할 수 있다.
  LocalExpiryNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// 진행 중이거나 완료된 초기화. 동시 호출을 하나로 합친다.
  ///
  /// `bool _initialized` 플래그만 두면, 설정 화면의 권한 조회와 목록 변화에 따른 예약이
  /// 겹칠 때 **초기화가 두 번 돌아** 채널 생성·타임존 설정이 중복 실행된다. 실패하면
  /// 캐시를 비워 다음 호출이 다시 시도하게 한다.
  Future<void>? _initialization;

  /// 플러그인·타임존을 1회 초기화한다.
  ///
  /// 타임존을 따로 잡는 이유: `zonedSchedule`은 [tz.TZDateTime]을 요구하는데, 기본
  /// 로컬 로케이션은 UTC라 그대로 두면 **예약이 한국 시간 기준으로 9시간 어긋난다**
  /// (오전 9시 알림이 저녁 6시에 온다).
  Future<void> _ensureInitialized() async {
    final Future<void>? existing = _initialization;
    if (existing != null) return existing;

    final Future<void> started = _initialize();
    _initialization = started;
    try {
      await started;
    } catch (_) {
      _initialization = null; // 다음 호출이 다시 시도하도록 캐시를 비운다.
      rethrow;
    }
  }

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    try {
      final TimezoneInfo info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // 타임존 이름을 못 얻거나 DB에 없는 이름이면 UTC로 남는다. 알림 시각이 어긋날
      // 뿐 앱이 죽을 이유는 없으므로 삼키되, 원인을 알 수 있게 남긴다.
      debugPrint('KeepCon: 로컬 타임존 확인 실패 — UTC로 진행합니다. ($e)');
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        expiryChannelId,
        expiryChannelName,
        description: expiryChannelDescription,
        importance: Importance.defaultImportance,
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<NotificationPermissionStatus> requestPermission() async {
    await _ensureInitialized();
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return NotificationPermissionStatus.unsupported;

    final bool granted =
        await android.requestNotificationsPermission() ?? false;
    return granted
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied;
  }

  @override
  Future<NotificationPermissionStatus> currentPermission() async {
    await _ensureInitialized();
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return NotificationPermissionStatus.unsupported;

    final bool enabled = await android.areNotificationsEnabled() ?? false;
    return enabled
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied;
  }

  @override
  Future<int> sync(List<Gifticon> gifticons) async {
    await _ensureInitialized();

    // 권한이 없으면 예약해도 뜨지 않는다. 조용히 빠져나가되 기존 예약은 정리한다
    // (사용자가 설정에서 알림을 끈 경우 잔여 예약을 남겨둘 이유가 없다).
    if (await currentPermission() != NotificationPermissionStatus.granted) {
      await cancelAll();
      return 0;
    }

    final List<ScheduledExpiryNotification> plan =
        planExpiryNotifications(gifticons);

    await cancelAll();
    for (final ScheduledExpiryNotification n in plan) {
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: tz.TZDateTime.from(n.scheduledAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            expiryChannelId,
            expiryChannelName,
            channelDescription: expiryChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        // 정확 알람(setExactAndAllowWhileIdle)을 쓰지 않는 이유: Android 12+에서
        // `SCHEDULE_EXACT_ALARM` 특별 권한 화면을 따로 거쳐야 하는데, "만료 3일 전
        // 오전 9시"가 Doze로 수십 분 밀리는 것은 무해하다. 권한 마찰을 살 이유가 없다.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: n.gifticonId,
      );
    }
    return plan.length;
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _plugin.cancelAll();
  }
}
