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

import '../../../models/gifticon.dart';
import '../../../models/group.dart';
import '../../../models/share.dart';
import '../../../models/user.dart';
import '../../../util/korean_particle.dart';
import '../../auth_repository.dart';
import '../../gifticon_repository.dart';
import '../../share_repository.dart';

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

  static const String _defaultAvatar = '🙂';

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection(groupsCollection);
  CollectionReference<Map<String, dynamic>> get _shared =>
      _db.collection(sharedCollection);
  CollectionReference<Map<String, dynamic>> get _logs =>
      _db.collection(usageLogsCollection);
  CollectionReference<Map<String, dynamic>> get _notifs =>
      _db.collection(notificationsCollection);
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
  }) async {
    final User me = _requireUser();
    final DocumentReference<Map<String, dynamic>> ref = _groups.doc();
    final Group g = Group(
      id: ref.id,
      name: name,
      emoji: emoji,
      inviteCode: _randomCode(),
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
  Future<Group> joinGroup(String inviteCode) async {
    final User me = _requireUser();
    // 초대코드로 실제 그룹을 찾아 합류한다(mock의 가짜 그룹 생성과 달리 실 참여).
    final QuerySnapshot<Map<String, dynamic>> q =
        await _groups.where('inviteCode', isEqualTo: inviteCode).limit(1).get();
    if (q.docs.isEmpty) {
      throw StateError('No group for invite code: $inviteCode');
    }
    final DocumentReference<Map<String, dynamic>> ref = q.docs.first.reference;

    return _db.runTransaction<Group>((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Group disappeared: ${ref.id}');
      final Group g = _groupFromDoc(doc);
      if (g.isMember(me.id)) return g; // 이미 멤버면 no-op.
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
        tx.update(ref, _groupToDoc(g.copyWith(members: remaining)));
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
      final SharedGifticon item = _sharedFromDoc(doc);
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
      final SharedGifticon item = _sharedFromDoc(doc);
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
      final SharedGifticon item = _sharedFromDoc(doc);
      if (item.sharedByUserId != me.id) {
        throw StateError('Only the sharer can cancel the share');
      }
      if (item.status != ShareStatus.available) {
        throw StateError('Only an available share can be reclaimed');
      }
      // 항목과 공유 잠금을 함께 제거해 재공유가 가능해지도록 한다.
      tx.delete(ref);
      tx.delete(_locks.doc(item.gifticonId));
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
    } on Object {
      // 권한/네트워크 등 실패는 무시(동기화는 best-effort 계약).
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
        final String? gifticonId = d.data()['gifticonId'] as String?;
        if (gifticonId != null) batch.delete(_locks.doc(gifticonId));
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
        'inviteCode': g.inviteCode,
        'inviteOwnerOnly': g.inviteOwnerOnly,
        'members': g.members
            .map((GroupMember m) => <String, dynamic>{
                  'userId': m.userId,
                  'displayName': m.displayName,
                  'avatarEmoji': m.avatarEmoji,
                  'role': m.role.name,
                })
            .toList(growable: false),
        // 조회용 역정규화 — watchGroups의 array-contains 대상.
        'memberIds':
            g.members.map((GroupMember m) => m.userId).toList(growable: false),
        // 소유자 역정규화 — 보안 규칙이 방장 판정에 쓴다(members 배열 순회는 규칙에서 어려움).
        // 모든 그룹 write가 _groupToDoc을 거치므로 멤버 변경 시 자동으로 동기화된다.
        'ownerId': g.owner.userId,
      };

  /// 문서 → [Group]. **비멤버/멤버0/방장≠1** 등 [Group] 불변식을 못 만족하는 손상
  /// 문서는 `null`을 반환한다 — 목록 매핑에서 걸러 한 문서가 스트림 전체를 깨지 않게 한다.
  Group? _groupFromDocOrNull(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? const <String, dynamic>{};
    final List<dynamic> rawMembers =
        (data['members'] as List<dynamic>?) ?? const <dynamic>[];
    final List<GroupMember> members = rawMembers
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> m) => GroupMember(
              userId: m['userId'] as String? ?? '',
              displayName: m['displayName'] as String? ?? '',
              avatarEmoji: m['avatarEmoji'] as String? ?? _defaultAvatar,
              role: _roleFromName(m['role'] as String?),
            ))
        .toList(growable: false);
    // Group 생성자 불변식(멤버≥1, 방장 정확히 1명)을 못 지키면 스킵.
    final int owners =
        members.where((GroupMember m) => m.role == MemberRole.owner).length;
    if (members.isEmpty || owners != 1) return null;
    return Group(
      id: doc.id,
      name: data['name'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '🎁',
      inviteCode: data['inviteCode'] as String? ?? '',
      inviteOwnerOnly: data['inviteOwnerOnly'] as bool? ?? false,
      members: members,
    );
  }

  /// 유효한 그룹을 요구하는 문맥(트랜잭션 등)용 — 손상 문서면 [StateError].
  Group _groupFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Group? g = _groupFromDocOrNull(doc);
    if (g == null) throw StateError('Malformed group document: ${doc.id}');
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

  SharedGifticon _sharedFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? const <String, dynamic>{};
    return SharedGifticon(
      id: doc.id,
      groupId: data['groupId'] as String? ?? '',
      gifticonId: data['gifticonId'] as String? ?? '',
      sharedByUserId: data['sharedByUserId'] as String? ?? '',
      brand: data['brand'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      expiryDate: _toDate(data['expiryDate']),
      status: _shareStatusFromName(data['status'] as String?),
      lockedByUserId: data['lockedByUserId'] as String?,
      reservedByUserId: data['reservedByUserId'] as String?,
      barcode: data['barcode'] as String?,
    );
  }

  UsageLog _logFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? const <String, dynamic>{};
    return UsageLog(
      id: doc.id,
      groupId: data['groupId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      sharedGifticonId: data['sharedGifticonId'] as String? ?? '',
      brand: data['brand'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      usedAt: _toDate(data['usedAt']),
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

  GroupNotification _notifFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data() ?? const <String, dynamic>{};
    return GroupNotification(
      id: doc.id,
      groupId: data['groupId'] as String? ?? '',
      type: _notifTypeFromName(data['type'] as String?),
      title: data['title'] as String? ?? '',
      message: data['message'] as String? ?? '',
      createdAt: _toDate(data['createdAt']),
    );
  }

  DateTime _toDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  MemberRole _roleFromName(String? name) =>
      name == MemberRole.owner.name ? MemberRole.owner : MemberRole.member;

  ShareStatus _shareStatusFromName(String? name) {
    for (final ShareStatus s in ShareStatus.values) {
      if (s.name == name) return s;
    }
    return ShareStatus.available;
  }

  GroupNotificationType _notifTypeFromName(String? name) {
    for (final GroupNotificationType t in GroupNotificationType.values) {
      if (t.name == name) return t;
    }
    return GroupNotificationType.registered;
  }

  String _randomCode() {
    // 6자리 코드. 원본 인스턴스가 시간/랜덤에 의존하지 않도록 문서 id 해시를 쓴다.
    final int h = _shared.doc().id.hashCode & 0x7fffffff;
    return (100000 + (h % 900000)).toString();
  }
}
