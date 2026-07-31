/// share 페이지 — Riverpod 상태(공유 계약 소비).
///
/// 프로토타입 `ShareStore`(ChangeNotifier 싱글턴)를 **계약 소비형 Riverpod 파이프라인**으로
/// 교체한 것이다. 여기의 provider는 모두 `lib/shared/providers/repositories.dart`의 **SSOT**
/// provider([shareRepositoryProvider]/[authRepositoryProvider]/[gifticonRepositoryProvider])를
/// `watch`해 **같은 인스턴스**를 소비한다(재선언 금지 — 인스턴스 분기 방지).
///
/// 계약 준수:
/// - 행위자/멤버 식별 = [AuthRepository.currentUser]([shareCurrentUserProvider]).
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
import '../../../shared/models/share.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/my_groups_provider.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/util/invite_link.dart';

/// 현재 로그인 사용자(행위자). SSOT [authRepositoryProvider]를 구독한다.
final shareCurrentUserProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// 딥링크로 진입한 대기 중 초대코드(1회성).
///
/// 앱 시작 시 진입 URL([Uri.base])에서 시드된다([pendingInviteCodeFromPlatform]).
/// 셸이 로그인 후 이 코드를 소비해 참여 시트를 열고 `null`로 비운다(재진입 시 재실행 방지).
/// 테스트/조립부에서 override로 주입할 수 있다.
final pendingInviteCodeProvider =
    StateProvider<String?>((ref) => pendingInviteCodeFromPlatform());

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

/// 특정 그룹의 공유 기프티콘 스트림.
final sharedGifticonsProvider =
    StreamProvider.family<List<SharedGifticon>, String>((ref, groupId) {
  return ref.watch(shareRepositoryProvider).watchSharedGifticons(groupId);
});

/// 내 모든 그룹을 가로지른 공유 기프티콘(공유 메인 요약용).
///
/// 각 그룹별 [sharedGifticonsProvider]를 `watch`해 합친다. 어느 그룹의 스트림이 바뀌거나
/// 내 그룹 집합이 바뀌면 자동 재계산된다(리액티브 결합).
final allSharedProvider = Provider<List<SharedGifticon>>((ref) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
  final List<SharedGifticon> out = <SharedGifticon>[];
  for (final Group g in groups) {
    out.addAll(
      ref.watch(sharedGifticonsProvider(g.id)).valueOrNull ??
          const <SharedGifticon>[],
    );
  }
  return out;
});

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

/// 내가 속한 그룹들의 사용 이력(최신순). 로딩은 로딩으로 전파, data(null)만 빈 목록.
final usageLogsProvider = Provider<AsyncValue<List<UsageLog>>>((ref) {
  return ref.watch(shareCurrentUserProvider).when(
        data: (User? user) => user == null
            ? const AsyncData<List<UsageLog>>(<UsageLog>[])
            : ref.watch(_usageLogsByUserProvider(user.id)),
        loading: () => const AsyncLoading<List<UsageLog>>(),
        error: (Object e, StackTrace st) => AsyncError<List<UsageLog>>(e, st),
      );
});

/// 특정 사용자의 알림 스트림(내부용).
final _notificationsByUserProvider =
    StreamProvider.family<List<GroupNotification>, String>((ref, userId) {
  return ref.watch(shareRepositoryProvider).watchNotifications(userId);
});

/// 내가 속한 그룹들의 알림(최신순). 로딩은 로딩으로 전파, data(null)만 빈 목록.
final notificationsProvider =
    Provider<AsyncValue<List<GroupNotification>>>((ref) {
  return ref.watch(shareCurrentUserProvider).when(
        data: (User? user) => user == null
            ? const AsyncData<List<GroupNotification>>(<GroupNotification>[])
            : ref.watch(_notificationsByUserProvider(user.id)),
        loading: () => const AsyncLoading<List<GroupNotification>>(),
        error: (Object e, StackTrace st) =>
            AsyncError<List<GroupNotification>>(e, st),
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
  final User? user = ref.watch(shareCurrentUserProvider).valueOrNull;
  if (user == null) return null;
  return ref.watch(_notifReadAtByUserProvider(user.id)).valueOrNull;
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

/// 내 원본 기프티콘 목록(원본 [Gifticon]을 그대로 소비).
/// 로딩은 로딩으로 전파, data(null)(미로그인)만 빈 목록.
final shareableGifticonsProvider = Provider<AsyncValue<List<Gifticon>>>((ref) {
  return ref.watch(shareCurrentUserProvider).when(
        data: (User? user) => user == null
            ? const AsyncData<List<Gifticon>>(<Gifticon>[])
            : ref.watch(_gifticonsByUserProvider(user.id)),
        loading: () => const AsyncLoading<List<Gifticon>>(),
        error: (Object e, StackTrace st) => AsyncError<List<Gifticon>>(e, st),
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
/// = 재시도 불가 원인.
///
/// `hasError`만 보지 않고 `!hasValue`를 함께 요구하는 이유: 스트림이 데이터를 한 번
/// 방출한 뒤 순단 에러가 나면 Riverpod은 `copyWithPrevious`로 이전 목록을 보존한다
/// (hasError=true인데 화면에는 그룹 목록이 멀쩡히 렌더된다). 이때까지 배너를 띄우면
/// ① 정상 표시된 목록 위에 "불러오지 못했어요 + 앱을 다시 열어 주세요"가 **앱 재시작
/// 전까지 영구 표시**되고(아래 재시도 불가 참조 — 해소 경로가 없다), ② 이 값을 쓰는
/// 상세·시트가 함께 발생한 **재시도 가능한** 공유 스트림 에러의 버튼까지 부당하게
/// 감춘다. 보존 값이 있는 동안 목록 조회는 계속 동작하므로, 배너는 "값이 정말 없는"
/// 상태로 한정한다(정본 재시도 훅이 승격되면 순단 표시도 재검토 — #13 후속).
///
/// 이 에러는 정본 파일 안의 private 체인(`_currentUserProvider`/`_groupsByUserProvider`)에
/// 캐시되고, 페이지에서 `invalidate(myGroupsProvider)`를 해도 dependency로 전파되지 않아
/// 되살릴 수 없다(#13 실측). 그래서 배너들은 이 값이 true면 [ShareErrorBanner.onRetry]를
/// **null로 낮춰** 동작하지 않는 버튼을 감춘다 — "재시도 경로가 없으면 버튼도 없다"는
/// 배너 위젯의 자체 규약을 화면마다 일관되게 지키기 위한 단일 판정점이다.
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
/// [shareCurrentUserProvider]는 share 탭 전반이 watch하므로, 멀쩡한 세션을
/// invalidate하면 화면 전체가 잠깐 로딩으로 깜빡인다. 알림/이력/기프티콘 스트림은
/// 모두 세션 뒤에 붙으므로, 세션이 에러면 그것부터 되살려야 하위 재시도가 의미를 갖는다.
void _retrySessionIfFailed(WidgetRef ref) {
  if (ref.read(shareCurrentUserProvider).hasError) {
    ref.invalidate(shareCurrentUserProvider);
  }
}

/// 에러인 그룹별 공유 스트림 인스턴스만 재구독한다(내 **현재** 그룹 범위).
///
/// family 전체 invalidate를 쓰지 않는 이유 둘: ① 실패하지 않은 그룹의 Firestore
/// 리스너까지 재시작돼 문서 읽기·과금이 그룹 수만큼 늘고(재시도가 필요한 건 에러
/// 인스턴스뿐이다 — [_retrySessionIfFailed]와 같은 원칙), ② non-autoDispose family라
/// 탈퇴한 그룹의 스테일 인스턴스도 재실행돼 비멤버 구독(permission-denied)을 되살린다.
void _retryFailedSharedInstances(WidgetRef ref) {
  final List<Group> groups =
      ref.read(myGroupsProvider).valueOrNull ?? const <Group>[];
  for (final Group g in groups) {
    if (ref.read(sharedGifticonsProvider(g.id)).hasError) {
      ref.invalidate(sharedGifticonsProvider(g.id));
    }
  }
}

/// 알림 스트림 수동 재시도 — **에러인** 원천만 invalidate해 재구독한다.
///
/// 읽음 시각 스트림까지 무조건 invalidate하면 정상 동작 중인 리스너가 해제·재구독되고,
/// 그 갭 동안 [notificationsReadAtProvider]가 null로 접혀 안읽음 뱃지가 잠깐
/// 전체-안읽음으로 튄다 — 배너의 원인이 아닌 스트림은 건드리지 않는다.
void retryNotifications(WidgetRef ref) {
  _retrySessionIfFailed(ref);
  final User? user = ref.read(shareCurrentUserProvider).valueOrNull;
  if (user == null) return; // 세션 없음 — 세션이 회복되면 하위가 함께 재구성된다.
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
  final User? user = ref.read(shareCurrentUserProvider).valueOrNull;
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
/// ([_retryFailedSharedInstances]의 근거 참조).
void retrySharedGifticons(WidgetRef ref, {String? groupId}) {
  _retrySessionIfFailed(ref);
  if (groupId != null) {
    ref.invalidate(sharedGifticonsProvider(groupId));
    return;
  }
  _retryFailedSharedInstances(ref);
}

/// 공유 시트 후보 수동 재시도 — 후보 계산 경로(내 기프티콘 + 그룹별 공유 목록) 중
/// **에러인 원천만** 되살린다(한쪽만 실패해도 배너는 뜨지만, 멀쩡한 반대쪽 스트림을
/// 재구독할 이유는 없다).
void retryShareCandidates(WidgetRef ref) {
  _retrySessionIfFailed(ref);
  final User? user = ref.read(shareCurrentUserProvider).valueOrNull;
  if (user != null && ref.read(_gifticonsByUserProvider(user.id)).hasError) {
    ref.invalidate(_gifticonsByUserProvider(user.id));
  }
  _retryFailedSharedInstances(ref);
}

/// userId → 표시 이름 해석기. 내 그룹들의 멤버 정보로 조립한다.
///
/// 계약 모델은 [User.id]만 저장하므로(이름 문자열 저장을 폐기), 표시용 이름은 소비자가
/// 멤버 정보로 해석한다. 본인은 '나'로 표시한다.
final memberNamesProvider = Provider<MemberNames>((ref) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
  final User? user = ref.watch(shareCurrentUserProvider).valueOrNull;
  final Map<String, String> byId = <String, String>{};
  for (final Group g in groups) {
    for (final GroupMember m in g.members) {
      byId[m.userId] = m.displayName;
    }
  }
  return MemberNames(byId: byId, currentUserId: user?.id);
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
