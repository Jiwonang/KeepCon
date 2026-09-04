/// KeepCon 공유 계약 — ShareRepository 인터페이스.
///
/// share 페이지의 그룹/공유 도메인 데이터 계층 계약. 프로토타입의 `ShareStore`
/// (`lib/features/share/data/share_store.dart`) 동작을 정본 인터페이스로 승격한 것이다.
///
/// ## 설계 규약 (GifticonRepository 스타일 준수)
/// - **행위자(actor) = 현재 로그인 사용자.** 변경 메서드(create/leave/delete/share/markUsed 등)는
///   `AuthRepository.currentUser`가 행위자다. 구현체가 세션에서 행위자를 해석한다
///   (이 인터페이스는 행위자 id를 파라미터로 받지 않는다 — 조회 메서드만 [userId]를 받는다).
/// - **가드 위반은 [StateError].** 권한/상태/전이 위반은 [StateError]를 던진다
///   (GifticonRepository.updateStatus가 불허 전이에 [StateError]를 던지는 것과 동일 규약).
///   프로토타입 `ShareStore`는 `bool`을 반환했지만, 데이터 계약에서는 예외로 통일한다.
/// - **UI 게이팅은 모델 predicate로.** 버튼 노출 여부는 예외 try/catch가 아니라
///   [Group.isOwnedBy]/[Group.canInvite]/[SharedGifticon.isLockedFor] 등 순수 predicate로
///   판정한다(구현의 [StateError]는 방어선(defense-in-depth)이다).
/// - **정렬/필터 없음.** Repository는 소유자/그룹별 원천 목록/스트림만 제공한다
///   (정렬/필터/포맷은 소비자 책임 — GifticonRepository와 동일).
///
/// ## 경계면(다른 페이지와의 연결)
/// - **share ↔ auth:** 행위자와 멤버 식별은 [User.id] 기반. 구현체는 `AuthRepository`를 주입받는다.
/// - **share ↔ main:** [markUsed] 시 원본 [Gifticon]을 `GifticonStatus.used`로 동기화한다.
///   구현체는 기존 `GifticonRepository.updateStatus`를 **소비**한다(계약 무변경).
library;

import '../models/gifticon.dart';
import '../models/group.dart';
import '../models/join_request.dart';
import '../models/share.dart';

/// 초대 자격증명이 **만료되어** 거부됐음을 알리는 예외.
///
/// ## 왜 [StateError]를 상속하는가
/// 계약의 가드 위반은 전부 [StateError]다(맨 위 설계 규약). 그 규약을 깨지 않으면서
/// 화면이 만료만 **구별**할 수 있어야 해서 하위 타입으로 좁혔다. 기존 호출부의
/// `on StateError`와 `catch (e)`는 그대로 이 예외를 잡는다 — non-breaking이다.
///
/// ## 왜 구별해야 하는가
/// 초대코드는 5분([Group.inviteCodeValidity])이라 **만료가 정상 경로**다. 옆사람에게
/// 불러주는 동안 창이 닫히는 일이 흔하고, 그때 잘못됐거나 만료됐을 수 있다는 식의
/// 뭉뚱그린 안내를 받으면 사용자는 코드를 잘못 들었는지 시간이 지난 것인지 알 수
/// 없어 **같은 코드를 계속 다시 입력한다.** 만료라고 말해 주면 다음 행동이 하나로
/// 정해진다 — 방장에게 재발급을 요청한다.
///
/// ## 왜 [isCode]를 함께 싣는가 — 모양으로 추측하지 말 것
/// 만료 안내는 **링크와 코드가 서로 다른 다음 행동**을 가리킨다. 코드는 5분이라
/// "새 코드를 요청"이고, 링크는 24시간([Group.inviteValidity])이라 "링크 재발급을 요청"이다.
/// 그래서 화면은 둘을 갈라야 하는데, 그 판정을 `isWellFormedInviteCode(credential)`
/// 같은 **모양 검사로 다시 하면 틀린다** — v3.0(128비트) 이전의 링크 토큰은 6자리
/// 숫자였고 그 값들이 아직 살아 있다(팀 공용 시드 `482913`, 데모 시드, 레거시 Firestore
/// 문서). 그 링크가 만료되면 화면은 "새 **코드**를 요청하세요"라고 말하고, 사용자가
/// 코드를 받아 와도 만료된 링크는 그대로다 — 안내가 다음 행동을 틀리게 만든다.
///
/// 판정의 정본은 이미 저장소에 있다. `requestToJoin`은 코드 조회 문서를 먼저 보고
/// 없으면 링크 토큰으로 **폴백**하므로, **어느 쪽에서 그룹을 찾았는지**가 곧 [isCode]다.
/// 그 확정된 사실을 예외에 실어 화면이 같은 판정을 더 나쁜 근거로 되풀이하지 않게 한다
/// (같은 입력에 대해 저장소는 '링크', 화면은 '코드'라고 답하던 어긋남을 없애는 것이다).
///
/// ## 문자열로 구별하지 않는 이유
/// 예외 메시지를 `contains('expired')`로 검사하면 메시지를 다듬는 순간 UI가 조용히
/// 깨진다(테스트도 함께 통과한 채로). 타입은 컴파일러가 지켜 준다.
///
/// 만료가 아닌 실패(없는 코드·이미 멤버·세션 없음)는 평범한 [StateError]로 남긴다 —
/// "없는 코드"를 "만료"라고 말하면 존재하지 않는 그룹을 기다리게 만든다.
class InviteExpiredException extends StateError {
  /// 만료된 자격증명에 대한 예외를 만든다.
  ///
  /// [credential]은 만료된 링크 토큰 또는 초대코드다. 진단에 필요해 [message]에 담지만,
  /// 사용자에게 그대로 보여주지는 않는다(화면은 이 **타입**을 보고 문구를 고른다).
  ///
  /// [isCode]는 필수다 — 기본값을 두면 판정을 아는 구현체가 그것을 싣지 않고 넘어가는
  /// 길이 열리고, 그 침묵이 화면에서는 "링크"라는 단정으로 나타난다.
  InviteExpiredException(this.credential, {required this.isCode})
      : super('Invite credential expired: $credential');

  /// 만료 판정을 받은 자격증명(링크 토큰 또는 6자리 초대코드).
  final String credential;

  /// 이 자격증명이 **6자리 초대코드**였으면 `true`, **링크 토큰**이었으면 `false`.
  ///
  /// 화면은 이 값으로 만료 안내를 가른다 — 코드는 "새 코드를 요청"(5분), 링크는
  /// "링크 재발급을 요청"(24시간)으로 다음 행동이 다르다.
  ///
  /// **이 값의 정본은 저장소가 실제로 어느 조회 문서에서 그룹을 찾았는지다** —
  /// `isWellFormedInviteCode([credential])`의 결과가 아니다. 그 함수는 6자리 링크
  /// 토큰(v3.0 이전 발급분, 아직 살아 있다)에서 `true`를 내지만 저장소는 그것을 링크로
  /// 해석하므로, 같은 입력에서 두 값이 갈린다. 모양은 첫 조회 대상을 고르는 힌트일 뿐
  /// 최종 판정이 아니다.
  final bool isCode;
}

/// 참여 요청 문서를 **읽지 못해** "없음"으로 접었을 때의 [StateError].
///
/// 계약상으로는 평범한 "요청 없음"이라 호출부는 [StateError]로 잡으면 된다. 따로
/// 두는 이유는 **진단**이다 — Firebase 구현은 보안 규칙의 `permission-denied`를
/// "없음"으로 흡수하는데(없는 문서의 읽기 = 403, 존재 오라클 방지 규약), 그 원인이
/// 경합(정상)일 수도 규칙 회귀·배포 스큐(장애)일 수도 있다. 흡수하고 나면
/// `DebugPrintErrorReporter._kindOf`가 그 둘을 구별할 근거를 잃으므로, 접었다는
/// 사실만 타입으로 남긴다. ([InviteExpiredException]과 같은 규약 — `on StateError`·
/// `catch (e)`가 그대로 잡으므로 non-breaking이고, in-memory 구현은 규칙이 없어
/// 이 타입을 던질 일이 없다.)
class JoinRequestUnreadableException extends StateError {
  /// 읽기 거부를 "없음"으로 접은 요청 [joinRequestId]에 대한 예외를 만든다.
  ///
  /// 메시지는 평범한 "요청 없음"과 동일하게 유지한다 — 구별은 문자열이 아니라
  /// 타입으로 한다([InviteExpiredException]의 "문자열로 구별하지 않는 이유" 참조).
  JoinRequestUnreadableException(String joinRequestId)
      : super('Join request not found: $joinRequestId');
}

/// 그룹/공유 데이터 계약.
///
/// 페이지는 이 abstract 인터페이스에만 의존한다. 구현체(mock/실제 백엔드)는 교체 가능.
abstract class ShareRepository {
  // ── 그룹 조회 ───────────────────────────────────────────────────────
  /// [userId]가 멤버로 속한 그룹 목록을 반응형으로 관찰한다.
  ///
  /// 멤버십이 사라지면(나가기/소유권 이전) 해당 그룹은 이 스트림에서 빠진다.
  Stream<List<Group>> watchGroups(String userId);

  /// [userId]가 멤버로 속한 그룹 목록을 1회성으로 조회한다.
  Future<List<Group>> getGroups(String userId);

  /// id로 그룹 단건 조회. 없으면 `null`.
  Future<Group?> getGroupById(String groupId);

  // ── 그룹 관리 (행위자 = currentUser) ─────────────────────────────────
  /// 새 그룹을 생성한다. 행위자가 방장([MemberRole.owner])이 된다.
  ///
  /// [maxMembers]는 그룹 인원 상한(방장 포함, 기본 [Group.defaultMaxMembers], 최소 1).
  /// 함께 발급되는 초대 토큰은 생성 시점부터 [Group.inviteValidity](24시간) 동안만 유효하다
  /// ([Group.inviteExpiresAt]).
  /// 세션에 현재 사용자가 없으면 [StateError].
  Future<Group> createGroup({
    required String name,
    required String emoji,
    int maxMembers,
  });

  // `joinGroup`은 v3.8에서 **삭제됐다.**
  //
  // 링크(토큰) 소지만으로 즉시 멤버가 되던 경로다. 링크는 유출되면 그대로 참여
  // 경로가 되므로, 소지의 의미를 '참여 자격'에서 '**요청** 자격'으로 낮췄다 —
  // [requestToJoin] → [approveJoinRequest]. 옛 메서드를 남겨 두면 같은 토큰으로
  // 승인을 건너뛰는 우회로가 되므로 **삭제가 유일한 게이트**다
  // (`@Deprecated`도 문서도 호출을 막지 못한다).
  //
  // 옛 가드들이 간 자리:
  // - 없는 토큰·만료·중복 요청 → [requestToJoin]
  // - 정원 → [approveJoinRequest] (대기자가 자리를 선점하지 못하게 승인 시점으로 옮겼다)
  // - **이미 멤버 → [requestToJoin]인데 의미가 바뀌었다.** 옛 `joinGroup`은 no-op으로
  //   현재 그룹을 반환했고 그 판정이 만료·정원보다 **우선**이었다. 지금은 [StateError]로
  //   거부하고 **만료 검사가 먼저** 온다 — 이미 멤버라도 링크가 24시간을 넘겼으면
  //   '만료'로 거부된다(멤버가 단톡방에 남은 자기 링크를 누르는 흔한 경로다).
  //   이 동작 변경은 v2.9에서 들어왔고, 여기서는 대응 관계만 기록한다.

  /// 그룹에서 나간다.
  ///
  /// 가드: 행위자가 멤버여야 한다. 방장이면서 다른 멤버가 남아 있으면
  /// [transferOwnershipAndLeave]가 선행되어야 하므로 나갈 수 없다([StateError]).
  /// 단독 멤버(방장 포함)일 때 나가면 그룹이 정리된다.
  Future<void> leaveGroup(String groupId);

  /// 그룹을 삭제한다.
  ///
  /// 가드: 방장 본인만 삭제할 수 있다. 위반 시 [StateError].
  Future<void> deleteGroup(String groupId);

  /// 소유권을 [newOwnerUserId]에게 넘기고 행위자는 그룹에서 빠진다.
  ///
  /// 가드: 행위자가 방장이어야 하고, [newOwnerUserId]는 행위자를 제외한 기존 멤버여야 한다.
  /// 위반 시 [StateError]. 성공 시 갱신된(새 방장 반영·행위자 제거) 그룹을 반환한다.
  Future<Group> transferOwnershipAndLeave({
    required String groupId,
    required String newOwnerUserId,
  });

  /// 방장이 멤버를 그룹에서 내보낸다(강퇴).
  ///
  /// 가드: 행위자가 방장이어야 하고, [userId]는 방장 본인이 아닌 기존 멤버여야 한다
  /// (방장 자신은 강퇴 대상이 아니다 — [leaveGroup]/[transferOwnershipAndLeave]를 쓴다).
  /// 위반/그룹 없음이면 [StateError]. 성공 시 갱신된(해당 멤버 제거) 그룹을 반환한다.
  ///
  /// 내보낸 멤버가 그룹에 공유했던 항목은 [leaveGroup]과 동일하게 그대로 남는다
  /// (멤버 이탈 시 공유 항목을 정리하지 않는 현행 규약과 일치).
  Future<Group> removeMember({
    required String groupId,
    required String userId,
  });

  /// 초대 권한 정책(방장 한정 여부)을 설정한다.
  ///
  /// 가드: 방장 본인만 정책을 바꿀 수 있다. 위반 시 [StateError].
  /// 성공 시 갱신된 그룹을 반환한다.
  Future<Group> setInviteOwnerOnly({
    required String groupId,
    required bool ownerOnly,
  });

  /// 초대 토큰을 재발급한다 — 새 토큰을 발급해 **기존 링크를 무효화**한다.
  ///
  /// 만료([Group.inviteExpiresAt])는 재발급 시점 + [Group.inviteValidity](24시간)로 다시
  /// 계산된다. 만료된 초대를 되살리는 유일한 경로이며, 만료 기간 자체는 고를 수 없다.
  ///
  /// 가드: 방장 본인만 재발급할 수 있다. 위반/그룹 없음이면 [StateError].
  /// 성공 시 갱신된(새 코드·만료 갱신) 그룹을 반환한다.
  Future<Group> regenerateInviteToken({required String groupId});

  /// 6자리 초대**코드**를 발급한다 — 옆사람에게 **불러주기** 위한 두 번째 자격증명.
  ///
  /// 링크 토큰([regenerateInviteToken])과 **독립적으로** 동작한다. 코드를 발급해도 링크는
  /// 그대로 살아 있고, 링크를 재발급해도 활성 코드는 죽지 않는다. 두 갈래는 전달 수단이
  /// 다를 뿐 같은 그룹으로 가는 별개의 문이며, 하나를 닫는 것이 다른 하나를 닫아야 할
  /// 이유는 없다(초대 전체를 닫고 싶으면 둘 다 재발급한다).
  ///
  /// 발급 시점부터 [Group.inviteCodeValidity](**5분**) 동안만 유효하다. 링크의 24시간과
  /// 다른 이유는 6자리가 열거 가능한 공간이기 때문이다 — 좁은 공간을 수명으로 막는
  /// 설계다(`lib/shared/util/invite_code.dart`의 위협 모델 표 참조).
  ///
  /// 이미 활성 코드가 있어도 **새 코드로 교체한다**(no-op이 아니다). 옛 코드는 그 즉시
  /// 무효가 된다 — 한 그룹이 동시에 여러 코드를 갖지 않는다. 이 불변식이 필요한 이유는
  /// 두 가지다: 살아 있는 코드가 그룹당 하나여야 열거의 수확이 최소가 되고, 6자리 공간의
  /// 점유가 '그룹 수'로 묶여야 충돌이 무시할 수준으로 남는다.
  ///
  /// 가드: **방장 본인만** 발급할 수 있다([regenerateInviteToken]과 같은 권한).
  /// 위반/그룹 없음/세션 없음이면 [StateError].
  ///
  /// 일반 멤버에게 열지 않는 이유는 정책이 아니라 **정리 권한** 때문이다. 교체할 때
  /// 옛 코드의 조회 문서를 지워야 하는데 그 삭제 권한이 방장에게만 있어서(보안 규칙),
  /// 멤버에게 발급을 열면 옛 코드가 살아남아 "그룹당 활성 코드 하나" 불변식이 깨진다.
  ///
  /// [Group.inviteOwnerOnly]가 꺼져 있어도(기본값) 멤버가 초대할 길은 그대로 있다 —
  /// **링크**는 이미 발급돼 있고 누구나 공유할 수 있다. 코드만 방장 몫인 것은
  /// [regenerateInviteToken]이 방장 전용인 것과 같은 모양이다(새 자격증명을 찍어내는
  /// 행위 vs 이미 있는 것을 전달하는 행위).
  ///
  /// 성공 시 갱신된(새 코드·만료 반영) 그룹을 반환한다 — 호출부는 반환값의
  /// [Group.inviteCode]와 [Group.inviteCodeRemaining]으로 화면을 그린다.
  Future<Group> issueInviteCode({required String groupId});

  // ── 참여 요청(초대 링크·코드 → 방장 승인) ───────────────────────────
  /// 초대 자격증명으로 그룹 참여를 **요청**한다(아직 멤버가 되지 않는다).
  ///
  /// [credential]은 두 가지 중 하나다 — 링크에 실린 **토큰**(base64url 22자)이거나
  /// [issueInviteCode]가 발급한 **6자리 초대코드**. 구현체가 해당하는 조회 문서를 찾아
  /// 그룹으로 해석한다. 화면 입력란이 하나이므로 계약도 하나로 받는다 — 사용자에게
  /// "지금 넣는 것이 링크인지 코드인지" 고르게 하는 것은 전달 수단의 차이를 사용자
  /// 몫으로 떠넘기는 것이다.
  ///
  /// **모양(`isWellFormedInviteCode`)은 첫 조회 대상의 선택일 뿐 최종 판정이 아니다.**
  /// 6자리면 코드 조회 문서를 **먼저** 보지만, 거기 없으면 링크 토큰으로 **폴백**한다 —
  /// v3.0(128비트) 이전의 링크 토큰이 6자리 숫자였고 그 값들이 아직 살아 있어서(팀 공용
  /// 시드 `482913`, 데모 시드, 레거시 Firestore 문서), 모양만 보고 배타적으로 고르면 그
  /// 링크들이 통째로 '없는 코드'가 된다. 그래서 "이것이 코드였는가"의 정본은 모양이
  /// 아니라 **어느 조회 문서에서 그룹을 찾았는지**다.
  ///
  /// 자격증명은 유출되면 그대로 참여 경로가 되므로, 소지자는 참여가 아니라 **요청**만
  /// 할 수 있고 [approveJoinRequest]로 방장이 최종 결정한다.
  ///
  /// 가드: 해당하는 그룹이 없으면 [StateError]. **만료됐으면
  /// [InviteExpiredException]** — 화면이 "만료된 초대코드"라고 구별해 안내해야 하므로
  /// 이 실패만 하위 타입으로 좁혀 둔다(만료는 5분짜리 코드에서 정상 경로다).
  /// 행위자가 이미 멤버면 [StateError](요청할 이유가 없다).
  /// 세션에 현재 사용자가 없으면 [StateError].
  ///
  /// **구현체는 [InviteExpiredException.isCode]에 자기 폴백 판정을 그대로 실어야 한다**
  /// — 코드 조회 문서에서 찾았으면 `true`, 링크 토큰으로 폴백해 찾았으면 `false`다.
  /// 추측하지 말 것: 모양으로 다시 매기면 6자리 링크 토큰에서 저장소와 화면의 답이
  /// 갈린다(바로 위 폴백 문단). 만료 판정에 쓴 것과 **같은** 값이어야 한다 — 5분 창을
  /// 봤으면 `true`, 24시간 창을 봤으면 `false`이고, 둘이 어긋나면 화면은 저장소가 보지도
  /// 않은 만료를 근거로 다음 행동을 안내하게 된다.
  ///
  /// **만료 판정은 사용한 자격증명 기준이다.** 코드로 요청했으면
  /// [Group.inviteCodeExpiresAt](5분)를, 링크로 요청했으면 [Group.inviteExpiresAt]
  /// (24시간)를 본다. 둘을 합쳐 "그룹 초대가 살아 있는가"로 판정하면 5분짜리 코드가
  /// 링크의 남은 24시간을 물려받아, 만료가 화면에만 있는 문구가 된다.
  ///
  /// **정원([Group.isFull])은 여기서 보지 않는다.** 대기자는 자리를 차지하지 않으며,
  /// 정원 검사는 [approveJoinRequest] 시점에 한다 — 대기자가 자리를 선점하면 방장이
  /// 정작 받고 싶은 사람을 못 넣는다.
  ///
  /// 멱등: 이미 [JoinRequestStatus.pending] 요청이 있으면 **새로 만들지 않고** 그것을
  /// 반환한다(같은 링크를 두 번 눌러도 방장에게 요청이 두 개 쌓이지 않는다).
  /// 이미 **결정이 끝난** 요청(거절당했거나, 승인된 뒤 강퇴당한 경우)이 남아 있으면 그
  /// 요청이 다시 [JoinRequestStatus.pending]이 된다 — 오거절을 되돌리고 강퇴된 사람이
  /// 다시 물어볼 경로가 이것뿐이기 때문이다(재요청 빈도 제한은 아직 없다).
  ///
  /// 그룹이 삭제되면 그 그룹의 요청도 함께 사라진다 — 남겨 두면 아무도 끝낼 수 없는
  /// '대기 중'이 요청자 화면에 영원히 남는다.
  ///
  /// **알림 문서를 남기지 않는다.** 방장이 요청을 알아채는 신호는
  /// [watchPendingJoinRequests] 하나뿐이며, 화면은 그 스트림의 길이로 배지를 그린다.
  ///
  /// 그룹 알림([GroupNotification])으로 알리지 않는 이유: 이 메서드의 행위자는 정의상
  /// **비멤버**인데(바로 위 가드), 알림 문서는 멤버만 만들 수 있다. 규칙에 비멤버 예외를
  /// 뚫으면 그룹의 알림 피드에 외부인이 쓰는 길이 열리고, 서버(Cloud Functions)로
  /// 대신 쓰게 하려면 유료 플랜이 필요하다. 대기 목록이 이미 같은 정보를 갖고 있으므로
  /// 둘 다 치르지 않는다 — 요청 문서 자체가 알림이다.
  Future<JoinRequest> requestToJoin(String credential);

  /// [userId]가 보낸 참여 요청들을 반응형으로 관찰한다(최신순).
  ///
  /// 요청자 화면이 대기/거절 상태를 보여주는 근거다. 비멤버는 그룹 알림을 읽을 수 없으므로
  /// 거절 결과를 알 수 있는 경로는 이것뿐이다.
  Stream<List<JoinRequest>> watchMyJoinRequests(String userId);

  /// [userId]가 보낸 참여 요청들을 1회성으로 조회한다(최신순).
  Future<List<JoinRequest>> getMyJoinRequests(String userId);

  /// [groupId]의 **대기 중** 참여 요청을 반응형으로 관찰한다(오래된 순).
  ///
  /// 방장의 승인 목록이 소비하며, 요청이 도착했음을 방장에게 알리는 **유일한 신호**다
  /// ([requestToJoin] 참조 — 알림 문서는 만들지 않는다). 처리된
  /// ([JoinRequestStatus.approved]/[JoinRequestStatus.rejected]) 요청은 포함하지 않는다.
  ///
  /// **읽기 권한: 그 그룹의 방장만.** 대기자 명단은 아직 멤버가 아닌 사람들의 이름이라
  /// 일반 멤버에게도 열지 않는다. in-memory 구현은 이 제한을 강제하지 않으므로
  /// (조회 메서드는 행위자를 받지 않는다) 실제 차단은 Firestore 보안 규칙이 맡는다 —
  /// 규칙을 쓸 때 이 문장이 기준이다. 요청자 본인은 [watchMyJoinRequests]로 자기
  /// 요청만 읽는다.
  Stream<List<JoinRequest>> watchPendingJoinRequests(String groupId);

  /// [groupId]의 대기 중 참여 요청을 1회성으로 조회한다(오래된 순).
  Future<List<JoinRequest>> getPendingJoinRequests(String groupId);

  /// 방장이 참여 요청을 승인한다 — 요청자가 [MemberRole.member]로 합류한다.
  ///
  /// 가드: 행위자가 그룹의 방장이어야 하고, 요청이 [JoinRequestStatus.pending]이어야 한다.
  /// 승인 시점에 정원이 찼으면([Group.isFull]) [StateError]로 거부한다.
  /// 요청/그룹 없음도 [StateError].
  ///
  /// 요청자가 그 사이 이미 멤버가 됐다면(다른 요청이 먼저 승인되는 등) 요청만
  /// [JoinRequestStatus.approved]로 정리하고 멤버는 중복 추가하지 않는다.
  ///
  /// 성공 시 갱신된(요청자가 추가된) 그룹을 반환한다.
  Future<Group> approveJoinRequest(String joinRequestId);

  /// 방장이 참여 요청을 거절한다.
  ///
  /// 가드: 행위자가 그룹의 방장이어야 하고, 요청이 [JoinRequestStatus.pending]이어야 한다.
  /// 위반/요청 없음이면 [StateError].
  ///
  /// 문서를 지우지 않고 [JoinRequestStatus.rejected]로 남긴다 — 요청자가 결과를 확인할
  /// 유일한 경로다([watchMyJoinRequests]).
  ///
  /// 성공 시 갱신된 요청을 반환한다.
  Future<JoinRequest> rejectJoinRequest(String joinRequestId);

  /// 요청자가 자기 요청을 거둔다 — 문서를 **삭제**한다.
  ///
  /// 가드: 행위자가 요청자 본인이어야 한다. 위반/요청 없음이면 [StateError].
  /// 거절당한 요청도 지울 수 있다(요청자가 결과를 확인한 뒤 치우는 경로).
  Future<void> cancelJoinRequest(String joinRequestId);

  // ── 공유 기프티콘 ────────────────────────────────────────────────────
  /// 특정 그룹의 공유 기프티콘 목록을 반응형으로 관찰한다.
  Stream<List<SharedGifticon>> watchSharedGifticons(String groupId);

  /// 특정 그룹의 공유 기프티콘 목록을 1회성으로 조회한다.
  Future<List<SharedGifticon>> getSharedGifticons(String groupId);

  /// 원본 [Gifticon]을 그룹에 공유한다. 행위자가 공유자가 된다.
  ///
  /// [SharedGifticon.gifticonId]에 [gifticon]의 id를, 표시 필드를 스냅샷으로 담고,
  /// [ShareStatus.available] 상태로 등록한다. 그룹에 '등록' 알림을 남긴다.
  ///
  /// 공유 자체는 원본 [Gifticon]의 상태를 바꾸지 않는다(원본은 사용되기 전까지 available).
  ///
  /// **불변식: 한 기프티콘은 최대 1회만 공유될 수 있다.** 같은 [Gifticon.id]가 행위자가 속한
  /// 어느 그룹에든 이미 공유돼 있으면 [StateError]를 던진다(이중 사용·[UsageLog] 다중 발생 방지).
  /// [cancelShare]로 회수하면 다시 공유할 수 있고, 사용 완료([markUsed])된 기프티콘은 재공유되지 않는다.
  ///
  /// 그룹 없음/비멤버여도 [StateError].
  Future<SharedGifticon> shareGifticon({
    required String groupId,
    required Gifticon gifticon,
  });

  /// 찜(사용 예정) 토글 — 행위자가 찜/찜 해제한다.
  ///
  /// 다른 멤버가 이미 찜한 항목은 덮어쓸 수 없다([StateError]). 항목 없음도 [StateError].
  /// 성공 시 갱신된 항목을 반환한다.
  Future<SharedGifticon> toggleReservation(String sharedGifticonId);

  /// 사용 완료 처리 — [ShareStatus.available] → [ShareStatus.used]로 전이한다.
  ///
  /// 가드: 항목이 [ShareStatus.available]이어야 한다(사용중/사용완료면 [StateError]).
  /// 부수효과: 잠금/찜 해제, 사용 이력([UsageLog]) 추가, 그룹 '사용 완료' 알림 추가,
  /// 그리고 **원본 [Gifticon]을 `GifticonStatus.used`로 동기화**(GifticonRepository.updateStatus).
  /// 원본이 조회되지 않거나(데모 시드) 이미 사용/만료면 동기화는 건너뛴다.
  /// 성공 시 갱신된 항목을 반환한다.
  Future<SharedGifticon> markUsed(String sharedGifticonId);

  /// 공유 취소(회수) — 공유자 본인이, 사용 가능한 항목만 회수한다.
  ///
  /// 가드: 행위자가 공유자([SharedGifticon.sharedByUserId])여야 하고, 항목이
  /// [ShareStatus.available]이어야 한다. 위반/항목 없음이면 [StateError].
  Future<void> cancelShare(String sharedGifticonId);

  // ── 사용 이력 / 알림 ─────────────────────────────────────────────────
  /// [userId]가 속한 그룹들의 사용 이력을 반응형으로 관찰한다(최신순).
  Stream<List<UsageLog>> watchUsageLogs(String userId);

  /// [userId]가 속한 그룹들의 사용 이력을 1회성으로 조회한다(최신순).
  Future<List<UsageLog>> getUsageLogs(String userId);

  /// [userId]가 속한 그룹들의 알림을 반응형으로 관찰한다(최신순).
  Stream<List<GroupNotification>> watchNotifications(String userId);

  /// [userId]가 속한 그룹들의 알림을 1회성으로 조회한다(최신순).
  Future<List<GroupNotification>> getNotifications(String userId);

  /// [userId]의 알림 '마지막 읽음' 시각을 반응형으로 관찰한다.
  ///
  /// 한 번도 읽지 않았으면 `null`(= 모든 알림이 안읽음). 소비자는 이 시각 이후에
  /// 생성된 [GroupNotification]을 안읽음으로 판정한다(안읽음 뱃지/카운트).
  Stream<DateTime?> watchNotificationsReadAt(String userId);

  /// 현재 사용자의 알림을 모두 읽음 처리한다(마지막 읽음 시각을 현재로 갱신).
  ///
  /// 세션에 현재 사용자가 없으면 [StateError].
  ///
  /// 호출 시점 가이드: 알림 화면에서 **알림 목록이 실제로 표시된 뒤**(스트림이
  /// 성공 데이터를 방출한 뒤) 호출한다 — 진입 즉시 무조건 호출하면 스트림
  /// 에러/로딩으로 목록을 못 본 상태에서도 읽음 처리되어, 사용자가 한 번도
  /// 보지 못한 알림이 읽음으로 유실된다(안읽음 뱃지 무단 해소).
  Future<void> markNotificationsRead();
}
