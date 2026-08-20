/// KeepCon 공유 계약 — FirebaseShareRepository (cloud_firestore 구현체).
///
/// [ShareRepository] 계약을 Cloud Firestore로 구현한다. **인터페이스는 그대로**이므로
/// provider override만으로 in-memory ↔ Firebase가 교체된다. 가드 위반은 계약대로
/// [StateError]를 던진다(권한/상태/전이/불변식).
///
/// ## 문서 매핑 (Firestore ↔ 계약)
/// - `groups/{id}`: 멤버는 `members`(맵 배열)로, 조회용으로 `memberIds`(문자열 배열)를
///   **역정규화**해 함께 저장한다(`watchGroups`가 `array-contains`로 질의).
/// - `sharedGifticons/{id}`: `groupId`로 그룹에 귀속. enum은 `.name`, [DateTime]은 [Timestamp].
/// - `usageLogs/{id}` / `notifications/{id}`: `groupId`로 귀속, 시각은 [Timestamp].
/// - `shareLocks/{gifticonId}`: "한 기프티콘 최대 1회 공유" 불변식을 **원자적으로** 강제하는
///   잠금 문서(트랜잭션에서 존재하면 거부). 공유취소 시 함께 삭제, 사용완료 시 유지(재공유 차단).
///
/// ## Firestore 제약 대응
/// - 클라이언트 트랜잭션은 쿼리를 못 하므로, 불변식은 잠금 **문서 id**(gifticonId)로 강제한다.
/// - 사용자 소속 그룹 전반의 이력/알림은 `watchGroups`를 상위 스트림으로 두고 그룹 변화 때마다
///   `whereIn`(≤30) 질의로 스위칭하는 client-side join으로 관찰한다.
///
/// ⚠️ 기본 실행 경로에서 인스턴스화하지 마라 — `Firebase.initializeApp()` 선행 필요.
/// 부트스트랩([firebase_bootstrap.dart]) 경유로만 활성화한다.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../models/gifticon.dart';
import '../../../models/group.dart';
import '../../../models/join_request.dart';
import '../../../models/share.dart';
import '../../../models/user.dart';
import '../../../util/invite_token.dart';
import '../../../util/korean_particle.dart';
import '../../auth_repository.dart';
import '../../gifticon_repository.dart';
import '../../share_repository.dart';
import 'doc_read.dart';

/// `whereIn` 질의의 값 개수 상한(Firestore 제약). 사용자가 이보다 많은 그룹에 속하면
/// 최신 [_whereInLimit]개 그룹의 이력/알림만 관찰한다(문서화된 한계).
const int _whereInLimit = 30;

/// [ShareRepository]의 Cloud Firestore 구현.
class FirebaseShareRepository implements ShareRepository {
  /// 세션([AuthRepository])·원본 기프티콘([GifticonRepository])·Firestore를 주입한다.
  /// [firestore] 미지정 시 [FirebaseFirestore.instance].
  FirebaseShareRepository({
    required AuthRepository authRepository,
    required GifticonRepository gifticonRepository,
    FirebaseFirestore? firestore,
  })  : _auth = authRepository,
        _gifticons = gifticonRepository,
        _db = firestore ?? FirebaseFirestore.instance;

  final AuthRepository _auth;
  final GifticonRepository _gifticons;
  final FirebaseFirestore _db;

  static const String groupsCollection = 'groups';
  static const String sharedCollection = 'sharedGifticons';
  static const String usageLogsCollection = 'usageLogs';
  static const String notificationsCollection = 'notifications';
  static const String shareLocksCollection = 'shareLocks';
  static const String notificationReadsCollection = 'notificationReads';

  /// 참여 요청. 문서 id는 `{groupId}_{userId}` — (그룹, 사용자)당 하나라는 계약을
  /// 저장소 차원에서 강제한다(멱등 재요청이 새 문서를 만들지 않는다).
  static const String joinRequestsCollection = 'joinRequests';

  /// 초대 토큰 → 그룹 조회 문서. 문서 id가 곧 토큰이다.
  ///
  /// **비멤버는 `groups`를 읽을 수 없으므로**(보안 규칙) 토큰만으로 그룹을 찾으려면
  /// 이 문서가 필요하다. 담는 것은 `groupId`와 만료 시각뿐이다 — 그룹명·이모지·인원은
  /// 승인 전 요청자에게 보여주지 않는 정책이라 저장하지 않는다(저장하면 언젠가 샌다).
  static const String inviteTokensCollection = 'inviteTokens';

  static const String _defaultAvatar = '🙂';

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection(groupsCollection);
  CollectionReference<Map<String, dynamic>> get _shared =>
      _db.collection(sharedCollection);
  CollectionReference<Map<String, dynamic>> get _logs =>
      _db.collection(usageLogsCollection);
  CollectionReference<Map<String, dynamic>> get _notifs =>
      _db.collection(notificationsCollection);
  CollectionReference<Map<String, dynamic>> get _notifReads =>
      _db.collection(notificationReadsCollection);
  CollectionReference<Map<String, dynamic>> get _locks =>
      _db.collection(shareLocksCollection);
  CollectionReference<Map<String, dynamic>> get _joinRequests =>
      _db.collection(joinRequestsCollection);
  CollectionReference<Map<String, dynamic>> get _inviteTokens =>
      _db.collection(inviteTokensCollection);

  User _requireUser() {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('No current user in session — cannot perform action');
    }
    return user;
  }

  // ── 그룹 조회 ────────────────────────────────────────────────────────
  @override
  Stream<List<Group>> watchGroups(String userId) {
    return _groups.where('memberIds', arrayContains: userId).snapshots().map(
        (QuerySnapshot<Map<String, dynamic>> s) =>
            s.docs.map(_groupFromDocOrNull).whereType<Group>().toList());
  }

  @override
  Future<List<Group>> getGroups(String userId) async {
    final QuerySnapshot<Map<String, dynamic>> s =
        await _groups.where('memberIds', arrayContains: userId).get();
    return s.docs.map(_groupFromDocOrNull).whereType<Group>().toList();
  }

  @override
  Future<Group?> getGroupById(String groupId) async {
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _groups.doc(groupId).get();
    if (!doc.exists) return null;
    return _groupFromDocOrNull(doc);
  }

  // ── 그룹 관리 ────────────────────────────────────────────────────────
  @override
  Future<Group> createGroup({
    required String name,
    required String emoji,
    int maxMembers = Group.defaultMaxMembers,
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc();
    final Group g = Group(
      id: ref.id,
      name: name,
      emoji: emoji,
      inviteToken: _randomToken(),
      maxMembers: maxMembers,
      members: <GroupMember>[
        GroupMember(
          userId: me.id,
          displayName: me.displayName,
          avatarEmoji: _defaultAvatar,
          role: MemberRole.owner,
        ),
      ],
    );
    await ref.set(_groupToDoc(g));
    // 토큰 조회 문서는 **그룹 다음에** 쓴다 — 규칙이 `get(groups/{id}).ownerId`로
    // 소유권을 확인하므로 그룹이 아직 없으면 거부된다(배치로 묶어도 규칙은 커밋 전
    // 상태를 본다).
    //
    // 실패하면 **그룹 문서를 되돌린다.** 던지기만 하면 사용자는 실패 안내를 받는데
    // `watchGroups`는 그 그룹을 계속 방출하고, 재시도하면 그룹이 하나 더 생긴다 —
    // 게다가 링크가 아무도 못 여는 그룹이라 초대 화면에서는 그 사실이 드러나지 않는다.
    try {
      await _inviteTokens.doc(g.inviteToken).set(_inviteTokenToDoc(g));
    } catch (_) {
      await ref.delete();
      rethrow;
    }
    return g;
  }

  @override
  Future<Group> joinGroup(String inviteToken) async {
    final User me = _requireUser();
    // 초대 토큰으로 실제 그룹을 찾아 합류한다(mock의 가짜 그룹 생성과 달리 실 참여).
    //
    // 레거시 `inviteCode` 필드는 **일부러 조회하지 않는다.** 읽기 매핑에는 폴백을 뒀지만
    // 여기에까지 두 번째 질의를 붙이는 건 값이 없다 — 이 질의 자체가 보안 규칙에 막히기
    // 때문이다. 비멤버는 `groups`를 읽을 수 없어서(`allow read`는 멤버 한정) 초대 토큰을
    // 아는 것과 무관하게 결과가 permission-denied다. 즉 이 경로는 필드 이름과 상관없이
    // 이미 동작하지 않으며, 승인제(`requestToJoin`)가 대체하면 통째로 사라진다.
    final QuerySnapshot<Map<String, dynamic>> q = await _groups
        .where('inviteToken', isEqualTo: inviteToken)
        .limit(1)
        .get();
    if (q.docs.isEmpty) {
      throw StateError('No group for invite token: $inviteToken');
    }
    final DocumentReference<Map<String, dynamic>> ref = q.docs.first.reference;

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group disappeared: ${ref.id}');
      final Group g = _groupFromDocForFullWrite(doc);
      if (g.isMember(me.id)) return g; // 이미 멤버면 no-op.
      // 만료된 초대코드는 참여 거부(가드는 트랜잭션 안에서 최신 문서 기준으로 판정).
      if (g.isInviteExpired(DateTime.now())) {
        throw StateError('Invite token expired: $inviteToken');
      }
      // 정원 초과 참여 거부(트랜잭션 안에서 최신 멤버 수 기준으로 판정).
      if (g.isFull) {
        throw StateError('Group is full: ${ref.id}');
      }
      final List<GroupMember> next = <GroupMember>[
        ...g.members,
        GroupMember(
          userId: me.id,
          displayName: me.displayName,
          avatarEmoji: _defaultAvatar,
          role: MemberRole.member,
        ),
      ];
      final Group updated = g.copyWith(members: next);
      tx.update(ref, _groupToDoc(updated));
      return updated;
    });
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);
    bool cascade = false;

    // 그룹이 사라질 참이면 참여 요청·토큰을 **먼저** 거둔다 — 삭제 뒤에는 규칙의
    // 소유권 검사가 통째로 거짓이 되어 손도 못 댄다(`_cascadeDeleteGroupJoinArtifacts`).
    // 트랜잭션 밖의 선행 읽기라 그사이 누가 합류하면 헛되이 지울 수 있는데, 여기 오는
    // 사람은 정의상 마지막 멤버이자 방장이고 승인 권한도 그 사람뿐이라 실질 위험이 없다.
    final DocumentSnapshot<Map<String, dynamic>> pre = await ref.get();
    Group? preGroup;
    if (pre.exists) {
      // 판정 기준을 트랜잭션과 맞춘다 — 트랜잭션은 `_groupFromDocForMembershipWrite`가
      // 읽은 멤버로 판단하므로, 여기서 관대 매퍼의 접힌 목록을 세면 두 값이 갈릴 수 있다.
      final Group? g = _groupFromDocOrNull(pre);
      final bool willVanish = g != null &&
          g.isMember(me.id) &&
          g.members.where((GroupMember m) => m.userId != me.id).isEmpty;
      if (willVanish) {
        preGroup = g;
        await _cascadeDeleteGroupJoinArtifacts(groupId, g.inviteToken);
      }
      // ⚠️ 남는 경쟁 조건: 선행 읽기에서 멤버가 둘 이상이라 정리를 건너뛰었는데, 그사이
      // 다른 멤버가 나가 트랜잭션이 그룹을 삭제하는 경우다. 그러면 요청·토큰이 고아로
      // 남고 규칙상 아무도 지울 수 없다(소유권을 그룹 문서로 확인하므로).
      // 근본 해결은 두 문서에 `ownerId`를 역정규화해 그룹 없이도 방장이 지울 수 있게 하는
      // 것이고, 그건 스키마·규칙을 함께 바꾸므로 별도 작업으로 둔다. 지금 창은 좁다 —
      // 마지막 멤버가 나가는 순간에만 열리고, 그 사람이 곧 방장이자 유일한 승인자다.
    }

    try {
      await _db.runTransaction<void>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
        if (!doc.exists) throw StateError('Group not found: $groupId');
        final Group g = _groupFromDocForMembershipWrite(doc);
        if (!g.isMember(me.id)) {
          throw StateError('Not a member of group: $groupId');
        }
        if (g.isOwnedBy(me.id) && g.memberCount > 1) {
          throw StateError(
            'Owner must transfer ownership before leaving a non-empty group',
          );
        }
        final List<GroupMember> remaining = g.members
            .where((GroupMember m) => m.userId != me.id)
            .toList(growable: false);
        if (remaining.isEmpty) {
          tx.delete(ref);
          cascade = true;
        } else {
          // 전체 문서가 아니라 **memberIds 한 필드만** 쓴다. 보안 규칙의 '나가기'
          // 분기가 그 필드만 허용하기 때문이다 — `members`(맵 배열)까지 열어 주면 규칙이
          // "지워진 원소가 정말 본인인가"를 확인할 수 없어, 나가면서 남을 지우는 조작이
          // 통과한다. 떠난 멤버의 표시용 항목은 `_groupFromDocOrNull`이 읽을 때 걸러내고,
          // 다음 방장 쓰기에서 문서에서도 정리된다.
          //
          // 전체 문서를 다시 쓰지 않는 또 다른 이유: 레거시 문서에 없던 필드(inviteExpiresAt·
          // maxMembers 등)가 기본값으로 채워지며 함께 변경돼 규칙 조건이 깨진다. 팀 공용
          // 시드 그룹이 정확히 그 모양이라, 전체 쓰기로는 아무도 그룹을 나갈 수 없다.
          tx.update(ref, _memberIdsPatch(remaining));
        }
      });
    } catch (_) {
      // 나가기가 무산됐다 — 사라질 줄 알고 미리 거둔 링크를 되살린다.
      // (참여 요청은 되살릴 수 없다. `_cascadeDeleteGroupJoinArtifacts` 주석 참조.)
      if (preGroup != null) await _restoreInviteToken(preGroup);
      rethrow;
    }

    if (cascade) {
      await _cascadeDeleteGroupShares(groupId);
    } else {
      // 그룹이 남는 분기 — 떠난 사람의 승인 기록만 거둔다.
      await _dropJoinRequest(groupId, me.id);
      // 사라질 줄 알고 미리 거뒀는데 그룹이 남았다면(그사이 누가 합류) 링크를 되살린다.
      if (preGroup != null) await _restoreInviteToken(preGroup);
    }
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);

    // 참여 요청·토큰은 그룹이 살아 있을 때만 지울 수 있다(규칙이 소유권을 그룹 문서로
    // 확인한다). 그래서 삭제 **앞**에 거둔다. 소유권은 아래 트랜잭션이 다시 검사하므로
    // 이 선행 검사는 "권한 없는 사람이 남의 그룹 요청을 지우는 것"만 막으면 된다 —
    // 규칙도 같은 것을 막지만, 여기서 걸러야 헛된 왕복이 없다.
    final DocumentSnapshot<Map<String, dynamic>> pre = await ref.get();
    Group? preGroup;
    if (pre.exists) {
      preGroup = _groupFromDocOrNull(pre);
      if (preGroup != null && preGroup.isOwnedBy(me.id)) {
        await _cascadeDeleteGroupJoinArtifacts(groupId, preGroup.inviteToken);
      } else {
        preGroup = null; // 정리하지 않았으므로 되돌릴 것도 없다.
      }
    }

    try {
      await _db.runTransaction<void>((Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
        if (!doc.exists) throw StateError('Group not found: $groupId');
        final Group g = _groupFromDoc(doc);
        if (!g.isOwnedBy(me.id)) {
          throw StateError('Only the owner can delete the group: $groupId');
        }
        tx.delete(ref);
      });
    } catch (_) {
      // 삭제가 무산됐다 — 그룹은 남는데 링크만 죽은 상태를 남기지 않는다.
      if (preGroup != null) await _restoreInviteToken(preGroup);
      rethrow;
    }

    await _cascadeDeleteGroupShares(groupId);
  }

  @override
  Future<Group> transferOwnershipAndLeave({
    required String groupId,
    required String newOwnerUserId,
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);

    final Group handedOver =
        await _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDocForFullWrite(doc);
      if (!g.isOwnedBy(me.id)) {
        throw StateError('Only the owner can transfer ownership: $groupId');
      }
      if (newOwnerUserId == me.id || !g.isMember(newOwnerUserId)) {
        throw StateError(
          'New owner must be an existing member other than the current owner',
        );
      }
      final List<GroupMember> next = g.members
          .where((GroupMember m) => m.userId != me.id)
          .map((GroupMember m) => m.userId == newOwnerUserId
              ? m.copyWith(role: MemberRole.owner)
              : m)
          .toList(growable: false);
      final Group updated = g.copyWith(members: next);
      tx.update(ref, _groupToDoc(updated));
      return updated;
    });
    // 소유권을 넘기는 쪽도 그룹을 떠난다 — 나가기·강퇴와 같은 정리가 필요하다.
    await _dropJoinRequest(groupId, me.id);
    return handedOver;
  }

  @override
  Future<Group> removeMember({
    required String groupId,
    required String userId,
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);

    final Group removed =
        await _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDocForFullWrite(doc);
      if (!g.isOwnedBy(me.id)) {
        throw StateError('Only the owner can remove members: $groupId');
      }
      if (userId == me.id) {
        throw StateError('Owner cannot remove themselves: $groupId');
      }
      if (!g.isMember(userId)) {
        throw StateError('Not a member of group: $userId');
      }
      // 방장은 남으므로 그룹이 비지 않는다(cascade 불필요). leaveGroup의 비-소멸
      // 분기와 동일하게 멤버십만 제거한다(공유 항목은 그대로 유지).
      final List<GroupMember> next = g.members
          .where((GroupMember m) => m.userId != userId)
          .toList(growable: false);
      final Group updated = g.copyWith(members: next);
      tx.update(ref, _groupToDoc(updated));
      return updated;
    });
    // 강퇴당한 사람의 승인 기록도 거둔다(나가기·소유권 이전과 같은 정리).
    await _dropJoinRequest(groupId, userId);
    return removed;
  }

  @override
  Future<Group> setInviteOwnerOnly({
    required String groupId,
    required bool ownerOnly,
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
      if (!g.isOwnedBy(me.id)) {
        throw StateError('Only the owner can change invite policy: $groupId');
      }
      final Group updated = g.copyWith(inviteOwnerOnly: ownerOnly);
      tx.update(ref, <String, dynamic>{'inviteOwnerOnly': ownerOnly});
      return updated;
    });
  }

  @override
  Future<Group> regenerateInviteToken({required String groupId}) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);
    // 만료 창은 재발급 시점부터 다시 24시간(트랜잭션 재시도에도 값이 흔들리지 않게 밖에서 고정).
    final DateTime expiresAt = DateTime.now().add(Group.inviteValidity);

    String? oldToken;
    final Group updated =
        await _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
      if (!g.isOwnedBy(me.id)) {
        throw StateError(
            'Only the owner can regenerate invite token: $groupId');
      }
      oldToken = g.inviteToken;
      final Group next =
          g.copyWith(inviteToken: _randomToken(), inviteExpiresAt: expiresAt);
      tx.update(ref, <String, dynamic>{
        'inviteToken': next.inviteToken,
        'inviteExpiresAt': Timestamp.fromDate(expiresAt),
      });
      return next;
    });

    // 옛 토큰 조회 문서를 **먼저** 지운다. 재발급의 계약은 "기존 링크 무효화"인데,
    // 새 문서를 먼저 쓰면 둘 다 열리는 창이 생긴다. 반대로 지우고 나서 쓰기가
    // 실패하면 링크가 잠깐 죽을 뿐이고, 그건 다시 재발급하면 복구된다(fail-closed).
    if (oldToken != null && oldToken != updated.inviteToken) {
      await _inviteTokens.doc(oldToken!).delete();
    }
    await _inviteTokens
        .doc(updated.inviteToken)
        .set(_inviteTokenToDoc(updated));
    return updated;
  }

  // ── 참여 요청(초대 링크 → 방장 승인) ────────────────────────────────
  //
  // 비멤버는 보안 규칙상 `groups`를 읽을 수 없다. 그래서 토큰으로 그룹을 찾는 일은
  // `inviteTokens/{token}` 문서가 대신한다 — 그 문서는 `groupId`와 만료 시각만 담고,
  // 규칙은 **get만 허용하고 list는 막는다**(토큰을 모르면 목록으로 훑을 수 없다).

  /// (그룹, 사용자)당 요청 하나를 강제하는 결정론적 문서 id.
  String _joinRequestId(String groupId, String userId) => '${groupId}_$userId';

  Map<String, dynamic> _inviteTokenToDoc(Group g) => <String, dynamic>{
        'groupId': g.id,
        'expiresAt': Timestamp.fromDate(g.inviteExpiresAt),
      };

  /// 손상 문서를 `null`로 흘려보내는 **읽기 전용** 매퍼(목록이 통째로 죽지 않게).
  /// 쓰기 판정에는 이 결과를 그대로 믿지 않는다 — 승인·거절은 원본 필드를 다시 본다.
  JoinRequest? _joinRequestFromDocOrNull(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> d = doc.data() ?? const <String, dynamic>{};
    final Object? groupId = d['groupId'];
    final Object? userId = d['userId'];
    final Object? requestedAt = d['requestedAt'];
    if (groupId is! String || groupId.isEmpty) return null;
    if (userId is! String || userId.isEmpty) return null;
    if (requestedAt is! Timestamp) return null;
    return JoinRequest(
      id: doc.id,
      groupId: groupId,
      userId: userId,
      displayName: d['displayName'] is String ? d['displayName'] as String : '',
      avatarEmoji: d['avatarEmoji'] is String
          ? d['avatarEmoji'] as String
          : _defaultAvatar,
      requestedAt: requestedAt.toDate(),
      status: _joinRequestStatusFrom(d['status']),
    );
  }

  /// 상태 문자열 → enum. **판정 불가는 거절로 닫는다(fail-closed).**
  ///
  /// 대기로 읽으면 처리가 끝난 요청이 방장의 대기 목록에 되살아나 같은 사람을 두 번
  /// 승인하게 된다 — 안전한 쪽은 "이미 끝난 것으로 본다"이다.
  JoinRequestStatus _joinRequestStatusFrom(Object? raw) {
    for (final JoinRequestStatus s in JoinRequestStatus.values) {
      if (s.name == raw) return s;
    }
    return JoinRequestStatus.rejected;
  }

  List<JoinRequest> _joinRequestsFrom(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) =>
      List<JoinRequest>.unmodifiable(
        snap.docs.map(_joinRequestFromDocOrNull).whereType<JoinRequest>(),
      );

  @override
  Future<JoinRequest> requestToJoin(String inviteToken) async {
    final User me = _requireUser();

    final DocumentSnapshot<Map<String, dynamic>> tokenDoc =
        await _inviteTokens.doc(inviteToken).get();
    final Map<String, dynamic> t = tokenDoc.data() ?? const <String, dynamic>{};
    final Object? groupId = t['groupId'];
    if (!tokenDoc.exists || groupId is! String || groupId.isEmpty) {
      throw StateError('No group for invite token: $inviteToken');
    }
    // 만료는 토큰 문서가 들고 있다(비멤버가 그룹을 못 읽으므로). 값이 없거나 손상이면
    // 만료로 닫는다 — 레거시 문서를 만료로 읽는 기존 규약과 같은 fail-closed다.
    final Object? expiresAt = t['expiresAt'];
    if (expiresAt is! Timestamp ||
        !DateTime.now().isBefore(expiresAt.toDate())) {
      throw StateError('Invite token expired: $inviteToken');
    }

    // 이미 멤버인지 — 멤버는 그룹을 읽을 수 있고 비멤버는 규칙에 막힌다. 그 차이를
    // 그대로 판정에 쓴다(읽지 못하는 것이 비멤버의 정상 경로다).
    try {
      final Group? g = await getGroupById(groupId);
      if (g != null && g.isMember(me.id)) {
        throw StateError('Already a member of group: $groupId');
      }
    } on FirebaseException {
      // 읽기 거부 = 비멤버. 요청을 계속 진행한다.
    }

    final DocumentReference<Map<String, dynamic>> ref =
        _joinRequests.doc(_joinRequestId(groupId, me.id));

    return _db.runTransaction<JoinRequest>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> prev = await tx.get(ref);
      final JoinRequest? existing =
          prev.exists ? _joinRequestFromDocOrNull(prev) : null;
      if (existing != null && existing.isPending) {
        return existing; // 멱등 — 같은 링크를 두 번 눌러도 요청이 쌓이지 않는다.
      }
      // 결정이 끝난 요청(거절, 또는 승인 후 강퇴)은 다시 대기로 되돌린다.
      final JoinRequest req = JoinRequest(
        id: ref.id,
        groupId: groupId,
        userId: me.id,
        displayName: me.displayName,
        avatarEmoji: _defaultAvatar,
        requestedAt: DateTime.now(),
      );
      tx.set(ref, <String, dynamic>{
        'groupId': req.groupId,
        'userId': req.userId,
        'displayName': req.displayName,
        'avatarEmoji': req.avatarEmoji,
        'requestedAt': Timestamp.fromDate(req.requestedAt),
        'status': req.status.name,
      });
      return req;
    });
  }

  @override
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId) => _joinRequests
      .where('userId', isEqualTo: userId)
      .orderBy('requestedAt', descending: true)
      .snapshots()
      .map(_joinRequestsFrom);

  @override
  Future<List<JoinRequest>> getMyJoinRequests(String userId) async =>
      _joinRequestsFrom(await _joinRequests
          .where('userId', isEqualTo: userId)
          .orderBy('requestedAt', descending: true)
          .get());

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) =>
      _pendingQuery(groupId).snapshots().map(_joinRequestsFrom);

  @override
  Future<List<JoinRequest>> getPendingJoinRequests(String groupId) async =>
      _joinRequestsFrom(await _pendingQuery(groupId).get());

  /// 대기 중 요청 — 오래된 순(먼저 기다린 사람이 위). **읽기 권한은 방장뿐**이다.
  Query<Map<String, dynamic>> _pendingQuery(String groupId) => _joinRequests
      .where('groupId', isEqualTo: groupId)
      .where('status', isEqualTo: JoinRequestStatus.pending.name)
      .orderBy('requestedAt');

  @override
  Future<Group> approveJoinRequest(String joinRequestId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> reqRef =
        _joinRequests.doc(joinRequestId);

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> reqDoc =
          await tx.get(reqRef);
      if (!reqDoc.exists) {
        throw StateError('Join request not found: $joinRequestId');
      }
      final JoinRequest? req = _joinRequestFromDocOrNull(reqDoc);
      if (req == null) {
        throw StateError('Malformed join request: $joinRequestId');
      }
      final DocumentReference<Map<String, dynamic>> groupRef =
          _groups.doc(req.groupId);
      final DocumentSnapshot<Map<String, dynamic>> groupDoc =
          await tx.get(groupRef);
      if (!groupDoc.exists) throw StateError('Group not found: ${req.groupId}');
      // 아래에서 `_groupToDoc`으로 문서 **전체**를 되쓰므로 엄격 매퍼로 읽는다 —
      // 관대 매퍼로 읽으면 그 폴백(정원 클램프·초대 정책·만료)이 되쓰기로 굳는다.
      final Group g = _groupFromDocForFullWrite(groupDoc);

      // 가드를 **전부** 통과한 뒤에 쓴다 — 중간에 던지면 요청만 승인으로 남고
      // 멤버는 안 들어간 어긋난 상태가 된다.
      if (!g.isOwnedBy(me.id)) {
        throw StateError('Only the owner can approve join requests: ${g.id}');
      }
      if (!req.isPending) {
        throw StateError('Join request is already decided: $joinRequestId');
      }
      final bool alreadyMember = g.isMember(req.userId);
      if (!alreadyMember && g.isFull) {
        throw StateError('Group is full: ${g.id}');
      }

      tx.update(reqRef, <String, dynamic>{
        'status': JoinRequestStatus.approved.name,
      });
      if (alreadyMember) {
        // 다른 경로로 이미 멤버가 됐다면 요청만 정리한다(중복 추가 금지).
        return g;
      }

      final Group updated = g.copyWith(
        members: <GroupMember>[
          ...g.members,
          GroupMember(
            userId: req.userId,
            displayName: req.displayName,
            avatarEmoji: req.avatarEmoji,
            role: MemberRole.member,
          ),
        ],
      );
      tx.update(groupRef, _groupToDoc(updated));
      return updated;
    });
  }

  @override
  Future<JoinRequest> rejectJoinRequest(String joinRequestId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> reqRef =
        _joinRequests.doc(joinRequestId);

    return _db.runTransaction<JoinRequest>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> reqDoc =
          await tx.get(reqRef);
      if (!reqDoc.exists) {
        throw StateError('Join request not found: $joinRequestId');
      }
      final JoinRequest? req = _joinRequestFromDocOrNull(reqDoc);
      if (req == null) {
        throw StateError('Malformed join request: $joinRequestId');
      }
      final DocumentSnapshot<Map<String, dynamic>> groupDoc =
          await tx.get(_groups.doc(req.groupId));
      if (!groupDoc.exists) throw StateError('Group not found: ${req.groupId}');
      if (!_groupFromDoc(groupDoc).isOwnedBy(me.id)) {
        throw StateError(
          'Only the owner can reject join requests: ${req.groupId}',
        );
      }
      if (!req.isPending) {
        throw StateError('Join request is already decided: $joinRequestId');
      }
      tx.update(reqRef, <String, dynamic>{
        'status': JoinRequestStatus.rejected.name,
      });
      return req.copyWith(status: JoinRequestStatus.rejected);
    });
  }

  @override
  Future<void> cancelJoinRequest(String joinRequestId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref =
        _joinRequests.doc(joinRequestId);
    final DocumentSnapshot<Map<String, dynamic>> doc = await ref.get();
    if (!doc.exists) {
      throw StateError('Join request not found: $joinRequestId');
    }
    if (doc.data()?['userId'] != me.id) {
      throw StateError('Only the requester can cancel: $joinRequestId');
    }
    await ref.delete();
  }

  // ── 공유 기프티콘 ─────────────────────────────────────────────────────
  @override
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId) {
    return _shared.where('groupId', isEqualTo: groupId).snapshots().map(
        (QuerySnapshot<Map<String, dynamic>> s) =>
            s.docs.map(_sharedFromDoc).toList(growable: false));
  }

  @override
  Future<List<SharedGifticon>> getSharedGifticons(String groupId) async {
    final QuerySnapshot<Map<String, dynamic>> s =
        await _shared.where('groupId', isEqualTo: groupId).get();
    return s.docs.map(_sharedFromDoc).toList(growable: false);
  }

  @override
  Future<SharedGifticon> shareGifticon({
    required String groupId,
    required Gifticon gifticon,
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> groupRef =
        _groups.doc(groupId);
    final DocumentReference<Map<String, dynamic>> lockRef =
        _locks.doc(gifticon.id);
    final DocumentReference<Map<String, dynamic>> sharedRef = _shared.doc();
    final DocumentReference<Map<String, dynamic>> notifRef = _notifs.doc();

    final SharedGifticon shared = SharedGifticon(
      id: sharedRef.id,
      groupId: groupId,
      gifticonId: gifticon.id,
      sharedByUserId: me.id,
      brand: gifticon.brand,
      productName: gifticon.productName,
      expiryDate: gifticon.expiryDate,
      status: ShareStatus.available,
      barcode: gifticon.barcode,
    );

    await _db.runTransaction<void>((Transaction tx) async {
      // 모든 read를 write보다 먼저 수행(Firestore 트랜잭션 규칙).
      final DocumentSnapshot<Map<String, dynamic>> groupDoc =
          await tx.get(groupRef);
      final DocumentSnapshot<Map<String, dynamic>> lockDoc =
          await tx.get(lockRef);

      if (!groupDoc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(groupDoc);
      if (!g.isMember(me.id)) {
        throw StateError('Not a member of group: $groupId');
      }
      // 불변식: 한 기프티콘은 최대 1회만 공유(잠금 문서로 원자적 강제).
      if (lockDoc.exists) {
        throw StateError('Gifticon already shared: ${gifticon.id}');
      }

      tx.set(sharedRef, _sharedToDoc(shared));
      tx.set(lockRef, <String, dynamic>{
        'sharedGifticonId': shared.id,
        'groupId': groupId,
      });
      tx.set(
        notifRef,
        _notifToDoc(GroupNotificationType.registered, groupId,
            title: '새 기프티콘 공유',
            message:
                '${me.displayName}님이 ${gifticon.brand} ${gifticon.productName}'
                '${gifticon.productName.eulReul} 공유했어요.'),
      );
    });

    return shared;
  }

  @override
  Future<SharedGifticon> toggleReservation(String sharedGifticonId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref =
        _shared.doc(sharedGifticonId);

    return _db.runTransaction<SharedGifticon>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) {
        throw StateError('Shared gifticon not found: $sharedGifticonId');
      }
      final SharedGifticon item = _requireSharedFromDoc(doc);
      final SharedGifticon updated;
      if (item.reservedByUserId == me.id) {
        updated = item.copyWith(reservedByUserId: null); // 내 찜 해제
      } else if (item.reservedByUserId == null) {
        updated = item.copyWith(reservedByUserId: me.id); // 새로 찜
      } else {
        throw StateError('Already reserved by another member'); // 단일 슬롯 보호
      }
      tx.update(ref, <String, dynamic>{
        'reservedByUserId': updated.reservedByUserId,
      });
      return updated;
    });
  }

  @override
  Future<SharedGifticon> markUsed(String sharedGifticonId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref =
        _shared.doc(sharedGifticonId);
    final DocumentReference<Map<String, dynamic>> logRef = _logs.doc();
    final DocumentReference<Map<String, dynamic>> notifRef = _notifs.doc();

    final SharedGifticon updated =
        await _db.runTransaction<SharedGifticon>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) {
        throw StateError('Shared gifticon not found: $sharedGifticonId');
      }
      final SharedGifticon item = _requireSharedFromDoc(doc);
      if (item.status != ShareStatus.available) {
        throw StateError(
          'Only an available shared gifticon can be marked used: ${item.status}',
        );
      }
      final SharedGifticon next = item.copyWith(
        status: ShareStatus.used,
        lockedByUserId: null,
        reservedByUserId: null,
      );
      tx.update(ref, <String, dynamic>{
        'status': ShareStatus.used.name,
        'lockedByUserId': null,
        'reservedByUserId': null,
      });
      tx.set(logRef, <String, dynamic>{
        'groupId': item.groupId,
        'userId': me.id,
        'sharedGifticonId': item.id,
        'brand': item.brand,
        'productName': item.productName,
        'usedAt': Timestamp.now(),
      });
      tx.set(
        notifRef,
        _notifToDoc(GroupNotificationType.used, item.groupId,
            title: '사용 완료',
            message: '${me.displayName}님이 ${item.brand} ${item.productName}'
                '${item.productName.eulReul} 사용했어요.'),
      );
      return next;
    });

    // share → main 동기화: 원본 Gifticon을 used로 전이(기존 계약 소비, 트랜잭션 밖).
    await _syncOriginalUsed(updated.gifticonId);
    return updated;
  }

  @override
  Future<void> cancelShare(String sharedGifticonId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref =
        _shared.doc(sharedGifticonId);

    await _db.runTransaction<void>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) {
        throw StateError('Shared gifticon not found: $sharedGifticonId');
      }
      final SharedGifticon item = _requireSharedFromDoc(doc);
      if (item.sharedByUserId != me.id) {
        throw StateError('Only the sharer can cancel the share');
      }
      if (item.status != ShareStatus.available) {
        throw StateError('Only an available share can be reclaimed');
      }
      // 항목과 공유 잠금을 함께 제거해 재공유가 가능해지도록 한다.
      tx.delete(ref);
      final DocumentReference<Map<String, dynamic>>? lock =
          _lockRefOrNull(item.gifticonId);
      if (lock != null) tx.delete(lock);
    });
  }

  Future<void> _syncOriginalUsed(String gifticonId) async {
    // best-effort 동기화. 보안 규칙상 원본 기프티콘은 **소유자만** 접근 가능하므로,
    // 사용한 행위자가 소유자가 아니면(다른 멤버가 공유분을 사용) 읽기/쓰기가
    // PERMISSION_DENIED로 막힌다 — 그 경우 조용히 건너뛴다(공유분 사용완료 자체는 유효).
    // (교차-멤버 원본 동기화는 추후 Cloud Function 트리거로 처리 예정.)
    try {
      final Gifticon? original = await _gifticons.getGifticonById(gifticonId);
      if (original == null) return;
      if (!GifticonStatusTransition.isAllowed(
        original.status,
        GifticonStatus.used,
      )) {
        return;
      }
      await _gifticons.updateStatus(gifticonId, GifticonStatus.used);
    } on Exception {
      // 권한(FirebaseException)·네트워크 등 예상된 런타임 실패만 무시(best-effort 계약).
      // Error(프로그래밍 버그)는 삼키지 않고 전파한다.
      return;
    }
  }

  /// 그룹 삭제/정리 시, 그 그룹의 공유 항목과 잠금 문서를 정리한다(best-effort, 트랜잭션 밖).
  /// 사용 이력/알림은 남기되 소속 그룹이 사라져 소비자 질의에서 자연히 제외된다(mock과 동일).
  ///
  /// ⚠️ 트랜잭션 밖 best-effort다(트랜잭션은 쿼리 불가). 중간에 실패하면 잔여 share/lock이
  /// 남을 수 있으므로, 항목당 (share, lock)을 **같은 배치**에 넣어 원자적으로 지우고,
  /// Firestore 500-op 한도를 넘지 않도록 청크로 나눈다.
  /// 그룹이 **사라지기 전에** 참여 요청과 토큰 조회 문서를 거둔다.
  ///
  /// ⚠️ **반드시 그룹 삭제보다 먼저 부른다.** 두 컬렉션의 규칙은 소유권을
  /// `get(groups/{id}).ownerId`로 확인하는데, 그룹이 이미 없으면 그 검사가 통째로
  /// 거짓이 되어 읽기도 삭제도 막힌다 — 정리를 뒤에 두면 영원히 못 지운다.
  ///
  /// 요청을 남기면 안 되는 이유: 요청은 멤버십이 아니라 `userId`로 조회되므로,
  /// 사라진 그룹을 가리키는 "대기 중"이 요청자 화면에 영원히 남는다(승인·거절은 그룹을
  /// 못 찾아 던지고 방장도 없어서 아무도 끝낼 수 없다). in-memory의 `_dropJoinRequest`와
  /// 같은 이유다. 토큰을 남기면 죽은 그룹을 가리키는 링크가 계속 열린다.
  ///
  /// 토큰은 **문서 id로** 지운다 — `inviteTokens`는 `list`가 막혀 있어(토큰을 모르는
  /// 사람이 전부 훑어 그룹 id를 얻는 것을 막는 규칙) `where` 질의 자체가 거부된다.
  ///
  /// ⚠️ **참여 요청은 복원할 수 없다.** 이 정리 뒤에 그룹 삭제가 실패하면(동시에 소유권이
  /// 넘어가는 등) 그룹은 남고 대기 목록만 비는 상태가 된다. 토큰 문서는 [_restoreInviteToken]
  /// 으로 되돌리지만 요청은 못 되돌린다 — 요청자는 다시 요청해야 한다. 그 대신 삭제가
  /// 성공했을 때 아무것도 남지 않는 쪽을 택했다(남으면 아무도 끝낼 수 없다).
  Future<void> _cascadeDeleteGroupJoinArtifacts(
    String groupId,
    String inviteToken,
  ) async {
    final QuerySnapshot<Map<String, dynamic>> reqs =
        await _joinRequests.where('groupId', isEqualTo: groupId).get();
    const int chunkSize = 400;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = reqs.docs;
    for (int i = 0; i < docs.length; i += chunkSize) {
      final WriteBatch batch = _db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d
          in docs.skip(i).take(chunkSize)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    if (inviteToken.isNotEmpty) {
      await _inviteTokens.doc(inviteToken).delete();
    }
  }

  /// 선행 정리 뒤 그룹 삭제가 실패했을 때 초대 링크를 되살린다.
  ///
  /// 되돌리지 못하면 그룹은 살아 있는데 링크만 죽은 상태가 남고, 방장이 재발급을 누르기
  /// 전까지 아무도 참여를 요청할 수 없다.
  Future<void> _restoreInviteToken(Group g) async {
    if (g.inviteToken.isEmpty) return;
    await _inviteTokens.doc(g.inviteToken).set(_inviteTokenToDoc(g));
  }

  Future<void> _cascadeDeleteGroupShares(String groupId) async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _shared.where('groupId', isEqualTo: groupId).get();
    if (snap.docs.isEmpty) return;

    // 항목당 최대 2 op(share + lock). 여유 있게 200개(≤400 op)씩 커밋한다.
    const int chunkSize = 200;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.docs;
    for (int i = 0; i < docs.length; i += chunkSize) {
      final WriteBatch batch = _db.batch();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d
          in docs.skip(i).take(chunkSize)) {
        batch.delete(d.reference);
        final DocumentReference<Map<String, dynamic>>? lock =
            _lockRefOrNull(docStringOrNull(d.data()['gifticonId']));
        if (lock != null) batch.delete(lock);
      }
      await batch.commit();
    }
  }

  // ── 사용 이력 / 알림 (사용자 소속 그룹 전반) ─────────────────────────────
  @override
  Stream<List<UsageLog>> watchUsageLogs(String userId) {
    return _switchOnGroups<UsageLog>(
      userId,
      (List<String> groupIds) => _logs
          .where('groupId', whereIn: groupIds)
          .orderBy('usedAt', descending: true)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> s) =>
              s.docs.map(_logFromDoc).toList(growable: false)),
    );
  }

  @override
  Future<List<UsageLog>> getUsageLogs(String userId) async {
    final List<String> groupIds = await _userGroupIds(userId);
    if (groupIds.isEmpty) return const <UsageLog>[];
    final QuerySnapshot<Map<String, dynamic>> s = await _logs
        .where('groupId', whereIn: groupIds)
        .orderBy('usedAt', descending: true)
        .get();
    return s.docs.map(_logFromDoc).toList(growable: false);
  }

  @override
  Stream<List<GroupNotification>> watchNotifications(String userId) {
    return _switchOnGroups<GroupNotification>(
      userId,
      (List<String> groupIds) => _notifs
          .where('groupId', whereIn: groupIds)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> s) =>
              s.docs.map(_notifFromDoc).toList(growable: false)),
    );
  }

  @override
  Future<List<GroupNotification>> getNotifications(String userId) async {
    final List<String> groupIds = await _userGroupIds(userId);
    if (groupIds.isEmpty) return const <GroupNotification>[];
    final QuerySnapshot<Map<String, dynamic>> s = await _notifs
        .where('groupId', whereIn: groupIds)
        .orderBy('createdAt', descending: true)
        .get();
    return s.docs.map(_notifFromDoc).toList(growable: false);
  }

  @override
  Stream<DateTime?> watchNotificationsReadAt(String userId) {
    return _notifReads.doc(userId).snapshots().map(
        (DocumentSnapshot<Map<String, dynamic>> d) =>
            docDateOrNull(d.data()?['readAt']));
  }

  @override
  Future<void> markNotificationsRead() async {
    final User me = _requireUser();
    await _notifReads.doc(me.id).set(<String, dynamic>{
      'readAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<List<String>> _userGroupIds(String userId) async {
    final List<Group> groups = await getGroups(userId);
    return groups.map((Group g) => g.id).take(_whereInLimit).toList();
  }

  /// 상위 스트림([watchGroups])의 그룹 집합이 바뀔 때마다 내부 질의를 스위칭한다
  /// (client-side join). 그룹이 없으면 빈 목록을 방출한다.
  Stream<List<T>> _switchOnGroups<T>(
    String userId,
    Stream<List<T>> Function(List<String> groupIds) inner,
  ) {
    late StreamController<List<T>> controller;
    StreamSubscription<List<Group>>? outerSub;
    StreamSubscription<List<T>>? innerSub;
    // 직전 그룹 id 집합(정렬·조인). 집합이 그대로면 inner 재구독을 건너뛴다
    // (그룹 이름/멤버 변경 등으로 watchGroups가 방출해도 이력/알림 스트림이 깜빡이지 않게).
    String? lastKey;

    void start() {
      outerSub = watchGroups(userId).listen(
        (List<Group> groups) {
          final List<String> ids = (groups.map((Group g) => g.id).toList()
                ..sort())
              .take(_whereInLimit)
              .toList();
          final String key = ids.join(',');
          if (key == lastKey) return; // 그룹 집합 불변 → 스위칭 스킵.
          lastKey = key;

          innerSub?.cancel();
          if (ids.isEmpty) {
            controller.add(<T>[]);
            innerSub = null;
            return;
          }
          innerSub = inner(ids).listen(
            controller.add,
            onError: controller.addError,
          );
        },
        onError: controller.addError,
        onDone: () => controller.close(),
      );
    }

    controller = StreamController<List<T>>(
      onListen: start,
      onCancel: () async {
        await innerSub?.cancel();
        await outerSub?.cancel();
      },
    );
    return controller.stream;
  }

  // ── 매핑 헬퍼 ─────────────────────────────────────────────────────────
  Map<String, dynamic> _groupToDoc(Group g) => <String, dynamic>{
        'name': g.name,
        'emoji': g.emoji,
        'inviteToken': g.inviteToken,
        'inviteOwnerOnly': g.inviteOwnerOnly,
        'inviteExpiresAt': Timestamp.fromDate(g.inviteExpiresAt),
        'maxMembers': g.maxMembers,
        'members': g.members
            .map((GroupMember m) => <String, dynamic>{
                  'userId': m.userId,
                  'displayName': m.displayName,
                  'avatarEmoji': m.avatarEmoji,
                  'role': m.role.name,
                })
            .toList(growable: false),
        // 멤버십의 **정본** — watchGroups의 array-contains 대상이자 보안 규칙의
        // 멤버십 판정 기준이다. 위의 `members`는 표시용 메타데이터다.
        'memberIds':
            g.members.map((GroupMember m) => m.userId).toList(growable: false),
        // 소유자 역정규화 — 보안 규칙이 방장 판정에 쓴다(members 배열 순회는 규칙에서 어려움).
        // 모든 그룹 write가 _groupToDoc을 거치므로 멤버 변경 시 자동으로 동기화된다.
        'ownerId': g.owner.userId,
      };

  /// 멤버십이 끊긴 사람의 참여 요청을 거둔다(나가기·강퇴·소유권 이전).
  ///
  /// in-memory의 `_dropJoinRequest`와 같은 이유다 — 남기면 그룹에 없는 사람의 화면에
  /// "승인됨"이 계속 보인다.
  ///
  /// **문서가 없는 것이 정상 경로다**(요청 없이 방장이 직접 넣은 멤버, 그리고 이 기능
  /// 이전부터 있던 모든 멤버). 그런데 `joinRequests`의 read·delete 규칙은 둘 다
  /// `resource.data`를 만지므로, 문서가 없으면 **읽기도 삭제도 403**이다 — `get`으로
  /// 존재를 확인하려던 시도가 바로 그 이유로 실패한다. 규칙에 `resource == null` 예외를
  /// 두지 않는 이유는 따로 있다: 두면 200/403이 문서 존재 오라클이 된다.
  ///
  /// 그래서 바로 지우고 **권한 거부를 정상 종료로 삼는다.** 이 경로에서 거부는 "없는
  /// 문서" 또는 "지울 권한 없음" 둘 중 하나인데, 어느 쪽이든 정리로서는 할 일이 없다.
  Future<void> _dropJoinRequest(String groupId, String userId) async {
    try {
      await _joinRequests.doc(_joinRequestId(groupId, userId)).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
  }

  /// 멤버 이탈만 반영하는 부분 갱신 페이로드([leaveGroup] 전용).
  ///
  /// 보안 규칙의 '나가기' 분기는 `memberIds` 외의 변경을 거부하므로 이 한 필드만 보낸다.
  Map<String, dynamic> _memberIdsPatch(List<GroupMember> members) =>
      <String, dynamic>{
        'memberIds':
            members.map((GroupMember m) => m.userId).toList(growable: false),
      };

  /// 문서 → [Group]. **비멤버/멤버0/방장≠1** 등 [Group] 불변식을 못 만족하는 손상
  /// 문서는 `null`을 반환한다 — 목록 매핑에서 걸러 한 문서가 스트림 전체를 깨지 않게 한다.
  Group? _groupFromDocOrNull(DocumentSnapshot<Map<String, dynamic>> doc) =>
      groupFromDataOrNull(doc.id, doc.data() ?? const <String, dynamic>{});

  /// [_groupFromDocOrNull]의 순수 본체(문서 없이 맵만으로 동작 — 테스트 진입점).
  @visibleForTesting
  static Group? groupFromDataOrNull(String id, Map<String, dynamic> data) {
    final List<dynamic> rawMembers =
        docListOrNull(data['members']) ?? const <dynamic>[];
    final List<GroupMember> parsed = rawMembers
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> m) => GroupMember(
              userId: docString(m['userId']),
              displayName: docString(m['displayName']),
              avatarEmoji: docString(m['avatarEmoji'], _defaultAvatar),
              role: _roleFromName(docStringOrNull(m['role'])),
            ))
        // userId를 못 읽은 항목(필드 없음/손상)은 유령이다 — 아무와도 매칭되지 않으면서
        // [Group.isFull]의 정원 한 칸을 먹고 화면에 빈 이름으로 남는다.
        .where((GroupMember m) => m.userId.isNotEmpty)
        .toList(growable: false);
    // 멤버십의 정본은 `memberIds`다 — 목록 쿼리(array-contains)와 보안 규칙의 멤버십
    // 판정이 모두 그 필드를 본다. 멤버 '나가기'는 규칙상 `memberIds`만 바꿀 수 있으므로
    // (`members`까지 열어 주면 나가면서 남을 지우는 조작이 통과한다) 떠난 사람의
    // 표시용 항목이 잠시 남는다. 여기서 걸러 두 필드의 불일치가 화면에 새지 않게 한다.
    // 남은 항목은 다음 방장 쓰기(`_groupToDoc`)에서 문서에서도 사라진다.
    // 손상 값(리스트가 아님)도 `null`과 같게 본다 — 여기서 터뜨려 봐야 목록 전체가
    // 죽을 뿐이고, 멤버십의 실제 판정은 보안 규칙이 서버에서 한다.
    final List<dynamic>? rawIds = docListOrNull(data['memberIds']);
    final List<GroupMember> members = rawIds == null
        // 레거시 문서엔 memberIds가 없을 수 있다 — 그때는 members를 그대로 믿는다.
        ? parsed
        : parsed
            .where((GroupMember m) => rawIds.contains(m.userId))
            .toList(growable: false);
    // Group 생성자 불변식(멤버≥1, 방장 정확히 1명)을 못 지키면 스킵.
    final int owners =
        members.where((GroupMember m) => m.role == MemberRole.owner).length;
    if (members.isEmpty || owners != 1) return null;
    // 레거시 문서엔 maxMembers가 없어 기본값을 쓰고, 손상 값(현재 멤버 수보다 작음)은
    // 현재 멤버 수로 끌어올려 불변식(>=1, >=memberCount)을 지킨다.
    //
    // **상한은 두지 않는다.** 계약([ShareRepository.createGroup])이 "최소 1"만 규정하고
    // 상한이 없으며 [InMemoryShareRepository]도 값을 그대로 보관하므로, 여기서만 조이면
    // 두 구현이 갈라진다(정원 30으로 만든 그룹이 20으로 읽히고, 방장이 한 번 쓰면
    // [_groupToDoc]이 그 축소값을 문서에 굳힌다). 프리셋은 UI 선택지이지 계약 상한이 아니다.
    //
    // 포화(`1e300` → int64 최대값 → [Group.isFull]이 영원히 false)는 [docInt]가 정수로
    // 정확히 읽히지 않는 double을 `null`로 떨어뜨려 막는다 — 값을 조이는 것이 아니라
    // **읽기 실패**로 다루는 쪽이 계약을 침범하지 않는다.
    final int rawMax = docInt(data['maxMembers']) ?? Group.defaultMaxMembers;
    final int maxMembers = rawMax < members.length ? members.length : rawMax;
    return Group(
      id: id,
      name: docString(data['name']),
      emoji: docString(data['emoji'], '🎁'),
      // 레거시 문서는 이 필드를 `inviteCode`로 갖고 있다(토큰으로 이름을 바꾸기 전).
      // 읽을 때만 받아 주고, 그 그룹에 다음 쓰기가 일어나면 새 이름으로 옮겨간다.
      inviteToken:
          docStringOrNull(data['inviteToken']) ?? docString(data['inviteCode']),
      // 결측(레거시)은 기본 정책(false)이지만, **손상은 true로 닫는다** —
      // [Group.canInvite]는 `!inviteOwnerOnly`일 때 모든 멤버에게 열리므로 false가 더
      // 허용적인 값이다. 뭉쳐서 false로 떨어뜨리면 방장이 잠가 둔 정책이 손상 하나로
      // 조용히 풀린다.
      inviteOwnerOnly:
          docBool(data['inviteOwnerOnly'], ifAbsent: false, ifCorrupt: true),
      // [docDate]의 epoch 폴백이 곧 **fail-closed**다 — 값이 없거나(24시간 정책 이전의
      // 레거시 문서) 손상이면 이미 만료된 것으로 보고 참여를 거부한다. 레거시 토큰은
      // 어차피 24시간이 지났고, 방장의 [regenerateInviteToken]이 복구 경로다.
      inviteExpiresAt: docDate(data['inviteExpiresAt']),
      maxMembers: maxMembers,
      members: members,
    );
  }

  /// 유효한 그룹을 요구하는 문맥용 — 불변식을 못 만족하면 [StateError].
  ///
  /// **되쓰지 않는 경로 전용이다**(삭제·권한 판정·인자로 받은 값만 갱신). 관대 매퍼의 폴백을
  /// 그대로 받아들이는데, 그 값이 문서로 돌아가지 않으므로 굳을 일이 없다.
  ///
  /// 여기에 강한 검증을 붙이면 **손상 문서의 유일한 앱 내 탈출구가 막힌다** — 손상된 그룹을
  /// 삭제하거나 나가려는 것마저 거부되어 콘솔 수동 편집 말고는 복구 경로가 없어진다.
  /// 검증은 "무엇을 되쓰는가"에 맞춘다([_groupFromDocForMembershipWrite]·
  /// [_groupFromDocForFullWrite]).
  Group _groupFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Group? g = _groupFromDocOrNull(doc);
    if (g == null) throw StateError('Malformed group document: ${doc.id}');
    return g;
  }

  /// 멤버십을 **파생해 되쓰는** 경로용([leaveGroup]의 [_memberIdsPatch]).
  Group _groupFromDocForMembershipWrite(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      requireGroupMembershipFromData(
          doc.id, doc.data() ?? const <String, dynamic>{});

  /// 문서 **전체를 되쓰는** 경로용([_groupToDoc]).
  Group _groupFromDocForFullWrite(DocumentSnapshot<Map<String, dynamic>> doc) =>
      requireGroupFromData(doc.id, doc.data() ?? const <String, dynamic>{});

  /// 멤버십 되쓰기용 검증 — `members`·`memberIds`의 손상만 거부한다.
  ///
  /// **읽기는 관대하게, 쓰기는 엄격하게.** [groupFromDataOrNull]의 폴백 흡수는 목록이 문서
  /// 하나로 죽지 않게 하려는 것이지, 그 값으로 쓰기를 진행해도 된다는 뜻이 아니다. 멤버십은
  /// 관대 매퍼가 두 번 걸러내는데(유령 멤버 필터, `memberIds` 교집합), 걸러진 결과를 되쓰면
  /// **그 멤버가 문서에서 영구히 사라진다** — 표시 문제가 데이터 손실이 된다:
  ///
  /// - `userId`를 못 읽은 항목은 유령 필터에 걸린다.
  /// - `memberIds` 원소가 손상되면 `rawIds.contains(userId)`가 실패해 **정상 멤버가 탈락**한다.
  ///
  /// 되쓰지 않는 필드(`name`·`emoji`·만료 등)는 여기서 보지 않는다 — 막아도 얻는 것 없이
  /// 나가기만 못 하게 된다.
  ///
  /// **결측은 손상이 아니다.** 레거시 문서엔 `memberIds`가 없고, 그건 `members`를 그대로
  /// 믿는 것이 맞다.
  @visibleForTesting
  static Group requireGroupMembershipFromData(
    String id,
    Map<String, dynamic> data,
  ) {
    final Group? g = groupFromDataOrNull(id, data);
    if (g == null) throw StateError('Malformed group document: $id');
    if (!_membershipTypesOk(data)) {
      throw StateError('Malformed group document: $id');
    }
    return g;
  }

  /// 전체 되쓰기용 검증 — [_groupToDoc]이 싣는 필드의 **원본 타입**을 전부 확인한다.
  ///
  /// [requireGroupMembershipFromData]의 멤버십 검사에 더해, 흡수된 폴백이 되쓰기로 굳으면
  /// **실제로 무언가를 잃는** 필드를 막는다:
  ///
  /// - `name`·`emoji`·`inviteToken` — 손상 값도 사람이 보면 원래 의도를 알 수 있는 정보인데,
  ///   되쓰면 `''`로 지워진다(결측은 애초에 잃을 것이 없어 허용한다).
  /// - `inviteOwnerOnly` — **결측(false)과 손상(true)의 결과가 다른 유일한 필드**다. 손상이
  ///   굳으면 방장이 정하지 않은 정책이 문서에 박혀 일반 멤버의 초대가 영구히 닫힌다.
  ///
  /// **막지 않는 것과 그 이유** — `maxMembers`·`inviteExpiresAt`은 [docInt]·[docDate]가
  /// 결측과 손상에 **똑같은 값**을 주므로(기본값·epoch), 거부해도 최종 상태가 달라지지 않고
  /// 잃는 것은 방장의 멤버 관리 능력뿐이다(그 문서에서 멤버를 못 내보낸다). 만료가 깨진
  /// 그룹의 복구 경로인 [regenerateInviteToken]은 되쓰지 않는 등급이라 이미 동작한다.
  /// `inviteCode`는 [_groupToDoc]이 아예 쓰지 않고, `inviteToken`이 정상이면 읽히지도 않는다.
  /// `ownerId`도 검사하지 않는다 — 매퍼가 읽지 않고 [_groupToDoc]이 `g.owner.userId`로 항상
  /// 재계산하므로 손상 값은 굳는 게 아니라 복구된다.
  ///
  /// 어긋나면 [StateError] — 트랜잭션이 실패하고 문서는 손상된 채 보존된다(고칠 기회가 남는다).
  @visibleForTesting
  static Group requireGroupFromData(String id, Map<String, dynamic> data) {
    final Group g = requireGroupMembershipFromData(id, data);
    final bool typesOk = _absentOrString(data['name']) &&
        _absentOrString(data['emoji']) &&
        _absentOrString(data['inviteToken']) &&
        (data['inviteOwnerOnly'] == null || data['inviteOwnerOnly'] is bool);
    if (!typesOk) throw StateError('Malformed group document: $id');
    return g;
  }

  static bool _absentOrString(Object? v) => v == null || v is String;

  /// 되쓰기로 멤버가 사라질 수 있는 두 필드의 원본 타입 검사.
  static bool _membershipTypesOk(Map<String, dynamic> data) {
    final Object? rawMembers = data['members'];
    final bool membersOk = rawMembers == null ||
        (rawMembers is List<dynamic> &&
            rawMembers.every((dynamic m) =>
                m is Map<String, dynamic> &&
                m['userId'] is String &&
                (m['userId'] as String).isNotEmpty &&
                _absentOrString(m['displayName']) &&
                _absentOrString(m['avatarEmoji']) &&
                _absentOrString(m['role'])));
    final Object? rawIds = data['memberIds'];
    final bool idsOk = rawIds == null ||
        (rawIds is List<dynamic> && rawIds.every((dynamic e) => e is String));
    return membersOk && idsOk;
  }

  Map<String, dynamic> _sharedToDoc(SharedGifticon s) => <String, dynamic>{
        'groupId': s.groupId,
        'gifticonId': s.gifticonId,
        'sharedByUserId': s.sharedByUserId,
        'brand': s.brand,
        'productName': s.productName,
        'expiryDate': Timestamp.fromDate(s.expiryDate),
        'status': s.status.name,
        'lockedByUserId': s.lockedByUserId,
        'reservedByUserId': s.reservedByUserId,
        'barcode': s.barcode,
      };

  SharedGifticon _sharedFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      sharedFromData(doc.id, doc.data() ?? const <String, dynamic>{});

  /// [_sharedFromDoc]의 순수 본체(문서 없이 맵만으로 동작 — 테스트 진입점).
  ///
  /// 손상 문서라도 **던지지 않는다.** 이 매퍼는 목록 매핑
  /// ([watchSharedGifticons]/[getSharedGifticons])에서도 쓰이므로, 문서 하나가 예외를
  /// 던지면 그룹의 공유 목록 스트림 전체가 죽는다.
  ///
  /// ⚠️ **이 관용은 읽기(목록) 전용이다.** 손상된 `status`가 [ShareStatus.available]로
  /// 떨어지는 것은 화면에 한 줄 잘못 그리는 정도지만, 쓰기 경로에서는 사용 완료 가드를
  /// 통과시켜 [UsageLog]를 중복 적재한다. 쓰기 트랜잭션은 [requireSharedFromData]를 쓴다.
  @visibleForTesting
  static SharedGifticon sharedFromData(String id, Map<String, dynamic> data) {
    return SharedGifticon(
      id: id,
      groupId: docString(data['groupId']),
      gifticonId: docString(data['gifticonId']),
      sharedByUserId: docString(data['sharedByUserId']),
      brand: docString(data['brand']),
      productName: docString(data['productName']),
      expiryDate: docDate(data['expiryDate']),
      status: _shareStatusFromName(docStringOrNull(data['status'])),
      lockedByUserId: docStringOrNull(data['lockedByUserId']),
      reservedByUserId: docStringOrNull(data['reservedByUserId']),
      barcode: docStringOrNull(data['barcode']),
    );
  }

  /// 쓰기 트랜잭션용 매퍼 — 손상 문서면 [StateError].
  SharedGifticon _requireSharedFromDoc(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      requireSharedFromData(doc.id, doc.data() ?? const <String, dynamic>{});

  /// [_requireSharedFromDoc]의 순수 본체(문서 없이 맵만으로 동작 — 테스트 진입점).
  ///
  /// **읽기는 관대하게, 쓰기는 엄격하게.** [sharedFromData]의 기본값 흡수는 문서 하나가
  /// 목록 스트림 전체를 죽이지 않게 하려는 것이지, 손상 문서로 **쓰기를 진행해도 된다는
  /// 뜻이 아니다.** 그대로 쓰기에 쓰면:
  ///
  /// - 손상된 `status`가 [ShareStatus.available]로 읽혀 [markUsed]의 상태 가드를 통과한다
  ///   (가드가 이 매퍼의 결과를 보므로 독립 검증이 아니다). 이미 사용한 항목이 한 번 더
  ///   사용 완료되고 [UsageLog]가 중복 적재된다.
  /// - 빈 `groupId`·`sharedGifticonId`가 이력·알림 문서에 그대로 적재된다.
  /// - 빈 `gifticonId`가 `_syncOriginalUsed('')`로 흘러 빈 문서 경로를 만든다.
  ///
  /// 그래서 관대 매퍼의 **결과가 아니라 원본 문서**를 다시 보고 필수 식별자 셋과 `status`의
  /// 온전함을 확인하며, 하나라도 어긋나면 계약대로 [StateError]를 던진다. 정상 문서는 항상
  /// 이 넷을 갖는다 — [_sharedToDoc]과 `tool/seed_emulator.sh`가 모두 채워 쓴다.
  @visibleForTesting
  static SharedGifticon requireSharedFromData(
    String id,
    Map<String, dynamic> data,
  ) {
    final SharedGifticon item = sharedFromData(id, data);
    final bool identifiersOk = item.groupId.isNotEmpty &&
        item.gifticonId.isNotEmpty &&
        item.sharedByUserId.isNotEmpty;
    // status는 폴백이 available이라 결과값만으로는 손상을 알 수 없다 — 원본을 다시 본다.
    final bool statusOk =
        _shareStatusFromNameOrNull(docStringOrNull(data['status'])) != null;
    if (!identifiersOk || !statusOk) {
      throw StateError('Malformed shared gifticon document: $id');
    }
    return item;
  }

  UsageLog _logFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      logFromData(doc.id, doc.data() ?? const <String, dynamic>{});

  /// [_logFromDoc]의 순수 본체(문서 없이 맵만으로 동작 — 테스트 진입점).
  @visibleForTesting
  static UsageLog logFromData(String id, Map<String, dynamic> data) {
    return UsageLog(
      id: id,
      groupId: docString(data['groupId']),
      userId: docString(data['userId']),
      sharedGifticonId: docString(data['sharedGifticonId']),
      brand: docString(data['brand']),
      productName: docString(data['productName']),
      usedAt: docDate(data['usedAt']),
    );
  }

  Map<String, dynamic> _notifToDoc(
    GroupNotificationType type,
    String groupId, {
    required String title,
    required String message,
  }) =>
      <String, dynamic>{
        'groupId': groupId,
        'type': type.name,
        'title': title,
        'message': message,
        'createdAt': Timestamp.now(),
      };

  GroupNotification _notifFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      notifFromData(doc.id, doc.data() ?? const <String, dynamic>{});

  /// [_notifFromDoc]의 순수 본체(문서 없이 맵만으로 동작 — 테스트 진입점).
  @visibleForTesting
  static GroupNotification notifFromData(String id, Map<String, dynamic> data) {
    return GroupNotification(
      id: id,
      groupId: docString(data['groupId']),
      type: _notifTypeFromName(docStringOrNull(data['type'])),
      title: docString(data['title']),
      message: docString(data['message']),
      createdAt: docDate(data['createdAt']),
    );
  }

  /// 잠금 문서 참조 — [gifticonId]를 문서 id로 쓸 수 없으면 `null`.
  ///
  /// `doc('')`은 [ArgumentError]를 던져, 손상 문서 하나가 **그룹 삭제·공유 회수를 영구히
  /// 막는다**(재시도해도 문서가 그대로다). 지울 잠금을 못 찾으면 건너뛰는 편이 낫다.
  ///
  /// ⚠️ 호출부에 따라 의미가 다르다. [cancelShare]에서는 [requireSharedFromData]가 앞서
  /// 빈 `gifticonId`를 걸러내므로 이 널 가지에 **도달하지 않는다** — 이 방어는 검증 없이
  /// 원시 문서를 순회하는 [_cascadeDeleteGroupShares]를 위한 것이다.
  ///
  /// 그쪽의 잔여 위험: 빈 id에는 대응 잠금이 아예 없지만, `gifticonId` **필드가 타입 손상**
  /// 이면 원래 id를 알 수 없어 그 id로 만들어진 잠금이 **고아로 남는다** — 해당 기프티콘은
  /// [shareGifticon]의 잠금 검사에 걸려 다시 공유할 수 없다. 전체 실패보다는 나은 절충이며,
  /// 복구는 콘솔에서 잠금 문서를 지우는 것이다.
  DocumentReference<Map<String, dynamic>>? _lockRefOrNull(String? gifticonId) =>
      isUsableDocId(gifticonId) ? _locks.doc(gifticonId!) : null;

  static MemberRole _roleFromName(String? name) =>
      name == MemberRole.owner.name ? MemberRole.owner : MemberRole.member;

  /// 저장된 `status` 문자열 → [ShareStatus]. **알 수 없는 값이면 `null`.**
  ///
  /// 폴백을 붙이지 않은 변형이 따로 필요한 이유: [_shareStatusFromName]이 알 수 없는 값을
  /// [ShareStatus.available]로 떨어뜨리므로, 결과값만 보면 "정상 available"과 "손상"을
  /// 구분할 수 없다. 쓰기 경로의 검증([requireSharedFromData])은 그 구분이 필요하다.
  static ShareStatus? _shareStatusFromNameOrNull(String? name) {
    for (final ShareStatus s in ShareStatus.values) {
      if (s.name == name) return s;
    }
    return null;
  }

  static ShareStatus _shareStatusFromName(String? name) =>
      _shareStatusFromNameOrNull(name) ?? ShareStatus.available;

  static GroupNotificationType _notifTypeFromName(String? name) {
    for (final GroupNotificationType t in GroupNotificationType.values) {
      if (t.name == name) return t;
    }
    return GroupNotificationType.registered;
  }

  /// 새 초대 토큰. 생성 규칙은 공유 유틸 하나에서만 정한다(두 구현이 갈리지 않게).
  String _randomToken() => newInviteToken();
}
