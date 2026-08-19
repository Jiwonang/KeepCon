/// KeepCon 공유 계약 — 공유 기프티콘 / 사용 이력 / 그룹 알림 모델 + enum.
///
/// share 페이지의 공유 도메인 SSOT. 프로토타입
/// (`lib/features/share/data/share_models.dart`)의 로컬 `SharedGifticon`/`UsageLog`/
/// `GroupNotification`을 정본으로 승격한 것이다.
///
/// 핵심 개선점(프로토타입 대비):
/// - [SharedGifticon.gifticonId] 신설 — 원본 [Gifticon.id]를 참조한다. 공유 항목이
///   소비(사용 완료)될 때 이 참조로 원본 [Gifticon] 상태를 available→used로 동기화한다.
/// - 이름(문자열) 기반 식별을 [User.id] 참조로 대체
///   (`sharedByName`→[SharedGifticon.sharedByUserId], `lockedByName`/`reservedByName`→
///   [SharedGifticon.lockedByUserId]/[SharedGifticon.reservedByUserId], `who`→[UsageLog.userId]).
/// - 표시용 라벨 문자열을 실제 타입으로 대체(`expiryLabel`(String)→[SharedGifticon.expiryDate]
///   (DateTime), `when`(String)→[UsageLog.usedAt]/[GroupNotification.createdAt](DateTime)).
///   상대 시각("방금", "2일 전") 포맷은 소비자(UI) 책임.
///
/// 매직 스트링 금지 — 상태/알림 유형은 [ShareStatus]/[GroupNotificationType] enum으로만 표현한다.
library;

/// 공유 기프티콘의 사용 상태.
///
/// 원본 [Gifticon]의 `GifticonStatus`(available/used/expired)와는 **다른** 관심사다.
/// [ShareStatus]는 "그룹 안에서의 사용 흐름"(사용 가능 → 사용중(잠금) → 사용 완료)을 표현한다.
/// 사용 완료([used]) 시 원본 [Gifticon]도 `GifticonStatus.used`로 동기화된다(경계면 규약).
enum ShareStatus {
  /// 그룹 누구나 사용 가능.
  available('사용 가능'),

  /// 한 멤버가 사용 중 → 다른 멤버에게 잠김.
  inUse('사용중'),

  /// 사용 완료(소진).
  used('사용 완료');

  const ShareStatus(this.label);

  /// 뱃지 등에 노출하는 한국어 라벨.
  final String label;
}

/// [ShareStatus] 전이 규칙 헬퍼(SSOT).
///
/// 개별 `ShareRepository` 메서드는 이 표보다 더 엄격한 가드를 둘 수 있다
/// (예: `markUsed`는 [ShareStatus.available]에서만 사용 완료를 허용).
extension ShareStatusTransition on ShareStatus {
  /// 허용된 상태 전이 표. 키에서 값 집합으로의 전이만 유효하다.
  static const Map<ShareStatus, Set<ShareStatus>> allowed = {
    ShareStatus.available: {ShareStatus.inUse, ShareStatus.used},
    ShareStatus.inUse: {ShareStatus.available, ShareStatus.used},
    ShareStatus.used: <ShareStatus>{},
  };

  /// `this` 상태에서 [next]로의 전이가 허용되는지.
  /// 같은 상태로의 no-op 전이(`this == next`)는 허용으로 간주한다.
  bool canTransitionTo(ShareStatus next) =>
      this == next || (allowed[this]?.contains(next) ?? false);

  /// 정적 형태의 전이 검사. 구현/QA가 재사용한다.
  static bool isAllowed(ShareStatus from, ShareStatus to) =>
      from.canTransitionTo(to);
}

/// 센티널 — [SharedGifticon.copyWith]에서 nullable 필드를 명시적으로 `null`로 지우기 위함.
const Object _unset = Object();

/// 그룹에 공유된 기프티콘 한 개.
///
/// 불변 값 객체. 상태/잠금/찜 변경은 [copyWith]로 새 인스턴스를 만든다
/// (변경 로직은 `ShareRepository` 구현이 소유한다).
///
/// 표시용 필드([brand]/[productName]/[expiryDate]/[barcode])는 원본 [Gifticon]의 **스냅샷**이다.
/// 다른 그룹 멤버는 공유자의 개인 기프티콘 목록을 조회할 수 없으므로(소유자별 조회 경계),
/// 표시에 필요한 값을 공유 시점에 스냅샷으로 담는다. 원본과의 연결은 [gifticonId]로 유지한다.
class SharedGifticon {
  /// SharedGifticon 인스턴스를 생성한다.
  const SharedGifticon({
    required this.id,
    required this.groupId,
    required this.gifticonId,
    required this.sharedByUserId,
    required this.brand,
    required this.productName,
    required this.expiryDate,
    required this.status,
    this.lockedByUserId,
    this.reservedByUserId,
    this.barcode,
  });

  /// 공유 항목 식별자. **non-nullable.**
  final String id;

  /// 소속 그룹 id([Group.id]). **non-nullable.**
  final String groupId;

  /// 원본 기프티콘 id([Gifticon.id]) 참조. **non-nullable.**
  ///
  /// 사용 완료 시 이 참조로 원본 [Gifticon]을 `GifticonStatus.used`로 동기화한다.
  final String gifticonId;

  /// 공유한 멤버 id([User.id]). **non-nullable.**
  final String sharedByUserId;

  /// 브랜드명(원본 [Gifticon.brand] 스냅샷). **non-nullable.**
  final String brand;

  /// 상품명(원본 [Gifticon.productName] 스냅샷). **non-nullable.**
  final String productName;

  /// 유효기간(원본 [Gifticon.expiryDate] 스냅샷). **non-nullable.**
  final DateTime expiryDate;

  /// 사용 상태. **non-nullable.**
  final ShareStatus status;

  /// 사용중 잠금 주체 id([User.id]). **nullable** — [ShareStatus.inUse]가 아니면 보통 `null`.
  final String? lockedByUserId;

  /// 찜(사용 예정)한 멤버 id([User.id]). **nullable** — 미찜이면 `null`.
  final String? reservedByUserId;

  /// 바코드 문자열(원본 [Gifticon.barcode] 스냅샷). **nullable** — 없을 수 있다.
  final String? barcode;

  /// 사용 완료 여부.
  bool get isUsed => status == ShareStatus.used;

  /// [userId] 관점에서 "다른 멤버에게 잠김"인지(사용중이며 잠근 주체가 내가 아님).
  bool isLockedFor(String userId) =>
      status == ShareStatus.inUse &&
      lockedByUserId != null &&
      lockedByUserId != userId;

  /// [userId] 관점에서 "다른 멤버가 찜함"인지.
  bool isReservedByOther(String userId) =>
      reservedByUserId != null && reservedByUserId != userId;

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  ///
  /// [lockedByUserId]/[reservedByUserId]/[barcode]는 인자를 명시적으로 `null`로 전달하면
  /// 값을 **지운다**(센티널 기본값 덕분에 "미지정"과 "null로 지정"을 구분한다). 미지정 시 값 유지.
  SharedGifticon copyWith({
    String? id,
    String? groupId,
    String? gifticonId,
    String? sharedByUserId,
    String? brand,
    String? productName,
    DateTime? expiryDate,
    ShareStatus? status,
    Object? lockedByUserId = _unset,
    Object? reservedByUserId = _unset,
    Object? barcode = _unset,
  }) {
    return SharedGifticon(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      gifticonId: gifticonId ?? this.gifticonId,
      sharedByUserId: sharedByUserId ?? this.sharedByUserId,
      brand: brand ?? this.brand,
      productName: productName ?? this.productName,
      expiryDate: expiryDate ?? this.expiryDate,
      status: status ?? this.status,
      lockedByUserId: identical(lockedByUserId, _unset)
          ? this.lockedByUserId
          : lockedByUserId as String?,
      reservedByUserId: identical(reservedByUserId, _unset)
          ? this.reservedByUserId
          : reservedByUserId as String?,
      barcode: identical(barcode, _unset) ? this.barcode : barcode as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedGifticon &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          groupId == other.groupId &&
          gifticonId == other.gifticonId &&
          sharedByUserId == other.sharedByUserId &&
          brand == other.brand &&
          productName == other.productName &&
          expiryDate == other.expiryDate &&
          status == other.status &&
          lockedByUserId == other.lockedByUserId &&
          reservedByUserId == other.reservedByUserId &&
          barcode == other.barcode;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        gifticonId,
        sharedByUserId,
        brand,
        productName,
        expiryDate,
        status,
        lockedByUserId,
        reservedByUserId,
        barcode,
      );

  @override
  String toString() =>
      'SharedGifticon(id: $id, groupId: $groupId, gifticonId: $gifticonId, '
      'brand: $brand, productName: $productName, status: $status)';
}

/// 사용 이력 로그 한 줄.
///
/// 공유 기프티콘이 사용 완료될 때 생성된다. 표시용 상대 시각 포맷은 소비자(UI) 책임.
class UsageLog {
  /// UsageLog 인스턴스를 생성한다.
  const UsageLog({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.sharedGifticonId,
    required this.brand,
    required this.productName,
    required this.usedAt,
  });

  /// 로그 식별자. **non-nullable.**
  final String id;

  /// 소속 그룹 id([Group.id]). **non-nullable** — 프로토타입의 `groupName`(String)을 대체.
  final String groupId;

  /// 사용 주체 id([User.id]). **non-nullable** — 프로토타입의 `who`(이름)를 대체.
  final String userId;

  /// 사용된 공유 항목 id([SharedGifticon.id]). **non-nullable.**
  final String sharedGifticonId;

  /// 브랜드명(스냅샷). **non-nullable.**
  final String brand;

  /// 상품명(스냅샷). **non-nullable.**
  final String productName;

  /// 사용 시각. **non-nullable** — 프로토타입의 `when`(라벨)을 실제 타입으로 대체.
  final DateTime usedAt;

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  UsageLog copyWith({
    String? id,
    String? groupId,
    String? userId,
    String? sharedGifticonId,
    String? brand,
    String? productName,
    DateTime? usedAt,
  }) {
    return UsageLog(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      sharedGifticonId: sharedGifticonId ?? this.sharedGifticonId,
      brand: brand ?? this.brand,
      productName: productName ?? this.productName,
      usedAt: usedAt ?? this.usedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageLog &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          groupId == other.groupId &&
          userId == other.userId &&
          sharedGifticonId == other.sharedGifticonId &&
          brand == other.brand &&
          productName == other.productName &&
          usedAt == other.usedAt;

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        userId,
        sharedGifticonId,
        brand,
        productName,
        usedAt,
      );

  @override
  String toString() => 'UsageLog(id: $id, groupId: $groupId, userId: $userId, '
      'what: $brand $productName, usedAt: $usedAt)';
}

/// 그룹 알림 유형.
enum GroupNotificationType {
  /// 새 기프티콘이 그룹에 등록(공유)됨.
  registered('등록'),

  /// 만료 임박.
  expiringSoon('만료 임박'),

  /// 사용 완료.
  used('사용 완료');

  // 참여 요청은 여기에 넣지 않는다 — 요청의 행위자는 비멤버인데 알림 문서는 멤버만
  // 만들 수 있어, 클라이언트가 만들 수 없는 알림이 된다. 방장에게 요청을 알리는 신호는
  // `ShareRepository.watchPendingJoinRequests` 하나다.

  const GroupNotificationType(this.label);

  /// 알림 유형 라벨.
  final String label;
}

/// 그룹 알림 한 건.
class GroupNotification {
  /// GroupNotification 인스턴스를 생성한다.
  const GroupNotification({
    required this.id,
    required this.groupId,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  /// 알림 식별자. **non-nullable.**
  final String id;

  /// 소속 그룹 id([Group.id]). **non-nullable** — 알림을 소속 그룹으로 귀속(프로토타입엔 없던 참조).
  final String groupId;

  /// 알림 유형. **non-nullable.**
  final GroupNotificationType type;

  /// 알림 제목. **non-nullable.**
  final String title;

  /// 알림 본문. **non-nullable.**
  final String message;

  /// 발생 시각. **non-nullable** — 프로토타입의 `when`(라벨)을 실제 타입으로 대체.
  final DateTime createdAt;

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  GroupNotification copyWith({
    String? id,
    String? groupId,
    GroupNotificationType? type,
    String? title,
    String? message,
    DateTime? createdAt,
  }) {
    return GroupNotification(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupNotification &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          groupId == other.groupId &&
          type == other.type &&
          title == other.title &&
          message == other.message &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(id, groupId, type, title, message, createdAt);

  @override
  String toString() =>
      'GroupNotification(id: $id, groupId: $groupId, type: $type, '
      'title: $title)';
}
