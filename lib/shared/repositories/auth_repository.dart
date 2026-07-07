/// KeepCon 공유 계약 — AuthRepository 인터페이스.
///
/// 현재 로그인 사용자([User])를 앱 전체에 제공하는 단일 접근점.
/// auth 페이지가 구현/제공하며, scan(소유자 식별)이 소비한다.
/// 이번 검증 슬라이스에서는 [InMemoryAuthRepository] mock으로 대체한다.
library;

import '../models/user.dart';

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
}
