/// KeepCon 공유 계약 — InMemoryAuthRepository (mock 구현).
///
/// 실제 백엔드 없이 페이지 개발자가 즉시 병렬 개발할 수 있도록 제공하는 in-memory 구현체.
/// 검증 슬라이스에서 scan의 소유자 식별을 위한 고정 사용자를 제공한다.
library;

import 'dart:async';

import '../../models/user.dart';
import '../auth_repository.dart';

/// [AuthRepository]의 in-memory mock 구현.
///
/// 기본적으로 검증용 고정 사용자([defaultUser])로 로그인된 상태를 제공한다.
/// [signIn]/[signOut]으로 세션을 바꿀 수 있으며, [watchCurrentUser]가 변화를 방출한다.
class InMemoryAuthRepository implements AuthRepository {
  /// 검증용 기본 사용자. scan/main이 동일 소유자를 공유하도록 고정 id를 쓴다.
  static const User defaultUser = User(
    id: 'user-1',
    email: 'khm78544@gmail.com',
    displayName: 'KeepCon Tester',
  );

  User? _currentUser;
  final StreamController<User?> _controller =
      StreamController<User?>.broadcast();

  /// 초기 사용자를 지정해 생성한다. 미지정 시 [defaultUser]로 로그인된 상태로 시작한다.
  InMemoryAuthRepository({User? initialUser = defaultUser})
      : _currentUser = initialUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<User?> watchCurrentUser() async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  /// mock 로그인 — 현재 사용자를 [user]로 바꾸고 스트림에 방출한다.
  void signIn(User user) {
    _currentUser = user;
    _controller.add(user);
  }

  /// mock 로그아웃 — 현재 사용자를 비우고 `null`을 방출한다.
  void signOut() {
    _currentUser = null;
    _controller.add(null);
  }

  /// 리소스 정리. 앱 종료/테스트 teardown 시 호출.
  void dispose() {
    _controller.close();
  }
}
