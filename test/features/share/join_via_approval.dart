// 테스트 지원 — **승인제를 거쳐** 그룹 멤버가 되는 헬퍼.
//
// `joinGroup`이 사라지면서(v3.8) "다른 사람 그룹의 멤버가 된 상태"를 만드는 한 줄짜리
// 수단이 없어졌다. 그 자리를 이 헬퍼가 메운다 — 그리고 **실제 경로를 그대로 탄다**:
// 요청자가 `requestToJoin`, 방장이 `approveJoinRequest`.
//
// 옛 테스트들은 `repo.joinGroup('111111')`처럼 **존재하지 않는 토큰**으로 멤버가 됐다.
// in-memory 구현이 없는 토큰에 가짜 그룹을 만들어 주는 계약 위반 스텁을 갖고 있었기
// 때문이다(리뷰에서 두 번 지적된 자리). 그 스텁을 걷어내면서, 셋업도 실제 그룹과 실제
// 승인을 거치도록 바꾼다 — 셋업이 거짓이면 그 위에 쌓은 단언도 거짓이다.
library;

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';

/// 방장 계정 정보 — 승인하려면 방장으로 되돌아가야 한다.
class OwnerCredentials {
  /// 계정 정보를 만든다.
  const OwnerCredentials({required this.email, required this.password});

  /// 방장 이메일.
  final String email;

  /// 방장 비밀번호.
  final String password;
}

/// **현재 로그인한 사용자**를 [inviteToken] 그룹의 멤버로 만든다.
///
/// 흐름은 실제와 같다 — 지금 사용자가 요청하고, [owner]로 전환해 승인한 뒤, 다시 지금
/// 사용자로 돌아온다. 반환값은 승인 직후의 그룹이다.
///
/// 호출 전후로 로그인 사용자가 바뀌지 않는다(승인을 위해 잠시 전환할 뿐이다) — 그래서
/// 셋업 헬퍼로 안전하게 끼워 넣을 수 있다.
Future<Group> joinViaApproval(
  ShareRepository repo,
  InMemoryAuthRepository auth, {
  required String inviteToken,
  required OwnerCredentials owner,
  required String requesterEmail,
  required String requesterPassword,
}) async {
  final JoinRequest request = await repo.requestToJoin(inviteToken);
  try {
    // 승인은 방장만 할 수 있다.
    await auth.signIn(email: owner.email, password: owner.password);
    return await repo.approveJoinRequest(request.id);
  } finally {
    // 실패해도 요청자로 되돌린다 — 여기서 새는 세션은 뒤따르는 단언을 **방장 기준으로**
    // 조용히 평가시킨다(정원이 찬 그룹이면 `approveJoinRequest`가 던진다).
    await auth.signIn(email: requesterEmail, password: requesterPassword);
  }
}

/// [email]로 새 계정을 만들고 그 사용자로 로그인한 상태로 둔다(편의 래퍼).
Future<User> signUpAs(
  InMemoryAuthRepository auth, {
  required String email,
  required String displayName,
  String password = 'pw123456',
}) =>
    auth.signUp(email: email, password: password, displayName: displayName);

/// **남의 그룹에 멤버로 합류한 상태**를 만든다(승인제를 실제로 거친다).
///
/// 옛 테스트는 `repo.joinGroup('111111')` 한 줄로 이 상태를 만들었는데, 그 토큰에 해당하는
/// 그룹은 **존재하지 않았다** — in-memory 구현이 없는 토큰에 가짜 그룹을 만들어 주는 계약
/// 위반 스텁이 있었기 때문이다. `joinGroup`과 함께 그 스텁을 걷어내면서 셋업도 실제 그룹 +
/// 실제 승인을 거치도록 바꿨다. **셋업이 거짓이면 그 위에 쌓은 단언도 거짓이다.**
///
/// 방장 계정은 [name]에서 파생한다 — **이름이 다르면** 계정도 다르다. 한 테스트에서
/// **같은 이름으로** 두 번 부르면 여전히 `AuthException(emailInUse)`로 죽으므로, 그때는
/// 이름을 다르게 주거나 [joinViaApproval]을 직접 쓴다. 시드 그룹과 같은 이름(`'가족'`)을
/// 쓰면 이름이 같은 그룹이 둘이 되므로 단언은 id로 한다.
///
/// 호출 뒤 로그인 사용자는 **요청자(기본 사용자)** 로 돌아온다.
Future<Group> joinHostGroup(
  ShareRepository repo,
  InMemoryAuthRepository auth,
  String name, {
  String emoji = '🏠',
}) async {
  final String hostEmail = 'host-${name.hashCode.toUnsigned(32)}@keepcon.app';
  const String hostPassword = 'pw123456';

  // 방장 계정으로 그룹을 만든다. `createGroup`이 던져도 세션이 호스트로 남지 않게
  // 복귀를 finally 로 보장한다(형제 [joinViaApproval]과 같은 규약).
  await signUpAs(auth,
      email: hostEmail, displayName: '방장', password: hostPassword);
  final Group hosted;
  try {
    hosted = await repo.createGroup(name: name, emoji: emoji);
  } finally {
    await auth.signIn(
      email: InMemoryAuthRepository.defaultUser.email,
      password: InMemoryAuthRepository.defaultPassword,
    );
  }
  return joinViaApproval(
    repo,
    auth,
    inviteToken: hosted.inviteToken,
    owner: OwnerCredentials(email: hostEmail, password: hostPassword),
    requesterEmail: InMemoryAuthRepository.defaultUser.email,
    requesterPassword: InMemoryAuthRepository.defaultPassword,
  );
}
