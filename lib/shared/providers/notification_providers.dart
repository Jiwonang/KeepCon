/// KeepCon 공유 계약 — 알림 스케줄러 DI provider (SSOT).
///
/// 공유 provider는 반드시 이곳 정본을 소비한다. 페이지가 스케줄러를 각자 `new` 하면
/// 인스턴스가 갈려 초기화·권한 상태가 화면마다 달라진다(계약 조립 규칙).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/expiry_notification_scheduler.dart';
import '../notifications/local_expiry_notification_scheduler.dart';

/// 만료 임박 알림 스케줄러. **SSOT.**
///
/// 플랫폼별로 구현을 고른다 — 호출부가 `if (kIsWeb)` 같은 분기를 갖지 않게 하기 위해서다.
/// - **안드로이드**: 실제 로컬 알림([LocalExpiryNotificationScheduler]).
/// - **웹**: no-op. 브라우저 Notification API에는 예약 개념이 없어, 탭이 열려 있는 동안만
///   즉시 알림을 띄울 수 있다 — "앱을 꺼도 만료 전에 알려준다"는 이 기능의 목적을
///   만족시키지 못하므로 흉내내지 않는다.
/// - **iOS·데스크톱**: no-op. iOS는 이번 범위에서 제외했고(플랫폼 구성 자체가 미검증),
///   데스크톱은 Firebase 초기화부터 미구성이다.
final Provider<ExpiryNotificationScheduler>
    expiryNotificationSchedulerProvider =
    Provider<ExpiryNotificationScheduler>((Ref ref) {
  if (kIsWeb) return const NoopExpiryNotificationScheduler();
  if (defaultTargetPlatform == TargetPlatform.android) {
    return LocalExpiryNotificationScheduler();
  }
  return const NoopExpiryNotificationScheduler();
});
