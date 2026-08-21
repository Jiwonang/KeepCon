/// share 페이지 — Riverpod 상태(공유 계약 소비).
///
/// 프로토타입 `ShareStore`(ChangeNotifier 싱글턴)를 **계약 소비형 Riverpod 파이프라인**으로
/// 교체한 것이다. 여기의 provider는 모두 `lib/shared/providers/repositories.dart`의 **SSOT**
/// provider([shareRepositoryProvider]/[authRepositoryProvider]/[gifticonRepositoryProvider])를
/// `watch`해 **같은 인스턴스**를 소비한다(재선언 금지 — 인스턴스 분기 방지).
///
/// 계약 준수:
/// - 행위자/멤버 식별 = 세션 정본 [sessionUserProvider]
///   (`lib/shared/providers/session_provider.dart`)를 **직접** 소비한다(페이지 별칭 없음).
///   세션 재구독(invalidate) 대상도 그 정본이다 — [_retrySessionIfFailed] 참조.
/// - 그룹/공유/이력/알림은 [ShareRepository]의 watch 스트림을 구독한다.
/// - **내 그룹 목록은 계약 정본 [myGroupsProvider]**
///   (`lib/shared/providers/my_groups_provider.dart`)를 소비한다 — 이 페이지에서 세션→
///   `watchGroups` 체인을 다시 조립하지 않는다. scan 페이지도 같은 정본을 보므로 두
///   페이지의 구독이 하나로 합쳐진다(승격 전에는 같은 사용자에 대해 `watchGroups`가
///   2번 구독됐다). 노출 형태(`AsyncValue` 전파)는 정본이 이미 이 페이지 규약과 같아
///   파생 없이 그대로 쓴다.
/// - 공유 후보(내 기프티콘)는 원본 [Gifticon]을 [GifticonRepository.watchGifticons]로 받는다
///   (프로토타입의 `MyGifticon` 폐기).
/// - 표시 이름/상대 시각 포맷은 소비자(UI) 책임 — userId→이름 해석은 [memberNamesProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/join_request.dart';
import '../../../shared/models/share.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/my_groups_provider.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
import '../../../shared/providers/shared_gifticons_provider.dart';

// 세션은 계약 정본 [sessionUserProvider]를 각 파생·화면이 직접 `watch` 한다(경과 조치였던
// 페이지 별칭 `shareCurrentUserProvider`는 제거됨 — 매트릭스 #13).
// 정본은 autoDispose지만 이 파일의 keepAlive 파생들이 그것을 watch하므로, share 탭을
// 한 번 연 뒤로는 별칭이 하던 것과 동일하게 컨테이너 수명 동안 구독이 유지된다.
//
// **id만 쓰는 소비 지점은 `select`로 좁힌다.** 정본은 [StreamProvider]라 같은 값이 다시
// 방출돼도(Firebase `userChanges()`의 토큰 갱신 등) 리스너에게 통지한다 — 삭제된 별칭이
// [Provider]의 `!=` 비교로 흡수하던 몫이다. 세션 [AsyncValue] 전체가 필요한 폴딩 3곳만
// provider를 통째로 watch하고, 나머지(읽는 값이 `user?.id` 뿐인 곳)는 select로 거른다.
//
// 세션 파생들의 폴딩은 계약 정본 [foldSessionUser](`session_provider.dart`)를 그대로
// 소비한다 — 정본 [myGroupsProvider]와 같은 한 구현이라, 같은 세션 순단에 그룹 목록만
// 멀쩡하고 알림·이력·후보가 비워지는 축 간 비대칭(QA [medium 1])이 구조적으로 불가능하다.
// `.when`을 쓰지 않는 이유·분기 순서(에러를 로딩보다 먼저 — 재시도 중 배너 유지)·
// 미로그인 확정 = AsyncData(빈 값) 보존(알림 읽음 가드가 의존)은 정본 dartdoc이 규정한다.

// 대기 중 초대코드(`pendingInviteTokenProvider`)는 계약 정본
// `shared/providers/deep_link_providers.dart`의 `pendingDestinationProvider`로 승격됐다.
// 초대는 이제 목적지 하나의 형태(`InviteDestination`)이며, 알림 탭 등 다른 신호와 같은
// 통로를 쓴다. 별칭(재export shim)은 남기지 않는다 — 두 이름이 살아 있으면 수신부마다
// 다른 쪽에 쓰게 되어 인스턴스가 갈린다(매트릭스 #13 규약).

/// id로 내 그룹 단건 조회. 로딩은 로딩으로 전파하고, data(null)은 "그룹 없음"
/// (나가기/삭제/이전으로 멤버십이 사라진 경우 포함)을 뜻한다. 소비 페이지는 로딩과
/// 데이터-null을 구분해 로딩 중엔 pop 하지 않는다.
final groupByIdProvider =
    Provider.family<AsyncValue<Group?>, String>((ref, groupId) {
  return ref.watch(myGroupsProvider).whenData((List<Group> groups) {
    for (final Group g in groups) {
      if (g.id == groupId) return g;
    }
    return null;
  });
});

// [sharedGifticonsProvider]·[allSharedProvider]는 계약 정본으로 승격됐다
// (`lib/shared/providers/shared_gifticons_provider.dart`) — main 상세가 "이 기프티콘이
// 공유 중인가"를 물어야 하는 두 번째 소비자가 됐기 때문이다. 별칭(재export shim)을 남기지
// 않고 선언을 삭제한 뒤 정본을 직수입한다(#13 규약). 이 파일의 나머지 파생들은 import된
// 정본을 그대로 `watch`하므로 호출 형태는 승격 전과 같다.

/// id로 공유 항목 단건 조회(내 그룹들을 가로질러 탐색). 공유취소 등으로 사라지면 null.
final sharedItemByIdProvider =
    Provider.family<SharedGifticon?, String>((ref, itemId) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
  for (final Group g in groups) {
    final List<SharedGifticon> list =
        ref.watch(sharedGifticonsProvider(g.id)).valueOrNull ??
            const <SharedGifticon>[];
    for (final SharedGifticon s in list) {
      if (s.id == itemId) return s;
    }
  }
  return null;
});

/// 특정 사용자의 사용 이력 스트림(내부용).
final _usageLogsByUserProvider =
    StreamProvider.family<List<UsageLog>, String>((ref, userId) {
  return ref.watch(shareRepositoryProvider).watchUsageLogs(userId);
});

/// 내가 속한 그룹들의 사용 이력(최신순). 폴딩 규약은 [foldSessionUser] — 로딩은 로딩으로
/// 전파, 미로그인 확정만 빈 목록, 세션 순단(보존 user)에는 목록을 유지한다.
final usageLogsProvider = Provider<AsyncValue<List<UsageLog>>>((ref) {
  return foldSessionUser<List<UsageLog>>(
    ref.watch(sessionUserProvider),
    (User user) => ref.watch(_usageLogsByUserProvider(user.id)),
    signedOut: const <UsageLog>[],
  );
});

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

/// 특정 사용자의 원본 기프티콘 스트림(내부용).
final _gifticonsByUserProvider =
    StreamProvider.family<List<Gifticon>, String>((ref, userId) {
  return ref.watch(gifticonRepositoryProvider).watchGifticons(userId);
});

/// 내 원본 기프티콘 목록(원본 [Gifticon]을 그대로 소비). 폴딩 규약은 [foldSessionUser] —
/// 로딩은 로딩으로 전파, 미로그인 확정만 빈 목록, 세션 순단에는 후보 계산을 계속한다
/// (그러지 않으면 세션 순단만으로 공유 시트에 배너가 뜬다 — QA [medium 1] ③).
final shareableGifticonsProvider = Provider<AsyncValue<List<Gifticon>>>((ref) {
  return foldSessionUser<List<Gifticon>>(
    ref.watch(sessionUserProvider),
    (User user) => ref.watch(_gifticonsByUserProvider(user.id)),
    signedOut: const <Gifticon>[],
  );
});

/// 공유 시트 후보 = 아직 **내 어느 그룹에도** 공유하지 않은 사용 가능한 내 기프티콘.
///
/// [shareableGifticonsProvider](내 원본 기프티콘) 중 [GifticonStatus.available]이고,
/// [allSharedProvider](내 전 그룹의 공유 항목) 집합의 [SharedGifticon.gifticonId]에 없는 것만
/// 남긴다. 이미 다른 그룹에 공유된 기프티콘을 후보에서 아예 제외해 이중 공유(이중 사용)를
/// 사전 차단하는 UX 방어선이다(저장소의 [StateError] 가드와 이중 방어).
final unsharedGifticonsProvider = Provider<List<Gifticon>>((ref) {
  final List<Gifticon> mine =
      ref.watch(shareableGifticonsProvider).valueOrNull ?? const <Gifticon>[];
  final Set<String> sharedGifticonIds = ref
      .watch(allSharedProvider)
      .map((SharedGifticon s) => s.gifticonId)
      .toSet();
  return mine
      .where((Gifticon g) =>
          g.status == GifticonStatus.available &&
          !sharedGifticonIds.contains(g.id))
      .toList(growable: false);
});

// ───────────────── 에러 표시 / 수동 재시도 (크로스페이지 주의점 #13) ─────────────────
//
// 화면들은 크래시 방지를 위해 `valueOrNull ?? []`로 폴딩한다. 폴딩된 결과에는 에러
// 정보가 남지 않으므로, 에러 감지는 **원천 AsyncValue provider**에서 해야 한다.
// 아래 파생들은 "그 화면이 보는 원천 중 하나라도 에러인가"만 bool로 요약한다
// (에러 객체는 UI로 내보내지 않는다 — 내부 메시지 비노출 규약).
//
// ⚠️ 자동 재시도는 넣지 않는다. 장애 중 전 화면이 동시에 재구독하면 retry storm이
// 되기 때문이다(#13에 명시된 근거). 재시도는 아래 `retry*` 함수로만, 즉 사용자
// 액션으로만 일어난다.

/// 내 그룹 목록(계약 정본 [myGroupsProvider])이 **표시할 값도 없이** 에러인지
/// = 그룹 축 배너를 띄울지의 단일 판정점.
///
/// `hasError`만 보지 않고 `!hasValue`를 함께 요구하는 이유: 스트림이 데이터를 한 번
/// 방출한 뒤 순단 에러가 나면 Riverpod은 `copyWithPrevious`로 이전 목록을 보존한다
/// (hasError=true인데 화면에는 그룹 목록이 멀쩡히 렌더된다). 이때까지 배너를 띄우면
/// ① 정상 표시·조회되는 목록 위에 실패 문구가 얹히고, ② 이 값을 쓰는 상세·시트가 함께
/// 발생한 공유 스트림 에러의 배너 문구까지 그룹 원인으로 오인시킨다.
///
/// **v2.6 재검토(재시도 훅 도착 후에도 판정 유지).** 승격 전에는 억제 근거가 둘이었다 —
/// (i) 되살릴 방법이 없어 배너가 앱 재시작 전까지 영구 표시된다, (ii) 멀쩡히 렌더되는
/// 목록 위에 실패를 얹지 않는다. [retryMyGroups] 도착으로 (i)은 사라졌지만 (ii)는 그대로
/// 남는다: 보존 값이 있는 동안 그룹 카드·필터 칩·단건 조회가 모두 정상 동작하므로,
/// 사용자가 취할 행동이 없는 배너를 띄울 이유가 없다(다음 방출이 성공하면 조용히 회복).
/// 따라서 판정식(`hasError && !hasValue`)은 유지한다.
///
/// **더 이상 "재시도 불가"의 뜻이 아니다.** 이 값이 true여도 배너는 [ShareErrorBanner]에
/// 실제 재시도를 넘긴다 — 계약 정본이 [retryMyGroups](세션 + 그룹 스트림 중 **에러인
/// 계층만** 재구독)를 제공하기 때문이다. 승격 전에는 에러가 정본의 private 체인에 캐시되고
/// `invalidate(myGroupsProvider)`가 dependency로 전파되지 않아(#13 실측) 배너들이
/// `onRetry`를 null로 낮췄지만, 그 강등은 전부 제거됐다.
final myGroupListUnavailableProvider = Provider<bool>((ref) {
  final AsyncValue<List<Group>> groups = ref.watch(myGroupsProvider);
  return groups.hasError && !groups.hasValue;
});

/// 그룹별 공유 스트림([sharedGifticonsProvider]) 중 하나라도 에러인지.
///
/// 내 그룹 목록([myGroupsProvider]) 자체의 에러는 **포함하지 않는다** — 그 에러는
/// 그룹 섹션이 따로 표시하고 재시도 경로도 다르기 때문이다(배너 중복 방지).
final sharedGifticonsHaveErrorProvider = Provider<bool>((ref) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
  for (final Group g in groups) {
    if (ref.watch(sharedGifticonsProvider(g.id)).hasError) return true;
  }
  return false;
});

/// 공유 기프티콘 합산 경로가 아직 **첫 방출 전**(값 없는 로딩)인지.
///
/// 콜드 스타트에는 그룹 목록·그룹별 공유 스트림이 값 없이 로딩 중인 창이 있고, 그동안
/// 폴딩된 목록은 []가 된다 — 이때 "공유된 기프티콘이 없어요"를 띄우면 **로딩을 확정
/// 부재로 위장**하는 false-empty다(에러 축과 같은 문제의 로딩 축). 빈 안내는 이 값이
/// false일 때만 띄운다. 이전 값을 보존한 재조회 로딩(hasValue)은 목록이 계속 보이므로
/// 로딩으로 치지 않는다.
final sharedGifticonsPendingProvider = Provider<bool>((ref) {
  final AsyncValue<List<Group>> groupsAsync = ref.watch(myGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) return true;
  for (final Group g in groupsAsync.valueOrNull ?? const <Group>[]) {
    final AsyncValue<List<SharedGifticon>> shared =
        ref.watch(sharedGifticonsProvider(g.id));
    if (shared.isLoading && !shared.hasValue) return true;
  }
  return false;
});

/// 공유 항목 단건 조회([sharedItemByIdProvider])의 null을 "없음"으로 믿을 수 없는 상태인지.
///
/// [sharedItemByIdProvider]는 내 그룹 목록 × 그룹별 공유 목록을 가로질러 탐색하므로,
/// 둘 중 어느 쪽이 에러여도 결과가 null이 된다 — 이때의 null은 "공유취소로 사라짐"이
/// 아니라 **조회 실패**다. 상세 화면은 이 값으로 두 경우를 구분한다.
final sharedItemLookupHasErrorProvider = Provider<bool>((ref) {
  return ref.watch(myGroupListUnavailableProvider) ||
      ref.watch(sharedGifticonsHaveErrorProvider);
});

/// 공유 시트 후보([unsharedGifticonsProvider]) 계산 경로에 에러가 있는지.
///
/// 후보 = 내 기프티콘 − 이미 공유된 것. 어느 쪽이 에러여도 후보 목록이 틀린다
/// (내 기프티콘 실패 → 후보 0개로 "없어요" 오인 / 공유 목록 실패 → 이미 공유된 항목이
/// 다시 후보에 노출). 저장소의 [StateError] 가드가 최후 방어선이지만, 사용자가 이유를
/// 모른 채 실패를 겪지 않도록 시트에서 미리 알린다.
final shareCandidatesHaveErrorProvider = Provider<bool>((ref) {
  return ref.watch(shareableGifticonsProvider).hasError ||
      ref.watch(sharedItemLookupHasErrorProvider);
});

/// 세션 스트림이 에러일 때만 재구독한다(정상일 땐 건드리지 않아 불필요한 리빌드 방지).
///
/// 대상은 **계약 정본 [sessionUserProvider]** 다(share는 그것을 직접 소비한다 — 통과
/// 별칭을 두면 invalidate가 dependents 방향으로만 전파돼 원천이 재구독되지 않는다).
/// 세션은 share 탭 전반이 watch하므로 멀쩡한 세션을 invalidate하면 화면 전체가 잠깐
/// 로딩으로 깜빡인다. 알림/이력/기프티콘 스트림은 모두 세션 뒤에 붙으므로, 세션이
/// 에러면 그것부터 되살려야 하위 재시도가 의미를 갖는다.
///
/// 계약 훅 [retryMyGroups]도 세션 계층을 같은 규칙(에러일 때만)으로 되살린다. 둘의 차이는
/// **범위**뿐이다 — 그룹 축이 재시도 대상에 포함된 경로(그룹 목록·단건 조회·공유 후보)는
/// [retryMyGroups]가 세션+그룹을 함께 맡고, 그룹과 무관한 경로(알림·이력·그룹별 공유
/// 스트림)는 이 함수가 세션만 맡는다. 한 번의 사용자 액션에서 둘을 겹쳐 부르지 않는다
/// (겹치면 이미 재구독 중인 세션을 한 번 더 끊었다 잇는다).
void _retrySessionIfFailed(WidgetRef ref) {
  // 검사용 read를 [WidgetRef.exists]로 가드한다(계약 훅 [MyGroupsRetry.retry]와 같은
  // 근거): `read`는 살아 있지 않은 autoDispose 인스턴스를 새로 만들어 실제 스트림을
  // 구독하므로, 세션 체인이 마운트되지 않은 컨텍스트에서 호출되면 검사가 곧 낭비
  // 구독이 된다. 존재하지 않는 인스턴스엔 캐시된 에러도 있을 수 없어 판정으로도 정확하다.
  if (!ref.exists(sessionUserProvider)) return;
  if (ref.read(sessionUserProvider).hasError) {
    ref.invalidate(sessionUserProvider);
  }
}

// 에러인 그룹별 공유 스트림만 재구독하는 `_retryFailedSharedInstances`는 계약 정본
// [retryFailedSharedGifticonStreams](`lib/shared/providers/shared_gifticons_provider.dart`)로
// 승격됐다 — main 상세도 같은 축을 되살려야 하는 두 번째 소비자가 됐다. 사본을 남기면
// 한쪽만 손볼 때 갈라지므로 선언을 삭제하고 정본을 직수입한다(#13 규약).

/// 알림 스트림 수동 재시도 — **에러인** 원천만 invalidate해 재구독한다.
///
/// 읽음 시각 스트림까지 무조건 invalidate하면 정상 동작 중인 리스너가 해제·재구독되고,
/// 그 갭 동안 [notificationsReadAtProvider]가 null로 접혀 안읽음 뱃지가 잠깐
/// 전체-안읽음으로 튄다 — 배너의 원인이 아닌 스트림은 건드리지 않는다.
void retryNotifications(WidgetRef ref) {
  _retrySessionIfFailed(ref);
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

/// 사용 이력 스트림 수동 재시도(에러일 때만 재구독 — [retryNotifications]와 같은 원칙).
void retryUsageLogs(WidgetRef ref) {
  _retrySessionIfFailed(ref);
  final User? user = ref.read(sessionUserProvider).valueOrNull;
  if (user == null) return;
  if (ref.read(_usageLogsByUserProvider(user.id)).hasError) {
    ref.invalidate(_usageLogsByUserProvider(user.id));
  }
}

/// 그룹별 공유 기프티콘 스트림 수동 재시도.
///
/// [groupId]를 주면 **그 그룹 인스턴스만** 재구독한다(그룹 상세처럼 한 그룹만 보는
/// 화면 — 에러 여부와 무관하게 사용자가 그 그룹을 명시적으로 되살리는 의미). 인자가
/// 없으면(share 메인·공유 상세처럼 전 그룹을 합쳐 보는 화면) **에러인 인스턴스만**
/// 골라 재구독한다 — 합쳐 보는 화면이라도 재시도가 필요한 건 실패한 스트림뿐이다
/// ([retryFailedSharedGifticonStreams]의 근거 참조).
void retrySharedGifticons(WidgetRef ref, {String? groupId}) {
  _retrySessionIfFailed(ref);
  if (groupId != null) {
    ref.invalidate(sharedGifticonsProvider(groupId));
    return;
  }
  retryFailedSharedGifticonStreams(ref);
}

/// 공유 항목 단건 조회([sharedItemByIdProvider]) 실패의 수동 재시도.
///
/// 조회는 **내 그룹 목록 × 그룹별 공유 목록**을 가로지르므로 실패 원인이 두 축 중
/// 어느 쪽이든 될 수 있다([sharedItemLookupHasErrorProvider]가 그 합집합이다). 그래서
/// 두 축을 함께 되살린다 — 각 축은 여전히 **에러인 계층만** 재구독하므로(계약
/// [retryMyGroups] + [retryFailedSharedGifticonStreams]) 멀쩡한 스트림은 건드리지 않는다.
///
/// 세션 계층은 [retryMyGroups]가 맡으므로 [_retrySessionIfFailed]를 겹쳐 부르지 않는다.
void retrySharedItemLookup(WidgetRef ref) {
  retryMyGroups(ref);
  retryFailedSharedGifticonStreams(ref);
}

/// 공유 시트 후보 수동 재시도 — 후보 계산 경로(내 기프티콘 + 내 그룹 목록 + 그룹별
/// 공유 목록) 중 **에러인 원천만** 되살린다(한쪽만 실패해도 배너는 뜨지만, 멀쩡한
/// 반대쪽 스트림을 재구독할 이유는 없다).
///
/// 그룹 목록이 경로에 포함되는 이유: 후보 = 내 기프티콘 − 이미 공유된 것이고, "이미
/// 공유된 것"은 내 그룹들을 가로질러 모은다([shareCandidatesHaveErrorProvider]가
/// [sharedItemLookupHasErrorProvider]를 포함하는 것과 같은 이유). 세션 계층은
/// [retryMyGroups]가 맡는다(중복 호출 방지 — [_retrySessionIfFailed] 참조).
void retryShareCandidates(WidgetRef ref) {
  // 후보 에러 판정([shareCandidatesHaveErrorProvider])이 lookup 판정을 포함하듯,
  // 재시도도 lookup 재시도를 **합성**한다 — 감지와 재시도가 1:1로 대응해, lookup
  // 축에 계층이 추가될 때 한쪽만 갱신되는 비대칭이 생기지 않는다.
  retrySharedItemLookup(ref);
  final User? user = ref.read(sessionUserProvider).valueOrNull;
  if (user != null && ref.read(_gifticonsByUserProvider(user.id)).hasError) {
    ref.invalidate(_gifticonsByUserProvider(user.id));
  }
}

/// userId → 표시 이름 해석기. 내 그룹들의 멤버 정보로 조립한다.
///
/// 계약 모델은 [User.id]만 저장하므로(이름 문자열 저장을 폐기), 표시용 이름은 소비자가
/// 멤버 정보로 해석한다. 본인은 '나'로 표시한다.
final memberNamesProvider = Provider<MemberNames>((ref) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
  // 본인 판별에 쓰는 값이 id 뿐이므로 `select`로 좁힌다. [MemberNames]는 `==`가 없어
  // 재계산이 곧 새 인스턴스 = 소비 위젯 리빌드이므로, 같은 사용자 재방출(토큰 갱신 등)에
  // 반응하지 않게 거르는 것이 특히 중요하다.
  final String? currentUserId = ref.watch(
    sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
  );
  final Map<String, String> byId = <String, String>{};
  for (final Group g in groups) {
    for (final GroupMember m in g.members) {
      byId[m.userId] = m.displayName;
    }
  }
  return MemberNames(byId: byId, currentUserId: currentUserId);
});

/// userId를 표시 이름으로 바꾸는 해석기(불변).
class MemberNames {
  /// [byId]는 멤버 id→표시 이름, [currentUserId]는 현재 사용자 id(본인 판별용).
  const MemberNames({
    required Map<String, String> byId,
    required String? currentUserId,
  })  : _byId = byId,
        _currentUserId = currentUserId;

  final Map<String, String> _byId;
  final String? _currentUserId;

  /// [userId]가 현재 사용자(나)인지.
  bool isMe(String userId) =>
      _currentUserId != null && userId == _currentUserId;

  /// 표시 이름. 본인은 '나', 아는 멤버는 [GroupMember.displayName], 모르면 [fallback].
  String labelFor(String userId, {String fallback = '멤버'}) {
    if (isMe(userId)) return '나';
    return _byId[userId] ?? fallback;
  }
}

/// Scan 페이지에서 저장 대상 그룹 목록 선택 시 소비하는 프로바이더.
///
/// 계약 정본인 [myGroupsProvider]를 watch하여 AsyncValue 내의 [Group] 리스트를 추출한다.
/// 로딩 중이거나 에러 발생 시 빈 리스트를 반환하여 UI 안전성을 보장한다.
final scanTargetGroupsProvider = Provider<List<Group>>((ref) {
  return ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
});

// ─── 참여 요청 ────────────────────────────────────────────────────────────
//
// 두 방향이 있고 **읽을 수 있는 사람이 서로 다르다.**
//  - 내가 보낸 요청([myJoinRequestsProvider]) — 요청자 본인만 읽는다.
//  - 그룹에 들어온 요청([pendingJoinRequestsProvider]) — **방장만** 읽는다.
//    일반 멤버에게도 열지 않는다(아직 멤버가 아닌 사람들의 이름이다 — 계약 참조).

/// 특정 사용자가 보낸 참여 요청 스트림(내부용).
final _myJoinRequestsByUserProvider =
    StreamProvider.family<List<JoinRequest>, String>((ref, userId) {
  return ref.watch(shareRepositoryProvider).watchMyJoinRequests(userId);
});

/// 내가 보낸 참여 요청(대기·거절 포함).
///
/// 거절도 여기 남는다 — 비멤버는 그룹 알림을 못 읽으므로 **요청자가 결과를 알 유일한
/// 경로**다(계약: 거절은 상태로 남기고, 취소는 삭제한다).
final joinRequestsProvider = Provider<AsyncValue<List<JoinRequest>>>((ref) {
  return foldSessionUser<List<JoinRequest>>(
    ref.watch(sessionUserProvider),
    (User user) => ref.watch(_myJoinRequestsByUserProvider(user.id)),
    signedOut: const <JoinRequest>[],
  );
});

/// 특정 그룹의 대기 중 참여 요청(방장 전용).
///
/// 방장에게 "요청이 도착했다"를 알리는 신호는 **이 스트림 하나**다 — 알림 문서로 알리려면
/// 비멤버가 `notifications`에 써야 하는데 규칙이 막는다(계약 참조). 화면은 이 스트림의
/// 길이로 배지를 그린다.
final pendingJoinRequestsProvider =
    StreamProvider.family<List<JoinRequest>, String>((ref, groupId) {
  return ref.watch(shareRepositoryProvider).watchPendingJoinRequests(groupId);
});
