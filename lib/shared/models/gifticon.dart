/// KeepCon 공유 계약 — Gifticon 모델 + 관련 enum.
///
/// scan(생산자) → main(소비자) 축의 핵심 계약. scan이 [Gifticon]을 생성해
/// 저장하고, main이 정렬/필터로 소비한다.
///
/// 크로스페이지 계약 규칙(반드시 준수):
/// - scan이 반드시 채워야 하는 필수 필드: [id], [ownerId], [brand],
///   [productName], [expiryDate], [category], [status](=[GifticonStatus.available]),
///   [registeredAt].
/// - main의 정렬은 [expiryDate](만료임박순)·[registeredAt](최신 등록순)·[brand](브랜드명순)을,
///   필터는 [status](상태별)·[category](카테고리별)를 소비한다.
library;

/// 기프티콘의 사용/유효 상태.
///
/// main의 상태 필터([FilterOption.status])와 공유 페이지의 사용 동기화가 이 값을 공유한다.
///
/// ## 허용 상태 전이 (SSOT)
/// 아래 전이만 유효하다. 그 외 전이는 계약 위반이며 QA가 잡는다.
/// - [available] → [used]     : 사용자가 사용 완료 처리 (공유 사용 동기화 포함)
/// - [available] → [expired]  : 만료일 경과 시 시스템/조회 시점에 전이
///
/// 되돌리는 전이(used→available, expired→available 등)와 used↔expired는 **불허**.
/// 프로그램적 검증은 [GifticonStatusTransition.isAllowed]를 사용한다.
enum GifticonStatus {
  /// 사용 가능. scan이 신규 생성 시 채우는 기본 상태.
  available,

  /// 사용 완료.
  used,

  /// 만료됨(유효기간 경과).
  expired,
}

/// [GifticonStatus] 전이 규칙 헬퍼.
extension GifticonStatusTransition on GifticonStatus {
  /// 허용된 상태 전이 표(SSOT). 키에서 값 집합으로의 전이만 유효하다.
  static const Map<GifticonStatus, Set<GifticonStatus>> allowed = {
    GifticonStatus.available: {GifticonStatus.used, GifticonStatus.expired},
    GifticonStatus.used: <GifticonStatus>{},
    GifticonStatus.expired: <GifticonStatus>{},
  };

  /// `this` 상태에서 [next]로의 전이가 허용되는지 여부.
  ///
  /// 같은 상태로의 no-op 전이(`this == next`)는 허용으로 간주한다.
  bool canTransitionTo(GifticonStatus next) =>
      this == next || (allowed[this]?.contains(next) ?? false);

  /// 정적 형태의 전이 검사. Repository 구현/QA가 재사용한다.
  static bool isAllowed(GifticonStatus from, GifticonStatus to) =>
      from.canTransitionTo(to);
}

/// main 페이지 정렬 옵션.
///
/// 정렬 로직은 Repository/consumer 어느 쪽에서 수행하는가 → **소비자(main)가 수행**한다.
/// Repository는 정렬하지 않은 원천 스트림([GifticonRepository.watchGifticons])만 제공하며,
/// 정렬은 main의 상태 계층에서 이 enum에 따라 적용한다. (계약 매트릭스 참조)
enum SortOption {
  /// 만료임박순 — [Gifticon.expiryDate] 오름차순(가까운 만료가 먼저).
  expiryAsc,

  /// 최신 등록순 — [Gifticon.registeredAt] 내림차순(최근 등록이 먼저).
  registeredDesc,

  /// 브랜드명순 — [Gifticon.brand] 사전순 오름차순.
  brandAsc,
}

/// main 페이지 필터 종류.
///
/// 필터 로직도 정렬과 마찬가지로 **소비자(main)** 가 수행한다.
enum FilterOption {
  /// 상태별 필터 — [Gifticon.status]로 거른다.
  status,

  /// 카테고리별 필터 — [Gifticon.category]로 거른다.
  category,
}

/// 기프티콘.
///
/// 불변 값 객체. 상태/필드 변경은 [copyWith]로 새 인스턴스를 만든다.
class Gifticon {
  /// 고유 식별자. **non-nullable** — 저장 시 Repository가 발급하거나 scan이 생성.
  final String id;

  /// 소유자 [User.id]. **non-nullable** — scan은 현재 로그인 사용자 id로 채운다.
  /// main은 이 값으로 "나의 기프티콘"을 조회한다.
  final String ownerId;

  /// 브랜드명(예: "스타벅스"). **non-nullable** — 브랜드명순 정렬의 키이자 표시 핵심 정보.
  /// scan은 세 경로(카메라/갤러리/수동) 모두에서 반드시 채운다(미상 시 사용자 입력 강제).
  final String brand;

  /// 상품명(예: "아메리카노 T"). **non-nullable** — 목록 표시 핵심 정보.
  final String productName;

  /// 액면가/가격(원 단위 KRW). **non-nullable, required.**
  ///
  /// 용도: (1) 카드에 가격 표시(볼드, "원"), (2) 홈(main) 총금액 통계 합산.
  /// 원 단위 정수이므로 소수점 없음(예: 4500 = 4,500원). scan은 세 경로
  /// (카메라/갤러리/수동) 모두에서 반드시 채운다(미상 시 사용자 입력 강제).
  /// 정확한 금액을 모를 때도 0을 허용하되(무료/사은품), 빈 값/누락은 불허.
  final int price;

  /// 바코드 번호. **nullable** — 카메라/갤러리 인식 실패나 수동 입력 미기재 시 없을 수 있다.
  /// main 정렬/필터는 사용하지 않으므로 nullable 허용.
  final String? barcode;

  /// 카테고리(예: "카페", "편의점"). **non-nullable** — 카테고리 필터의 키.
  /// scan은 반드시 지정한다(미분류 시 "기타" 등 기본 카테고리를 부여하는 것을 계약으로 함).
  final String category;

  /// 유효기간(만료일). **non-nullable** — 만료임박순 정렬과 만료 상태 판정의 기준.
  /// scan은 반드시 채운다(인식 실패 시 사용자 입력 강제).
  final DateTime expiryDate;

  /// 등록(저장) 시각. **non-nullable** — 최신 등록순 정렬의 기준.
  /// Repository 저장 시점에 확정되며, scan은 생성 시 채우거나 Repository가 발급한다.
  final DateTime registeredAt;

  /// 사용/유효 상태. **non-nullable** — 상태 필터의 키. scan 생성 시 항상
  /// [GifticonStatus.available]로 시작한다.
  final GifticonStatus status;

  /// 기프티콘 이미지 경로(로컬 파일 경로 또는 URL). **nullable** — 수동 입력은
  /// 이미지 없이 등록 가능하므로 없을 수 있다.
  final String? imagePath;

  /// Gifticon 인스턴스를 생성한다.
  const Gifticon({
    required this.id,
    required this.ownerId,
    required this.brand,
    required this.productName,
    required this.price,
    this.barcode,
    required this.category,
    required this.expiryDate,
    required this.registeredAt,
    this.status = GifticonStatus.available,
    this.imagePath,
  });

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  ///
  /// nullable 필드([barcode], [imagePath])를 명시적으로 null로 지우는 것은 이 계약에서
  /// 지원하지 않는다(값 유지 또는 새 값 설정만). 필요 시 후속 계약에서 확장.
  Gifticon copyWith({
    String? id,
    String? ownerId,
    String? brand,
    String? productName,
    int? price,
    String? barcode,
    String? category,
    DateTime? expiryDate,
    DateTime? registeredAt,
    GifticonStatus? status,
    String? imagePath,
  }) {
    return Gifticon(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      brand: brand ?? this.brand,
      productName: productName ?? this.productName,
      price: price ?? this.price,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      expiryDate: expiryDate ?? this.expiryDate,
      registeredAt: registeredAt ?? this.registeredAt,
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Gifticon &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          ownerId == other.ownerId &&
          brand == other.brand &&
          productName == other.productName &&
          price == other.price &&
          barcode == other.barcode &&
          category == other.category &&
          expiryDate == other.expiryDate &&
          registeredAt == other.registeredAt &&
          status == other.status &&
          imagePath == other.imagePath;

  @override
  int get hashCode => Object.hash(
        id,
        ownerId,
        brand,
        productName,
        price,
        barcode,
        category,
        expiryDate,
        registeredAt,
        status,
        imagePath,
      );

  @override
  String toString() => 'Gifticon(id: $id, ownerId: $ownerId, brand: $brand, '
      'productName: $productName, price: $price, category: $category, '
      'expiryDate: $expiryDate, status: $status)';
}
