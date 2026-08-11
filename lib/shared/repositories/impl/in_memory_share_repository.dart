/// KeepCon 공유 계약 — InMemoryShareRepository (mock 구현).
///
/// 실제 백엔드 없이 share 페이지가 즉시 개발할 수 있도록 제공하는 in-memory 구현체.
/// 프로토타입 `ShareStore`(`lib/features/share/data/share_store.dart`)의 가드 로직과
/// 시드 데이터를 계약 인터페이스로 이관한 것이다.
///
/// ## 세션/원본 동기화 의존성
/// - `AuthRepository`를 주입받아 **행위자(현재 사용자)** 를 해석한다(share ↔ auth 경계).
/// - `GifticonRepository`를 주입받아 [markUsed] 시 원본 [Gifticon]을 used로 전이한다
///   (share ↔ main 경계). 기존 `GifticonRepository.updateStatus`를 소비할 뿐 계약을 바꾸지 않는다.
///
/// ## 프로토타입과의 차이
/// - `ShareStore`는 가드 위반에 `bool`을 반환했지만, 여기서는 계약대로 [StateError]를 던진다.
/// - `myId`('me') 하드코딩 대신 `AuthRepository.currentUser.id`를 행위자로 쓴다.
/// - `ChangeNotifier` 대신 소유자/그룹별 [Stream]을 방출한다(리액티브 계약).
library;

import 'dart:async';

import '../../models/gifticon.dart';
import '../../models/group.dart';
import '../../models/share.dart';
import '../../models/user.dart';
import '../../util/korean_particle.dart';
import '../auth_repository.dart';
import '../gifticon_repository.dart';
import '../share_repository.dart';

/// [ShareRepository]의 in-memory mock 구현.
class InMemoryShareRepository implements ShareRepository {
  /// 세션([AuthRepository])·원본 기프티콘([GifticonRepository]) 저장소를 주입해 생성한다.
  ///
  /// [seed]가 `true`면 데모용 시드 그룹/공유/이력/알림을 채운다(현재 사용자 기준).
  InMemoryShareRepository({
    required AuthRepository authRepository,
    required GifticonRepository gifticonRepository,
    bool seed = true,
  })  : _auth = authRepository,
        _gifticons = gifticonRepository {
    if (seed) _seed();
  }

  final AuthRepository _auth;
  final GifticonRepository _gifticons;

  final List<Group> _groups = <Group>[];
  final Map<String, List<SharedGifticon>> _sharedByGroup =
      <String, List<SharedGifticon>>{};
  final List<UsageLog> _usageLogs = <UsageLog>[];
  final List<GroupNotification> _notifications = <GroupNotification>[];

  /// 사용자별 알림 마지막 읽음 시각(userId → 시각). 없으면 한 번도 안 읽음.
  final Map<String, DateTime> _notifReadAt = <String, DateTime>{};

  final StreamController<void> _tick = StreamController<void>.broadcast();
  int _seq = 100;

  // ── 내부 헬퍼 ────────────────────────────────────────────────────────
  void _emit() => _tick.add(null);

  String _nextId(String prefix) => '$prefix${_seq++}';

  /// 현재 행위자(로그인 사용자). 없으면 [StateError].
  User _requireUser() {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw StateError('No current user in session — cannot perform action');
    }
    return user;
  }

  Group _requireGroup(String groupId) {
    final Group? g = _groupByIdOrNull(groupId);
    if (g == null) throw StateError('Group not found: $groupId');
    return g;
  }

  Group? _groupByIdOrNull(String groupId) {
    for (final Group g in _groups) {
      if (g.id == groupId) return g;
    }
    return null;
  }

  int _groupIndex(String groupId) =>
      _groups.indexWhere((Group g) => g.id == groupId);

  List<Group> _groupsFor(String userId) => List<Group>.unmodifiable(
        _groups.where((Group g) => g.isMember(userId)),
      );

  /// 모든 그룹을 가로질러 공유 항목을 찾는다. (id는 전역 유일)
  ({List<SharedGifticon> list, int index})? _locateShared(
      String sharedGifticonId) {
    for (final List<SharedGifticon> list in _sharedByGroup.values) {
      final int idx =
          list.indexWhere((SharedGifticon s) => s.id == sharedGifticonId);
      if (idx >= 0) return (list: list, index: idx);
    }
    return null;
  }

  void _pushNotification({
    required String groupId,
    required GroupNotificationType type,
    required String title,
    required String message,
  }) {
    _notifications.insert(
      0,
      GroupNotification(
        id: _nextId('n'),
        groupId: groupId,
        type: type,
        title: title,
        message: message,
        createdAt: DateTime.now(),
      ),
    );
  }

  // ── 그룹 조회 ────────────────────────────────────────────────────────
  @override
  Stream<List<Group>> watchGroups(String userId) async* {
    yield _groupsFor(userId);
    yield* _tick.stream.map((_) => _groupsFor(userId));
  }

  @override
  Future<List<Group>> getGroups(String userId) async => _groupsFor(userId);

  @override
  Future<Group?> getGroupById(String groupId) async =>
      _groupByIdOrNull(groupId);

  // ── 그룹 관리 ────────────────────────────────────────────────────────
  @override
  Future<Group> createGroup({
    required String name,
    required String emoji,
    int maxMembers = Group.defaultMaxMembers,
  }) async {
    final User me = _requireUser();
    final Group g = Group(
      id: _nextId('g'),
      name: name,
      emoji: emoji,
      inviteCode: _randomCode(),
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
    _groups.insert(0, g);
    _sharedByGroup[g.id] = <SharedGifticon>[];
    _emit();
    return g;
  }

  @override
  Future<Group> joinGroup(String inviteCode) async {
    final User me = _requireUser();

    // 저장된 그룹을 초대코드로 먼저 조회한다(계약 준수 — Firebase 구현과 동일하게
    // 만료·멤버십을 검증). 실제 그룹이 있으면 그 그룹에 합류한다.
    final int existing =
        _groups.indexWhere((Group g) => g.inviteCode == inviteCode);
    if (existing >= 0) {
      final Group g = _groups[existing];
      if (g.isMember(me.id)) return g; // 이미 멤버면 no-op.
      if (g.isInviteExpired(DateTime.now())) {
        throw StateError('Invite code expired: $inviteCode');
      }
      if (g.isFull) {
        throw StateError('Group is full: ${g.id}');
      }
      final Group updated = g.copyWith(
        members: <GroupMember>[
          ...g.members,
          GroupMember(
            userId: me.id,
            displayName: me.displayName,
            avatarEmoji: _defaultAvatar,
            role: MemberRole.member,
          ),
        ],
      );
      _groups[existing] = updated;
      _emit();
      return updated;
    }

    // 미발견 코드는 데모용으로 가짜 그룹을 만들어 합류를 시연한다(in-memory 한정 스텁).
    final Group g = Group(
      id: _nextId('g'),
      name: '초대받은 그룹',
      emoji: '🎁',
      inviteCode: inviteCode,
      members: <GroupMember>[
        const GroupMember(
          userId: 'u_host',
          displayName: '방장',
          avatarEmoji: '👑',
          role: MemberRole.owner,
        ),
        GroupMember(
          userId: me.id,
          displayName: me.displayName,
          avatarEmoji: _defaultAvatar,
          role: MemberRole.member,
        ),
      ],
    );
    _groups.insert(0, g);
    _sharedByGroup[g.id] = <SharedGifticon>[];
    _emit();
    return g;
  }

  @override
  Future<void> leaveGroup(String groupId) async {
    final User me = _requireUser();
    final Group g = _requireGroup(groupId);
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
      _removeGroup(groupId);
    } else {
      _groups[_groupIndex(groupId)] = g.copyWith(members: remaining);
    }
    _emit();
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final User me = _requireUser();
    final Group g = _requireGroup(groupId);
    if (!g.isOwnedBy(me.id)) {
      throw StateError('Only the owner can delete the group: $groupId');
    }
    _removeGroup(groupId);
    _emit();
  }

  @override
  Future<Group> transferOwnershipAndLeave({
    required String groupId,
    required String newOwnerUserId,
  }) async {
    final User me = _requireUser();
    final Group g = _requireGroup(groupId);
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
        .map((GroupMember m) =>
            m.userId == newOwnerUserId ? m.copyWith(role: MemberRole.owner) : m)
        .toList(growable: false);
    final Group updated = g.copyWith(members: next);
    _groups[_groupIndex(groupId)] = updated;
    _emit();
    return updated;
  }

  @override
  Future<Group> removeMember({
    required String groupId,
    required String userId,
  }) async {
    final User me = _requireUser();
    final Group g = _requireGroup(groupId);
    if (!g.isOwnedBy(me.id)) {
      throw StateError('Only the owner can remove members: $groupId');
    }
    if (userId == me.id) {
      throw StateError('Owner cannot remove themselves: $groupId');
    }
    if (!g.isMember(userId)) {
      throw StateError('Not a member of group: $userId');
    }
    final List<GroupMember> next = g.members
        .where((GroupMember m) => m.userId != userId)
        .toList(growable: false);
    final Group updated = g.copyWith(members: next);
    _groups[_groupIndex(groupId)] = updated;
    _emit();
    return updated;
  }

  @override
  Future<Group> setInviteOwnerOnly({
    required String groupId,
    required bool ownerOnly,
  }) async {
    final User me = _requireUser();
    final Group g = _requireGroup(groupId);
    if (!g.isOwnedBy(me.id)) {
      throw StateError('Only the owner can change invite policy: $groupId');
    }
    final Group updated = g.copyWith(inviteOwnerOnly: ownerOnly);
    _groups[_groupIndex(groupId)] = updated;
    _emit();
    return updated;
  }

  @override
  Future<Group> regenerateInviteCode({required String groupId}) async {
    final User me = _requireUser();
    final Group g = _requireGroup(groupId);
    if (!g.isOwnedBy(me.id)) {
      throw StateError('Only the owner can regenerate invite code: $groupId');
    }
    // 새 코드 발급 + 만료 창 갱신(재발급 시점부터 다시 24시간).
    final Group updated = g.copyWith(
      inviteCode: _nextCode(),
      inviteExpiresAt: DateTime.now().add(Group.inviteValidity),
    );
    _groups[_groupIndex(groupId)] = updated;
    _emit();
    return updated;
  }

  void _removeGroup(String groupId) {
    _groups.removeWhere((Group g) => g.id == groupId);
    _sharedByGroup.remove(groupId);
  }

  // ── 공유 기프티콘 ─────────────────────────────────────────────────────
  @override
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId) async* {
    yield _sharedFor(groupId);
    yield* _tick.stream.map((_) => _sharedFor(groupId));
  }

  @override
  Future<List<SharedGifticon>> getSharedGifticons(String groupId) async =>
      _sharedFor(groupId);

  List<SharedGifticon> _sharedFor(String groupId) =>
      List<SharedGifticon>.unmodifiable(
        _sharedByGroup[groupId] ?? const <SharedGifticon>[],
      );

  /// [gifticonId]가 [userId]가 속한 어느 그룹에든 이미 공유돼 있는지.
  /// "한 기프티콘은 한 번만 공유" 불변식의 판정 진입점.
  bool _isAlreadyShared(String gifticonId, String userId) {
    for (final Group g in _groups) {
      if (!g.isMember(userId)) continue;
      final List<SharedGifticon>? list = _sharedByGroup[g.id];
      if (list == null) continue;
      if (list.any((SharedGifticon s) => s.gifticonId == gifticonId)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<SharedGifticon> shareGifticon({
    required String groupId,
    required Gifticon gifticon,
  }) async {
    final User me = _requireUser();
    final Group g = _requireGroup(groupId);
    if (!g.isMember(me.id)) {
      throw StateError('Not a member of group: $groupId');
    }
    // 불변식: 한 기프티콘은 최대 1회만 공유될 수 있다(이중 사용/UsageLog 다중 발생 방지).
    // 행위자가 속한 어느 그룹에든 같은 gifticonId가 이미 공유돼 있으면 거부한다.
    // (공유취소로 제거되거나 사용완료 후에도 항목은 남으므로, 회수 후 재공유는 허용되고
    //  사용완료된 기프티콘의 재공유는 차단된다.)
    if (_isAlreadyShared(gifticon.id, me.id)) {
      throw StateError('Gifticon already shared: ${gifticon.id}');
    }
    final SharedGifticon shared = SharedGifticon(
      id: _nextId('s'),
      groupId: groupId,
      gifticonId: gifticon.id,
      sharedByUserId: me.id,
      brand: gifticon.brand,
      productName: gifticon.productName,
      expiryDate: gifticon.expiryDate,
      status: ShareStatus.available,
      barcode: gifticon.barcode,
    );
    _sharedByGroup
        .putIfAbsent(groupId, () => <SharedGifticon>[])
        .insert(0, shared);
    _pushNotification(
      groupId: groupId,
      type: GroupNotificationType.registered,
      title: '새 기프티콘 공유',
      message: '${me.displayName}님이 ${gifticon.brand} ${gifticon.productName}'
          '${gifticon.productName.eulReul} 공유했어요.',
    );
    _emit();
    return shared;
  }

  @override
  Future<SharedGifticon> toggleReservation(String sharedGifticonId) async {
    final User me = _requireUser();
    final loc = _locateShared(sharedGifticonId);
    if (loc == null) {
      throw StateError('Shared gifticon not found: $sharedGifticonId');
    }
    final SharedGifticon item = loc.list[loc.index];
    final SharedGifticon updated;
    if (item.reservedByUserId == me.id) {
      updated = item.copyWith(reservedByUserId: null); // 내 찜 해제
    } else if (item.reservedByUserId == null) {
      updated = item.copyWith(reservedByUserId: me.id); // 새로 찜
    } else {
      throw StateError('Already reserved by another member'); // 단일 슬롯 보호
    }
    loc.list[loc.index] = updated;
    _emit();
    return updated;
  }

  @override
  Future<SharedGifticon> markUsed(String sharedGifticonId) async {
    final User me = _requireUser();
    final loc = _locateShared(sharedGifticonId);
    if (loc == null) {
      throw StateError('Shared gifticon not found: $sharedGifticonId');
    }
    final SharedGifticon item = loc.list[loc.index];
    if (item.status != ShareStatus.available) {
      throw StateError(
        'Only an available shared gifticon can be marked used: ${item.status}',
      );
    }
    final SharedGifticon updated = item.copyWith(
      status: ShareStatus.used,
      lockedByUserId: null,
      reservedByUserId: null,
    );
    loc.list[loc.index] = updated;

    _usageLogs.insert(
      0,
      UsageLog(
        id: _nextId('u'),
        groupId: item.groupId,
        userId: me.id,
        sharedGifticonId: item.id,
        brand: item.brand,
        productName: item.productName,
        usedAt: DateTime.now(),
      ),
    );
    _pushNotification(
      groupId: item.groupId,
      type: GroupNotificationType.used,
      title: '사용 완료',
      message: '${me.displayName}님이 ${item.brand} ${item.productName}'
          '${item.productName.eulReul} 사용했어요.',
    );

    // share → main 동기화: 원본 Gifticon을 used로 전이(기존 계약 소비).
    await _syncOriginalUsed(item.gifticonId);

    _emit();
    return updated;
  }

  @override
  Future<void> cancelShare(String sharedGifticonId) async {
    final User me = _requireUser();
    final loc = _locateShared(sharedGifticonId);
    if (loc == null) {
      throw StateError('Shared gifticon not found: $sharedGifticonId');
    }
    final SharedGifticon item = loc.list[loc.index];
    if (item.sharedByUserId != me.id) {
      throw StateError('Only the sharer can cancel the share');
    }
    if (item.status != ShareStatus.available) {
      throw StateError('Only an available share can be reclaimed');
    }
    loc.list.removeAt(loc.index);
    // 공유는 원본 상태를 바꾸지 않았으므로(available 유지) 원복 동기화도 불필요.
    _emit();
  }

  /// 원본 [Gifticon]을 used로 동기화한다.
  ///
  /// 원본이 조회되지 않거나(데모 시드의 가짜 gifticonId) 이미 used/expired여서
  /// 전이가 불허되면 조용히 건너뛴다(사용 완료 자체는 유효).
  Future<void> _syncOriginalUsed(String gifticonId) async {
    final Gifticon? original = await _gifticons.getGifticonById(gifticonId);
    if (original == null) return;
    if (!GifticonStatusTransition.isAllowed(
      original.status,
      GifticonStatus.used,
    )) {
      return;
    }
    await _gifticons.updateStatus(gifticonId, GifticonStatus.used);
  }

  // ── 사용 이력 / 알림 ──────────────────────────────────────────────────
  @override
  Stream<List<UsageLog>> watchUsageLogs(String userId) async* {
    yield _usageLogsFor(userId);
    yield* _tick.stream.map((_) => _usageLogsFor(userId));
  }

  @override
  Future<List<UsageLog>> getUsageLogs(String userId) async =>
      _usageLogsFor(userId);

  List<UsageLog> _usageLogsFor(String userId) => List<UsageLog>.unmodifiable(
        _usageLogs.where((UsageLog log) => _isMemberOf(log.groupId, userId)),
      );

  @override
  Stream<List<GroupNotification>> watchNotifications(String userId) async* {
    yield _notificationsFor(userId);
    yield* _tick.stream.map((_) => _notificationsFor(userId));
  }

  @override
  Future<List<GroupNotification>> getNotifications(String userId) async =>
      _notificationsFor(userId);

  @override
  Stream<DateTime?> watchNotificationsReadAt(String userId) async* {
    yield _notifReadAt[userId];
    yield* _tick.stream.map((_) => _notifReadAt[userId]);
  }

  @override
  Future<void> markNotificationsRead() async {
    final User me = _requireUser();
    _notifReadAt[me.id] = DateTime.now();
    _emit();
  }

  List<GroupNotification> _notificationsFor(String userId) =>
      List<GroupNotification>.unmodifiable(
        _notifications
            .where((GroupNotification n) => _isMemberOf(n.groupId, userId)),
      );

  bool _isMemberOf(String groupId, String userId) {
    final Group? g = _groupByIdOrNull(groupId);
    return g != null && g.isMember(userId);
  }

  /// 리소스 정리. 앱 종료/테스트 teardown 시 호출.
  void dispose() {
    _tick.close();
  }

  // ── 유틸 ─────────────────────────────────────────────────────────────
  /// [User]가 아직 아바타를 갖지 않으므로 현재 사용자 멤버의 기본 아바타.
  static const String _defaultAvatar = '🙂';

  String _randomCode() {
    final int base = 100000 + (_seq * 37) % 900000;
    return base.toString();
  }

  /// 매 호출마다 다른 코드 — 재발급용. [_randomCode]는 [_seq]에 결정적이므로
  /// 시퀀스를 먼저 진행시켜 이전 코드와 겹치지 않게 한다.
  String _nextCode() {
    _seq++;
    return _randomCode();
  }

  // ── 시드 데이터 ──────────────────────────────────────────────────────
  void _seed() {
    final User? me = _auth.currentUser;
    if (me == null) return; // 세션 없으면 시드 스킵.

    final GroupMember meAsOwner = GroupMember(
      userId: me.id,
      displayName: me.displayName,
      avatarEmoji: _defaultAvatar,
      role: MemberRole.owner,
    );
    final GroupMember meAsMember = meAsOwner.copyWith(role: MemberRole.member);

    final Group family = Group(
      id: 'g_family',
      name: '가족',
      emoji: '🏠',
      inviteCode: '482913',
      members: <GroupMember>[
        meAsOwner,
        const GroupMember(
            userId: 'u_mom',
            displayName: '엄마',
            avatarEmoji: '👩',
            role: MemberRole.member),
        const GroupMember(
            userId: 'u_dad',
            displayName: '아빠',
            avatarEmoji: '🧔',
            role: MemberRole.member),
        const GroupMember(
            userId: 'u_sis',
            displayName: '누나',
            avatarEmoji: '👧',
            role: MemberRole.member),
      ],
    );
    final Group friends = Group(
      id: 'g_friends',
      name: '친구 모임',
      emoji: '👥',
      inviteCode: '771205',
      inviteOwnerOnly: true, // 방장(홍길동) 한정 초대 — 멤버인 나에겐 초대 진입점 숨김(시연).
      members: <GroupMember>[
        const GroupMember(
            userId: 'u_gil',
            displayName: '홍길동',
            avatarEmoji: '🧑',
            role: MemberRole.owner),
        meAsMember,
        const GroupMember(
            userId: 'u_kim',
            displayName: '김철수',
            avatarEmoji: '👨',
            role: MemberRole.member),
      ],
    );
    _groups.addAll(<Group>[family, friends]);

    _sharedByGroup['g_family'] = <SharedGifticon>[
      SharedGifticon(
        id: 's_1',
        groupId: 'g_family',
        gifticonId: 'seed-gift-1',
        sharedByUserId: 'u_mom',
        brand: '스타벅스',
        productName: '아메리카노 T',
        expiryDate: DateTime(2026, 9, 30),
        status: ShareStatus.available,
      ),
      SharedGifticon(
        id: 's_2',
        groupId: 'g_family',
        gifticonId: 'seed-gift-2',
        sharedByUserId: me.id,
        brand: 'BBQ',
        productName: '황금올리브 세트',
        expiryDate: DateTime(2026, 8, 15),
        status: ShareStatus.inUse,
        lockedByUserId: 'u_dad',
      ),
      SharedGifticon(
        id: 's_3',
        groupId: 'g_family',
        gifticonId: 'seed-gift-3',
        sharedByUserId: 'u_sis',
        brand: 'CU',
        productName: '5,000원 금액권',
        expiryDate: DateTime(2026, 7, 20),
        status: ShareStatus.used,
      ),
    ];
    _sharedByGroup['g_friends'] = <SharedGifticon>[
      SharedGifticon(
        id: 's_4',
        groupId: 'g_friends',
        gifticonId: 'seed-gift-4',
        sharedByUserId: 'u_gil',
        brand: '올리브영',
        productName: '1만원 금액권',
        expiryDate: DateTime(2026, 10, 10),
        status: ShareStatus.available,
        reservedByUserId: 'u_kim',
      ),
      SharedGifticon(
        id: 's_5',
        groupId: 'g_friends',
        gifticonId: 'seed-gift-5',
        sharedByUserId: 'u_kim',
        brand: '배스킨라빈스',
        productName: '파인트',
        expiryDate: DateTime(2026, 11, 1),
        status: ShareStatus.available,
      ),
    ];

    final DateTime now = DateTime.now();
    _usageLogs.addAll(<UsageLog>[
      UsageLog(
        id: 'ul_1',
        groupId: 'g_family',
        userId: 'u_sis',
        sharedGifticonId: 's_3',
        brand: 'CU',
        productName: '5,000원 금액권',
        usedAt: now.subtract(const Duration(days: 4)),
      ),
      UsageLog(
        id: 'ul_2',
        groupId: 'g_friends',
        userId: 'u_gil',
        sharedGifticonId: 's_4',
        brand: '스타벅스',
        productName: '아메리카노',
        usedAt: now.subtract(const Duration(days: 7)),
      ),
      UsageLog(
        id: 'ul_3',
        groupId: 'g_family',
        userId: 'u_mom',
        sharedGifticonId: 's_1',
        brand: '올리브영',
        productName: '1만원권',
        usedAt: now.subtract(const Duration(days: 14)),
      ),
    ]);

    _notifications.addAll(<GroupNotification>[
      GroupNotification(
        id: 'gn_1',
        groupId: 'g_family',
        type: GroupNotificationType.registered,
        title: '새 기프티콘 공유',
        message: '엄마님이 스타벅스 아메리카노 T를 공유했어요.',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      GroupNotification(
        id: 'gn_2',
        groupId: 'g_family',
        type: GroupNotificationType.expiringSoon,
        title: '만료 임박',
        message: 'CU 5,000원 금액권이 곧 만료돼요.',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      GroupNotification(
        id: 'gn_3',
        groupId: 'g_family',
        type: GroupNotificationType.used,
        title: '사용 완료',
        message: '누나님이 CU 5,000원 금액권을 사용했어요.',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
    ]);
  }
}
