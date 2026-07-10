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

/// 초대코드 만료 시간 선택지(UI 표시용).
///
/// 초대 링크/코드의 유효 기간 선택지를 enum으로 못박아 매직 스트링을 방지한다.
enum InviteExpiry {
  /// 1시간.
  oneHour('1시간'),

  /// 1일.
  oneDay('1일'),

  /// 7일.
  sevenDays('7일'),

  /// 무제한.
  never('무제한');

  const InviteExpiry(this.label);

  /// 선택지 표시 라벨.
  final String label;
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
  const Group({
    required this.id,
    required this.name,
    required this.emoji,
    required this.members,
    required this.inviteCode,
    this.inviteOwnerOnly = false,
  });

  /// 그룹 식별자. **non-nullable.**
  final String id;

  /// 그룹명. **non-nullable.**
  final String name;

  /// 그룹 대표 이모지. **non-nullable.**
  final String emoji;

  /// 멤버 목록. **non-nullable** — 항상 1명 이상(방장 포함).
  /// 순서가 아니라 [MemberRole]로 방장을 판별한다.
  final List<GroupMember> members;

  /// 초대코드. **non-nullable.**
  final String inviteCode;

  /// 초대 권한 정책 — `true`면 방장만 멤버를 초대할 수 있다(기본 `false`, 누구나).
  /// 정책 변경은 방장만 가능하며 `ShareRepository.setInviteOwnerOnly`로만 바꾼다.
  final bool inviteOwnerOnly;

  /// 초대 URL(초대코드 기반 조립).
  String get inviteUrl => 'https://keepcon.app/invite/$inviteCode';

  /// 멤버 수.
  int get memberCount => members.length;

  /// 방장 멤버(없으면 첫 멤버 — 계약상 항상 방장이 존재).
  GroupMember get owner => members.firstWhere(
        (GroupMember m) => m.isOwner,
        orElse: () => members.first,
      );

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
  Group copyWith({
    String? id,
    String? name,
    String? emoji,
    List<GroupMember>? members,
    String? inviteCode,
    bool? inviteOwnerOnly,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      members: members ?? this.members,
      inviteCode: inviteCode ?? this.inviteCode,
      inviteOwnerOnly: inviteOwnerOnly ?? this.inviteOwnerOnly,
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
          inviteOwnerOnly == other.inviteOwnerOnly;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        emoji,
        Object.hashAll(members),
        inviteCode,
        inviteOwnerOnly,
      );

  @override
  String toString() => 'Group(id: $id, name: $name, memberCount: $memberCount, '
      'inviteOwnerOnly: $inviteOwnerOnly)';
}

/// 멤버 리스트 동치 비교(순서 포함). 외부 컬렉션 의존성 없이 == 구현에 사용한다.
bool _memberListEquals(List<GroupMember> a, List<GroupMember> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
