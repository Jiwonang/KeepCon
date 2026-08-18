/// KeepCon 공유 계약 — User 모델.
///
/// 앱 전체에서 "현재 로그인 사용자"를 식별하는 단일 진실 원천.
/// auth 페이지가 생산하고, scan(소유자 식별)과 main(소유자 필터)이 소비한다.
///
/// 이번 검증 슬라이스(scan→main)에서는 소유자 식별에 필요한 최소 필드만 확정한다.
/// 프로필/설정 관련 필드는 후속 계약 확장에서 추가한다.
library;

/// 구독 플랜.
///
/// 마이페이지(상태 확인·변경)가 생산·소비하고, 무료 제한(저장 개수·공유 가능 여부)은
/// 스캔/홈/공유 파트가 이후 소비한다. Firestore `users/{uid}.plan`에 [name]으로
/// 저장하며, **필드 부재 = [free]** 로 해석한다(기존 문서 마이그레이션 불필요).
///
/// ⚠️ 클라이언트는 이 값을 **읽기만** 한다 — `firestore.rules`가 `users/{uid}` 쓰기에서
/// `plan` 필드 변경을 차단한다(자가 프리미엄 승격 방지). 변경은 결제 검증이 붙기
/// 전까지 데모(in-memory) 경로에서만 실동작한다.
enum UserPlan {
  /// 무료 — 저장 10개 제한·공유 불가(제한 강제는 각 파트 소관).
  free,

  /// 프리미엄 — 무제한 저장·가족 공유·광고 제거.
  premium;

  /// 무료 플랜의 기프티콘 저장 개수 상한. 정책 값(SSOT)이다.
  ///
  /// ⚠️ 이 상수는 **값만 정의**할 뿐 강제하지 않는다 — 실제 저장 차단은 스캔(등록 경로),
  /// "N/상한개" 표시·업그레이드 유도는 홈이 이 값을 읽어 구현한다([free] 문서 참조).
  /// [premium]은 무제한이라 대응 상한이 없다.
  static const int freeGifticonLimit = 10;

  /// 저장 문자열([name])에서 파싱한다. 모르는 값·null은 [free]다.
  static UserPlan fromName(String? name) =>
      name == premium.name ? premium : free;
}

/// 앱 사용자.
///
/// 불변(immutable) 값 객체로 정의한다. 필드 변경은 [copyWith]로 새 인스턴스를
/// 만들어 처리한다.
class User {
  /// 사용자 고유 식별자. **non-nullable** — 소유자 식별의 기준 키이므로 항상 존재.
  ///
  /// [Gifticon.ownerId]가 이 값을 참조한다.
  final String id;

  /// 로그인 이메일. **non-nullable** — 인증 수단이자 표시 정보로 항상 존재한다고 본다.
  final String email;

  /// 화면 표시용 이름. **non-nullable** — 미설정 시 auth 레이어가 이메일 로컬파트 등으로
  /// 기본값을 채워 넣는 것을 계약으로 한다(빈 문자열 금지). 소비자는 항상 값이 있다고 가정 가능.
  final String displayName;

  /// User 인스턴스를 생성한다.
  const User({
    required this.id,
    required this.email,
    required this.displayName,
  });

  /// 일부 필드만 교체한 새 인스턴스를 반환한다.
  User copyWith({
    String? id,
    String? email,
    String? displayName,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          displayName == other.displayName;

  @override
  int get hashCode => Object.hash(id, email, displayName);

  @override
  String toString() =>
      'User(id: $id, email: $email, displayName: $displayName)';
}
