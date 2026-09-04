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
import '../../../util/invite_code.dart';
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

  /// 초대코드 → 그룹 조회 컬렉션. 문서 id가 **6자리 코드**다.
  ///
  /// `inviteTokens`와 나눈 이유는 만료의 정본이 다르기 때문이다([_inviteCodeToDoc] 참조).
  /// 점유는 **그룹당 최대 1건**으로 묶인다(발급 시 옛 문서를 먼저 지운다) — 10^6 공간에서
  /// 충돌이 무시할 수준으로 남는 근거이자, 열거의 수확을 '지금 초대를 기다리는 그룹'으로
  /// 제한하는 근거다.
  static const String inviteCodesCollection = 'inviteCodes';

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

  CollectionReference<Map<String, dynamic>> get _inviteCodes =>
      _db.collection(inviteCodesCollection);

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
        await _cascadeDeleteGroupJoinArtifacts(groupId, g.inviteToken,
            inviteCode: g.inviteCode);
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
      if (preGroup != null) await _restoreInviteCredentials(preGroup);
      rethrow;
    }

    if (cascade) {
      await _cascadeDeleteGroupShares(groupId);
    } else {
      // 그룹이 남는 분기 — 떠난 사람의 승인 기록만 거둔다.
      await _dropJoinRequest(groupId, me.id);
      // 사라질 줄 알고 미리 거뒀는데 그룹이 남았다면(그사이 누가 합류) 링크를 되살린다.
      if (preGroup != null) await _restoreInviteCredentials(preGroup);
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
        await _cascadeDeleteGroupJoinArtifacts(groupId, preGroup.inviteToken,
            inviteCode: preGroup.inviteCode);
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
      if (preGroup != null) await _restoreInviteCredentials(preGroup);
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

  /// 이 그룹이 쓸 수 있는 6자리 코드를 고른다 — **남의 그룹이 쥔 코드는 피한다.**
  ///
  /// 조회 문서 id가 코드이므로 10^6 공간에서 충돌이 가능하다. 확률은 낮지만(점유는
  /// 그룹당 1건), 충돌을 그냥 두면 보안 규칙의 '돌려쓰기 금지' 조항에 막혀 발급이
  /// permission-denied로 죽는다 — 방장에게는 이유 없는 실패로 보인다. 미리 피한다.
  ///
  /// 만료된 남의 문서도 피하는 이유: 규칙은 만료를 보지 않고 `groupId`만 본다(그래야
  /// 남의 링크를 빼앗을 수 없다). 즉 만료 여부와 무관하게 그 코드는 쓸 수 없다.
  ///
  /// 시도가 모두 실패하면 [StateError] — 조용히 충돌한 코드를 반환해 다음 단계에서
  /// 정체 모를 권한 오류를 내는 것보다 낫다.
  /// ⚠️ **레거시 6자리 링크 토큰과도 겹치면 안 된다.** 링크 토큰이 128비트가 된 것은
  /// v3.0이고 그 이전 토큰은 6자리 숫자였다 — 그 값들이 아직 살아 있다(팀 공용 시드
  /// `482913` 등). 같은 값을 코드로 발급하면 [requestToJoin]이 코드를 먼저 보므로
  /// **그 그룹의 레거시 링크가 도달 불가**가 된다(코드가 만료되면 '만료' 안내까지 받는다).
  /// 두 컬렉션을 모두 확인해 그 값을 피한다.
  Future<String> _availableInviteCode(String groupId) async {
    const int attempts = 5;
    for (int i = 0; i < attempts; i++) {
      final String code = newInviteCode();
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _inviteCodes.doc(code).get();
      // 남의 그룹이 쥔 코드는 규칙이 돌려쓰기를 막으므로 다시 뽑는다.
      if (doc.exists && docStringOrNull(doc.data()?['groupId']) != groupId) {
        continue;
      }
      // 레거시 링크 토큰과 겹쳐도 다시 뽑는다. 내 그룹 것이어도 마찬가지다 —
      // 내 링크를 내 코드로 가리는 것도 똑같이 그 링크를 죽인다.
      if ((await _inviteTokens.doc(code).get()).exists) continue;
      return code;
    }
    throw StateError('Could not allocate an invite code for group: $groupId');
  }

  @override
  Future<Group> issueInviteCode({required String groupId}) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);
    final String code = await _availableInviteCode(groupId);
    final DateTime expiresAt = DateTime.now().add(Group.inviteCodeValidity);

    String? oldCode;
    // 그룹 문서를 **먼저** 갱신한다. 순서를 뒤집을 수 없다 — 조회 문서의 쓰기 규칙이
    // `expiresAt == group.inviteCodeExpiresAt`를 요구하므로, 그룹이 아직 옛 값이면
    // 새 조회 문서 쓰기가 규칙에 막힌다.
    final Group updated =
        await _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
      if (!g.isOwnedBy(me.id)) {
        throw StateError('Only the owner can issue an invite code: $groupId');
      }
      oldCode = g.inviteCode;
      final Group next =
          g.copyWith(inviteCode: code, inviteCodeExpiresAt: expiresAt);
      // 부분 갱신이다 — 전체 되쓰기가 아니므로 관대 매퍼(`_groupFromDoc`)로 충분하고,
      // 레거시 문서에 없던 필드가 기본값으로 함께 굳는 일도 없다(PR #100 규약).
      tx.update(ref, <String, dynamic>{
        'shortInviteCode': next.inviteCode,
        'shortInviteCodeExpiresAt': Timestamp.fromDate(expiresAt),
      });
      return next;
    });

    try {
      // 옛 코드 문서를 **먼저** 지운다(재발급과 같은 fail-closed 순서). 계약이
      // "그룹당 활성 코드 하나"라, 새 문서를 먼저 쓰면 둘 다 열리는 창이 생긴다.
      //
      // 이 삭제도 `try` 안이어야 한다 — 밖에 두면 삭제 실패 시 되돌리기 없이 예외가
      // 나가고, 옛 코드가 살아남은 채 그룹만 새 코드를 내걸어 '활성 코드 하나'가
      // 깨진다(그 창 동안 6자리를 정당화하는 세 축 중 하나가 무너진다).
      if (oldCode != null && oldCode != code) {
        await _inviteCodes.doc(oldCode!).delete();
      }
      await _inviteCodes.doc(code).set(_inviteCodeToDoc(updated));
    } catch (_) {
      // 조회 문서를 못 만들었으면 그룹이 **아무도 풀 수 없는 코드**를 내걸게 된다 —
      // 방장 화면엔 6자리가 뜨는데 받는 쪽은 '없는 코드'로 거부당한다. 그룹 쪽 표시를
      // 원래대로 되돌려 그 어긋남을 없앤다(복구 경로는 버튼을 다시 누르는 것).
      await _restoreInviteCodeAfterFailure(ref, oldCode);
      rethrow;
    }
    return updated;
  }

  /// 조회 문서 생성 실패 시 그룹 문서의 코드 표시를 되돌린다.
  ///
  /// 되돌리기 자체가 실패해도 삼킨다 — 이 경로는 이미 원래 예외를 던지는 중이고, 정리
  /// 실패로 그 예외를 가리면 방장이 진짜 원인을 못 본다. 최악의 결과는 화면에 뜬 코드가
  /// 먹히지 않는 것이고, 그건 5분 뒤 저절로 사라진다.
  Future<void> _restoreInviteCodeAfterFailure(
    DocumentReference<Map<String, dynamic>> ref,
    String? oldCode,
  ) async {
    try {
      // 옛 코드는 이 시점에 이미 지워졌으므로 되살리지 않는다(살려도 조회 문서가 없다).
      // 표시만 '코드 없음'으로 닫는다.
      await ref.update(<String, dynamic>{
        'shortInviteCode': FieldValue.delete(),
        'shortInviteCodeExpiresAt': FieldValue.delete(),
      });
    } catch (_) {
      // 무시 — 위 주석 참조.
    }
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

  /// 초대**코드** 조회 문서 — 토큰 쪽과 같은 두 필드지만 만료의 정본이 다르다
  /// (`inviteCodeExpiresAt`, 5분). 컬렉션을 나눈 이유가 이것이다: 보안 규칙이 조회
  /// 문서의 `expiresAt`을 그룹 문서의 정본과 **같은 값으로 못박는데**, 한 컬렉션에
  /// 24시간짜리와 5분짜리를 섞으면 그 검사를 쓸 수 없다.
  ///
  /// [g]의 코드가 비어 있으면 호출하지 않는다(호출부가 발급 직후에만 부른다).
  Map<String, dynamic> _inviteCodeToDoc(Group g) => <String, dynamic>{
        'groupId': g.id,
        'expiresAt': Timestamp.fromDate(g.inviteCodeExpiresAt!),
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
  Future<JoinRequest> requestToJoin(String credential) async {
    final User me = _requireUser();

    // 자격증명은 모양으로 갈린다 — 6자리 숫자면 초대코드(`inviteCodes`), 아니면 링크
    // 토큰(`inviteTokens`). 비멤버는 규칙상 `groups`를 못 읽으므로 그룹으로 가는 다리는
    // 이 조회 문서뿐이고, 그래서 만료의 정본도 이 문서가 들고 있다.
    //
    // ⚠️ 모양으로 **고르되, 빗나가면 다른 쪽도 본다.** 배타적으로 고르면 v3.0(128비트)
    //    이전의 **6자리 링크 토큰**이 통째로 '없는 코드'가 된다 — 그 값들은 아직 살아
    //    있다(팀 공용 시드 `482913`, 데모 시드, 레거시 Firestore 문서). 보안 규칙의
    //    `credentialGrants`도 두 컬렉션을 OR로 보므로, 여기만 배타적이면 클라이언트가
    //    규칙보다 좁아 **정상 링크를 스스로 거부**하는 셈이 된다.
    //
    //    코드를 **먼저** 보므로 "만료는 사용한 자격증명 기준"은 그대로다 — 살아 있는
    //    코드가 있으면 그것으로 판정되고, 폴백은 코드 문서가 아예 없을 때만 탄다.
    final bool codeShaped = isWellFormedInviteCode(credential);
    DocumentSnapshot<Map<String, dynamic>> credDoc =
        await (codeShaped ? _inviteCodes : _inviteTokens).doc(credential).get();
    // "이것이 코드였는가"의 정본은 모양이 아니라 **어느 컬렉션에서 찾았는가**다. 폴백을
    // 타면 6자리라도 링크 토큰이므로 여기서 `false`로 내린다 — 이 값이 아래 만료 안내의
    // 근거가 되고, 화면은 이것을 그대로 쓴다(계약: 구현체가 폴백 판정을 싣는다).
    bool isCode = codeShaped;
    if (!credDoc.exists && codeShaped) {
      credDoc = await _inviteTokens.doc(credential).get();
      isCode = false;
    }
    final Map<String, dynamic> t = credDoc.data() ?? const <String, dynamic>{};
    final Object? groupId = t['groupId'];
    if (!credDoc.exists || groupId is! String || groupId.isEmpty) {
      throw StateError('No group for invite credential: $credential');
    }
    // 값이 없거나 손상이면 만료로 닫는다 — 레거시 문서를 만료로 읽는 기존 규약과 같은
    // fail-closed다. 코드로 들어왔으면 이 문서의 만료가 5분 창이고, 링크면 24시간 창이라
    // **사용한 자격증명 기준**이라는 계약이 문서 선택만으로 지켜진다.
    final Object? expiresAt = t['expiresAt'];
    if (expiresAt is! Timestamp ||
        !DateTime.now().isBefore(expiresAt.toDate())) {
      // 만료 창을 고른 것이 곧 문서 선택이므로, 같은 판정을 그대로 싣는다.
      throw InviteExpiredException(credential, isCode: isCode);
    }

    // 이미 멤버인지 — 멤버는 그룹을 읽을 수 있고 비멤버는 규칙에 막힌다. 그 차이를
    // 그대로 판정에 쓴다(읽지 못하는 것이 비멤버의 정상 경로다).
    try {
      final Group? g = await getGroupById(groupId);
      if (g != null && g.isMember(me.id)) {
        throw StateError('Already a member of group: $groupId');
      }
    } on FirebaseException catch (e) {
      // 읽기 **거부** = 비멤버. 요청을 계속 진행한다. 거부만 그렇다 — 일시적 실패
      // (unavailable 등)까지 삼키면 이미 멤버인 사람이 비멤버로 오판되어 자기
      // 그룹에 참여 요청을 만들러 내려간다(아래 요청 문서 읽기와 같은 규약).
      if (e.code != 'permission-denied') rethrow;
    }

    final DocumentReference<Map<String, dynamic>> ref =
        _joinRequests.doc(_joinRequestId(groupId, me.id));

    // 존재 확인(멱등성 판정) — 읽기 규약은 [_readJoinRequestDocOrNull] 한 벌이고,
    // 여기서는 그 `null`(권한 거부)을 "아직 없음"으로 소비한다.
    //
    // 예전에는 이 확인이 트랜잭션 안의 읽기였고, 없는 문서의 반오라클 403(공용 읽기
    // 머리말 참조)에 걸려 규칙 있는 백엔드에서 **첫 요청이 항상 실패**했다
    // (2026-09-03 dev 실측 — 여기는 문서 없음이 **정상 경로**다). 그래서 트랜잭션을
    // 걷어냈다. 서버 강제가 아니면 캐시가 판정을 뒤집는다 — 캐시가 비면 살아 있는
    // 대기 요청을 덮어써 `requestedAt`이 초기화되고, 낡은 pending이 남았으면 거절 뒤
    // 재요청이 아무것도 쓰지 않은 채 "대기 중"으로 끝난다.
    // ⚠️ 읽기 성공 뒤 연결이 끊기면 아래 `set`은 로컬 큐에 들어가고 Future는 서버
    //    ack까지 끝나지 않는다(flutterfire #17643) — 그 창은 아래 쓰기 타임아웃이
    //    닫는다.
    final DocumentSnapshot<Map<String, dynamic>>? snap =
        await _readJoinRequestDocOrNull(ref);
    // 없는 문서는 매퍼가 null로 접는다(`data()`가 null → 필수 필드 결측).
    final JoinRequest? existing =
        snap == null ? null : _joinRequestFromDocOrNull(snap);
    if (existing != null && existing.isPending) {
      return existing; // 멱등 — 같은 링크를 두 번 눌러도 요청이 쌓이지 않는다.
    }
    // 결정이 끝난 요청(거절, 또는 승인 후 강퇴)은 다시 대기로 되돌린다.
    //
    // 확인-후-쓰기는 원자적이지 않다. 이 쓰기를 다투는 상대는 사실상 **다른 기기의
    // 나 자신**뿐이고(방장의 승인·거절과의 경합은 규칙이 닫는다 — 승인 뒤에는
    // `canRequestJoin`의 멤버십 검사가, 거절 직후에는 방장 조항의
    // `status == 'pending'` 전제가 서로의 쓰기를 거부한다), 겹치면 내 대기 요청을
    // 내가 덮어써 `requestedAt`이 뒤로 가고(방장 목록은 오래된 순 — 손해 보는 쪽도
    // 나다) `credential`이 마지막 것으로 바뀐다(규칙의 만료 판정도 그 마지막
    // 자격증명 기준이 되므로 "만료는 사용한 자격증명 기준" 계약과는 정합).
    final JoinRequest req = JoinRequest(
      id: ref.id,
      groupId: groupId,
      userId: me.id,
      displayName: me.displayName,
      avatarEmoji: _defaultAvatar,
      requestedAt: DateTime.now(),
    );
    // 큐에 걸린 채 침묵하지 않도록 시간을 끊는다(위 ⚠️ — 쓰기 도중 단절 창). 타임아웃
    // 뒤 큐의 쓰기가 나중에 도착해도 해롭지 않다 — 다음 요청에서 위 멱등 분기가 그
    // 대기 요청을 그대로 돌려준다. 매달린 스피너보다 시끄러운 실패가 낫다.
    await ref.set(<String, dynamic>{
      'groupId': req.groupId,
      'userId': req.userId,
      'displayName': req.displayName,
      'avatarEmoji': req.avatarEmoji,
      'requestedAt': Timestamp.fromDate(req.requestedAt),
      'status': req.status.name,
      // 사용한 자격증명을 함께 싣는다 — **보안 규칙이 만료를 검사할 근거**다.
      //
      // 규칙은 요청이 어떤 경로로 왔는지 알 수 없으므로, 이 값이 없으면 그룹의
      // 24시간 `inviteExpiresAt`으로 판정할 수밖에 없다. 그러면 5분짜리 코드로 얻은
      // `groupId`가 남은 24시간 동안 계속 먹혀서 "5분 만료"가 화면에만 있는 문구가
      // 된다(계약: 만료는 사용한 자격증명 기준).
      //
      // [JoinRequest] 모델에는 넣지 않는다 — 승인 목록도 요청자 화면도 이 값을 쓰지
      // 않는 저장·검증 계층의 세부이고, 계약에 올리면 모든 구현이 지고 갈 짐이 된다
      // (in-memory에는 보안 규칙이 없다). `memberIds`가 문서에만 있는 것과 같은 결이다.
      'credential': credential,
    }).timeout(const Duration(seconds: 15));
    return req;
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

  /// 요청 문서를 서버에서 읽되, **권한 거부만** `null`로 접는다(그 외는 rethrow).
  ///
  /// 첫 요청([requestToJoin]의 멱등성 판정)과 승인·거절·취소의 사전 확인
  /// ([_requireJoinRequestDoc])이 이 읽기 한 벌을 쓴다 — #161과 #162가 같은 규약을
  /// 각자 구현했던 것을 여기로 모았다(두 벌이면 한쪽만 고쳐져 조용히 갈라진다).
  /// **종착만 다르다**: requestToJoin은 `null`을 "아직 없음"으로 소비하고,
  /// _requireJoinRequestDoc은 [JoinRequestUnreadableException]으로 올린다.
  ///
  /// ## 왜 거부가 "없음"인가 (반오라클 403)
  ///
  /// `joinRequests` 읽기 규칙은 `resource.data`를 참조하므로 **없는 문서에서는 평가가
  /// 오류(=거부)로 죽는다** — 존재 오라클을 막으려고 의도적으로 남긴 403이고,
  /// `tool/verify_firestore_rules.sh`의 "없는 요청 문서 조회 → 403"이 그 규약을
  /// 못박는다.
  ///
  /// ## 거부를 "없음"으로 읽어도 안전한 이유
  ///
  /// 읽기 규칙은 요청자 본인과 그 그룹의 방장에게만 열려 있다. 요청자 쪽 대칭은
  /// 생성·변경 규칙이 담보한다 — 문서 id 규약(`{groupId}_{uid}`)과 `userId` 불변을
  /// 강제하므로 이 id에 존재하는 문서는 언제나 내 것이고, 내 문서의 읽기는 허용된다.
  /// 그래서 정당한 행위자(첫 요청·취소하는 요청자, 결정하는 방장)의 읽기가 거부되는
  /// 경우는 문서가 없을 때뿐이다. 제3자의 읽기도 같은 403으로 "없음"이 되지만, 그쪽에
  /// 존재 여부를 구별해 주는 것이야말로 규칙의 반(反)오라클 규약을 저장소가 되뚫는
  /// 일이다 — 행위 가드는 어차피 규칙과 각 본론이 막는다. (그룹이 먼저 소멸해
  /// `isGroupOwner`가 죽은 **고아 요청**도 방장에게 같은 403인데, 그 상태에서 해 줄 수
  /// 있는 것이 없어 다음 행동은 같다. 규칙을 **우회해** 심긴 손상 문서는 이 대칭
  /// 밖이지만, 그때는 뒤이은 쓰기도 같은 이유로 거부되므로 조용히 잘못되지는 않는다
  /// — 이 읽기 쪽 안전 논거는 쓰기 규칙의 그 별도 보증에 기대고 있다.)
  ///
  /// ## `Source.server`
  ///
  /// 판정용 일회성 읽기는 서버를 강제한다(`firebase_bootstrap.dart`의 도달성 검사·
  /// `firebase_auth_repository.dart`의 플랜 조회와 같은 규약 — "캐시로 성공한 척하는
  /// 것을 막는다"). 기본 `serverAndCache`는 오프라인에서 캐시가 답해 판정이 뒤집힌다
  /// — 지워진 문서를 "있음"으로 읽고 본론에서 죽거나, 살아 있는 대기 요청을
  /// "없음"으로 읽어 덮어쓴다(`requestedAt` 초기화). 서버 강제면 오프라인은 즉시
  /// unavailable로 떨어져(rethrow) 화면이 실패를 안내한다.
  /// ⚠️ 이것이 닫는 것은 **읽기 시점의** 단절뿐이다 — 읽기 성공 뒤의 쓰기 단절 창을
  /// 실제로 끊는 것은 [requestToJoin]의 `set`·[cancelJoinRequest]의 `delete`에 걸린
  /// `Future.timeout` 15초 둘뿐이다. 승인·거절의 `runTransaction` 기본 30초는 상한으로
  /// 세지 않는다 — 그 `timeout` 인자가 트랜잭션을 실제로 끊지 못한다는 보고가 있다
  /// (flutterfire #653·#9118). 그쪽 창은 아직 열려 있다.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _readJoinRequestDocOrNull(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await ref.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      // 다른 실패(unavailable 등)까지 "없음"으로 읽으면 일시적 네트워크 문제가
      // "요청이 사라졌다/아직 없다"는 오진이 된다 — 권한 거부만 없음의 신호다.
      if (e.code != 'permission-denied') rethrow;
      return null;
    }
  }

  /// 승인·거절·취소가 본론(트랜잭션·삭제)에 들어가기 **전에** 요청 문서를 서버에서
  /// 읽고([_readJoinRequestDocOrNull]), 없으면 계약의 [StateError]("Join request not
  /// found")로 던진다.
  ///
  /// ## 왜 본론의 읽기만으로는 안 되는가 (경합 경로)
  ///
  /// 없는 문서의 읽기는 반오라클 403으로 죽는다([_readJoinRequestDocOrNull] 머리말이
  /// 정본 — 여기 다시 적지 않는다). 그래서 요청자가 취소한 직후 방장이 승인/거절하거나
  /// 그룹 삭제 캐스케이드 직후 취소하는 **경합**에서, 규칙 있는 백엔드는 계약이 약속한
  /// [StateError] 대신 `FirebaseException(permission-denied)`을 UI까지 올려보냈다
  /// ([requestToJoin]의 "첫 요청" 결함과 같은 뿌리 — 거기는 문서 없음이 정상 경로,
  /// 여기는 경합 한정이라는 점만 다르다).
  ///
  /// 트랜잭션 **전체**의 거부를 뭉뚱그려 번역하는 것으로는 풀 수 없다 — 트랜잭션은
  /// 읽기 하나가 거부되면 통째로 죽고, 그 시점의 permission-denied는 요청 문서 읽기가
  /// 아니라 그룹 읽기·쓰기의 거부일 수도 있어, 뭉뚱그려 "없음"으로 번역하면 다른
  /// 원인을 오진한다. 거부의 주어를 요청 문서 하나로 좁히는 길은 둘이고 이 파일은 둘
  /// 다 쓴다 — 존재 확인을 트랜잭션 밖 **단일 읽기**로 빼는 것(이 함수)과, 트랜잭션
  /// **안의 호출 지점 하나**에만 catch를 붙이는 것([_txGetJoinRequest]).
  /// ⚠️ 그래서 이 함수가 승인·거절에 남는 이유는 좁힘이 **아니다**(그쪽은
  /// [_txGetJoinRequest]가 이미 덮는다) — **오프라인 빠른 실패**다. 서버 강제가 아니면
  /// 캐시가 존재 확인을 통과시켜 본론으로 들여보내는데, 그 뒤의 실패 지연은 SDK가
  /// 정한다 — 벤더 문서는 "Transactions will fail when the client is offline"이지만
  /// 실측 보고는 처음 수십 ms에서 반복하면 10~30초로 늘고 `timeout` 인자가 그것을 끊지
  /// 못한다(flutterfire #6736·#9118). 취소의 **옛 코드**(기본 소스 get)는 같은 이유로
  /// `delete`가 서버 확인을 하염없이 기다려 **버튼이 잠긴 채 아무 안내가 없었다**
  /// (지금은 delete의 15초 상한이 그 창을 닫는다). 취소에는 좁힘·빠른 실패에
  /// 더해 `userId` 소유권 판정까지 여기서 한다. (거부="없음"의 안전 근거와
  /// `Source.server` 규약은 [_readJoinRequestDocOrNull]에 있다.)
  ///
  /// 잔여 창: 이 확인과 본론 사이에 문서가 지워지는 극히 짧은 경합은 남는다 — 그쪽은
  /// 본론의 **요청 문서 접근 한 곳에만** 붙인 같은 번역이 받는다(승인·거절은
  /// [_txGetJoinRequest], 취소는 delete를 감싼 catch). 호출 지점 하나에 붙은 catch라
  /// 거부의 주어가 요청 문서로 좁혀져 있어, 트랜잭션 **전체**의 거부를 뭉뚱그려
  /// 번역할 때의 오진(그룹 읽기·쓰기 거부를 "요청 없음"으로 읽는 것)이 없다. 그룹
  /// 접근의 거부는 그대로 [FirebaseException]으로 올라간다.
  ///
  /// ⚠️ "흡수한 거부를 [JoinRequestUnreadableException]으로 흔적 남기기" 현황.
  /// 통합 뒤로 **catch 지점과 종착이 1:1이 아니므로** 둘을 나눠 센다.
  ///
  /// `permission-denied`를 접는 catch는 **5곳**: 공용 읽기
  /// ([_readJoinRequestDocOrNull])·[_txGetJoinRequest]·[cancelJoinRequest]의 delete·
  /// [requestToJoin]의 멤버십 판정·[_dropJoinRequest]. 이 중 **자기 자리에서 무음인
  /// 것은 둘**이다 — 멤버십 판정(그룹 문서를 만지며 분기만 바꾼다)과
  /// [_dropJoinRequest](예외 없이 정상 종료). 공용 읽기는 스스로 판정하지 않는다.
  ///
  /// 타입 흔적이 남는 **종착은 셋**이다 — 이 함수(공용 읽기의 `null`을 예외로 올림)·
  /// [_txGetJoinRequest]·취소의 delete. 같은 공용 읽기의 `null`이라도 [requestToJoin]
  /// 쪽 종착은 "아직 없음"이라 흔적이 없다(후속 쓰기가 부분적 신호일 뿐이다).
  /// 전면 적용은 별도 작업(저장소→진단 방향 import 순환을 피하는 구조가 필요하다).
  Future<DocumentSnapshot<Map<String, dynamic>>> _requireJoinRequestDoc(
      DocumentReference<Map<String, dynamic>> ref) async {
    final DocumentSnapshot<Map<String, dynamic>>? doc =
        await _readJoinRequestDocOrNull(ref);
    if (doc == null) {
      // 거부를 접되 **접었다는 사실**은 타입으로 남긴다 — 경합(정상)과 규칙 회귀·
      // 배포 스큐(장애)를 리포터가 구별할 유일한 흔적이다([JoinRequestUnreadableException]).
      throw JoinRequestUnreadableException(ref.id);
    }
    // 규칙 없는 백엔드(fake·에뮬레이터의 열린 규칙)는 없는 문서를 거부 대신
    // 빈 스냅샷으로 준다 — 같은 계약 위반이지만 **흡수가 아니라 진짜 없음**이라
    // 신호가 다르므로 평범한 [StateError]로 남긴다.
    if (!doc.exists) {
      throw StateError('Join request not found: ${ref.id}');
    }
    return doc;
  }

  /// 트랜잭션 안에서 요청 문서를 읽되, **이 읽기 한 곳의** 권한 거부만 계약의
  /// "요청 없음"으로 번역한다 — [_requireJoinRequestDoc]이 성공한 뒤 트랜잭션이
  /// 읽기 전에 문서가 지워지는 잔여 경합이 이 모양이다(규칙은 없는 문서의 읽기를
  /// 403으로 닫는다). catch가 호출 지점 하나에 붙어 있으므로 거부의 주어가 요청
  /// 문서로 좁혀져 있다 — 트랜잭션 전체의 거부를 뭉뚱그려 번역할 때의 오진(그룹
  /// 읽기·쓰기 거부를 "요청 없음"으로 읽는 것)과 다르다.
  Future<DocumentSnapshot<Map<String, dynamic>>> _txGetJoinRequest(
      Transaction tx, DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await tx.get(ref);
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      throw JoinRequestUnreadableException(ref.id);
    }
  }

  @override
  Future<Group> approveJoinRequest(String joinRequestId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> reqRef =
        _joinRequests.doc(joinRequestId);
    // 존재 확인은 트랜잭션 밖에서 — 경합으로 이미 지워진 요청이 계약의 [StateError]
    // 대신 permission-denied로 새지 않게 한다([_requireJoinRequestDoc]).
    await _requireJoinRequestDoc(reqRef);

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> reqDoc =
          await _txGetJoinRequest(tx, reqRef);
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
    // 존재 확인은 트랜잭션 밖에서([approveJoinRequest]와 같은 이유 —
    // [_requireJoinRequestDoc]).
    await _requireJoinRequestDoc(reqRef);

    return _db.runTransaction<JoinRequest>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> reqDoc =
          await _txGetJoinRequest(tx, reqRef);
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
    // 그룹 소멸 캐스케이드가 요청을 먼저 지웠을 수 있다 — 그때의 읽기 거부를 계약의
    // [StateError]로 번역하고, 존재 판정은 캐시가 아니라 서버가 한다
    // ([_requireJoinRequestDoc]).
    final DocumentSnapshot<Map<String, dynamic>> doc =
        await _requireJoinRequestDoc(ref);
    if (doc.data()?['userId'] != me.id) {
      throw StateError('Only the requester can cancel: $joinRequestId');
    }
    // 존재 확인이 성공한 **뒤** 끊기면 이 삭제는 로컬 큐에 들어가고 Future는 서버
    // ack까지 끝나지 않는다(flutterfire #17643). 화면의 `_busy`는 catch에서만
    // 풀리므로 그대로 두면 버튼이 영구히 잠긴다 — [requestToJoin]의 쓰기와 같은
    // 상한을 건다. 타임아웃 뒤 큐의 삭제가 늦게 도착해도 해롭지 않다 —
    // `Future.timeout`은 상한이 발화한 뒤 원본 future의 결과를 전달하지 않고
    // (`timer.isActive`가 거짓 — dart-sdk `future_impl.dart`), 핸들러가 달려
    // 있으므로 미처리 비동기 에러도 아니다. ⚠️ "없는 문서의 삭제는 no-op"이라서가
    // 아니다 — `joinRequests`의 delete 규칙은 `resource.data`를 만지므로 문서가
    // 없으면 **403**이다([_dropJoinRequest] 머리말이 같은 사실을 설계 근거로 삼는다).
    try {
      await ref.delete().timeout(const Duration(seconds: 15));
    } on FirebaseException catch (e) {
      // 존재 확인과 이 삭제 사이에 문서가 지워진 잔여 경합 — 규칙은 없는 문서의
      // 삭제를 403으로 닫으므로, 이 한 곳의 거부만 계약의 "요청 없음"으로 번역한다
      // ([_txGetJoinRequest]와 같은 규약 — 이 delete는 요청 문서만 만지므로 거부의
      // 주어가 이미 좁혀져 있다).
      if (e.code != 'permission-denied') rethrow;
      throw JoinRequestUnreadableException(joinRequestId);
    }
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
  /// 넘어가는 등) 그룹은 남고 대기 목록만 비는 상태가 된다. 토큰·코드 문서는 [_restoreInviteCredentials]
  /// 으로 되돌리지만 요청은 못 되돌린다 — 요청자는 다시 요청해야 한다. 그 대신 삭제가
  /// 성공했을 때 아무것도 남지 않는 쪽을 택했다(남으면 아무도 끝낼 수 없다).
  Future<void> _cascadeDeleteGroupJoinArtifacts(
    String groupId,
    String inviteToken, {
    String? inviteCode,
  }) async {
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
    // 초대코드 조회 문서도 함께 거둔다. 남기면 사라진 그룹을 가리키는 코드가 6자리
    // 공간을 계속 점유하고(그 값은 어느 그룹도 다시 쓸 수 없다 — 규칙이 돌려쓰기를
    // 막는다), 코드를 입력한 사람은 '없는 그룹'으로 가는 요청을 만들게 된다.
    // 그룹 삭제 시점에는 방장이므로 삭제 권한이 있다.
    if (inviteCode != null && inviteCode.isNotEmpty) {
      await _inviteCodes.doc(inviteCode).delete();
    }
  }

  /// 선행 정리 뒤 그룹 삭제가 실패했을 때 **초대 자격증명 둘 다** 되살린다.
  ///
  /// 되돌리지 못하면 그룹은 살아 있는데 링크만 죽은 상태가 남고, 방장이 재발급을 누르기
  /// 전까지 아무도 참여를 요청할 수 없다.
  ///
  /// 코드를 빠뜨리면 같은 종류의 어긋남이 코드 쪽에 남는다 — 그룹 문서는 6자리를 계속
  /// 내걸어 방장 화면이 "483920 · 3:52 후 만료"를 표시하는데, 그 코드를 받은 사람은
  /// 조회 문서가 없어 '없는 코드'로 거부당한다(만료 안내조차 아니다).
  /// [_restoreInviteCodeAfterFailure]가 발급 경로에서 막는 것과 같은 상태다.
  Future<void> _restoreInviteCredentials(Group g) async {
    if (g.inviteToken.isNotEmpty) {
      await _inviteTokens.doc(g.inviteToken).set(_inviteTokenToDoc(g));
    }
    // 이미 만료된 코드는 되살리지 않는다 — 조회 문서가 있든 없든 결과가 같고,
    // 되살리면 5분 창이 지난 값이 컬렉션에 남아 점유만 늘린다.
    if (g.hasActiveInviteCode(DateTime.now())) {
      await _inviteCodes.doc(g.inviteCode!).set(_inviteCodeToDoc(g));
    }
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
        // 초대코드는 **있을 때만** 싣는다. 없는 상태를 `null`로 쓰면 "코드 필드가
        // null인 문서"와 "코드 필드가 없는 문서"가 갈리고, 보안 규칙의 필드 검사도
        // 두 모양을 다 받아 줘야 한다 — 결측 하나로 통일한다.
        //
        // ⚠️ 이 맵의 소비자는 대부분 `tx.update`이고, **`update`는 맵에 없는 필드를
        // 지우지 않는다** — 조건부로 빼는 것만으로는 기존 코드가 무효화되지 않는다.
        // 실제로 지우려면 `FieldValue.delete()`를 명시해야 한다
        // ([_restoreInviteCodeAfterFailure]가 그렇게 한다). 여기서 조건부로 싣는 것은
        // '코드 없음'을 `null`이 아니라 **결측**으로 통일하려는 것일 뿐이다(두 모양이
        // 생기면 보안 규칙의 필드 검사도 둘 다 받아 줘야 한다).
        //
        // ⚠️ 문서 키는 `inviteCode`가 **아니라** `shortInviteCode`다. `inviteCode`는
        // 이미 임자가 있다 — 링크 토큰의 **옛 이름**이라, 레거시 문서는 그 키에 토큰을
        // 담고 있고 매퍼가 `inviteToken` 결측 시 폴백으로 읽는다. 같은 키에 6자리를
        // 쓰면 그 그룹의 링크 토큰이 덮여 사라진다(모델 필드명과 문서 키가 다른 이유).
        if (g.inviteCode != null) 'shortInviteCode': g.inviteCode,
        if (g.inviteCodeExpiresAt != null)
          'shortInviteCodeExpiresAt':
              Timestamp.fromDate(g.inviteCodeExpiresAt!),
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
    // 초대코드와 그 만료는 **짝으로** 읽는다 — [Group] 생성자가 "둘 다 있거나 둘 다
    // 없거나"를 강제하므로 한쪽만 넘기면 assert가 깨진다. 관대 매퍼의 일은 손상 문서를
    // 죽이지 않는 것이니, 한쪽이 상하면 둘 다 버려 '코드 없음'으로 떨어뜨린다.
    // 잃는 것은 5분짜리 코드 하나이고 복구는 방장이 버튼을 다시 누르는 것이다.
    //
    // ⚠️ 여기서는 `docDate`의 epoch 폴백을 **쓰지 않는다.** 코드는 없는 것이 기본
    // 상태라, 결측을 '만료된 코드'로 읽으면 코드를 발급한 적 없는 그룹의 발급 화면이
    // 존재한 적 없는 코드의 만료를 표시하게 된다(`inviteExpiresAt`은 반대다 — 만료 없는
    // 링크가 존재하지 않으므로 결측을 만료로 닫는 것이 fail-closed다).
    //
    // 키가 `shortInviteCode`인 이유는 [_groupToDoc] 참조 — `inviteCode`는 링크 토큰의
    // 옛 이름이라 이미 임자가 있다(바로 아래 `inviteToken` 폴백이 그 키를 읽는다).
    final String inviteCode = docString(data['shortInviteCode']);
    final Object? rawCodeUntil = data['shortInviteCodeExpiresAt'];
    final DateTime? inviteCodeUntil =
        inviteCode.isEmpty || rawCodeUntil is! Timestamp
            ? null
            : rawCodeUntil.toDate();
    return Group(
      id: id,
      name: docString(data['name']),
      emoji: docString(data['emoji'], '🎁'),
      // 아래 `inviteCode*` 두 필드는 위에서 짝으로 판정한 값을 쓴다.
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
      // 초대코드는 **없는 것이 기본 상태**다(발급 후 5분만 존재). 그래서 결측을
      // 만료로 닫는 `inviteExpiresAt`과 달리 결측을 그대로 `null`로 둔다 — 여기서
      // epoch 폴백을 쓰면 코드가 없는 그룹이 "만료된 코드를 가진 그룹"이 되어,
      // 발급 화면이 존재한 적 없는 코드의 만료를 표시하게 된다.
      //
      // 짝 불변식(둘 다 있거나 둘 다 없거나)은 [Group] 생성자가 강제하므로, 한쪽만
      // 성한 손상 문서는 여기서 **둘 다 버려** 불변식 위반으로 죽지 않게 한다.
      inviteCode: inviteCodeUntil == null ? null : inviteCode,
      inviteCodeExpiresAt: inviteCodeUntil,
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
  /// 레거시 키 `inviteCode`(= 링크 토큰의 옛 이름)는 [_groupToDoc]이 쓰지 않고,
  /// `inviteToken`이 정상이면 읽히지도 않는다.
  ///
  /// `shortInviteCode`(6자리 초대코드)도 막지 않는다 — 매퍼가 손상을 **결측과 같게**
  /// 다루므로(둘 다 '코드 없음') 거부해도 최종 상태가 달라지지 않는다. 되쓰기로 잃는
  /// 것은 이미 못 읽던 5분짜리 값 하나뿐이고, 거부하면 그 문서에서 멤버 관리가 통째로
  /// 막힌다 — `maxMembers`·`inviteExpiresAt`을 막지 않는 것과 같은 계산이다.
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
