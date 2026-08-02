/// KeepCon 공유 계약 — FirebaseAuthRepository (firebase_auth + firestore 구현체).
///
/// [AuthRepository] 계약을 Firebase Authentication(이메일/비밀번호)으로 구현하고,
/// 회원가입 시 사용자 프로필을 Cloud Firestore `users/{uid}`에 저장한다.
/// **인터페이스는 그대로**이므로, provider override만으로 in-memory ↔ Firebase가 교체된다.
///
/// 백엔드 예외([fb.FirebaseAuthException])는 도메인 [AuthException]으로 매핑해 던진다 —
/// 페이지가 firebase 타입에 의존하지 않게 한다(계약 규약).
///
/// ⚠️ 기본 실행 경로에서 인스턴스화하지 마라 — `Firebase.initializeApp()` 선행 필요.
/// 부트스트랩([firebase_bootstrap.dart]) 경유로만 활성화한다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import '../../../models/user.dart';
import '../../auth_repository.dart';

/// [AuthRepository]의 Firebase(Authentication + Firestore) 구현.
class FirebaseAuthRepository implements AuthRepository {
  /// [fb.FirebaseAuth]/[FirebaseFirestore]를 주입받는다(테스트에서 가짜/에뮬레이터 주입).
  /// 미지정 시 각 `.instance`를 사용한다.
  FirebaseAuthRepository({fb.FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _db;

  /// 사용자 프로필 컬렉션 이름(SSOT).
  static const String usersCollection = 'users';

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(usersCollection);

  @override
  User? get currentUser => _mapUser(_auth.currentUser);

  @override
  Stream<User?> watchCurrentUser() => _auth.userChanges().map(_mapUser);
  // ↑ authStateChanges()가 아니라 userChanges(): 로그인/로그아웃뿐 아니라
  //   updateDisplayName 등 프로필 갱신도 방출해야 계약(갱신된 사용자 방출)을 지킨다.

  @override
  Future<User> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final String normalized = email.trim();
    final fb.UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: normalized,
        password: password,
      );
    } on fb.FirebaseAuthException catch (e) {
      throw _mapException(e);
    }

    // 계정은 이미 생성·로그인된 상태. 이후 단계(displayName 갱신·프로필 저장)가
    // 실패하면 raw 예외가 페이지의 AuthException catch를 빠져나가므로, 도메인
    // 예외로 감싸 계약을 지킨다. (부분 가입 — 계정은 존재하고 로그인됨.)
    try {
      final fb.User raw = cred.user!;
      final String name = displayName.trim().isNotEmpty
          ? displayName.trim()
          : _localPart(normalized);

      // firebase 세션의 displayName을 갱신(authStateChanges 반영).
      await raw.updateDisplayName(name);

      final User user = User(
        id: raw.uid,
        email: raw.email ?? normalized,
        displayName: name,
      );

      // 프로필을 Firestore에 저장(계약: 회원가입 데이터 DB 저장).
      await _users.doc(raw.uid).set(<String, dynamic>{
        'email': user.email,
        'displayName': user.displayName,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw _mapException(e);
    } on Object catch (e) {
      // 프로필 저장 등 비-Auth 실패(Firestore 권한/네트워크). 계정은 생성됐으므로
      // 호출부가 재시도/프로필 보정할 수 있도록 도메인 예외로 통일한다.
      throw AuthException(AuthErrorCode.unknown, 'signUp post-step failed: $e');
    }
  }

  @override
  Future<User> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final fb.UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final User? user = _mapUser(cred.user);
      if (user == null) {
        throw const AuthException(
            AuthErrorCode.unknown, 'no user after signIn');
      }
      return user;
    } on fb.FirebaseAuthException catch (e) {
      throw _mapException(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      // 미가입 이메일은 조용히 성공 처리(계정 존재 노출 방지 계약).
      if (e.code == 'user-not-found') return;
      throw _mapException(e);
    }
  }

  @override
  Future<User> updateDisplayName({required String displayName}) async {
    final fb.User? raw = _auth.currentUser;
    if (raw == null) {
      throw const AuthException(AuthErrorCode.unknown, 'not signed in');
    }
    final String name = displayName.trim();
    if (name.isEmpty) {
      // 빈 문자열 금지 계약 — 호출부 검증을 뚫고 와도 여기서 차단한다.
      throw const AuthException(AuthErrorCode.unknown, 'empty displayName');
    }
    try {
      await raw.updateDisplayName(name);
      // 로컬 캐시를 갱신해 currentUser 동기 접근점에도 즉시 반영한다.
      await raw.reload();

      // 영속 프로필(users/{uid})에도 반영(계약: 프로필 저장 포함).
      await _users.doc(raw.uid).set(
        <String, dynamic>{'displayName': name},
        SetOptions(merge: true),
      );

      final User? updated = _mapUser(_auth.currentUser);
      if (updated == null) {
        throw const AuthException(
            AuthErrorCode.unknown, 'no user after update');
      }
      return updated;
    } on fb.FirebaseAuthException catch (e) {
      throw _mapException(e);
    } on AuthException {
      rethrow;
    } on Object catch (e) {
      // Firestore 프로필 반영 등 비-Auth 실패도 도메인 예외로 통일한다.
      throw AuthException(
          AuthErrorCode.unknown, 'updateDisplayName failed: $e');
    }
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    final fb.User? raw = _auth.currentUser;
    final String? email = raw?.email;
    if (raw == null || email == null) {
      throw const AuthException(AuthErrorCode.unknown, 'not signed in');
    }
    try {
      // 계약: 비밀번호 재확인. 불일치는 _mapException이 invalidCredential로
      // 매핑한다. 재인증으로 세션이 갱신되므로 firebase의 requires-recent-login
      // 거부도 함께 예방된다.
      await raw.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: password),
      );

      // 프로필 문서를 계정보다 먼저 삭제한다 — 계정 삭제 후에는 토큰이 무효라
      // firestore.rules(본인만 write)상 users/{uid}에 접근할 수 없다.
      await _users.doc(raw.uid).delete();

      // 계정 삭제. 완료 시 세션이 종료되고 userChanges()가 null을 방출한다.
      await raw.delete();
    } on fb.FirebaseAuthException catch (e) {
      throw _mapException(e);
    } on Object catch (e) {
      // Firestore 문서 삭제 등 비-Auth 실패도 도메인 예외로 통일한다.
      throw AuthException(AuthErrorCode.unknown, 'deleteAccount failed: $e');
    }
  }

  // --- 매핑 헬퍼 ---------------------------------------------------------

  /// [fb.FirebaseAuthException.code]를 도메인 [AuthException]으로 매핑한다.
  AuthException _mapException(fb.FirebaseAuthException e) {
    debugPrint('🔥 [Firebase 원본 에러 코드]: ${e.code}');
    debugPrint('🔥 [Firebase 원본 에러 메시지]: ${e.message}');

    switch (e.code) {
      case 'email-already-in-use':
        return AuthException(AuthErrorCode.emailInUse, e.message);
      case 'invalid-email':
        return AuthException(AuthErrorCode.invalidEmail, e.message);
      case 'weak-password':
        return AuthException(AuthErrorCode.weakPassword, e.message);
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return AuthException(AuthErrorCode.invalidCredential, e.message);
      default:
        return AuthException(AuthErrorCode.unknown, e.message);
    }
  }

  /// firebase_auth의 [fb.User]를 계약 [User]로 매핑한다.
  ///
  /// - 미로그인(null) → `null`.
  /// - [User.displayName]은 **빈 문자열 금지** 규칙: firebase displayName이 비면
  ///   이메일 로컬파트로, 그마저 없으면 uid 앞부분으로 채운다.
  /// - [User.email]은 non-nullable 계약이므로, firebase email이 없으면(익명 등)
  ///   '<uid>@keepcon.local' placeholder를 부여한다.
  User? _mapUser(fb.User? raw) {
    if (raw == null) return null;

    final String uid = raw.uid;
    final String email = (raw.email != null && raw.email!.isNotEmpty)
        ? raw.email!
        : '$uid@keepcon.local';

    final String displayName = _resolveDisplayName(
      rawDisplayName: raw.displayName,
      email: email,
      uid: uid,
    );

    return User(id: uid, email: email, displayName: displayName);
  }

  /// [User.displayName] 빈 문자열 금지 규칙을 적용해 표시 이름을 결정한다.
  ///
  /// 우선순위: firebase displayName → 이메일 로컬파트 → uid 앞 8자.
  String _resolveDisplayName({
    required String? rawDisplayName,
    required String email,
    required String uid,
  }) {
    if (rawDisplayName != null && rawDisplayName.trim().isNotEmpty) {
      return rawDisplayName.trim();
    }
    final String local = _localPart(email);
    if (local.isNotEmpty && local != email) {
      return local;
    }
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }

  /// 이메일 로컬파트('@' 앞부분). '@'가 없으면 원문을 반환한다.
  String _localPart(String email) {
    final int at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }
}
