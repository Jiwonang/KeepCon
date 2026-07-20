/// KeepCon 공유 계약 — InMemoryAuthRepository (mock 구현).
///
/// 실제 백엔드 없이 회원가입·로그인 플로우를 시연/테스트할 수 있는 in-memory 구현체.
/// 이메일→계정(비밀번호·프로필) 맵을 들고 [signUp]/[signIn]/[signOut]/[sendPasswordReset]
/// 를 계약대로 구현한다. 기본적으로 데모 기본 사용자([defaultUser])로 로그인된 상태로
/// 시작하며(기존 데모/테스트 호환), 같은 계정으로 로그아웃 후 재로그인도 가능하다.
library;

import 'dart:async';

import '../../models/user.dart';
import '../auth_repository.dart';

/// [AuthRepository]의 in-memory mock 구현.
class InMemoryAuthRepository implements AuthRepository {
  /// 검증용 기본 사용자. scan/main이 동일 소유자를 공유하도록 고정 id를 쓴다.
  static const User defaultUser = User(
    id: 'user-1',
    email: 'khm78544@gmail.com',
    displayName: 'KeepCon Tester',
  );

  /// 데모 기본 계정의 비밀번호(in-memory 로그인 플로우 시연/테스트용).
  static const String defaultPassword = 'keepcon';

  /// Firebase 기본 정책과 맞춘 최소 비밀번호 길이.
  static const int minPasswordLength = 6;

  /// 이메일(소문자 정규화) → 계정. 등록된 사용자 저장소.
  final Map<String, _Account> _accounts = <String, _Account>{};

  /// 신규 가입 id 발급용 시퀀스(결정적 — 랜덤/시간 비의존).
  int _seq = 0;

  User? _currentUser;
  final StreamController<User?> _controller =
      StreamController<User?>.broadcast();

  /// 초기 사용자를 지정해 생성한다. 미지정 시 [defaultUser]로 로그인된 상태로 시작한다.
  ///
  /// 데모 기본 계정([defaultUser]/[defaultPassword])을 등록해 두어, 로그아웃 후에도
  /// 같은 계정으로 다시 로그인할 수 있다.
  InMemoryAuthRepository({User? initialUser = defaultUser}) {
    _accounts[_key(defaultUser.email)] =
        const _Account(password: defaultPassword, user: defaultUser);
    _currentUser = initialUser;
  }

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<User?> watchCurrentUser() async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  Future<User> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final String normalized = email.trim();
    if (!_isValidEmail(normalized)) {
      throw const AuthException(AuthErrorCode.invalidEmail);
    }
    if (password.length < minPasswordLength) {
      throw const AuthException(AuthErrorCode.weakPassword);
    }
    final String key = _key(normalized);
    if (_accounts.containsKey(key)) {
      throw const AuthException(AuthErrorCode.emailInUse);
    }

    final String name = displayName.trim().isNotEmpty
        ? displayName.trim()
        : _localPart(normalized);
    final User user =
        User(id: 'mem-${_seq++}', email: normalized, displayName: name);
    _accounts[key] = _Account(password: password, user: user);
    _setCurrent(user);
    return user;
  }

  @override
  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    final _Account? acc = _accounts[_key(email)];
    if (acc == null || acc.password != password) {
      // 계정 없음/비번 불일치를 구분하지 않는다(계정 존재 노출 방지).
      throw const AuthException(AuthErrorCode.invalidCredential);
    }
    _setCurrent(acc.user);
    return acc.user;
  }

  @override
  Future<void> signOut() async {
    _setCurrent(null);
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    final String normalized = email.trim();
    if (!_isValidEmail(normalized)) {
      throw const AuthException(AuthErrorCode.invalidEmail);
    }
    // in-memory: 실제 메일 시스템이 없으므로 성공 처리한다(미가입이어도 조용히 성공 —
    // 계정 존재 노출 방지 계약과 일치).
  }

  /// 리소스 정리. 앱 종료/테스트 teardown 시 호출.
  void dispose() {
    _controller.close();
  }

  // --- 내부 헬퍼 ---------------------------------------------------------

  void _setCurrent(User? user) {
    _currentUser = user;
    _controller.add(user);
  }

  String _key(String email) => email.trim().toLowerCase();

  String _localPart(String email) {
    final int at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// 최소한의 이메일 형식 검사(local@domain.tld). Firebase의 invalid-email과
  /// 대충 맞춰, mock이 '@'·'a@'·'@b' 같은 쓰레기를 통과시키지 않게 한다.
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _isValidEmail(String email) => _emailPattern.hasMatch(email);
}

/// 등록된 계정(비밀번호 + 프로필).
class _Account {
  const _Account({required this.password, required this.user});

  final String password;
  final User user;
}
