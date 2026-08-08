/// KeepCon 공유 계약 — 만료 임박 알림 스케줄러 인터페이스.
///
/// 계획 계산([planExpiryNotifications])과 **실제 예약**을 가르는 경계다. 페이지·조립부는
/// 이 인터페이스에만 의존하고, 구현체(안드로이드 로컬 알림 / no-op)는 조립 시점에 고른다
/// — Repository 계약과 같은 규약이다.
library;

import '../models/gifticon.dart';

/// 알림 권한 상태.
///
/// 안드로이드 13부터 알림은 런타임 권한이라, "예약했는데 안 온다"의 원인 대부분이
/// 여기다. 설정 화면이 사용자에게 지금 어느 상태인지 보여줄 수 있어야 한다.
enum NotificationPermissionStatus {
  /// 허용됨 — 예약한 알림이 뜬다.
  granted,

  /// 거부됨 — 예약해도 뜨지 않는다. 시스템 설정에서 켜야 한다.
  denied,

  /// 이 플랫폼에서 로컬 알림을 지원하지 않는다(웹·데스크톱).
  unsupported,
}

/// 만료 임박 알림 예약 계약.
abstract class ExpiryNotificationScheduler {
  /// 알림 권한을 요청하고 결과를 반환한다. 이미 허용돼 있으면 그대로 돌려준다.
  Future<NotificationPermissionStatus> requestPermission();

  /// 요청 없이 현재 권한 상태만 조회한다.
  Future<NotificationPermissionStatus> currentPermission();

  /// [gifticons] 기준으로 예약을 **현재 상태에 맞춘다**(전량 취소 후 재예약).
  ///
  /// 증분 갱신이 아니라 전량 교체인 이유: 목록 변화는 추가뿐 아니라 삭제·사용 완료·
  /// 만료일 수정으로도 오는데, 그때마다 "어떤 예약을 지워야 하는가"를 추적하면 상태가
  /// 두 벌(앱과 OS)이 되어 갈라진다. 예약 건수가 [maxScheduledExpiryNotifications]
  /// 수준이라 전량 교체 비용이 문제되지 않는다.
  ///
  /// 권한이 없거나 지원되지 않는 플랫폼이면 조용히 no-op이다(호출부가 분기하지 않아도 된다).
  /// 예약한 알림 건수를 반환한다.
  Future<int> sync(List<Gifticon> gifticons);

  /// 예약된 알림을 모두 취소한다. 로그아웃 시 호출한다 — 계정을 바꿨는데 이전 사용자의
  /// 기프티콘 알림이 뜨면 안 된다.
  Future<void> cancelAll();

  /// 사용자가 알림을 탭할 때마다 그 알림의 [Gifticon.id]를 방출한다.
  ///
  /// **앱이 이미 떠 있을 때** 탭한 경우를 위한 것이다. 앱이 알림으로 처음 뜬 경우는
  /// 이 스트림이 구독되기 전에 이벤트가 지나가므로 [takeLaunchPayload]로 따로 받는다
  /// (딥링크의 웜 스타트/콜드 스타트와 같은 구조다).
  Stream<String> get notificationTaps;

  /// 앱을 띄운 알림의 [Gifticon.id]. 알림으로 열린 것이 아니면 `null`.
  ///
  /// **1회성** — 한 번 읽으면 비워진다. 비우지 않으면 로그아웃 후 다시 로그인할 때마다
  /// 같은 기프티콘으로 다시 끌려간다.
  Future<String?> takeLaunchPayload();
}

/// 아무것도 하지 않는 구현. 웹·데스크톱과 위젯 테스트에서 쓴다.
///
/// 플랫폼 미지원을 호출부의 `if (kIsWeb)` 분기로 처리하면 그 분기가 화면마다 번진다.
/// 대신 조립부가 구현체를 고르고, 호출부는 언제나 같은 코드를 쓴다.
class NoopExpiryNotificationScheduler implements ExpiryNotificationScheduler {
  /// NoopExpiryNotificationScheduler 인스턴스를 생성한다.
  const NoopExpiryNotificationScheduler();

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.unsupported;

  @override
  Future<NotificationPermissionStatus> currentPermission() async =>
      NotificationPermissionStatus.unsupported;

  @override
  Future<int> sync(List<Gifticon> gifticons) async => 0;

  @override
  Future<void> cancelAll() async {}

  @override
  Stream<String> get notificationTaps => const Stream<String>.empty();

  @override
  Future<String?> takeLaunchPayload() async => null;
}
