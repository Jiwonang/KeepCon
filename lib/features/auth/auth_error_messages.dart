/// KeepCon auth 페이지 공용 — AuthErrorCode → 한국어 사용자 메시지 매핑.
///
/// [AuthException.message]는 계약 문서상 "디버깅용 원인 메시지(사용자 표시용 아님)"이므로,
/// 화면에 보여줄 문구는 [AuthErrorCode]로 분기해 이 헬퍼가 결정한다.
/// login/signup/reset 페이지가 공용으로 소비(중복 제거). 공유 계약 타입 재정의가 아니라
/// 페이지 로컬 프레젠테이션 헬퍼라 lib/features/auth/에 둔다.
library;

import '../../shared/repositories/auth_repository.dart';

/// [code]에 대응하는 사용자 표시용 한국어 메시지.
String authErrorMessage(AuthErrorCode code) {
  switch (code) {
    case AuthErrorCode.emailInUse:
      return '이미 가입된 이메일입니다.';
    case AuthErrorCode.invalidCredential:
      return '이메일 또는 비밀번호가 올바르지 않습니다.';
    case AuthErrorCode.weakPassword:
      return '비밀번호는 6자 이상이어야 합니다.';
    case AuthErrorCode.invalidEmail:
      return '이메일 형식이 올바르지 않습니다.';
    case AuthErrorCode.unknown:
      return '알 수 없는 오류가 발생했습니다.';
  }
}
