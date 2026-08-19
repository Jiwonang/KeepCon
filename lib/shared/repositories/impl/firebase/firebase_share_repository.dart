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
      final Group g = _groupFromDoc(doc);
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

    await _db.runTransaction<void>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
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

    if (cascade) await _cascadeDeleteGroupShares(groupId);
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);

    await _db.runTransaction<void>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
      if (!g.isOwnedBy(me.id)) {
        throw StateError('Only the owner can delete the group: $groupId');
      }
      tx.delete(ref);
    });

    await _cascadeDeleteGroupShares(groupId);
  }

  @override
  Future<Group> transferOwnershipAndLeave({
    required String groupId,
    required String newOwnerUserId,
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
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
  }

  @override
  Future<Group> removeMember({
    required String groupId,
    required String userId,
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc(groupId);

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
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

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group not found: $groupId');
      final Group g = _groupFromDoc(doc);
      if (!g.isOwnedBy(me.id)) {
        throw StateError('Only the owner can regenerate invite code: $groupId');
      }
      final Group updated =
          g.copyWith(inviteToken: _randomToken(), inviteExpiresAt: expiresAt);
      tx.update(ref, <String, dynamic>{
        'inviteToken': updated.inviteToken,
        'inviteExpiresAt': Timestamp.fromDate(expiresAt),
      });
      return updated;
    });
  }

  // ── 참여 요청(초대 링크 → 방장 승인) ────────────────────────────────
  //
  // **아직 구현하지 않았다.** 계약과 in-memory 구현을 먼저 확정하고, Firestore 구현은
  // 다음 단계에서 스키마와 함께 넣는다. 이 경로는 저장소 스키마 결정에 통째로 매여 있다 —
  // 비멤버는 보안 규칙상 `groups`를 읽을 수 없으므로 토큰으로 그룹을 찾으려면 토큰을
  // 키로 하는 별도 조회 문서가 필요하고, 그 문서를 어떤 모양으로 둘지가 규칙·인덱스를
  // 함께 정한다. 지금 지어 두면 그 결정이 내려질 때 통째로 다시 쓰게 된다.
  //
  // 그때까지 이 메서드들을 호출하는 화면은 없다(참여 요청 UI가 아직 없다). 조용히
  // 아무 일도 안 하는 스텁 대신 [UnimplementedError]를 던지는 이유 — 배선이 먼저
  // 들어왔을 때 즉시 드러나게 하려는 것이다.
  static Never _joinRequestsNotOnFirebaseYet() => throw UnimplementedError(
        '참여 요청은 Firestore 구현이 아직 없습니다. '
        'InMemoryShareRepository(USE_DEMO)에서만 동작합니다.',
      );

  @override
  Future<JoinRequest> requestToJoin(String inviteToken) async =>
      _joinRequestsNotOnFirebaseYet();

  @override
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId) async* {
    // `async*`가 아니면 호출 지점에서 동기 throw가 되어, build나 initState
    // 안에서 스트림을 만드는 순간 프레임이 죽는다. 나머지 6개(Future)는 에러가
    // Future로 전달되므로 실패 방식을 여기에 맞춘다.
    _joinRequestsNotOnFirebaseYet();
  }

  @override
  Future<List<JoinRequest>> getMyJoinRequests(String userId) async =>
      _joinRequestsNotOnFirebaseYet();

  @override
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId) async* {
    // `async*`가 아니면 호출 지점에서 동기 throw가 되어, build나 initState
    // 안에서 스트림을 만드는 순간 프레임이 죽는다. 나머지 6개(Future)는 에러가
    // Future로 전달되므로 실패 방식을 여기에 맞춘다.
    _joinRequestsNotOnFirebaseYet();
  }

  @override
  Future<List<JoinRequest>> getPendingJoinRequests(String groupId) async =>
      _joinRequestsNotOnFirebaseYet();

  @override
  Future<Group> approveJoinRequest(String joinRequestId) async =>
      _joinRequestsNotOnFirebaseYet();

  @override
  Future<JoinRequest> rejectJoinRequest(String joinRequestId) async =>
      _joinRequestsNotOnFirebaseYet();

  @override
  Future<void> cancelJoinRequest(String joinRequestId) async =>
      _joinRequestsNotOnFirebaseYet();

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

  /// 유효한 그룹을 요구하는 문맥(트랜잭션 등)용 — 손상 문서면 [StateError].
  Group _groupFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      requireGroupFromData(doc.id, doc.data() ?? const <String, dynamic>{});

  /// [_groupFromDoc]의 순수 본체(문서 없이 맵만으로 동작 — 테스트 진입점).
  ///
  /// **읽기는 관대하게, 쓰기는 엄격하게.** [groupFromDataOrNull]의 폴백 흡수는 목록이
  /// 문서 하나로 죽지 않게 하려는 것이지, 그 값으로 **쓰기를 진행해도 된다는 뜻이 아니다.**
  /// 이 경로의 결과는 [_groupToDoc]으로 문서 **전체**에 되쓰이므로, 흡수한 값을 그대로
  /// 통과시키면 손상이 정상 값으로 굳는다:
  ///
  /// - 어긋난 `inviteOwnerOnly`가 `true`로 읽혀 되쓰이면 일반 멤버의 초대 권한이 영구히 닫힌다.
  /// - `userId`를 못 읽은 멤버 항목은 유령 필터에 걸러지는데, 그 상태로 되쓰면 **그 멤버가
  ///   문서에서 사라진다**(표시 문제가 데이터 손실이 된다).
  /// - 어긋난 `inviteExpiresAt`이 epoch로 굳으면 방장이 재발급하기 전까지 참여가 막힌다.
  ///
  /// 그래서 [_groupToDoc]이 싣는 필드의 **원본 타입**을 확인하고 하나라도 어긋나면
  /// [StateError]를 던진다 — 트랜잭션이 실패하고 문서는 손상된 채 보존된다(고칠 기회가 남는다).
  ///
  /// **결측은 손상이 아니다.** 레거시 문서엔 `memberIds`·`maxMembers`·`inviteExpiresAt`가
  /// 없고, 그건 기본값을 쓰는 것이 맞다.
  @visibleForTesting
  static Group requireGroupFromData(String id, Map<String, dynamic> data) {
    final Group? g = groupFromDataOrNull(id, data);
    if (g == null) throw StateError('Malformed group document: $id');

    bool absentOrString(Object? v) => v == null || v is String;
    final Object? rawMembers = data['members'];
    final bool membersOk = rawMembers == null ||
        (rawMembers is List<dynamic> &&
            rawMembers.every((dynamic m) =>
                m is Map<String, dynamic> &&
                m['userId'] is String &&
                (m['userId'] as String).isNotEmpty &&
                absentOrString(m['displayName']) &&
                absentOrString(m['avatarEmoji']) &&
                absentOrString(m['role'])));

    final bool typesOk = membersOk &&
        absentOrString(data['name']) &&
        absentOrString(data['emoji']) &&
        absentOrString(data['inviteToken']) &&
        absentOrString(data['inviteCode']) &&
        (data['inviteOwnerOnly'] == null || data['inviteOwnerOnly'] is bool) &&
        (data['maxMembers'] == null || docInt(data['maxMembers']) != null) &&
        (data['inviteExpiresAt'] == null ||
            docDateOrNull(data['inviteExpiresAt']) != null) &&
        // 리스트인지만 보면 부족하다 — 원소가 손상되면 `rawIds.contains(userId)`가
        // 실패해 **정상 멤버가 탈락**하고, 그 상태로 되쓰면 문서에서 영구히 사라진다
        // (유령 멤버 검증이 막으려던 것과 같은 데이터 손실이 다른 경로로 들어온다).
        (data['memberIds'] == null ||
            (data['memberIds'] is List<dynamic> &&
                (data['memberIds'] as List<dynamic>)
                    .every((dynamic e) => e is String)));
    if (!typesOk) throw StateError('Malformed group document: $id');
    return g;
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

  String _randomToken() {
    // 6자리 코드. 원본 인스턴스가 시간/랜덤에 의존하지 않도록 문서 id 해시를 쓴다.
    final int h = _shared.doc().id.hashCode & 0x7fffffff;
    return (100000 + (h % 900000)).toString();
  }
}
