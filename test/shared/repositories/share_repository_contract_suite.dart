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
/// 1. **보안 규칙 — "제한적"이 아니라 아예 평가되지 않는다.** 규칙 엔진
///    `fake_firebase_security_rules 0.5.4`는 `resource`·`request.resource`·**커스텀
///    함수**·`exists()`·`get()`·timestamps를 전부 미지원으로 명시한다(그 패키지 README의
///    "Missing" 절). 이 저장소의 `firestore.rules`는 `allow` 34개 중 `if false` 5개를 뺀
///    **29개 전부**가 그중 하나 이상을 쓴다(`isSignedIn()`만 24개) — 즉 `securityRules:`를
///    넘겨도 규칙이 한 줄도 평가되지 않는다. 정본은 에뮬레이터 검증
///    (`tool/verify_firestore_rules.sh`, CI `Firestore rules` 잡)이고 그대로 남는다.
///    여기서 통과한다고 규칙이 그 요청을 허용한다는 뜻이 아니다 — 실제로 PR #100·#104의
///    권한 결함은 이 계층이 아니라 에뮬레이터에서만 드러났다.
/// 2. **트랜잭션 경합·원자성.** fake의 `runTransaction`은 콜백을 돌려줄 뿐 동시성
///    충돌을 만들지 않는다. 멱등성 같은 **로직**은 검증되지만 "두 요청이 겹칠 때"는
///    여전히 미검증이다.
/// 3. **복합 인덱스 요구.** fake는 인덱스를 강제하지 않는다. 인덱스 없는 쿼리를 새로
///    짜면 **여기서는 통과하고 실서비스에서 죽는다** — `firestore.indexes.json`에 항목이
///    넷 있고 **그중 둘이 `joinRequests`**다(`[groupId, status, requestedAt]`·
///    `[userId, requestedAt]`, 나머지는 `usageLogs`·`notifications`). 이 스위트가 다루는
///    컬렉션이 바로 그것이므로, 대기 목록·요청자 조회에 정렬이나 필터를 더할 때는 반드시
///    그 파일을 함께 본다.
/// 4. **규칙이 없으므로 비멤버가 프로덕션과 다른 분기를 탄다.** 실서비스에서 게스트는
///    `groups`를 읽지 못하고(`firestore.rules`: `uid() in resource.data.memberIds`),
///    `requestToJoin`은 그 거부를 `on FirebaseException`으로 흡수해 "비멤버"로 판정한다.
///    fake에서는 읽기가 **성공**하므로 그 catch가 한 번도 실행되지 않는다 — 실측: 그
///    catch를 `rethrow`로 바꿔도 이 스위트 18건이 전부 통과한다(프로덕션에서는 모든
///    게스트의 참여 요청이 `permission-denied`로 죽는 변경인데도). 같은 이유로
///    `_dropJoinRequest`의 `permission-denied` 흡수도 여기서는 미검증이다.
///    **게스트 케이스가 초록이라고 프로덕션 경로가 검증된 것이 아니다.**
///    (같은 부류 중 요청 문서 읽기 둘은 예외 주입으로 따로 덮었다 — 첫 요청의 흡수는
///    `firebase_join_request_first_read_test.dart`, 승인·거절·취소의 경합 번역은
///    `firebase_join_request_race_read_test.dart`. 이 스위트가 아니라 거기가 정본인
///    이유도 각 파일 머리말에 있다.)
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

import 'package:keepcon/shared/models/gifticon.dart';
import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/share.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/gifticon_repository.dart';
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

  /// 공유의 **원본**을 담는 저장소.
  ///
  /// 공유 항목의 만료일은 원본의 스냅샷이라, 연장 계약은 "둘이 함께 움직였는가"를
  /// 봐야 한다 — 한쪽만 보면 갈라진 상태가 그대로 통과한다.
  GifticonRepository get gifticons;

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
    final ShareBackend created = makeBackend();
    // ⚠️ **정리는 만들어진 인스턴스에 붙인다.** 상단에 `tearDown(() => backend.stop())`을
    //    두면, `makeBackend()`가 던졌을 때도 `flutter_test`가 그 정리를 실행하면서
    //    아직 대입되지 않은 `backend`를 만져 `LateInitializationError`가 나고, **그것이
    //    원래 예외를 가린다.** `addTearDown`은 생성이 성공한 뒤에만 등록된다.
    addTearDown(created.stop);
    backend = created;
    // 방장 세션으로 시작한다 — `createGroup`의 행위자가 곧 방장이다.
    await backend.auth.signUp(
      email: 'contract-owner@keepcon.test',
      password: guestPassword,
      displayName: '방장',
    );
  });

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

    test('이미 멤버면 요청할 수 없다 — 화면이 구별할 수 있는 타입으로 거부한다', () async {
      final Group g = await newGroup();
      final Group issued = await backend.repo.issueInviteCode(groupId: g.id);
      // 방장 본인이 자기 코드를 넣는 경로 — 세션을 바꾸지 않는다.
      //
      // 타입까지 고정하는 이유: 이 실패에는 **다음 행동이 없다**(코드를 다시 받아
      // 와도 같은 답이다). 뭉뚱그린 StateError로 두면 화면이 "링크나 코드가
      // 잘못됐을 수 있어요"라고 말해 고칠 수 없는 것을 고치게 만든다.
      await expectLater(
        backend.repo.requestToJoin(issued.inviteCode!),
        throwsA(allOf(
          isA<AlreadyGroupMemberException>(),
          // 계약의 가드 위반은 전부 StateError라는 규약을 깨지 않는다.
          isA<StateError>(),
        )),
      );
    });

    test('이미 대기 중인 요청이 있으면 새로 만들지 않고 그 사실을 알린다', () async {
      // 두 구현 모두에 도는 것이 요점이다 — in-memory는 리스트를, firebase는
      // 결정론적 문서 id(`{groupId}_{userId}`)를 근거로 같은 판정을 해야 한다.
      final Group g = await newGroup();
      await asGuest();
      final JoinRequest first = await backend.repo.requestToJoin(g.inviteToken);

      await expectLater(
        backend.repo.requestToJoin(g.inviteToken),
        throwsA(allOf(
          isA<JoinRequestAlreadyPendingException>().having(
            (JoinRequestAlreadyPendingException e) => e.request.id,
            'request.id',
            first.id,
          ),
          isA<StateError>(),
        )),
      );
      // 저장소의 부작용은 그대로 없다 — 방장 목록에 요청이 쌓이지 않는다.
      expect(await backend.repo.getPendingJoinRequests(g.id), hasLength(1));
    });

    test('결정이 끝난 요청은 다시 대기로 되살아난다(알림이 아니라 정상 반환)', () async {
      // ⚠️ 위 분기와 갈리는 지점이다. 거절당한 사람의 재요청은 오거절을 되돌리는
      //    유일한 경로이므로 **성공해야** 한다 — 여기까지 예외로 닫으면 승인제에
      //    복구 경로가 없어진다.
      final Group g = await newGroup();
      await asGuest();
      final JoinRequest first = await backend.repo.requestToJoin(g.inviteToken);

      // 방장 세션으로 돌아가 거절한다 — 거절은 방장만 할 수 있다.
      await backend.auth.signIn(
          email: 'contract-owner@keepcon.test', password: guestPassword);
      await backend.repo.rejectJoinRequest(first.id);

      await asGuest();
      final JoinRequest again = await backend.repo.requestToJoin(g.inviteToken);
      expect(again.id, first.id);
      expect(again.status, JoinRequestStatus.pending);
      expect(await backend.repo.getPendingJoinRequests(g.id), hasLength(1));
    });
  });
}

/// 두 구현이 **같은 답을 내야 하는** 공유 기프티콘 유효기간 연장 계약.
///
/// 이 축이 보는 것은 하나다 — **스냅샷과 원본이 함께 움직이는가.**
/// [SharedGifticon.expiryDate]는 공유 시점의 복사본이라, 한쪽만 옮기면 그룹 화면과 개인
/// 목록이 같은 기프티콘을 두고 다른 만료일을 말한다. 그 어긋남은 어느 화면에도 보이지
/// 않으므로 여기서 고정한다.
///
/// [makeBackend]는 `setUp()`마다 새 백엔드를 만든다.
void runSharedExpiryExtensionContract(ShareBackend Function() makeBackend) {
  late ShareBackend backend;

  const String password = 'keepcon';
  const String ownerEmail = 'extend-owner@keepcon.test';
  const String memberEmail = 'extend-member@keepcon.test';

  final DateTime oldExpiry = DateTime(2026, 1, 10);
  final DateTime newExpiry = DateTime(2026, 7, 20);

  setUp(() async {
    final ShareBackend created = makeBackend();
    // 정리는 만들어진 인스턴스에 붙인다(위 스위트의 ⚠️와 같은 이유).
    addTearDown(created.stop);
    backend = created;
    await backend.auth.signUp(
      email: ownerEmail,
      password: password,
      displayName: '공유자',
    );
  });

  /// 이미 가입된 계정이면 로그인, 아니면 가입한다.
  Future<User> signInOrUp(String email, String displayName) async {
    try {
      return await backend.auth.signIn(email: email, password: password);
    } on Object {
      return backend.auth.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
    }
  }

  Future<User> asOwner() => signInOrUp(ownerEmail, '공유자');
  Future<User> asMember() => signInOrUp(memberEmail, '다른 멤버');

  /// 원본 기프티콘을 저장소에 심는다. [store]가 `false`면 **저장하지 않고** 값만 만든다
  /// — 데모 시드처럼 원본이 없는 공유 항목을 재현하기 위함이다.
  Future<Gifticon> makeOriginal({
    DateTime? expiry,
    GifticonStatus status = GifticonStatus.available,
    bool store = true,
  }) async {
    final Gifticon g = Gifticon(
      id: store ? '' : 'ghost-gifticon',
      ownerId: backend.auth.currentUser!.id,
      brand: '스타벅스',
      productName: '아메리카노 T',
      price: 4500,
      category: '카페',
      expiryDate: expiry ?? oldExpiry,
      registeredAt: DateTime(2025, 1, 1),
      status: status,
    );
    return store ? backend.gifticons.addGifticon(g) : g;
  }

  /// 방장 세션으로 그룹을 만들고 기프티콘 하나를 공유한다.
  Future<(Group, Gifticon, SharedGifticon)> shareOne({
    DateTime? expiry,
    GifticonStatus status = GifticonStatus.available,
    bool storeOriginal = true,
  }) async {
    await asOwner();
    final Group group = await backend.repo
        .createGroup(name: '연장 계약 그룹', emoji: '📄', maxMembers: 5);
    final Gifticon original = await makeOriginal(
      expiry: expiry,
      status: status,
      store: storeOriginal,
    );
    final SharedGifticon item =
        await backend.repo.shareGifticon(groupId: group.id, gifticon: original);
    return (group, original, item);
  }

  /// 승인 흐름을 그대로 타서 [group]에 두 번째 멤버를 넣는다.
  Future<User> joinAsMember(Group group) async {
    final User member = await asMember();
    final JoinRequest req = await backend.repo.requestToJoin(group.inviteToken);
    await asOwner();
    await backend.repo.approveJoinRequest(req.id);
    return member;
  }

  group('연장이 되는 경우', () {
    test('스냅샷과 원본이 함께 옮겨진다', () async {
      final (_, Gifticon original, SharedGifticon item) = await shareOne();

      final SharedGifticon updated =
          await backend.repo.extendSharedExpiry(item.id, newExpiry);

      expect(updated.expiryDate, newExpiry);
      final Gifticon? synced =
          await backend.gifticons.getGifticonById(original.id);
      expect(synced?.expiryDate, newExpiry,
          reason: '원본이 안 따라오면 내 목록은 여전히 만료된 기프티콘을 보여준다');
    });

    test('만료 상태였던 원본이 available로 되살아난다', () async {
      final (_, Gifticon original, SharedGifticon item) =
          await shareOne(status: GifticonStatus.expired);

      await backend.repo.extendSharedExpiry(item.id, newExpiry);

      expect((await backend.gifticons.getGifticonById(original.id))?.status,
          GifticonStatus.available);
    });

    test('그룹에 기간 연장 알림이 남는다', () async {
      final (Group group, _, SharedGifticon item) = await shareOne();

      await backend.repo.extendSharedExpiry(item.id, newExpiry);

      final List<GroupNotification> notifs =
          await backend.repo.getNotifications(backend.auth.currentUser!.id);
      final Iterable<GroupNotification> extended = notifs.where(
        (GroupNotification n) =>
            n.groupId == group.id &&
            n.type == GroupNotificationType.expiryExtended,
      );
      expect(extended, hasLength(1),
          reason: '만료라 못 쓴다고 판단했던 멤버가 다시 쓸 수 있게 됐음을 알 경로가 이것뿐이다');
      // 새 만료일이 문구에 실려야 "언제까지 늘었는지"를 알림만 보고 안다.
      expect(extended.first.message, contains('2026.07.20'));
    });

    test('찜해 둔 항목도 연장된다 — 찜을 건드리지 않는다', () async {
      final (Group group, _, SharedGifticon item) = await shareOne();
      await joinAsMember(group);

      await asMember();
      await backend.repo.toggleReservation(item.id);

      await asOwner();
      final SharedGifticon updated =
          await backend.repo.extendSharedExpiry(item.id, newExpiry);
      expect(updated.expiryDate, newExpiry);
      expect(updated.reservedByUserId, isNotNull);
    });

    test('원본이 없어도(데모 시드) 스냅샷은 옮겨진다', () async {
      final (_, _, SharedGifticon item) = await shareOne(storeOriginal: false);

      final SharedGifticon updated =
          await backend.repo.extendSharedExpiry(item.id, newExpiry);
      expect(updated.expiryDate, newExpiry);
    });

    test('원본이 이미 더 뒤면 원본은 그대로, 스냅샷만 따라붙는다', () async {
      final (_, Gifticon original, SharedGifticon item) = await shareOne();
      // 스냅샷이 뒤처진 상태를 만든다 — 원본만 2026-12-31로 옮긴다.
      final DateTime far = DateTime(2026, 12, 31);
      await backend.gifticons.extendExpiry(original.id, far);

      // 그룹 화면이 보여주는 값(뒤처진 스냅샷) 기준으로 고른 날짜.
      final SharedGifticon updated =
          await backend.repo.extendSharedExpiry(item.id, newExpiry);

      expect(updated.expiryDate, newExpiry);
      expect((await backend.gifticons.getGifticonById(original.id))?.expiryDate,
          far,
          reason: '앞당기기 가드에 걸려 통째로 실패시키지 않는다 — 스냅샷만 따라붙으면 둘이 만난다');
    });
  });

  group('연장이 거부되는 경우', () {
    test('공유자가 아닌 멤버는 연장할 수 없다', () async {
      final (Group group, Gifticon original, SharedGifticon item) =
          await shareOne();
      await joinAsMember(group);

      await asMember();
      await expectLater(
        backend.repo.extendSharedExpiry(item.id, newExpiry),
        throwsStateError,
      );

      // 거부됐으면 **양쪽 다** 그대로여야 한다. 원본만 옮겨 두면 규칙이 막은 뒤에도
      // 개인 목록의 만료일이 조용히 바뀐다.
      final List<SharedGifticon> shared =
          await backend.repo.getSharedGifticons(group.id);
      expect(shared.single.expiryDate, oldExpiry);
      expect((await backend.gifticons.getGifticonById(original.id))?.expiryDate,
          oldExpiry);
    });

    test('사용 완료된 항목은 연장할 수 없다', () async {
      final (_, _, SharedGifticon item) = await shareOne();
      await backend.repo.markUsed(item.id);

      await expectLater(
        backend.repo.extendSharedExpiry(item.id, newExpiry),
        throwsStateError,
      );
    });

    test('연장 도중 사용 완료되면 거부한다 — 원본 동기화 뒤에도 다시 판정한다', () async {
      // 연장은 원본을 옮기는 동안 한 번 멈춘다(`await`). 그 창에서 누가 써 버리면
      // 판정 근거가 사라진 것이므로 거부해야 한다. **한쪽만 다시 판정하면 두 구현이
      // 같은 입력에 다른 답을 낸다** — firebase는 트랜잭션 안에서 다시 보고,
      // in-memory는 재조회 뒤에 다시 본다.
      final (Group group, Gifticon original, SharedGifticon item) =
          await shareOne();

      // 결과를 **즉시** 붙잡아 둔다. `expectLater`를 나중에 걸면, 그 사이에 실패한
      // Future가 리스너 없이 완료돼 unhandled async error로 터진다(검증하려던 실패가
      // 테스트 실패로 둔갑한다).
      final Future<Object?> outcome = backend.repo
          .extendSharedExpiry(item.id, newExpiry)
          .then<Object?>((SharedGifticon v) => v, onError: (Object e) => e);
      await backend.repo.markUsed(item.id);

      expect(await outcome, isA<StateError>());

      final List<SharedGifticon> shared =
          await backend.repo.getSharedGifticons(group.id);
      expect(shared.single.status, ShareStatus.used);
      expect(shared.single.expiryDate, oldExpiry,
          reason: '사용 완료된 항목의 만료일이 옮겨지면 "쓴 기프티콘이 되살아난 것처럼" 보인다');

      // ⚠️ 거절 지점이 원본 동기화 **뒤**라 원본은 이미 옮겨져 있다. 그리고 이 분기는
      // 항목이 `used`가 되어 재연장 가드에 영구히 막히므로, 계약이 적어 둔 복구("같은
      // 연장을 다시")가 통하지 않는다. 지금 고정되는 상태를 그대로 적어 둔다 — 이
      // 비대칭을 없애는 변경은 여기서 시끄럽게 실패해야 한다.
      final Gifticon? origin =
          await backend.gifticons.getGifticonById(original.id);
      expect(origin!.expiryDate, newExpiry,
          reason: '원본만 옮겨진 채 남는다(사용 완료된 기프티콘이라 실질 피해는 없다)');
    });

    test('앞당기기는 연장이 아니다', () async {
      final (_, _, SharedGifticon item) = await shareOne();

      await expectLater(
        backend.repo.extendSharedExpiry(item.id, DateTime(2025, 12, 1)),
        throwsStateError,
      );
    });

    test('없는 항목', () async {
      await asOwner();
      await expectLater(
        backend.repo.extendSharedExpiry('no-such-item', newExpiry),
        throwsStateError,
      );
    });
  });
}
