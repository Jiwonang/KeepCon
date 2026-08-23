/// KeepCon 공유 계약 — 그룹 알림 목록·읽음·안읽음 수 provider (SSOT).
///
/// share 페이지 전용이던 것을 승격했다. 알림 벨은 이제 **세 화면**(공유 탭 헤더·마이페이지·
/// 홈 헤더)에 있고, 셋이 같은 안읽음 수를 보여야 한다. 페이지마다 세션→`watchNotifications`
/// 체인을 다시 조립하면 같은 사용자에 대해 스트림이 여러 번 구독되고, 한 화면에서 읽음
/// 처리한 결과가 다른 화면의 뱃지에 반영되지 않는다(승격 전 [myGroupsProvider]가 겪은 것과
/// 같은 인스턴스 분기).
///
/// 소비만 한다 — 페이지 폴더에서 재선언 금지(CLAUDE.md 핵심 규약, `tool/check_ssot.sh`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/share.dart';
import '../models/user.dart';
import 'repositories.dart';
import 'session_provider.dart';

/// 특정 사용자의 알림 스트림(내부용).
final _notificationsByUserProvider =
    StreamProvider.family<List<GroupNotification>, String>((ref, userId) {
  return ref.watch(shareRepositoryProvider).watchNotifications(userId);
});

/// 내가 속한 그룹들의 알림(최신순). 폴딩 규약은 [foldSessionUser] — 로딩은 로딩으로 전파,
/// 미로그인 확정만 빈 목록, 세션 순단(보존 user)에는 보고 있던 목록을 유지한다.
final notificationsProvider =
    Provider<AsyncValue<List<GroupNotification>>>((ref) {
  return foldSessionUser<List<GroupNotification>>(
    ref.watch(sessionUserProvider),
    (User user) => ref.watch(_notificationsByUserProvider(user.id)),
    signedOut: const <GroupNotification>[],
  );
});

/// 특정 사용자의 알림 마지막 읽음 시각 스트림(내부용).
final _notifReadAtByUserProvider =
    StreamProvider.family<DateTime?, String>((ref, userId) {
  return ref.watch(shareRepositoryProvider).watchNotificationsReadAt(userId);
});

/// 내 알림 마지막 읽음 시각. 미로그인/로딩/에러는 null로 접는다
/// (null = 전부 안읽음 판정 — 과대 표시가 과소 표시보다 안전한 보수적 방향).
final notificationsReadAtProvider = Provider<DateTime?>((ref) {
  // 읽는 값이 id 뿐이라 `select`로 좁힌다(같은 사용자 재방출에는 재계산 없음).
  final String? uid = ref.watch(
    sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
  );
  if (uid == null) return null;
  return ref.watch(_notifReadAtByUserProvider(uid)).valueOrNull;
});

/// 안읽음 알림 개수 — 마지막 읽음 시각 이후에 생성된 알림 수.
///
/// 읽음 시각이 없으면(한 번도 안 읽음) 전체가 안읽음이다. 알림 화면이 **목록을 실제로
/// 보여준 뒤**(성공 데이터 방출 후 1회 — 진입 즉시가 아니다, 계약
/// [ShareRepository.markNotificationsRead] dartdoc 참조) 읽음 시각이 갱신돼 0으로 수렴한다.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final List<GroupNotification> notifs =
      ref.watch(notificationsProvider).valueOrNull ??
          const <GroupNotification>[];
  final DateTime? readAt = ref.watch(notificationsReadAtProvider);
  if (readAt == null) return notifs.length;
  return notifs
      .where((GroupNotification n) => n.createdAt.isAfter(readAt))
      .length;
});

/// 알림 스트림 수동 재시도 — **에러인** 원천만 invalidate해 재구독한다.
///
/// 읽음 시각 스트림까지 무조건 invalidate하면 정상 동작 중인 리스너가 해제·재구독되고,
/// 그 갭 동안 [notificationsReadAtProvider]가 null로 접혀 안읽음 뱃지가 잠깐
/// 전체-안읽음으로 튄다 — 배너의 원인이 아닌 스트림은 건드리지 않는다.
void retryNotifications(WidgetRef ref) {
  retrySessionIfFailed(ref);
  final User? user = ref.read(sessionUserProvider).valueOrNull;
  // 세션이 null인 경우는 "알려진 user가 한 번도 없던" 상태뿐이다: 세션이 값을 가진 적이
  // 있으면 에러 전이도, 위 invalidate 직후의 로딩 전이도 copyWithPrevious로 값을
  // 보존하므로 valueOrNull이 그 user를 계속 돌려준다(하위 스코프 재시도 진행). user가
  // 없었다면 하위 family 인스턴스도 만들어진 적이 없어 되살릴 대상 자체가 없다 —
  // 세션이 회복되면 하위가 함께 재구성된다.
  if (user == null) return;
  if (ref.read(_notificationsByUserProvider(user.id)).hasError) {
    ref.invalidate(_notificationsByUserProvider(user.id));
  }
  if (ref.read(_notifReadAtByUserProvider(user.id)).hasError) {
    ref.invalidate(_notifReadAtByUserProvider(user.id));
  }
}
