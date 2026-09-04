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
import 'now_provider.dart';
import 'raw_gifticons_provider.dart';
import 'repositories.dart';
import 'session_provider.dart';

/// 특정 사용자의 알림 스트림(내부용).
///
/// **autoDispose다** — keepAlive면 로그아웃이 이 provider를 죽인 채 박제한다.
/// 로그아웃 순간 살아 있는 백엔드 리스너는 인증 없는 재평가에서 permission-denied로
/// 종료되는데, keepAlive는 그 에러를 앱 수명 동안 캐시하므로 같은 계정으로 재로그인해도
/// 재구독이 없다(세 화면의 알림 벨·알림 센터가 에러에 영구히 머문다). autoDispose면
/// 로그아웃 시 [notificationsProvider]의 폴딩이 세션 null로 재계산되며 이 family를 놓아
/// 구독이 해제되고, 재로그인은 새 인스턴스로 새로 구독한다.
/// `_groupsByUserProvider`(my_groups_provider.dart)와 같은 수명 규약이다.
final AutoDisposeStreamProviderFamily<List<GroupNotification>, String>
    _notificationsByUserProvider = StreamProvider.autoDispose
        .family<List<GroupNotification>, String>((ref, userId) {
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
///
/// **autoDispose다** — 근거는 [_notificationsByUserProvider]와 동일하다. 로그아웃 시
/// [notificationsReadAtProvider]가 uid null로 재계산되며 이 family를 놓아 구독이
/// 해제되고, 재로그인은 새 인스턴스로 새로 구독한다(keepAlive면 죽은 에러가 박제되어
/// `valueOrNull` 폴딩이 영구히 null — 전부 안읽음 과대 표시가 앱 수명 동안 남는다).
final AutoDisposeStreamProviderFamily<DateTime?, String>
    _notifReadAtByUserProvider =
    StreamProvider.autoDispose.family<DateTime?, String>((ref, userId) {
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

/// 알림 목록의 원천 중 **에러인 것만** invalidate해 재구독한다.
///
/// 읽음 시각 스트림까지 무조건 invalidate하면 정상 동작 중인 리스너가 해제·재구독되고,
/// 그 갭 동안 [notificationsReadAtProvider]가 null로 접혀 안읽음 뱃지가 잠깐
/// 전체-안읽음으로 튄다 — 배너의 원인이 아닌 스트림은 건드리지 않는다.
///
/// **기프티콘 원천도 대상이다.** [allNotificationsProvider]가 그 스트림의 에러로도 배너를
/// 띄우므로 여기서 빼면 그 배너의 '다시 시도'가 아무것도 되살리지 못하는 막다른 길이 된다
/// (`rawGifticonsProvider`는 keepAlive라 **같은 세션 안에서** 실패한 에러가 재시도 전까지
/// 남는다 — 로그아웃은 uid select가 create를 재실행해 스스로 버린다. 그 파일 doc 참조).
///
/// 검사용 read는 [WidgetRef.exists]로 가드한다 — 근거(read가 살아 있지 않은 인스턴스를
/// 만들어 실제 스트림을 구독; keepAlive인 rawGifticons는 그 낭비 구독이 영구 잔존)는
/// 계약 훅 `MyGroupsRetry.retry`의 dartdoc(`my_groups_provider.dart`)이 정본이다.
void retryNotifications(WidgetRef ref) {
  retrySessionIfFailed(ref);
  // 파생 축의 원천도 배너를 띄우므로 여기서 빠지면 그 배너가 막다른 길이 된다.
  // 세션과 무관한 최상위 provider라 uid 가드보다 앞에 둔다.
  if (ref.exists(rawGifticonsProvider) &&
      ref.read(rawGifticonsProvider).hasError) {
    ref.invalidate(rawGifticonsProvider);
  }
  if (!ref.exists(sessionUserProvider)) return;
  final User? user = ref.read(sessionUserProvider).valueOrNull;
  // 세션이 null인 경우는 "알려진 user가 한 번도 없던" 상태뿐이다: 세션이 값을 가진 적이
  // 있으면 에러 전이도, 위 invalidate 직후의 로딩 전이도 copyWithPrevious로 값을
  // 보존하므로 valueOrNull이 그 user를 계속 돌려준다(하위 스코프 재시도 진행). user가
  // 없었다면 하위 family 인스턴스도 만들어진 적이 없어 되살릴 대상 자체가 없다 —
  // 세션이 회복되면 하위가 함께 재구성된다.
  if (user == null) return;
  final AutoDisposeStreamProvider<List<GroupNotification>> notifs =
      _notificationsByUserProvider(user.id);
  if (ref.exists(notifs) && ref.read(notifs).hasError) {
    ref.invalidate(notifs);
  }
  final AutoDisposeStreamProvider<DateTime?> readAt =
      _notifReadAtByUserProvider(user.id);
  if (ref.exists(readAt) && ref.read(readAt).hasError) {
    ref.invalidate(readAt);
  }
}

/// 알림 센터 목록 — 그룹 알림 + 개인 만료 알림을 최신순으로 합친 **정본**.
///
/// 두 출처의 성질 차이는 [AppNotification] dartdoc에 있다. 요약하면 그룹 알림은 저장된
/// 문서고, 개인 만료 알림은 내 기프티콘에서 **계산해 복원**한 것이다.
///
/// **에러여도 파생 항목은 지우지 않는다.** 파생 축은 로컬 계산이라 네트워크와 무관한데,
/// 그룹 스트림의 에러를 목록 전체에 전파하면 오프라인일 때 방금 받은 만료 알림까지 함께
/// 사라진다 — 이 기능이 고치려던 증상 그대로다. 그래서 에러 상태는 [AsyncError]로 유지해
/// 배너를 띄우되(일부만 빠진 목록을 정상으로 위장하지 않는다), 값 자리에는 파생 항목이
/// 담긴 목록을 실어 둔다. 화면의 읽음 가드는 [AsyncData]만 "봤다"로 인정하므로, 이렇게
/// 해도 못 본 그룹 알림이 읽음 처리되지 않는다.
///
/// **첫 로딩은 값 없이 전파한다.** 파생 항목을 먼저 보여주면 목록이 [AsyncData]가 되어
/// 읽음 가드가 열리는데, 그 순간 아직 도착하지 않은 그룹 알림까지 읽음으로 찍혀 유실된다.
final allNotificationsProvider =
    Provider<AsyncValue<List<AppNotification>>>((ref) {
  // 시각은 계약 정본 [nowProvider]에서 받는다. `DateTime.now()`를 직접 읽으면 ①이
  // provider가 캐시되므로 목록이 **최초 계산 시점에 얼어붙고**(앱을 켜 둔 채 알림이
  // 울려도 목록에 안 나타난다) ②홈의 만료 임박 판정과 다른 "오늘"을 볼 수 있다
  // (정본 dartdoc이 기록한 실제 사고).
  final DateTime now = ref.watch(nowProvider);
  final AsyncValue<List<Gifticon>> gifticonsAsync =
      ref.watch(rawGifticonsProvider);
  final AsyncValue<List<GroupNotification>> groupAsync =
      ref.watch(notificationsProvider);

  // 파생 축의 **첫 방출 전**에는 값 없이 로딩을 전파한다. 로딩을 빈 목록으로 접으면
  // 그룹 축이 먼저 도착하는 순간 목록이 [AsyncData]가 되어 읽음 가드가 열리고, 뒤늦게
  // 합류하는 파생 항목은 `createdAt`이 `readAt`(그 순간의 벽시계)보다 과거라 **영구히
  // 읽음**이 된다 — 아래 그룹 축에 대해 막아 둔 사고의 대칭형이다. 한쪽만 막으면
  // 뱃지를 살리려던 기능이 뱃지를 지운다.
  if (!gifticonsAsync.hasValue && !gifticonsAsync.hasError) {
    return const AsyncLoading<List<AppNotification>>();
  }

  final List<ExpiryNotificationItem> expiry = firedExpiryNotifications(
    gifticonsAsync.valueOrNull ?? const <Gifticon>[],
    now: now,
  );

  List<AppNotification> merge(List<GroupNotification> groupNotifs) {
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
  }

  // **두 축 중 어느 쪽이 에러여도** 배너를 띄운다. 파생 축의 원천인 `rawGifticonsProvider`도
  // Firestore 스트림이라 실패할 수 있는데, 그것을 안 보면 만료 알림이 배너 없이 조용히
  // 사라진다("파생은 로컬 계산이라 무관"은 **계산**에만 맞는 말이고 원천에는 틀리다).
  final AsyncValue<Object?> failed =
      groupAsync.hasError ? groupAsync : gifticonsAsync;
  if (failed.hasError) {
    // 에러를 유지한 채(배너) 지금 가진 것을 값 자리에 싣는다 — 순단 중 보고 있던
    // 목록이 사라지지 않는다. 읽음 가드는 [AsyncData]만 "봤다"로 인정하므로 못 본
    // 알림이 읽음 처리되지도 않는다.
    return AsyncError<List<AppNotification>>(
      failed.error!,
      failed.stackTrace ?? StackTrace.current,
    ).copyWithPrevious(
      AsyncData<List<AppNotification>>(
        merge(groupAsync.valueOrNull ?? const <GroupNotification>[]),
      ),
    );
  }

  return groupAsync.whenData(merge);
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
