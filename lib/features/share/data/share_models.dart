/// share 페이지 — 그룹/공유 도메인 로컬 모델 (프로토타입 하드코딩).
///
/// **프로토타입 하드코딩 · 계약 v1 확정 후 `lib/shared`로 이관 예정.**
/// 그룹 공유 도메인(Group, GroupMember, SharedGifticon, UsageLog, GroupNotification 등)은
/// 아직 공유 계약(`lib/shared`)에 없다. 통합 전 화면을 구동하기 위한 **share 스코프 전용
/// 로컬 타입**이며, 계약 v1이 확정되면 `lib/shared/models/`의 정본으로 대체한다.
///
/// - 여기 정의는 `lib/features/share/` 밖에서 import 하지 않는다(계약 아님).
/// - 상태 라벨/전이는 [ShareStatus] enum으로만 표현한다(매직 스트링 금지).
library;

/// 공유 기프티콘의 사용 상태(프로토타입).
///
/// 계약 이관 시 원본 `Gifticon`의 상태 전이(available → used)와 정합을 맞춘다.
/// - [available] : 그룹 누구나 사용 가능
/// - [inUse]     : 한 멤버가 사용 중 → 다른 멤버에게 잠김
/// - [used]      : 사용 완료(소진)
enum ShareStatus {
  available('사용 가능'),
  inUse('사용중'),
  used('사용 완료');

  const ShareStatus(this.label);

  /// 뱃지 등에 노출하는 한국어 라벨.
  final String label;
}

/// 그룹 내 멤버 역할(프로토타입).
enum MemberRole {
  /// 방장(대표자) — 그룹 삭제/초대 권한.
  owner,

  /// 일반 멤버.
  member,
}

/// 그룹 알림 유형(프로토타입).
enum GroupNotificationType {
  /// 새 기프티콘이 그룹에 등록됨.
  registered('등록'),

  /// 만료 임박.
  expiringSoon('만료 임박'),

  /// 사용 완료.
  used('사용 완료');

  const GroupNotificationType(this.label);

  /// 알림 유형 라벨.
  final String label;
}

/// 초대코드 만료 시간 선택지(프로토타입, UI 표시용).
enum InviteExpiry {
  oneHour('1시간'),
  oneDay('1일'),
  sevenDays('7일'),
  never('무제한');

  const InviteExpiry(this.label);

  /// 선택지 라벨.
  final String label;
}

/// 그룹 멤버 한 명(프로토타입).
class GroupMember {
  const GroupMember({
    required this.id,
    required this.name,
    required this.emoji,
    required this.role,
  });

  /// 멤버 식별자.
  // TODO(contract): 계약 이관 시 AuthRepository.currentUser 기반 사용자 식별로 대체.
  final String id;

  /// 표시 이름.
  final String name;

  /// 아바타로 쓰는 이모지.
  final String emoji;

  /// 그룹 내 역할.
  final MemberRole role;

  /// 방장 여부.
  bool get isOwner => role == MemberRole.owner;

  GroupMember copyWith({MemberRole? role}) => GroupMember(
        id: id,
        name: name,
        emoji: emoji,
        role: role ?? this.role,
      );
}

/// 그룹 한 개(프로토타입).
class Group {
  Group({
    required this.id,
    required this.name,
    required this.emoji,
    required this.members,
    required this.inviteCode,
  });

  /// 그룹 식별자.
  final String id;

  /// 그룹명.
  String name;

  /// 그룹 대표 이모지.
  String emoji;

  /// 멤버 목록(첫 요소가 아닌, [role]로 방장 판별).
  List<GroupMember> members;

  /// 초대코드(프로토타입 고정값).
  final String inviteCode;

  /// 초대 URL(프로토타입 — 초대코드 기반 조립).
  String get inviteUrl => 'https://keepcon.app/invite/$inviteCode';

  /// 방장 멤버.
  GroupMember get owner =>
      members.firstWhere((GroupMember m) => m.isOwner, orElse: () => members.first);

  /// 멤버 수.
  int get memberCount => members.length;
}

/// 그룹에 공유된 기프티콘 한 개(프로토타입).
class SharedGifticon {
  SharedGifticon({
    required this.id,
    required this.groupId,
    required this.brand,
    required this.product,
    required this.sharedByName,
    required this.status,
    required this.expiryLabel,
    this.lockedByName,
    this.reservedByName,
    this.barcode = '8801234 567890',
  });

  /// 공유 기프티콘 식별자.
  final String id;

  /// 소속 그룹 id.
  final String groupId;

  /// 브랜드명.
  final String brand;

  /// 상품명.
  final String product;

  /// 공유한 멤버 이름.
  final String sharedByName;

  /// 사용 상태.
  ShareStatus status;

  /// 유효기간 라벨(프로토타입).
  final String expiryLabel;

  /// 사용중 잠금 주체(있으면 다른 멤버에게 잠김).
  String? lockedByName;

  /// 찜(사용 예정)한 멤버 이름. null이면 미찜.
  String? reservedByName;

  /// 바코드 문자열(placeholder).
  final String barcode;

  /// 사용 완료 여부.
  bool get isUsed => status == ShareStatus.used;
}

/// 사용 이력 로그 한 줄(프로토타입).
class UsageLog {
  const UsageLog({
    required this.who,
    required this.what,
    required this.groupName,
    required this.when,
  });

  /// 사용 주체 이름.
  final String who;

  /// 사용한 기프티콘 요약(브랜드+상품).
  final String what;

  /// 소속 그룹명.
  final String groupName;

  /// 사용 시점 라벨(프로토타입: "방금", "2일 전" 등).
  final String when;
}

/// 그룹 알림 한 건(프로토타입).
class GroupNotification {
  const GroupNotification({
    required this.type,
    required this.title,
    required this.message,
    required this.when,
  });

  /// 알림 유형.
  final GroupNotificationType type;

  /// 알림 제목.
  final String title;

  /// 알림 본문.
  final String message;

  /// 발생 시점 라벨.
  final String when;
}

/// 내 기프티콘(공유 대상 선택용, 프로토타입).
///
/// 실제로는 메인/스캔이 채우는 원본 `Gifticon` 목록에서 온다.
// TODO(contract): 계약 이관 시 GifticonRepository.watchGifticons(ownerId) 소비로 대체.
class MyGifticon {
  const MyGifticon({
    required this.id,
    required this.brand,
    required this.product,
    required this.expiryLabel,
  });

  /// 식별자.
  final String id;

  /// 브랜드명.
  final String brand;

  /// 상품명.
  final String product;

  /// 유효기간 라벨.
  final String expiryLabel;
}
