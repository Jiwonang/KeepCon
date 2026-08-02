/// auth 페이지 공용 — [AuthException] → 사용자용 한국어 메시지.
///
/// 페이지가 백엔드 예외가 아니라 계약 [AuthErrorCode]로 분기해 메시지를 정한다.
library;

import 'package:flutter/foundation.dart';

import '../../shared/repositories/auth_repository.dart';

/// [AuthException]의 [AuthErrorCode]를 사용자 표시용 한국어 문구로 변환한다.
String authErrorMessage(AuthException e) {
  // 디버깅을 위한 원본 에러 정보 콘솔 출력
  debugPrint('🔥 AuthException 발생 - Code: ${e.code}, Message: ${e.message}');

  switch (e.code) {
    case AuthErrorCode.emailInUse:
      return '이미 가입된 이메일이에요.';
    case AuthErrorCode.invalidCredential:
      return '이메일 또는 비밀번호가 올바르지 않아요.';
    case AuthErrorCode.weakPassword:
      return '비밀번호는 6자 이상이어야 해요.';
    case AuthErrorCode.invalidEmail:
      return '이메일 형식을 확인해 주세요.';
    case AuthErrorCode.unknown:
      return '문제가 발생했어요. 잠시 후 다시 시도해 주세요.';
  }
}
