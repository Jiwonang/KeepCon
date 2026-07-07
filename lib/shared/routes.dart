/// KeepCon 공유 계약 — named route 상수.
///
/// 페이지 간 내비게이션에 쓰이는 route 이름을 이곳에서 단일 정의한다.
/// 매직 스트링 불일치(예: '/scan' vs 'scan')를 원천 차단하기 위해, 페이지는 반드시
/// 이 상수를 참조하고 문자열 리터럴을 직접 쓰지 않는다.
library;

/// 앱 named route 이름 모음.
///
/// 하단 탭 셸이 이 상수들로 탭을 배선한다. auth 라우트는 후속 확장에서 추가.
abstract final class AppRoutes {
  /// 메인 페이지(나의 기프티콘 목록) — 앱 진입 후 홈.
  static const String main = '/main';

  /// 스캔/추가 페이지(카메라·갤러리·수동 입력).
  static const String scan = '/scan';

  /// 공유 페이지(그룹 관리·멤버 초대·그룹 공유 기프티콘) — 하단 탭 셸의 공유 탭.
  static const String share = '/share';
}
