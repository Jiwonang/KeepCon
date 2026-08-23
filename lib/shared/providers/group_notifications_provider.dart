/// KeepCon 공유 계약 — 알림 센터 provider (SSOT).
///
/// share 페이지 전용이던 것을 승격했다. 알림 벨은 이제 **세 화면**(공유 탭 헤더·마이페이지·
/// 홈 헤더)에 있고, 셋이 같은 안읽음 수를 보여야 한다. 페이지마다 세션→`watchNotifications`
/// 체인을 다시 조립하면 같은 사용자에 대해 스트림이 여러 번 구독되고, 한 화면에서 읽음
/// 처리한 결과가 다른 화면의 뱃지에 반영되지 않는다(승격 전 [myGroupsProvider]가 겪은 것과
/// 같은 인스턴스 분기).
///
/// 목록 정본은 [allNotificationsProvider]다 — 저장된 그룹 알림과 **계산으로 복원한**
/// 개인 만료 알림을 합친다(두 출처의 성질 차이는 [AppNotification] dartdoc).
///
/// 소비만 한다 — 페이지 폴더에서 재선언 금지(CLAUDE.md 핵심 규약, `tool/check_ssot.sh`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../models/gifticon.dart';
import '../models/share.dart';
import '../models/user.dart';
import '../notifications/expiry_notification_plan.dart';
import 'raw_gifticons_provider.dart';
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

/// 알림 센터 목록 — 그룹 알림 + 개인 만료 알림을 최신순으로 합친 **정본**.
///
/// 두 출처의 성질 차이는 [AppNotification] dartdoc에 있다. 요약하면 그룹 알림은 저장된
/// 문서고, 개인 만료 알림은 내 기프티콘에서 **계산해 복원**한 것이다.
///
/// 그룹 알림 축의 로딩/에러를 그대로 전파한다 — 파생 축은 실패할 수 없으므로(순수 계산)
/// 목록이 못 뜨는 이유는 언제나 그룹 알림 스트림이다. 파생 축이 값을 냈다고 해서 그룹
/// 알림의 에러를 감추면, 배너 없이 **일부만 빠진 목록**이 정상처럼 보인다.
final allNotificationsProvider =
    Provider<AsyncValue<List<AppNotification>>>((ref) {
  final DateTime now = DateTime.now();
  // 파생 축은 원천 목록만 있으면 계산된다. 값이 아직 없으면(로딩·미로그인) 빈 목록으로
  // 두고 그룹 알림 축의 상태를 그대로 따른다.
  final List<Gifticon> gifticons =
      ref.watch(rawGifticonsProvider).valueOrNull ?? const <Gifticon>[];
  final List<ExpiryNotificationItem> expiry =
      firedExpiryNotifications(gifticons, now: now);

  return ref.watch(notificationsProvider).whenData(
    (List<GroupNotification> groupNotifs) {
      final List<AppNotification> merged = <AppNotification>[
        for (final GroupNotification n in groupNotifs) GroupNotificationItem(n),
        ...expiry,
      ];
      // 최신순. 같은 시각이면 id로 안정 정렬한다(순서가 흔들리면 같은 데이터에도 목록이
      // 달라 보이고, 위젯 재사용이 어긋나 스크롤이 튄다).
      merged.sort((AppNotification a, AppNotification b) {
        final int byTime = b.createdAt.compareTo(a.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
      return merged;
    },
  );
});

/// 안읽음 알림 개수 — 마지막 읽음 시각 이후에 생긴 알림 수(**두 출처 합산**).
///
/// 파생 만료 알림의 발송 시각이 정책 상수로 결정론적이라, 저장된 그룹 알림과 **같은
/// 타임스탬프 하나**([notificationsReadAtProvider])로 읽음/안읽음이 갈린다 — 파생 항목을
/// 위해 별도 읽음 저장소를 두지 않아도 되는 이유다.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final List<AppNotification> notifs =
      ref.watch(allNotificationsProvider).valueOrNull ??
          const <AppNotification>[];
  final DateTime? readAt = ref.watch(notificationsReadAtProvider);
  if (readAt == null) return notifs.length;
  return notifs
      .where((AppNotification n) => n.createdAt.isAfter(readAt))
      .length;
});
