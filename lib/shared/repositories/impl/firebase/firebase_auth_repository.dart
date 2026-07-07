/// KeepCon 공유 계약 — FirebaseAuthRepository (firebase_auth 구현체).
///
/// [AuthRepository] 계약을 Firebase Authentication으로 구현한다.
/// **인터페이스는 그대로**이므로, provider override만으로 in-memory ↔ Firebase가 교체된다.
/// (계약의 가치: 페이지는 [AuthRepository]에만 의존하므로 이 구현체의 존재를 몰라도 된다.)
///
/// ⚠️ 기본 실행 경로에서 인스턴스화하지 마라 — 이 구현체는 `Firebase.initializeApp()`가
/// 선행되어야 동작한다. 부트스트랩([firebase_bootstrap.dart]) 경유로만 활성화한다.
library;

import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../../models/user.dart';
import '../../auth_repository.dart';

/// [AuthRepository]의 Firebase Authentication 구현.
///
/// [fb.FirebaseAuth]의 현재 사용자/인증 상태 변화를 계약 [User]로 매핑한다.
class FirebaseAuthRepository implements AuthRepository {
  /// 주입받는 [fb.FirebaseAuth] 인스턴스. 미지정 시 [fb.FirebaseAuth.instance] 사용.
  ///
  /// 테스트에서 가짜 인스턴스를 주입할 수 있도록 생성자 파라미터로 노출한다.
  FirebaseAuthRepository({fb.FirebaseAuth? auth})
      : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  @override
  User? get currentUser => _mapUser(_auth.currentUser);

  @override
  Stream<User?> watchCurrentUser() =>
      _auth.authStateChanges().map(_mapUser);

  /// firebase_auth의 [fb.User]를 계약 [User]로 매핑한다.
  ///
  /// - 미로그인(null) → `null` (계약: [AuthRepository.currentUser] nullable).
  /// - [User.displayName]은 **빈 문자열 금지** 규칙을 지킨다: firebase의 displayName이
  ///   비어 있으면 이메일 로컬파트로, 그마저 없으면 uid 앞부분으로 채운다.
  /// - [User.email]은 non-nullable 계약이므로, firebase email이 null이면 빈 문자열 대신
  ///   uid 기반 placeholder를 넣지 않고 uid를 이메일 자리로 쓰지 않는다 — 대신 익명 로그인 등
  ///   email이 없는 경우를 대비해 '<uid>@keepcon.local' 형태의 안정적 placeholder를 부여한다.
  User? _mapUser(fb.User? raw) {
    if (raw == null) return null;

    final String uid = raw.uid;
    final String email =
        (raw.email != null && raw.email!.isNotEmpty)
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
    final int at = email.indexOf('@');
    if (at > 0) {
      return email.substring(0, at);
    }
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }
}
