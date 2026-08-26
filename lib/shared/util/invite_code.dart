/// KeepCon 공유 계약 — 초대코드(6자리 OTP) 생성(SSOT).
///
/// 두 `ShareRepository` 구현이 각자 코드를 만들면 자릿수·분포가 갈린다. 한 곳에서 만든다
/// (`invite_token.dart`가 링크용 토큰에 대해 하는 일과 같은 역할).
///
/// ## 링크 토큰과 무엇이 다른가
/// 초대는 두 갈래이고, 둘은 **다른 위협 모델**을 갖는다.
///
/// | | 링크 토큰(`newInviteToken`) | 초대코드(여기) |
/// |---|---|---|
/// | 크기 | 128비트(22자) | 6자리 숫자(10^6) |
/// | 수명 | 24시간([Group.inviteValidity]) | 5분([Group.inviteCodeValidity]) |
/// | 전달 | 카카오톡 등으로 링크 공유 | 옆사람에게 **불러주기** |
/// | 조회 문서 | `inviteTokens/{token}` | `inviteCodes/{code}` |
///
/// 코드가 6자리인 것은 UX 요구다 — 128비트 문자열은 소리내어 읽을 수 없다. 그래서
/// **엔트로피 대신 수명으로 방어한다.**
///
/// ## 6자리가 안전한 이유는 "짧아서"가 아니라 "잠깐이라서"다
/// `inviteCodes/{code}`는 로그인한 누구나 **id로 조회**할 수 있다(목록은 막혀 있다).
/// 10^6은 병렬 조회로 훑을 수 있는 크기이므로, 공간만 놓고 보면 열거가 성립한다.
/// 방어는 다른 축에 있다:
///
/// - **상시 활성 코드가 없다.** 24시간 토큰은 모든 그룹이 항상 열려 있지만, 코드는
///   방장이 발급 버튼을 누른 뒤 5분뿐이다. 전수 조회의 수확은 "지금 막 초대를
///   기다리는 중인 소수 그룹"으로 줄어든다.
/// - **요청은 계정당 그룹당 하나다.** `joinRequests` 문서 id가 `{groupId}_{userId}`라
///   한 계정이 같은 그룹의 승인 큐를 도배할 수 없다.
/// - **만료를 규칙이 강제한다.** 참여 요청 생성 규칙이 *사용한 자격증명의* 만료를
///   본다(`canRequestJoin`). 이게 없으면 5분짜리 코드로 얻은 `groupId`가 그룹 토큰의
///   남은 24시간 동안 계속 먹혀서, "5분 만료"는 화면에만 있는 문구가 된다.
///
/// 세 축 중 하나라도 빠지면 6자리는 방어되지 않는다. 자릿수를 줄이거나 수명을 늘릴 때는
/// 이 표를 먼저 다시 계산할 것.
library;

import 'dart:math';

/// 초대코드 자릿수. **6자리 고정** — 옆사람에게 불러주는 것이 이 자격증명의 존재 이유다.
const int inviteCodeLength = 6;

/// 초대코드가 가질 수 있는 값의 수(10^[inviteCodeLength]).
const int inviteCodeSpace = 1000000;

/// 새 초대코드를 만든다 — `000000`~`999999`의 6자리 **문자열**.
///
/// ## 왜 `int`가 아니라 `String`인가
/// `012345`는 유효한 코드이고 `int`로 담으면 `12345`가 되어 **다른 코드가 된다**.
/// 앞자리 0을 잃으면 사용자가 화면에서 읽은 값과 저장된 값이 어긋나고, Firestore
/// 문서 id로 쓸 때도 조회가 빗나간다. 생성·저장·비교·표시 전 구간에서 문자열로 다룬다
/// (선행 0을 버리는 공간 축소는 10^6을 9·10^5로 만드는 조용한 엔트로피 손실이기도 하다).
///
/// [random]은 테스트에서만 주입한다. 기본은 [Random.secure] — **일반 [Random]을 쓰면
/// 안 된다.** 시드가 예측 가능하면 코드도 예측 가능해지고, 그러면 위 문서의 "열거에
/// 5분이 걸린다"는 전제가 통째로 무너진다(추측은 즉시다).
///
/// 분포: [Random.nextInt]는 `[0, max)` 균등이므로 [inviteCodeSpace]를 그대로 넘겨
/// 10^6 전체를 균등하게 쓴다(모듈로 바이어스 없음).
String newInviteCode({Random? random}) {
  final Random rng = random ?? Random.secure();
  return rng.nextInt(inviteCodeSpace).toString().padLeft(inviteCodeLength, '0');
}

/// [value]가 초대코드의 형태인지 — 정확히 [inviteCodeLength]자리이고 전부 숫자인지.
///
/// 자격증명 하나로 링크 토큰과 초대코드를 **함께 받는** 입력(참여 시트, `requestToJoin`)이
/// 어느 쪽을 조회할지 고르는 판정의 단일 진입점이다. 링크 토큰은 base64url 22자라
/// 이 검사를 통과할 수 없으므로 둘은 모양으로 구분된다.
///
/// 검사가 판정의 전부는 아니다 — 형태가 맞아도 존재하지 않거나 만료된 코드일 수 있고,
/// 그 판정은 조회 문서가 한다. 여기서는 **어느 컬렉션을 볼지**만 정한다.
bool isWellFormedInviteCode(String value) {
  if (value.length != inviteCodeLength) return false;
  for (int i = 0; i < value.length; i++) {
    final int c = value.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false; // '0'..'9'
  }
  return true;
}
