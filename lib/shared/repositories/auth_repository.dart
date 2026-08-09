/// KeepCon 공유 계약 — AuthRepository 인터페이스.
///
/// 현재 로그인 사용자([User])를 앱 전체에 제공하고, 이메일/비밀번호 기반의
/// 회원가입·로그인·로그아웃·비밀번호 재설정을 담당하는 단일 접근점.
/// auth 페이지(login/signup/reset)가 이 계약을 소비하고, scan(소유자 식별)·
/// main/share가 세션을 공유한다. 구현체(mock/Firebase)는 provider override로 교체된다.
///
/// **백엔드 예외 격리:** 실패는 백엔드(Firebase 등) 예외 타입이 아니라 도메인
/// [AuthException]으로 던진다 — 페이지가 구현체에 의존하지 않게 하기 위함(계약 규약).
library;

import '../models/user.dart';

/// 인증 실패 사유(도메인 코드).
///
/// 백엔드별 예외(예: `FirebaseAuthException.code`)를 이 코드로 매핑해, 페이지가
/// 백엔드 예외에 의존하지 않고 사용자 메시지를 결정하도록 한다.
enum AuthErrorCode {
  /// 이미 가입된 이메일(회원가입).
  emailInUse,

  /// 이메일/비밀번호 불일치 또는 존재하지 않는 계정(로그인).
  invalidCredential,

  /// 비밀번호가 정책(최소 길이 등)을 만족하지 못함.
  weakPassword,

  /// 이메일 형식 오류.
  invalidEmail,

  /// 위에 해당하지 않는 기타 실패(네트워크·내부 오류 등).
  unknown,
}

/// 인증 계약 예외.
///
/// [AuthRepository.signUp]/[AuthRepository.signIn]/[AuthRepository.sendPasswordReset]
/// 등이 실패하면 이 예외를 던진다. 페이지는 [code]로 분기해 사용자 메시지를 정한다.
class AuthException implements Exception {
  /// [code]와 선택적 원인 [message]로 예외를 만든다.
  const AuthException(this.code, [this.message]);

  /// 실패 사유(도메인 코드).
  final AuthErrorCode code;

  /// 디버깅용 원인 메시지(사용자 표시용 아님). 없을 수 있다.
  final String? message;

  @override
  String toString() =>
      'AuthException($code${message != null ? ': $message' : ''})';
}

/// 인증/세션 계약.
///
/// 페이지는 이 abstract 인터페이스에만 의존한다. 구현체(mock/실제 백엔드)는 교체 가능.
abstract class AuthRepository {
  /// 동기 접근점 — 지금 이 순간의 현재 사용자.
  ///
  /// 로그인되어 있으면 [User], 아니면 `null`. **nullable** — 미로그인 상태 표현.
  /// scan은 신규 기프티콘의 [Gifticon.ownerId]를 채우기 위해 이 값을 사용한다.
  User? get currentUser;

  /// 반응형 접근점 — 현재 사용자의 변화를 관찰한다.
  ///
  /// 로그인/로그아웃 시 새 값을 방출한다. 미로그인 상태는 `null`을 방출한다.
  /// Riverpod의 StreamProvider가 이 스트림을 구독한다.
  Stream<User?> watchCurrentUser();

  /// 이메일/비밀번호로 회원가입한다.
  ///
  /// 성공 시 **즉시 로그인 상태**가 되고([watchCurrentUser]가 새 사용자를 방출),
  /// 사용자 프로필([User])을 영속 저장소에 기록한다(계약: 프로필 저장 포함).
  /// [displayName]은 빈 문자열 금지 계약을 지킨다(호출부가 비우면 구현체가
  /// 이메일 로컬파트로 폴백).
  ///
  /// 실패 시 [AuthException]을 던진다:
  /// - 이미 가입된 이메일 → [AuthErrorCode.emailInUse]
  /// - 약한 비밀번호 → [AuthErrorCode.weakPassword]
  /// - 잘못된 이메일 형식 → [AuthErrorCode.invalidEmail]
  Future<User> signUp({
    required String email,
    required String password,
    required String displayName,
  });

  /// 이메일/비밀번호로 로그인한다.
  ///
  /// 성공 시 로그인 상태가 되고 [User]를 반환한다.
  /// 실패 시 [AuthException] — 이메일/비번 불일치·미가입은
  /// [AuthErrorCode.invalidCredential].
  Future<User> signIn({
    required String email,
    required String password,
  });

  /// 로그아웃한다. 미로그인 상태여도 안전하다(멱등).
  ///
  /// 완료 후 [watchCurrentUser]가 `null`을 방출한다.
  Future<void> signOut();

  /// 비밀번호 재설정 메일을 발송한다.
  ///
  /// 계정 존재 여부를 노출하지 않기 위해, 미가입 이메일이어도 예외 없이 성공
  /// 처리할 수 있다(구현체 재량). 형식 오류 등은 [AuthException]을 던진다.
  Future<void> sendPasswordReset({required String email});

  /// 현재 사용자의 표시 이름을 변경한다.
  ///
  /// 성공 시 갱신된 [User]를 반환하고, [watchCurrentUser]가 갱신된 사용자를
  /// 방출하며, 영속 프로필 저장소에도 반영한다(계약: 프로필 저장 포함).
  ///
  /// [User.displayName] **빈 문자열 금지** 계약: 구현체는 트림 후 비면
  /// [AuthException]([AuthErrorCode.unknown])을 던진다 — 호출부(페이지)가
  /// 입력 검증으로 미리 막는 것을 권장한다.
  /// 미로그인 상태 호출도 [AuthException]([AuthErrorCode.unknown])이다.
  Future<User> updateDisplayName({required String displayName});

  /// 현재 계정을 삭제한다 — **비밀번호 재확인 필수**.
  ///
  /// 보안 민감 작업이므로 [password] 재확인을 계약으로 강제한다:
  /// - 비밀번호 불일치 → [AuthException]([AuthErrorCode.invalidCredential])
  /// - 미로그인 상태 호출 → [AuthException]([AuthErrorCode.unknown])
  ///
  /// (Firebase 등 실제 백엔드의 "오래된 세션은 민감 작업 거부"(recent-login 요구)
  /// 정책도 이 재인증 단계로 함께 충족된다.)
  ///
  /// 성공 시 계정과 영속 프로필이 삭제되고 로그아웃 상태가 되며,
  /// [watchCurrentUser]가 `null`을 방출한다.
  Future<void> deleteAccount({required String password});

  /// 현재 사용자의 구독 플랜을 관찰한다.
  ///
  /// 구독 시점의 현재 사용자를 기준으로 하며, 미로그인 상태에서는
  /// [UserPlan.free]를 방출한다. 세션이 바뀌면 소비자(provider)가 재구독하는
  /// 것을 계약으로 한다 — 구현체는 세션 전환을 스스로 추적하지 않는다.
  ///
  /// 저장 위치는 `users/{uid}.plan`(필드 부재 = free). [UserPlan] 문서 참조.
  Stream<UserPlan> watchPlan();

  /// 현재 사용자의 구독 플랜을 변경한다.
  ///
  /// - 미로그인 상태 호출 → [AuthException]([AuthErrorCode.unknown])
  /// - **실백엔드에서는 보안 규칙이 `plan` 필드 쓰기를 차단**하므로(자가 승격 방지,
  ///   `firestore.rules` 참조) [AuthException]으로 실패한다. 결제 검증(서버/스토어
  ///   영수증)이 붙으면 그 경로가 이 값을 쓴다. 데모(in-memory)에서는 실동작한다.
  Future<void> updatePlan({required UserPlan plan});
}
