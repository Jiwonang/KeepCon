/// KeepCon 공유 계약 — JoinRequest(그룹 참여 요청) 모델 + enum.
///
/// 초대 링크로 들어온 사람이 **곧바로 멤버가 되지 않고** 방장의 승인을 기다리는 중간
/// 상태를 표현한다. 링크는 유출되면 그대로 참여 경로가 되므로, 링크 소지 = 참여가 아니라
/// 링크 소지 = 요청 자격으로 한 단계 낮춘 것이다.
///
/// ## 요청자에게 그룹 정보를 담지 않는 이유
/// 이 모델에는 그룹명·이모지·멤버 수가 없다. 승인 전 요청자는 자기가 어느 그룹에 요청했는지
/// 조차 볼 수 없어야 한다는 정책이라, 화면이 쓰지 않는 값을 굳이 저장하지 않는다
/// (저장하면 언젠가 새어 나간다). 방장 쪽 승인 목록은 이미 그룹 문맥 안에 있으므로
/// [groupId]만으로 충분하다.
///
/// ## 크로스페이지 계약 규칙
/// - [userId]는 [User.id](`lib/shared/models/user.dart`)를 참조한다.
/// - [displayName]·[avatarEmoji]는 **요청 시점 스냅샷**이다. 방장은 요청자의 프로필을
///   조회할 권한이 없으므로(사용자 문서는 본인만 읽는다) 승인 목록에 보여줄 값을 요청에
///   함께 담는다. 승인 시 이 두 값이 그대로 `GroupMember`가 된다 — 승인 화면에서 보던
///   사람과 멤버 목록에 뜨는 사람이 달라 보이지 않게 하려는 것이다.
library;

/// 참여 요청의 처리 상태.
///
/// **취소는 상태가 아니다.** 요청자가 스스로 거두는 것은 기록으로 남길 이유가 없어
/// 문서를 지운다(`ShareRepository.cancelJoinRequest`). 반면 [rejected]는 남긴다 —
/// 요청자가 "왜 아직도 못 들어가지"에 답을 얻을 유일한 경로이기 때문이다(비멤버는
/// 그룹 알림을 읽을 수 없다).
///
/// 전이 규칙을 [ShareStatus]처럼 표로 두지 않는 이유: 상태를 바꾸는 곳이
/// `ShareRepository`의 세 메서드(요청·승인·거절)뿐이고 각자 가드를 갖는다. 표를 함께
/// 두면 진실 원천이 둘이 된다 — 실제로 "결정은 되돌릴 수 없다"는 표와 "거절당해도 다시
/// 요청할 수 있다"는 규약이 곧바로 어긋났다.
enum JoinRequestStatus {
  /// 방장의 결정을 기다리는 중.
  pending('대기 중'),

  /// 방장이 승인 — 요청자는 이 시점에 멤버가 된다.
  approved('승인됨'),

  /// 방장이 거절.
  rejected('거절됨');

  const JoinRequestStatus(this.label);

  /// 한국어 라벨.
  final String label;
}

/// 그룹 참여 요청 한 건.
///
/// 불변 값 객체. 상태 변경은 [copyWith]로 새 인스턴스를 만든다(변경 로직은
/// `ShareRepository` 구현이 소유한다).
class JoinRequest {
  /// JoinRequest 인스턴스를 생성한다.
  const JoinRequest({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.avatarEmoji,
    required this.requestedAt,
    this.status = JoinRequestStatus.pending,
  });

  /// 요청 식별자. **non-nullable.**
  final String id;

  /// 요청 대상 그룹 id([Group.id]). **non-nullable.**
  ///
  /// 요청자 화면은 이 값을 쓰지 않는다(승인 전에는 어느 그룹인지 보여주지 않는다).
  /// 방장의 승인 목록과 구현의 그룹 조회가 소비한다.
  final String groupId;

  /// 요청자 식별자([User.id]). **non-nullable.**
  final String userId;

  /// 요청자 표시 이름 — 요청 시점 스냅샷. **non-nullable.**
  final String displayName;

  /// 요청자 아바타 이모지 — 요청 시점 스냅샷. **non-nullable.**
  ///
  /// 승인되면 이 값이 그대로 `GroupMember.avatarEmoji`가 된다.
  final String avatarEmoji;

  /// 요청 시각. **non-nullable** — 방장의 승인 목록 정렬(오래된 순) 기준.
  final DateTime requestedAt;

  /// 처리 상태. **non-nullable** — 기본 [JoinRequestStatus.pending].
  final JoinRequestStatus status;

  /// 아직 방장의 결정을 기다리는 중인지. 판정의 단일 진입점(로직 drift 방지).
  bool get isPending => status == JoinRequestStatus.pending;

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  JoinRequest copyWith({
    String? id,
    String? groupId,
    String? userId,
    String? displayName,
    String? avatarEmoji,
    DateTime? requestedAt,
    JoinRequestStatus? status,
  }) {
    return JoinRequest(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      requestedAt: requestedAt ?? this.requestedAt,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoinRequest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          groupId == other.groupId &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarEmoji == other.avatarEmoji &&
          requestedAt == other.requestedAt &&
          status == other.status;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        userId,
        displayName,
        avatarEmoji,
        requestedAt,
        status,
      );

  @override
  String toString() => 'JoinRequest(id: $id, groupId: $groupId, '
      'userId: $userId, status: $status)';
}
