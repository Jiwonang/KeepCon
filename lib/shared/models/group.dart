/// KeepCon 공유 계약 — Group / GroupMember 모델 + 관련 enum.
///
/// share 페이지가 생산·소비하는 그룹 도메인의 단일 진실 원천(SSOT).
/// 프로토타입(`lib/features/share/data/share_models.dart`)의 로컬 `Group`/`GroupMember`를
/// 정본으로 승격한 것이다.
///
/// 크로스페이지 계약 규칙(반드시 준수):
/// - [GroupMember.userId]는 [User.id](`lib/shared/models/user.dart`)를 참조한다.
///   프로토타입의 하드코딩 `id`('me' 등)를 auth 세션 기반 식별로 대체한 것이 핵심 개선점.
/// - 방장/멤버/초대 권한 판정은 [Group]의 순수 predicate 메서드
///   ([Group.isOwnedBy]/[Group.isMember]/[Group.canInvite])로 수행한다.
///   페이지는 판정 로직을 재구현하지 말고 이 메서드를 소비한다(로직 drift 방지).
library;

/// 그룹 내 멤버 역할.
enum MemberRole {
  /// 방장(대표자) — 그룹 삭제/소유권 이전/초대 정책 변경 권한.
  owner,

  /// 일반 멤버.
  member,
}

/// 초대코드 만료 시간 선택지.
///
/// 초대 링크/코드의 유효 기간 선택지를 enum으로 못박아 매직 스트링을 방지한다.
/// [duration]으로 실제 만료 시각을 계산한다(`ShareRepository.setInviteExpiry`가 소비).
enum InviteExpiry {
  /// 1시간.
  oneHour('1시간', Duration(hours: 1)),

  /// 1일.
  oneDay('1일', Duration(days: 1)),

  /// 7일.
  sevenDays('7일', Duration(days: 7)),

  /// 무제한 — 만료 없음.
  never('무제한', null);

  const InviteExpiry(this.label, this.duration);

  /// 선택지 표시 라벨.
  final String label;

  /// 이 선택지의 유효 기간. `null`이면 만료 없음([never]).
  ///
  /// 만료 시각은 `설정 시점 + duration`으로 계산한다(구현체 책임).
  final Duration? duration;
}

/// 그룹 멤버 한 명.
///
/// 불변 값 객체. 멤버십/역할 변경은 [copyWith] 또는 [Group.copyWith]로 새 인스턴스를 만든다.
class GroupMember {
  /// GroupMember 인스턴스를 생성한다.
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.avatarEmoji,
    required this.role,
  });

  /// 사용자 식별자. **non-nullable** — [User.id]를 참조한다.
  ///
  /// 프로토타입의 하드코딩 멤버 id를 대체한다. 현재 사용자 판별은 이 값과
  /// `AuthRepository.currentUser!.id`를 비교해 수행한다.
  final String userId;

  /// 표시 이름. **non-nullable** — 통상 [User.displayName] 스냅샷.
  final String displayName;

  /// 아바타로 쓰는 이모지. **non-nullable.**
  ///
  /// 현재 [User] 모델에는 아바타 필드가 없으므로 share 도메인 표시용으로 유지한다.
  /// (프로토타입 표시 자산 — [User]가 아바타를 갖게 되면 그 값으로 대체 예정.)
  final String avatarEmoji;

  /// 그룹 내 역할. **non-nullable.**
  final MemberRole role;

  /// 방장 여부.
  bool get isOwner => role == MemberRole.owner;

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  GroupMember copyWith({
    String? userId,
    String? displayName,
    String? avatarEmoji,
    MemberRole? role,
  }) {
    return GroupMember(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      role: role ?? this.role,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupMember &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarEmoji == other.avatarEmoji &&
          role == other.role;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarEmoji, role);

  @override
  String toString() =>
      'GroupMember(userId: $userId, displayName: $displayName, '
      'role: $role)';
}

/// 그룹 한 개.
///
/// 불변 값 객체. 멤버/이름/정책 변경은 [copyWith]로 새 인스턴스를 만든다
/// (변경 로직은 `ShareRepository` 구현이 소유한다 — 모델은 상태를 직접 변경하지 않는다).
class Group {
  /// Group 인스턴스를 생성한다.
  ///
  /// 불변식(생성자에서 강제):
  /// - 멤버가 1명 이상이어야 한다.
  /// - 방장([MemberRole.owner])이 **정확히 1명** 존재해야 한다(단일 방장 정책).
  ///
  /// [members]는 방어적으로 [List.unmodifiable]로 복사해 보관한다 — 외부에서 원본 리스트를
  /// 바꿔도 [Group] 내부 상태가 오염되지 않는다(불변 값 객체 취지).
  Group({
    required this.id,
    required this.name,
    required this.emoji,
    required List<GroupMember> members,
    required this.inviteCode,
    this.inviteOwnerOnly = false,
    this.inviteExpiresAt,
    this.maxMembers = defaultMaxMembers,
  })  : assert(members.isNotEmpty, 'Group must have at least one member'),
        assert(
          _ownerCount(members) == 1,
          'Group must have exactly one owner (single-owner policy)',
        ),
        assert(maxMembers >= 1, 'maxMembers must be at least 1'),
        members = List<GroupMember>.unmodifiable(members);

  /// 그룹 인원 상한 기본값. 생성 시 별도 지정이 없거나 레거시 문서에 값이 없을 때 쓴다.
  static const int defaultMaxMembers = 10;

  /// 그룹 생성 시 고를 수 있는 인원 상한 프리셋(오름차순). 기본값([defaultMaxMembers])을 포함한다.
  static const List<int> memberCapPresets = <int>[4, 6, 10, 20];

  /// 그룹 식별자. **non-nullable.**
  final String id;

  /// 그룹명. **non-nullable.**
  final String name;

  /// 그룹 대표 이모지. **non-nullable.**
  final String emoji;

  /// 멤버 목록. **non-nullable** — 항상 1명 이상, 방장 정확히 1명(생성자 불변식).
  /// 순서가 아니라 [MemberRole]로 방장을 판별한다.
  ///
  /// 생성자에서 [List.unmodifiable]로 보관하므로 이 리스트는 수정할 수 없다
  /// (`add`/`remove` 등은 예외). 멤버 변경은 [copyWith]로 새 인스턴스를 만든다.
  final List<GroupMember> members;

  /// 초대코드. **non-nullable.**
  final String inviteCode;

  /// 초대 권한 정책 — `true`면 방장만 멤버를 초대할 수 있다(기본 `false`, 누구나).
  /// 정책 변경은 방장만 가능하며 `ShareRepository.setInviteOwnerOnly`로만 바꾼다.
  final bool inviteOwnerOnly;

  /// 초대코드 만료 시각. `null`이면 만료 없음([InviteExpiry.never] 또는 미설정).
  ///
  /// 방장이 `ShareRepository.setInviteExpiry`로 설정하며, 이 시각을 지나면
  /// `ShareRepository.joinGroup`이 [StateError]로 참여를 거부한다([isInviteExpired] 참조).
  final DateTime? inviteExpiresAt;

  /// 그룹 인원 상한(방장 포함). 기본 [defaultMaxMembers]. 생성 시 방장이 정한다.
  ///
  /// `joinGroup`은 [isFull]이면 참여를 거부한다([StateError]). 이 값보다 멤버가 많아지는
  /// 전이는 만들어지지 않는다(참여 가드가 유일한 증가 경로).
  final int maxMembers;

  /// 초대 URL(초대코드 기반 조립).
  String get inviteUrl => 'https://keepcon.app/invite/$inviteCode';

  /// 정원이 찼는지(멤버 수 ≥ [maxMembers]). 참여 가능 여부 판정의 단일 진입점.
  bool get isFull => memberCount >= maxMembers;

  /// 남은 자리 수(0 이상). 표시용.
  int get remainingSlots {
    final int left = maxMembers - memberCount;
    return left < 0 ? 0 : left;
  }

  /// [now] 기준으로 초대코드가 만료되었는지.
  ///
  /// [inviteExpiresAt]가 `null`(무제한)이면 항상 `false`. 만료 판정의 단일 진입점이며,
  /// UI 게이팅(참여 버튼 노출)과 구현체 가드가 모두 이 predicate를 소비한다(로직 drift 방지).
  bool isInviteExpired(DateTime now) =>
      inviteExpiresAt != null && !now.isBefore(inviteExpiresAt!);

  /// 멤버 수.
  int get memberCount => members.length;

  /// 방장 멤버. 생성자 불변식이 정확히 1명의 방장을 보장하므로 항상 존재한다
  /// (불변식이 깨졌다면 [StateError] — 조용히 첫 멤버를 반환해 결함을 감추지 않는다).
  GroupMember get owner => members.firstWhere((GroupMember m) => m.isOwner);

  /// [userId]에 해당하는 멤버를 반환한다. 없으면 `null`.
  GroupMember? memberById(String userId) {
    for (final GroupMember m in members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  /// [userId]가 이 그룹의 멤버인지.
  bool isMember(String userId) => memberById(userId) != null;

  /// [userId]가 이 그룹의 방장인지. 방장 판정의 단일 진입점(로직 drift 방지).
  bool isOwnedBy(String userId) {
    final GroupMember? m = memberById(userId);
    return m != null && m.isOwner;
  }

  /// [userId]가 이 그룹에 멤버를 초대할 수 있는지.
  ///
  /// 방장은 항상 가능, 일반 멤버는 [inviteOwnerOnly]가 꺼져 있을 때만 가능.
  /// 비멤버는 불가. UI 초대 진입점 노출을 이 판정으로 중앙화한다(권한 로직 중복 방지).
  bool canInvite(String userId) {
    if (!isMember(userId)) return false;
    return isOwnedBy(userId) || !inviteOwnerOnly;
  }

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  ///
  /// [inviteExpiresAt]는 nullable이라 "미지정"과 "명시적 null(무제한)"을 구분해야 하므로
  /// 센티널([_unset])을 기본값으로 둔다 — 인자를 생략하면 기존 값을 유지하고,
  /// `null`을 명시하면 만료 없음으로 되돌린다.
  Group copyWith({
    String? id,
    String? name,
    String? emoji,
    List<GroupMember>? members,
    String? inviteCode,
    bool? inviteOwnerOnly,
    Object? inviteExpiresAt = _unset,
    int? maxMembers,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      members: members ?? this.members,
      inviteCode: inviteCode ?? this.inviteCode,
      inviteOwnerOnly: inviteOwnerOnly ?? this.inviteOwnerOnly,
      inviteExpiresAt: identical(inviteExpiresAt, _unset)
          ? this.inviteExpiresAt
          : inviteExpiresAt as DateTime?,
      maxMembers: maxMembers ?? this.maxMembers,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          emoji == other.emoji &&
          _memberListEquals(members, other.members) &&
          inviteCode == other.inviteCode &&
          inviteOwnerOnly == other.inviteOwnerOnly &&
          inviteExpiresAt == other.inviteExpiresAt &&
          maxMembers == other.maxMembers;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        emoji,
        Object.hashAll(members),
        inviteCode,
        inviteOwnerOnly,
        inviteExpiresAt,
        maxMembers,
      );

  @override
  String toString() => 'Group(id: $id, name: $name, memberCount: $memberCount, '
      'maxMembers: $maxMembers, inviteOwnerOnly: $inviteOwnerOnly, '
      'inviteExpiresAt: $inviteExpiresAt)';
}

/// [Group.copyWith]가 "미지정"을 "명시적 null"과 구분하기 위한 센티널.
const Object _unset = Object();

/// 멤버 목록의 방장([MemberRole.owner]) 수. [Group] 생성자 불변식 검증에 사용한다.
int _ownerCount(List<GroupMember> members) =>
    members.where((GroupMember m) => m.role == MemberRole.owner).length;

/// 멤버 리스트 동치 비교(순서 포함). 외부 컬렉션 의존성 없이 == 구현에 사용한다.
bool _memberListEquals(List<GroupMember> a, List<GroupMember> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
