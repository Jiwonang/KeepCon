/// share 페이지 — 로컬 상태 저장소 (프로토타입 하드코딩).
///
/// **프로토타입 하드코딩 · 계약 v1 확정 후 `lib/shared`로 이관 예정.**
/// 그룹/공유 도메인은 아직 공유 계약(`lib/shared`)에 없으므로, 화면 상호작용
/// (그룹 생성/참여/나가기, 공유/찜/사용완료/공유취소)을 **실제로 반응**시키기 위한
/// share 스코프 전용 인메모리 저장소다.
///
/// - 프로젝트 표준은 Riverpod이지만, 하드코딩 프로토타입 상태는 share 기능 내부에
///   로컬로 둔다. `lib/shared`의 provider/repository는 절대 건드리지 않는다.
/// - 여러 전체화면 push 간에도 같은 상태를 공유해야 하므로, share 스코프 단일
///   인스턴스([ShareStore.instance])를 [ChangeNotifier]로 노출한다. 화면은
///   `ListenableBuilder`로 구독해 변경에 반응한다.
/// - 계약 이관 시 이 저장소는 GroupRepository/ShareRepository 소비 코드로 대체된다.
library;

import 'package:flutter/foundation.dart';

import 'korean_particle.dart';
import 'share_models.dart';

/// share 기능 전용 인메모리 저장소(싱글턴).
class ShareStore extends ChangeNotifier {
  ShareStore._() {
    _seed();
  }

  /// share 스코프 단일 인스턴스.
  static final ShareStore instance = ShareStore._();

  // ── 현재 사용자(프로토타입) ───────────────────────────────────────
  // TODO(contract): 계약 이관 시 AuthRepository.currentUser 로 대체.
  /// 현재 사용자(나) 식별자.
  static const String myId = 'me';

  /// 현재 사용자(나) 표시 이름.
  static const String myName = '나';

  /// 현재 사용자(나) 아바타 이모지.
  static const String myEmoji = '🙂';

  // ── 상태 ─────────────────────────────────────────────────────────
  final List<Group> _groups = <Group>[];
  final Map<String, List<SharedGifticon>> _sharedByGroup =
      <String, List<SharedGifticon>>{};
  final List<UsageLog> _usageLogs = <UsageLog>[];
  final List<GroupNotification> _notifications = <GroupNotification>[];
  final List<MyGifticon> _myGifticons = <MyGifticon>[];

  int _seq = 100;

  String _nextId(String prefix) => '$prefix${_seq++}';

  // ── 읽기 ─────────────────────────────────────────────────────────
  /// 내가 멤버로 속한 그룹(내부 공통). 소유권 이전으로 그룹을 떠나면 여기서 빠진다.
  Iterable<Group> get _myGroups => _groups
      .where((Group g) => g.members.any((GroupMember m) => m.id == myId));

  /// 내 그룹 목록(읽기 전용 뷰) — **내가 멤버인 그룹만** 노출한다.
  List<Group> get groups => List<Group>.unmodifiable(_myGroups);

  /// 전체 사용 이력(최신순).
  List<UsageLog> get usageLogs => List<UsageLog>.unmodifiable(_usageLogs);

  /// 그룹 알림(최신순).
  List<GroupNotification> get notifications =>
      List<GroupNotification>.unmodifiable(_notifications);

  /// 아직 공유하지 않은 내 기프티콘(공유 대상 후보).
  List<MyGifticon> get myGifticons =>
      List<MyGifticon>.unmodifiable(_myGifticons);

  /// 특정 그룹의 공유 기프티콘 목록.
  List<SharedGifticon> sharedOf(String groupId) =>
      List<SharedGifticon>.unmodifiable(
          _sharedByGroup[groupId] ?? const <SharedGifticon>[]);

  /// 내 그룹의 공유 기프티콘(공유 메인 요약용) — 떠난 그룹 것은 제외.
  List<SharedGifticon> get allShared => <SharedGifticon>[
        for (final Group g in _myGroups) ...?_sharedByGroup[g.id],
      ];

  /// id로 그룹 조회.
  Group? groupById(String id) {
    for (final Group g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// 특정 공유 기프티콘이 "다른 멤버에게 잠김"인지(사용중이며 잠금 주체가 내가 아님).
  bool isLockedForMe(SharedGifticon item) =>
      item.status == ShareStatus.inUse &&
      item.lockedByName != null &&
      item.lockedByName != myName;

  // ── 그룹 관리 ─────────────────────────────────────────────────────
  /// 그룹 생성 — 내가 방장인 새 그룹.
  Group createGroup({required String name, required String emoji}) {
    final Group g = Group(
      id: _nextId('g'),
      name: name,
      emoji: emoji,
      inviteCode: _randomCode(),
      members: <GroupMember>[
        const GroupMember(
          id: myId,
          name: myName,
          emoji: myEmoji,
          role: MemberRole.owner,
        ),
      ],
    );
    _groups.insert(0, g);
    _sharedByGroup[g.id] = <SharedGifticon>[];
    notifyListeners();
    return g;
  }

  /// 그룹 참여 — 초대코드로 참여(프로토타입: 데모 그룹에 멤버로 합류).
  Group joinGroup(String inviteCode) {
    final Group g = Group(
      id: _nextId('g'),
      name: '초대받은 그룹',
      emoji: '🎁',
      inviteCode: inviteCode,
      members: <GroupMember>[
        const GroupMember(
          id: 'u_host',
          name: '방장',
          emoji: '👑',
          role: MemberRole.owner,
        ),
        const GroupMember(
          id: myId,
          name: myName,
          emoji: myEmoji,
          role: MemberRole.member,
        ),
      ],
    );
    _groups.insert(0, g);
    _sharedByGroup[g.id] = <SharedGifticon>[];
    notifyListeners();
    return g;
  }

  /// 내가 [g]의 방장인지.
  bool _iAmOwnerOf(Group g) => g.owner.id == myId;

  /// 그룹 나가기(멤버). 방장이면 [transferOwnershipAndLeave]를 먼저 써야 한다.
  ///
  /// 정본 가드(UI 노출 조건과 별개):
  /// - 내가 그룹의 멤버여야 한다.
  /// - 내가 방장이면서 다른 멤버가 남아 있으면 나갈 수 없다(소유권 이전이 선행).
  ///   방장이 단독 멤버일 때만 나가기로 그룹을 정리할 수 있다.
  ///
  /// 조건 위반/대상 없음이면 `false`, 실제로 나가면 `true`.
  bool leaveGroup(String groupId) {
    final Group? g = groupById(groupId);
    if (g == null) return false;
    if (!g.members.any((GroupMember m) => m.id == myId)) return false; // 비멤버
    if (_iAmOwnerOf(g) && g.memberCount > 1) return false; // 이전 선행 필요
    _removeGroup(groupId);
    return true;
  }

  /// 그룹 삭제(방장 전용).
  ///
  /// 정본 가드: 방장 본인만 삭제할 수 있다. 위반/대상 없음이면 `false`, 삭제 시 `true`.
  bool deleteGroup(String groupId) {
    final Group? g = groupById(groupId);
    if (g == null) return false;
    if (!_iAmOwnerOf(g)) return false; // 방장만
    _removeGroup(groupId);
    return true;
  }

  /// 소유권 이전 후 나가기 — 지정 멤버를 방장으로 올리고 '나'만 그룹에서 빠진다.
  ///
  /// 이전 구현은 멤버를 재계산한 뒤 그룹을 통째로 삭제(`_removeGroup`)해, 승격이
  /// 반영되지 않고 그룹·공유 기프티콘이 모두 사라지는 버그가 있었다. 이제는
  /// [newOwnerId]를 방장으로 승격하고 '나'만 멤버에서 제거한다. 그룹 객체 자체는
  /// `_groups`에 남지만, 내 멤버십이 사라지므로 [groups]·[allShared] 뷰에서는
  /// **빠진다**(다른 멤버 관점의 그룹 유지를 단일 store로 근사). 상세 화면은
  /// 나가기 성공 시 호출부가 pop한다.
  ///
  /// 정본 가드: 방장 본인만 이전할 수 있고, [newOwnerId]는 나를 제외한 기존 멤버여야
  /// 한다. 위반/대상 없음이면 `false`, 성공 시 `true`.
  // ★ TODO(contract): 계약 이관 시 남은 멤버 관점의 그룹 유지·내 소속 해제를
  //    GroupRepository로 처리.
  bool transferOwnershipAndLeave({
    required String groupId,
    required String newOwnerId,
  }) {
    final Group? g = groupById(groupId);
    if (g == null) return false;
    if (!_iAmOwnerOf(g)) return false; // 방장만 이전 가능
    // 신임 방장은 나를 제외한 기존 멤버여야 한다.
    if (newOwnerId == myId ||
        !g.members.any((GroupMember m) => m.id == newOwnerId)) {
      return false;
    }
    // '나'를 제외하고, 신임 방장만 owner로 승격한다.
    g.members = g.members
        .where((GroupMember m) => m.id != myId)
        .map((GroupMember m) =>
            m.id == newOwnerId ? m.copyWith(role: MemberRole.owner) : m)
        .toList();
    notifyListeners();
    return true;
  }

  void _removeGroup(String groupId) {
    _groups.removeWhere((Group g) => g.id == groupId);
    _sharedByGroup.remove(groupId);
    notifyListeners();
  }

  // ── 공유 기프티콘 ─────────────────────────────────────────────────
  /// 내 기프티콘을 그룹에 공유.
  void shareGifticon({required String groupId, required MyGifticon g}) {
    final List<SharedGifticon> list =
        _sharedByGroup.putIfAbsent(groupId, () => <SharedGifticon>[]);
    list.insert(
      0,
      SharedGifticon(
        id: _nextId('s'),
        groupId: groupId,
        brand: g.brand,
        product: g.product,
        sharedByName: myName,
        status: ShareStatus.available,
        expiryLabel: g.expiryLabel,
      ),
    );
    _myGifticons.removeWhere((MyGifticon m) => m.id == g.id);
    _pushNotification(GroupNotification(
      type: GroupNotificationType.registered,
      title: '새 기프티콘 공유',
      message: '$myName님이 ${g.brand} ${g.product}${g.product.eulReul} 공유했어요.',
      when: '방금',
    ));
    // ★ TODO(contract): 원본 Gifticon을 '공유중'으로 표시(GifticonRepository 상태 갱신).
    notifyListeners();
  }

  /// 찜(사용 예정) 토글 — 내가 찜/찜 해제.
  ///
  /// 다른 멤버가 이미 찜한 항목은 덮어쓰지 않는다(단일 슬롯 찜을 보호).
  void toggleReservation(SharedGifticon item) {
    if (item.reservedByName == myName) {
      item.reservedByName = null; // 내 찜 해제
    } else if (item.reservedByName == null) {
      item.reservedByName = myName; // 새로 찜
    } else {
      return; // 다른 멤버가 찜한 상태 — 유지
    }
    notifyListeners();
  }

  /// 사용 완료 처리 — 사용 가능 → 사용 완료로 전이 후 이력/알림 동기화.
  ///
  /// 잠김(다른 멤버 사용중)·이미 사용 완료면 무시하고 `false`를 반환한다.
  /// 전이가 실제로 일어났을 때만 `true`를 반환한다.
  bool markUsed(SharedGifticon item) {
    if (item.status != ShareStatus.available) return false;
    item.status = ShareStatus.used;
    item.lockedByName = null;
    item.reservedByName = null;
    final Group? g = groupById(item.groupId);
    _usageLogs.insert(
      0,
      UsageLog(
        who: myName,
        what: '${item.brand} ${item.product}',
        groupName: g?.name ?? '그룹',
        when: '방금',
      ),
    );
    _pushNotification(GroupNotification(
      type: GroupNotificationType.used,
      title: '사용 완료',
      message:
          '$myName님이 ${item.brand} ${item.product}${item.product.eulReul} 사용했어요.',
      when: '방금',
    ));
    // ★ TODO(contract): 원본 Gifticon 상태를 available → used 로 전이
    //    (GifticonRepository 상태 갱신 메서드 호출) → 메인 목록/필터에 반영.
    notifyListeners();
    return true;
  }

  /// 공유 취소(회수) — 공유자 본인이, 사용 가능한 항목만 목록에서 제거한다.
  ///
  /// 권한·상태 방어는 UI 노출 조건과 **별개로** 이 정본에서 강제한다(다른 호출
  /// 경로·향후 코드에서도 불변식을 지키기 위함):
  /// - 공유자 본인만 회수 가능 — [SharedGifticon.sharedByName] == [myName].
  /// - [ShareStatus.available] 상태만 회수 가능. 사용중·사용완료 항목은 불가
  ///   ('회수=reclaim'은 아직 소비되지 않은 공유에만 의미가 있다).
  ///
  /// 조건 위반이거나 대상이 없으면 아무 것도 하지 않고 `false`, 실제 제거 시 `true`.
  bool cancelShare(SharedGifticon item) {
    if (item.sharedByName != myName) return false; // 공유자 본인만
    if (item.status != ShareStatus.available) return false; // 사용가능만 회수
    final List<SharedGifticon>? list = _sharedByGroup[item.groupId];
    if (list == null) return false;
    final int before = list.length;
    list.removeWhere((SharedGifticon s) => s.id == item.id);
    if (list.length == before) return false; // 이미 없던 항목
    // ★ TODO(contract): 원본 Gifticon의 공유 상태를 원복(GifticonRepository 갱신).
    notifyListeners();
    return true;
  }

  void _pushNotification(GroupNotification n) {
    _notifications.insert(0, n);
  }

  String _randomCode() {
    // 프로토타입: 시퀀스 기반 유사 코드.
    final int base = 100000 + (_seq * 37) % 900000;
    return base.toString();
  }

  // ── 시드 데이터 ───────────────────────────────────────────────────
  void _seed() {
    final Group family = Group(
      id: 'g_family',
      name: '가족',
      emoji: '🏠',
      inviteCode: '482913',
      members: const <GroupMember>[
        GroupMember(
            id: myId, name: myName, emoji: myEmoji, role: MemberRole.owner),
        GroupMember(
            id: 'u_mom', name: '엄마', emoji: '👩', role: MemberRole.member),
        GroupMember(
            id: 'u_dad', name: '아빠', emoji: '🧔', role: MemberRole.member),
        GroupMember(
            id: 'u_sis', name: '누나', emoji: '👧', role: MemberRole.member),
      ],
    );
    final Group friends = Group(
      id: 'g_friends',
      name: '친구 모임',
      emoji: '👥',
      inviteCode: '771205',
      members: const <GroupMember>[
        GroupMember(
            id: 'u_gil', name: '홍길동', emoji: '🧑', role: MemberRole.owner),
        GroupMember(
            id: myId, name: myName, emoji: myEmoji, role: MemberRole.member),
        GroupMember(
            id: 'u_kim', name: '김철수', emoji: '👨', role: MemberRole.member),
      ],
    );
    _groups.addAll(<Group>[family, friends]);

    _sharedByGroup['g_family'] = <SharedGifticon>[
      SharedGifticon(
        id: 's_1',
        groupId: 'g_family',
        brand: '스타벅스',
        product: '아메리카노 T',
        sharedByName: '엄마',
        status: ShareStatus.available,
        expiryLabel: '~2026.09.30',
      ),
      SharedGifticon(
        id: 's_2',
        groupId: 'g_family',
        brand: 'BBQ',
        product: '황금올리브 세트',
        sharedByName: myName,
        status: ShareStatus.inUse,
        lockedByName: '아빠',
        expiryLabel: '~2026.08.15',
      ),
      SharedGifticon(
        id: 's_3',
        groupId: 'g_family',
        brand: 'CU',
        product: '5,000원 금액권',
        sharedByName: '누나',
        status: ShareStatus.used,
        expiryLabel: '~2026.07.20',
      ),
    ];
    _sharedByGroup['g_friends'] = <SharedGifticon>[
      SharedGifticon(
        id: 's_4',
        groupId: 'g_friends',
        brand: '올리브영',
        product: '1만원 금액권',
        sharedByName: '홍길동',
        status: ShareStatus.available,
        reservedByName: '김철수',
        expiryLabel: '~2026.10.10',
      ),
      SharedGifticon(
        id: 's_5',
        groupId: 'g_friends',
        brand: '배스킨라빈스',
        product: '파인트',
        sharedByName: '김철수',
        status: ShareStatus.available,
        expiryLabel: '~2026.11.01',
      ),
    ];

    _usageLogs.addAll(const <UsageLog>[
      UsageLog(who: '누나', what: 'CU 5,000원 금액권', groupName: '가족', when: '4일 전'),
      UsageLog(
          who: '홍길동', what: '스타벅스 아메리카노', groupName: '친구 모임', when: '1주 전'),
      UsageLog(who: '엄마', what: '올리브영 1만원권', groupName: '가족', when: '2주 전'),
    ]);

    _notifications.addAll(const <GroupNotification>[
      GroupNotification(
        type: GroupNotificationType.registered,
        title: '새 기프티콘 공유',
        message: '엄마님이 스타벅스 아메리카노 T를 공유했어요.',
        when: '1일 전',
      ),
      GroupNotification(
        type: GroupNotificationType.expiringSoon,
        title: '만료 임박',
        message: 'CU 5,000원 금액권이 곧 만료돼요.',
        when: '2일 전',
      ),
      GroupNotification(
        type: GroupNotificationType.used,
        title: '사용 완료',
        message: '누나님이 CU 5,000원 금액권을 사용했어요.',
        when: '4일 전',
      ),
    ]);

    _myGifticons.addAll(const <MyGifticon>[
      MyGifticon(
          id: 'm_1',
          brand: '메가커피',
          product: '아이스 아메리카노',
          expiryLabel: '~2026.12.31'),
      MyGifticon(
          id: 'm_2',
          brand: 'GS25',
          product: '3,000원 금액권',
          expiryLabel: '~2026.09.15'),
      MyGifticon(
          id: 'm_3',
          brand: '교촌치킨',
          product: '허니콤보',
          expiryLabel: '~2026.10.05'),
      MyGifticon(
          id: 'm_4',
          brand: '투썸플레이스',
          product: '조각케이크',
          expiryLabel: '~2026.08.30'),
    ]);
  }
}
