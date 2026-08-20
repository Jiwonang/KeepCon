/// KeepCon 공유 계약 — 초대 토큰 생성(SSOT).
///
/// 두 `ShareRepository` 구현이 각자 토큰을 만들면 엔트로피가 갈린다. 한 곳에서 만든다.
///
/// ## 왜 128비트인가 — 토큰이 조회 가능한 문서 id가 됐기 때문이다
/// 예전 토큰은 6자리 숫자(90만 가지)였고, 그때는 "링크를 아는 사람만 쓴다"는 전제였다.
/// 그런데 비멤버가 토큰으로 그룹을 찾으려면 `inviteTokens/{token}` 문서를 읽어야 하고,
/// 그 문서는 로그인한 누구나 **id로 조회**할 수 있다(목록 조회는 막혀 있다).
///
/// 즉 토큰 공간이 좁으면 `list`를 막아도 소용이 없다 — 100000..999999를 훑어 살아 있는
/// 모든 그룹의 id와 만료를 긁을 수 있고, 그다음 그 그룹들에 참여 요청을 쏟아부어 방장의
/// 승인 큐를 오염시킬 수 있다. 좁은 공간은 충돌도 문제다: 토큰이 겹치면 남의 그룹을
/// 가리키는 링크가 생기고, 재발급이 남의 조회 문서를 지운다.
///
/// 그래서 **추측·열거가 불가능한 크기**로 올린다. 128비트면 열거가 성립하지 않는다.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// 초대 토큰의 바이트 수(128비트).
const int inviteTokenBytes = 16;

/// 새 초대 토큰을 만든다 — URL·Firestore 문서 id로 안전한 22자 문자열.
///
/// `base64Url`은 `A–Z a–z 0–9 - _`만 쓰므로 경로 세그먼트로도, 문서 id로도 그대로
/// 쓸 수 있다(Firestore가 금지하는 `/`·`.`·`__`가 나오지 않는다). 패딩 `=`은 URL에서
/// 인코딩을 유발하므로 뗀다.
///
/// [random]은 테스트에서만 주입한다. 기본은 [Random.secure] — **일반 [Random]을 쓰면
/// 안 된다.** 시드가 예측 가능하면 토큰도 예측 가능해지고, 그 순간 위 열거 방어가
/// 통째로 무너진다.
String newInviteToken({Random? random}) {
  final Random rng = random ?? Random.secure();
  final Uint8List bytes = Uint8List(inviteTokenBytes);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return base64Url.encode(bytes).replaceAll('=', '');
}
