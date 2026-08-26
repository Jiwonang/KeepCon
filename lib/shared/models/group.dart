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
  ///
  /// [inviteExpiresAt]를 생략하면 **지금 막 코드를 발급한 것**으로 보고
  /// `현재 + [inviteValidity]`(24시간)로 채운다 — 초대 정책상 만료 없는 그룹은 존재하지
  /// 않으므로 "미지정"이라는 상태를 만들지 않는다. 저장소에서 복원할 때처럼 발급 시점이
  /// 따로 있는 경우에만 명시한다.
  Group({
    required this.id,
    required this.name,
    required this.emoji,
    required List<GroupMember> members,
    required this.inviteToken,
    this.inviteOwnerOnly = false,
    DateTime? inviteExpiresAt,
    this.maxMembers = defaultMaxMembers,
    this.inviteCode,
    this.inviteCodeExpiresAt,
  })  : assert(members.isNotEmpty, 'Group must have at least one member'),
        assert(
          _ownerCount(members) == 1,
          'Group must have exactly one owner (single-owner policy)',
        ),
        assert(maxMembers >= 1, 'maxMembers must be at least 1'),
        // 코드와 그 만료는 **함께 있거나 함께 없다.** 한쪽만 채워지면 "만료 없는 코드"나
        // "가리킬 코드가 없는 만료"가 생기고, 그 순간 [hasActiveInviteCode]가 판정할 수
        // 없는 상태가 된다 — 그런 상태를 만들지 않는 것이 이 불변식의 목적이다.
        assert(
          (inviteCode == null) == (inviteCodeExpiresAt == null),
          'inviteCode and inviteCodeExpiresAt must be set or cleared together',
        ),
        inviteExpiresAt = inviteExpiresAt ?? DateTime.now().add(inviteValidity),
        members = List<GroupMember>.unmodifiable(members);

  /// 그룹 인원 상한 기본값. 생성 시 별도 지정이 없거나 레거시 문서에 값이 없을 때 쓴다.
  static const int defaultMaxMembers = 10;

  /// 초대 링크·코드의 유효 기간 — **모든 초대는 발급 시점부터 24시간만 유효하다.**
  ///
  /// 방장이 고르는 값이 아니라 앱 전체에 고정된 정책이다(선택 UI 없음). 초대가 만료되면
  /// `ShareRepository.regenerateInviteToken`로 새 코드를 발급받아 창을 다시 연다.
  static const Duration inviteValidity = Duration(hours: 24);

  /// 초대**코드**의 유효 기간 — 발급 시점부터 **5분**.
  ///
  /// 링크와 다른 값인 이유는 두 자격증명의 위협 모델이 다르기 때문이다. 링크 토큰은
  /// 128비트라 추측이 성립하지 않아 24시간을 열어 둘 수 있지만, 코드는 소리내어 읽으려고
  /// 6자리로 줄인 값이라 열거 가능한 공간이다(`lib/shared/util/invite_code.dart` 참조).
  /// 그 좁은 공간을 **수명으로 막는다** — 상시 활성 코드가 없으면 전수 조회의 수확이
  /// "지금 초대를 기다리는 중인 소수 그룹"으로 줄어든다.
  ///
  /// 방장이 고르는 값이 아니라 앱 전체에 고정된 정책이다(선택 UI 없음). 이 값을 늘리는
  /// 것은 UX 조정이 아니라 **보안 파라미터 변경**이다.
  static const Duration inviteCodeValidity = Duration(minutes: 5);

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

  /// 초대 토큰 — 초대 링크에 실려 그룹을 가리키는 값. **non-nullable.**
  final String inviteToken;

  /// 초대 권한 정책 — `true`면 방장만 멤버를 초대할 수 있다(기본 `false`, 누구나).
  /// 정책 변경은 방장만 가능하며 `ShareRepository.setInviteOwnerOnly`로만 바꾼다.
  final bool inviteOwnerOnly;

  /// 초대 토큰 만료 시각. **non-nullable** — 만료 없는 초대는 없다.
  ///
  /// 코드가 발급되는 시점(그룹 생성 / `ShareRepository.regenerateInviteToken`)에
  /// `발급 시각 + [inviteValidity]`로 정해지며, 이 시각을 지나면
  /// `ShareRepository.requestToJoin`이 [StateError]로 **요청 자체를** 거부한다
  /// ([isInviteExpired] 참조).
  final DateTime inviteExpiresAt;

  /// 그룹 인원 상한(방장 포함). 기본 [defaultMaxMembers]. 생성 시 방장이 정한다.
  ///
  /// 정원 검사는 **승인 시점**이다 — `ShareRepository.approveJoinRequest`가 [isFull]이면
  /// [StateError]로 거부한다. 요청은 정원과 무관하게 접수된다(대기자가 자리를 선점하면
  /// 방장이 정작 받고 싶은 사람을 못 넣는다). 이 값보다 멤버가 많아지는 전이는
  /// 만들어지지 않는다(승인이 유일한 증가 경로).
  final int maxMembers;

  /// 현재 발급된 초대코드(6자리 숫자 문자열). **없으면 `null`** — 기본 상태다.
  ///
  /// 링크 토큰([inviteToken])과 달리 그룹에 상주하지 않는다. 방장이 "초대코드 발급하기"를
  /// 누른 뒤 [inviteCodeValidity](5분) 동안만 존재하고, 그 창이 닫히면 값은 남아 있어도
  /// [hasActiveInviteCode]가 `false`가 된다.
  ///
  /// **`int`가 아니라 `String`이다** — `012345`의 앞자리 0을 잃으면 다른 코드가 된다
  /// (`lib/shared/util/invite_code.dart` 참조).
  ///
  /// 값이 남아 있는 채로 만료되는 이유: 만료 시각에 문서를 고쳐 줄 주체가 없다(그 순간
  /// 아무도 쓰지 않는다). 지우는 시점은 **다음 발급**이며, 그때 옛 조회 문서도 함께
  /// 정리된다. 그래서 판정은 항상 값의 유무가 아니라 [hasActiveInviteCode]로 한다.
  final String? inviteCode;

  /// [inviteCode]의 만료 시각. 코드가 없으면 `null`([inviteCode]와 항상 짝).
  ///
  /// 발급 시점 + [inviteCodeValidity]로 정해진다. 이 시각을 지난 코드로 참여를 요청하면
  /// `ShareRepository.requestToJoin`이 `InviteExpiredException`으로 거부한다 — 화면이
  /// "만료된 초대코드"라고 **구별해서** 안내할 수 있게 하려고 일반 [StateError]와
  /// 다른 타입을 쓴다(모델은 저장소 계약에 의존하지 않으므로 이름만 적는다).
  final DateTime? inviteCodeExpiresAt;

  // 초대 URL은 여기서 만들지 않는다.
  //
  // 예전에는 `inviteHost` 상수와 `inviteUrl` getter가 이 모델에 있었는데, 그 호스트는
  // prod(`keepcon-ab660.web.app`) 하나로 박혀 있었다. 그래서 **에뮬레이터나 dev에서
  // 띄운 앱이 실서비스 도메인을 가리키는 링크를 발급**했다 — 받은 사람이 누르면 남의
  // 실서비스 그룹으로 간다.
  //
  // 모델은 순수해서 "지금 어느 백엔드인지"를 알 수 없으므로, 조립을
  // `inviteOriginProvider` + `inviteUrlFrom()`으로 옮겼다
  // (`lib/shared/providers/invite_link_providers.dart`, `lib/shared/util/invite_link.dart`).
  //
  // ⚠️ 안드로이드에서 도메인을 바꾸려면 `AndroidManifest.xml`의 인텐트 필터 host와
  //    그 도메인의 `/.well-known/assetlinks.json`을 **함께** 손봐야 한다. 하나만 바뀌면
  //    링크가 조용히 브라우저로 샌다(App Links 검증은 실패해도 오류를 내지 않는다).

  /// 정원이 찼는지(멤버 수 ≥ [maxMembers]). 참여 가능 여부 판정의 단일 진입점.
  bool get isFull => memberCount >= maxMembers;

  /// 남은 자리 수(0 이상). 표시용.
  int get remainingSlots {
    final int left = maxMembers - memberCount;
    return left < 0 ? 0 : left;
  }

  /// [now] 기준으로 초대 토큰이 만료되었는지.
  ///
  /// 만료 판정의 단일 진입점이며, UI 게이팅(참여 버튼 노출)과 구현체 가드가 모두 이
  /// predicate를 소비한다(로직 drift 방지).
  bool isInviteExpired(DateTime now) => !now.isBefore(inviteExpiresAt);

  /// [now] 기준으로 **쓸 수 있는** 초대코드가 있는지.
  ///
  /// 초대코드 판정의 단일 진입점이다. 발급 화면의 코드 표시 여부, 구현체의 조회 가드가
  /// 모두 이 predicate를 소비한다.
  ///
  /// "코드가 있는지"([inviteCode] `!= null`)로 판정하면 안 된다 — 만료된 값이 그대로
  /// 남아 있기 때문이다([inviteCode] 문서 참조). 유효성은 항상 시각과 함께 본다.
  bool hasActiveInviteCode(DateTime now) {
    final DateTime? until = inviteCodeExpiresAt;
    return inviteCode != null && until != null && now.isBefore(until);
  }

  /// 초대코드가 만료되기까지 남은 시간. 쓸 수 있는 코드가 없으면 `null`.
  ///
  /// 발급 화면의 카운트다운이 소비한다. `null`과 [Duration.zero]를 구별한다 —
  /// `null`은 "보여줄 코드가 없다"(발급 전/만료 후), zero는 논리상 나오지 않는다
  /// ([hasActiveInviteCode]가 이미 `false`가 되므로).
  Duration? inviteCodeRemaining(DateTime now) {
    if (!hasActiveInviteCode(now)) return null;
    return inviteCodeExpiresAt!.difference(now);
  }

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
  /// [clearInviteCode]가 `true`면 [inviteCode]·[inviteCodeExpiresAt]를 **함께 비운다**
  /// (둘은 짝이라는 생성자 불변식을 이 경로에서도 지킨다). 이 플래그가 필요한 이유는
  /// nullable 필드의 `?? this.x` 패턴이 "값을 지운다"를 표현하지 못하기 때문이다 —
  /// 플래그가 없으면 `copyWith(inviteCode: null)`이 **조용히 아무 일도 하지 않아**,
  /// 코드를 무효화했다고 믿는 호출부가 살아 있는 코드를 그대로 남긴다.
  /// 지정하면 같은 호출의 [inviteCode]·[inviteCodeExpiresAt] 인자보다 우선한다.
  Group copyWith({
    String? id,
    String? name,
    String? emoji,
    List<GroupMember>? members,
    String? inviteToken,
    bool? inviteOwnerOnly,
    DateTime? inviteExpiresAt,
    int? maxMembers,
    String? inviteCode,
    DateTime? inviteCodeExpiresAt,
    bool clearInviteCode = false,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      members: members ?? this.members,
      inviteToken: inviteToken ?? this.inviteToken,
      inviteOwnerOnly: inviteOwnerOnly ?? this.inviteOwnerOnly,
      inviteExpiresAt: inviteExpiresAt ?? this.inviteExpiresAt,
      maxMembers: maxMembers ?? this.maxMembers,
      inviteCode: clearInviteCode ? null : (inviteCode ?? this.inviteCode),
      inviteCodeExpiresAt: clearInviteCode
          ? null
          : (inviteCodeExpiresAt ?? this.inviteCodeExpiresAt),
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
          inviteToken == other.inviteToken &&
          inviteOwnerOnly == other.inviteOwnerOnly &&
          inviteExpiresAt == other.inviteExpiresAt &&
          maxMembers == other.maxMembers &&
          inviteCode == other.inviteCode &&
          inviteCodeExpiresAt == other.inviteCodeExpiresAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        emoji,
        Object.hashAll(members),
        inviteToken,
        inviteOwnerOnly,
        inviteExpiresAt,
        maxMembers,
        inviteCode,
        inviteCodeExpiresAt,
      );

  // `inviteCode` 값 자체는 [toString]에 넣지 않는다 — 로그·오류 리포트로 새어 나가면
  // 5분짜리 자격증명이 그 로그를 읽는 사람에게 그대로 넘어간다. 활성 여부만 적는다.
  @override
  String toString() => 'Group(id: $id, name: $name, memberCount: $memberCount, '
      'maxMembers: $maxMembers, inviteOwnerOnly: $inviteOwnerOnly, '
      'inviteExpiresAt: $inviteExpiresAt, '
      'inviteCodeExpiresAt: $inviteCodeExpiresAt)';
}

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
