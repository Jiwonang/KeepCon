/// 두 [ShareRepository] 구현에 **같은 기대를 돌리는** 공유 계약 스위트.
///
/// ## 왜 구현별 테스트가 아니라 공유 스위트인가
///
/// 이 저장소가 반복해 데인 실패 양상(반복 패턴 #1)은 "firebase에 테스트가 없다"가
/// 아니라 **`flutter test`가 in-memory만 돌려서 두 구현이 갈라져도 green**이라는
/// 것이다. 그래서 firebase 전용 테스트를 따로 쓰면 그 테스트가 다시 in-memory 쪽과
/// 드리프트하고, 같은 구멍이 한 겹 아래에서 다시 열린다.
///
/// 기대를 **한 번** 쓰고 백엔드를 갈아 끼워 두 번 돌린다. 그러면 비대칭이 생기는
/// 순간 자동으로 잡히고, 나중에 축을 넓힐 때도 같은 보호가 따라온다.
///
/// ## ⚠️ 이 스위트가 대체하지 **못하는** 것 — 셋
///
/// fake는 Firestore의 *자료구조*를 흉내 낼 뿐 *서버*가 아니다. 아래는 여기서
/// 검증되지 않으며, **"이제 firebase가 테스트된다"고 읽으면 안 된다.**
///
/// 1. **보안 규칙.** `fake_cloud_firestore`의 규칙 지원은 문서상 불완전하다
///    (`DocumentReference` 연산만). 규칙의 정본은 에뮬레이터 검증
///    (`tool/verify_firestore_rules.sh`, CI `Firestore rules` 잡)이고 그대로 남는다.
///    여기서 통과한다고 규칙이 그 요청을 허용한다는 뜻이 아니다 — 실제로 PR #100·#104의
///    권한 결함은 이 계층이 아니라 에뮬레이터에서만 드러났다.
/// 2. **트랜잭션 경합·원자성.** fake의 `runTransaction`은 콜백을 돌려줄 뿐 동시성
///    충돌을 만들지 않는다. 멱등성 같은 **로직**은 검증되지만 "두 요청이 겹칠 때"는
///    여전히 미검증이다.
/// 3. **복합 인덱스 요구.** fake는 인덱스를 강제하지 않는다. 인덱스 없는 쿼리를 새로
///    짜면 **여기서는 통과하고 실서비스에서 죽는다** — `firestore.indexes.json`에
///    실제 항목이 있다(`usageLogs`·`notifications`). 쿼리를 더할 때는 그 파일을 본다.
///
/// ## 지금 덮는 축
///
/// `requestToJoin`의 **자격증명 해석과 만료 판정**이다. PR #154에서 이 축의 소스 검사가
/// 다섯 라운드에 걸쳐 매번 새 거짓 통과를 냈다(무는 구간이 두 줄뿐 → 사이 두 줄 무보호
/// → 판정을 *만드는* 줄 무보호 → 글자만 보고 줄을 안 봄 → 접두 일치). 소스 검사는
/// 무엇을 '같다'고 볼지 매번 명시해야 해서 수렴하지 않는다. 행위로 고정하면 그 열거가
/// 필요 없다.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';
import 'package:keepcon/shared/util/invite_code.dart';

/// 한 백엔드를 스위트에 물리는 어댑터.
///
/// 구현마다 **다를 수밖에 없는 것만** 여기 둔다 — 나머지는 계약 메서드로만 다룬다.
/// 백엔드 고유 API로 셋업하면 그 셋업이 검증 대상을 앞질러 버리기 때문이다
/// (v3.8에서 존재하지 않는 토큰으로 멤버를 만들던 셋업이 정확히 그 사고였다).
abstract class ShareBackend {
  /// 자원을 거둔다. 스트림 구독이 남으면 다음 테스트가 오염된다.
  ///
  /// ⚠️ 짝이 되는 `start()`는 **일부러 두지 않았다.** 준비 단계를 나누면 그것이 중간에
  /// 죽었을 때 `tearDown`의 이 메서드가 아직 초기화되지 않은 필드를 만져 진짜 원인을
  /// 가린다. 백엔드는 **생성 시점에 준비를 끝낸다**(구현 참조).
  void stop();

  ShareRepository get repo;
  AuthRepository get auth;

  /// 시간이 [d]만큼 흐른 것으로 만든다.
  ///
  /// ⚠️ **두 구현이 같은 수단을 쓰지 못한다.** in-memory는 주입 시계를 밀지만
  /// (`InMemoryShareRepository(now:)`), firebase 구현은 `DateTime.now()`를 직접
  /// 읽으므로 시계를 밀 수 없다 — 대신 **저장된 만료 시각을 그만큼 당긴다.**
  /// 만료 여부라는 관측 결과는 같고, 그것이 이 스위트가 보는 전부다.
  Future<void> passTime(Duration d);

  /// 링크 토큰이 **6자리 숫자**인 그룹을 만든다(v3.0 이전 발급분).
  ///
  /// 계약에는 토큰을 지정해 그룹을 만드는 API가 없다 — 있으면 안 된다(토큰은
  /// 저장소가 정한다). 그래서 이것만은 백엔드 고유 경로로 심는다. 이 픽스처가 없으면
  /// **모양과 실제가 갈리는 유일한 입력**을 만들 수 없고, 그 입력이 이 축의 전부다.
  ///
  /// **방장이 누구인지는 스위트가 묻지 않는다** — 백엔드가 알아서 정한다. 스위트가
  /// 요구하는 것은 하나뿐이다: 행위자(게스트)가 이 그룹의 멤버가 **아닐** 것.
  /// (in-memory는 데모 시드의 그룹을 그대로 쓰므로 방장을 고를 수 없다 — 인자로
  /// 받아 놓고 한쪽이 무시하면 그 인자가 곧 거짓말이 된다.)
  Future<Group> seedGroupWithLinkToken(String token);
}

/// 두 구현이 **같은 답을 내야 하는** 자격증명 해석·만료 판정 계약.
///
/// [makeBackend]는 `setUp()`마다 새 백엔드를 만든다.
void runCredentialResolutionContract(ShareBackend Function() makeBackend) {
  late ShareBackend backend;

  const String guestEmail = 'contract-guest@keepcon.test';
  const String guestPassword = 'keepcon';

  setUp(() async {
    // 생성이 곧 준비다(`ShareBackend.stop` 참조).
    backend = makeBackend();
    // 방장 세션으로 시작한다 — `createGroup`의 행위자가 곧 방장이다.
    await backend.auth.signUp(
      email: 'contract-owner@keepcon.test',
      password: guestPassword,
      displayName: '방장',
    );
  });

  tearDown(() => backend.stop());

  /// 행위자를 **비멤버**로 바꾼다. 요청은 정의상 비멤버가 한다.
  Future<User> asGuest() async {
    try {
      return await backend.auth
          .signIn(email: guestEmail, password: guestPassword);
    } on Object {
      return backend.auth.signUp(
        email: guestEmail,
        password: guestPassword,
        displayName: '초대받은 사람',
      );
    }
  }

  Future<Group> newGroup() =>
      backend.repo.createGroup(name: '계약 그룹', emoji: '📄', maxMembers: 5);

  /// 만료 예외의 **종류**까지 보는 매처. 이 스위트의 존재 이유가 이 필드다.
  Matcher expiredAs({required bool isCode}) => throwsA(
        isA<InviteExpiredException>().having(
          (InviteExpiredException e) => e.isCode,
          'isCode',
          isCode,
        ),
      );

  group('살아 있는 자격증명', () {
    test('6자리 초대코드로 요청이 접수된다', () async {
      final Group g = await newGroup();
      final Group issued = await backend.repo.issueInviteCode(groupId: g.id);

      await asGuest();
      final JoinRequest req =
          await backend.repo.requestToJoin(issued.inviteCode!);
      expect(req.groupId, g.id);
      expect(req.status, JoinRequestStatus.pending);
      // 요청일 뿐 멤버가 아니다 — 코드도 링크와 같은 등급의 자격증명이다.
      expect((await backend.repo.getGroupById(g.id))?.isMember(req.userId),
          isNot(isTrue));
    });

    test('22자 링크 토큰으로 요청이 접수된다', () async {
      final Group g = await newGroup();
      expect(isWellFormedInviteCode(g.inviteToken), isFalse,
          reason: '지금 발급되는 토큰은 6자리가 아니다 — 이 케이스의 전제');

      await asGuest();
      expect((await backend.repo.requestToJoin(g.inviteToken)).groupId, g.id);
    });

    test('레거시 6자리 **링크 토큰**으로도 요청이 접수된다', () async {
      // v3.0(128비트) 이전 토큰은 6자리 숫자였고 그 값들이 아직 살아 있다. 자격증명을
      // 모양으로 **배타적으로** 고르면 이 링크들이 통째로 '없는 코드'가 된다 — 보안
      // 규칙은 두 컬렉션을 OR로 보므로 클라이언트만 좁아 정상 링크를 스스로 거부하는
      // 셈이 된다(v3.9에서 실제로 그랬다).
      final Group legacy = await backend.seedGroupWithLinkToken('482913');

      await asGuest();
      expect((await backend.repo.requestToJoin('482913')).groupId, legacy.id);
    });
  });

  group('만료 — 종류를 싣는다', () {
    test('만료된 코드는 isCode: true', () async {
      final Group g = await newGroup();
      final Group issued = await backend.repo.issueInviteCode(groupId: g.id);

      await backend
          .passTime(Group.inviteCodeValidity + const Duration(minutes: 1));

      await asGuest();
      await expectLater(
        backend.repo.requestToJoin(issued.inviteCode!),
        expiredAs(isCode: true),
      );
    });

    test('만료된 22자 링크는 isCode: false', () async {
      final Group g = await newGroup();
      await backend.passTime(Group.inviteValidity + const Duration(minutes: 1));

      await asGuest();
      await expectLater(
        backend.repo.requestToJoin(g.inviteToken),
        expiredAs(isCode: false),
      );
    });

    test('만료된 레거시 6자리 **링크**는 isCode: false — 모양은 코드지만 링크다', () async {
      // ⚠️ **이 케이스가 모양 추측과 실제 판정이 갈리는 유일한 지점이다.**
      //    `isWellFormedInviteCode('482913')`는 true지만 저장소는 이 값을 코드로
      //    해석하지 않는다(그 값을 코드로 쓰는 그룹이 없어 링크로 폴백했다).
      //    화면이 모양으로 다시 매기면 "만료된 초대코드 / 새 코드를 요청"이라고 말하고,
      //    사용자가 코드를 받아 와도 **만료된 링크는 그대로**라 다음 행동이 틀린다.
      await backend.seedGroupWithLinkToken('482913');
      await backend.passTime(Group.inviteValidity + const Duration(minutes: 1));

      await asGuest();
      await expectLater(
        backend.repo.requestToJoin('482913'),
        expiredAs(isCode: false),
      );
      // 대조군 — 같은 값에 **모양**은 반대 답을 낸다. 이 단언이 무너지면 위 케이스는
      // 두 판정이 우연히 일치하는 무의미한 테스트가 된다.
      expect(isWellFormedInviteCode('482913'), isTrue);
    });

    test('만료는 **사용한 자격증명 기준**이다 — 코드가 죽어도 링크는 산다', () async {
      // 이 단언이 6자리 코드를 쓸 수 있게 해 준 근거 전체다. 만료를 그룹 단위로
      // 판정하면 5분짜리 코드가 링크의 남은 24시간을 물려받아, "5분 만료"가 화면에만
      // 있는 문구가 된다.
      final Group g = await newGroup();
      final Group issued = await backend.repo.issueInviteCode(groupId: g.id);
      await backend
          .passTime(Group.inviteCodeValidity + const Duration(minutes: 1));

      await asGuest();
      await expectLater(
        backend.repo.requestToJoin(issued.inviteCode!),
        expiredAs(isCode: true),
      );
      // 대조군 — 같은 그룹에 링크로는 여전히 들어갈 수 있다(24시간은 안 지났다).
      expect((await backend.repo.requestToJoin(g.inviteToken)).groupId, g.id);
    });
  });

  group('만료가 아닌 실패', () {
    test('없는 자격증명은 만료가 아니라 평범한 StateError다', () async {
      // "없는 코드"를 "만료됐다"고 말하면 존재한 적 없는 그룹을 기다리게 만든다.
      await asGuest();
      await expectLater(
        backend.repo.requestToJoin('000000'),
        throwsA(allOf(isA<StateError>(), isNot(isA<InviteExpiredException>()))),
      );
    });

    test('이미 멤버면 요청할 수 없다', () async {
      final Group g = await newGroup();
      final Group issued = await backend.repo.issueInviteCode(groupId: g.id);
      // 방장 본인이 자기 코드를 넣는 경로 — 세션을 바꾸지 않는다.
      await expectLater(
          backend.repo.requestToJoin(issued.inviteCode!), throwsStateError);
    });
  });
}
