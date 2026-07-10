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
/// - 공유 후보(내 기프티콘)는 원본 [Gifticon]을 [GifticonRepository.watchGifticons]로 받는다
///   (프로토타입의 `MyGifticon` 폐기).
/// - 표시 이름/상대 시각 포맷은 소비자(UI) 책임 — userId→이름 해석은 [memberNamesProvider].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/share.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';

/// 현재 로그인 사용자(행위자). SSOT [authRepositoryProvider]를 구독한다.
final shareCurrentUserProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// 내가 멤버로 속한 그룹 목록. 미로그인이면 빈 목록.
final myGroupsProvider = StreamProvider<List<Group>>((ref) {
  final User? user = ref.watch(shareCurrentUserProvider).value;
  if (user == null) return Stream<List<Group>>.value(const <Group>[]);
  return ref.watch(shareRepositoryProvider).watchGroups(user.id);
});

/// id로 내 그룹 단건 조회(없으면 null — 나가기/삭제/이전으로 멤버십이 사라진 경우 포함).
final groupByIdProvider = Provider.family<Group?, String>((ref, groupId) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).value ?? const <Group>[];
  for (final Group g in groups) {
    if (g.id == groupId) return g;
  }
  return null;
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
      ref.watch(myGroupsProvider).value ?? const <Group>[];
  final List<SharedGifticon> out = <SharedGifticon>[];
  for (final Group g in groups) {
    out.addAll(
      ref.watch(sharedGifticonsProvider(g.id)).value ??
          const <SharedGifticon>[],
    );
  }
  return out;
});

/// id로 공유 항목 단건 조회(내 그룹들을 가로질러 탐색). 공유취소 등으로 사라지면 null.
final sharedItemByIdProvider =
    Provider.family<SharedGifticon?, String>((ref, itemId) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).value ?? const <Group>[];
  for (final Group g in groups) {
    final List<SharedGifticon> list =
        ref.watch(sharedGifticonsProvider(g.id)).value ??
            const <SharedGifticon>[];
    for (final SharedGifticon s in list) {
      if (s.id == itemId) return s;
    }
  }
  return null;
});

/// 내가 속한 그룹들의 사용 이력(최신순).
final usageLogsProvider = StreamProvider<List<UsageLog>>((ref) {
  final User? user = ref.watch(shareCurrentUserProvider).value;
  if (user == null) return Stream<List<UsageLog>>.value(const <UsageLog>[]);
  return ref.watch(shareRepositoryProvider).watchUsageLogs(user.id);
});

/// 내가 속한 그룹들의 알림(최신순).
final notificationsProvider = StreamProvider<List<GroupNotification>>((ref) {
  final User? user = ref.watch(shareCurrentUserProvider).value;
  if (user == null) {
    return Stream<List<GroupNotification>>.value(const <GroupNotification>[]);
  }
  return ref.watch(shareRepositoryProvider).watchNotifications(user.id);
});

/// 내 원본 기프티콘 목록(원본 [Gifticon]을 그대로 소비).
final shareableGifticonsProvider = StreamProvider<List<Gifticon>>((ref) {
  final User? user = ref.watch(shareCurrentUserProvider).value;
  if (user == null) return Stream<List<Gifticon>>.value(const <Gifticon>[]);
  return ref.watch(gifticonRepositoryProvider).watchGifticons(user.id);
});

/// 공유 시트 후보 = 아직 **내 어느 그룹에도** 공유하지 않은 사용 가능한 내 기프티콘.
///
/// [shareableGifticonsProvider](내 원본 기프티콘) 중 [ShareStatus.available]이고,
/// [allSharedProvider](내 전 그룹의 공유 항목) 집합의 [SharedGifticon.gifticonId]에 없는 것만
/// 남긴다. 이미 다른 그룹에 공유된 기프티콘을 후보에서 아예 제외해 이중 공유(이중 사용)를
/// 사전 차단하는 UX 방어선이다(저장소의 [StateError] 가드와 이중 방어).
final unsharedGifticonsProvider = Provider<List<Gifticon>>((ref) {
  final List<Gifticon> mine =
      ref.watch(shareableGifticonsProvider).value ?? const <Gifticon>[];
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

/// userId → 표시 이름 해석기. 내 그룹들의 멤버 정보로 조립한다.
///
/// 계약 모델은 [User.id]만 저장하므로(이름 문자열 저장을 폐기), 표시용 이름은 소비자가
/// 멤버 정보로 해석한다. 본인은 '나'로 표시한다.
final memberNamesProvider = Provider<MemberNames>((ref) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).value ?? const <Group>[];
  final User? user = ref.watch(shareCurrentUserProvider).value;
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
