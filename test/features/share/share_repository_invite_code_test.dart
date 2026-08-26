// ShareRepository 초대코드(6자리 OTP) 테스트 (계약 대상).
//
// 검증 대상 계약:
// - issueInviteCode: 방장만. 발급 시점 + 5분. 이미 있어도 **교체**한다(그룹당 하나).
// - requestToJoin(코드): 살아 있는 코드는 통과, 만료된 코드는 InviteExpiredException.
// - **만료는 사용한 자격증명 기준이다** — 코드가 죽어도 링크가 살아 있으면, 링크로는
//   되고 코드로는 안 된다. 이 절이 이 기능의 보안 전제 전체를 떠받친다.
// - 링크 재발급과 코드 발급은 서로를 무효화하지 않는다(독립된 두 자격증명).
//
// 시계는 `InMemoryShareRepository(now:)`로 주입한다 — 5분을 실제로 기다릴 수 없고,
// 기다리는 테스트는 느린 데다 시간에 따라 깜빡인다.

import 'package:flutter_test/flutter_test.dart';

import 'package:keepcon/shared/models/group.dart';
import 'package:keepcon/shared/models/join_request.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_gifticon_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_share_repository.dart';
import 'package:keepcon/shared/repositories/share_repository.dart';
import 'package:keepcon/shared/util/invite_code.dart';

void main() {
  late InMemoryAuthRepository auth;
  late InMemoryGifticonRepository gifticons;

  /// 저장소가 '지금'이라고 믿는 시각. 테스트가 앞으로 민다.
  ///
  /// **고정 시각이 아니라 실제 현재 시각에서 출발한다.** 주입 시계의 범위는 만료
  /// *판정*으로 좁혀져 있어서(`InMemoryShareRepository` 문서 참조), 그룹 생성 시
  /// `Group.inviteExpiresAt`는 여전히 실제 `DateTime.now()` 기준으로 찍힌다. 여기서
  /// 임의의 고정 시각을 쓰면 두 기준이 어긋나 "링크가 만료됐다"가 실행 날짜에 따라
  /// 달라진다(실제로 그렇게 짰다가 이 파일에서 깜빡였다).
  late DateTime clock;

  late InMemoryShareRepository repo;

  const String guestEmail = 'code-guest@keepcon.test';
  const String guestPassword = 'keepcon';

  setUp(() {
    auth = InMemoryAuthRepository();
    gifticons = InMemoryGifticonRepository();
    clock = DateTime.now();
    repo = InMemoryShareRepository(
      authRepository: auth,
      gifticonRepository: gifticons,
      now: () => clock,
    );
  });

  tearDown(() {
    repo.dispose();
    gifticons.dispose();
    auth.dispose();
  });

  Future<User> asGuest() async {
    try {
      return await auth.signIn(email: guestEmail, password: guestPassword);
    } on Object {
      return auth.signUp(
        email: guestEmail,
        password: guestPassword,
        displayName: '초대받은 사람',
      );
    }
  }

  Future<User> asOwner() => auth.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );

  Future<Group> newGroup() =>
      repo.createGroup(name: '코드 그룹', emoji: '🔢', maxMembers: 5);

  group('issueInviteCode — 발급', () {
    test('6자리 코드와 5분짜리 만료가 함께 생긴다', () async {
      final Group before = await newGroup();
      // 갓 만든 그룹에는 코드가 없다 — 코드는 발급해야 생기는 것이지 그룹의 속성이 아니다.
      expect(before.inviteCode, isNull);
      expect(before.inviteCodeExpiresAt, isNull);
      expect(before.hasActiveInviteCode(clock), isFalse);

      final Group after = await repo.issueInviteCode(groupId: before.id);
      expect(after.inviteCode, isNotNull);
      expect(isWellFormedInviteCode(after.inviteCode!), isTrue);
      expect(after.inviteCodeExpiresAt, clock.add(Group.inviteCodeValidity));
      expect(after.hasActiveInviteCode(clock), isTrue);
    });

    test('정책은 5분 고정이다 — 고를 수 있는 API가 없다', () async {
      // 만료 기간을 인자로 받는 순간 "무제한"이 다시 선택지가 된다(초대 만료를 24시간
      // 단일 정책으로 못박은 v2.6과 같은 이유). 상수로만 존재하는지 고정한다.
      expect(Group.inviteCodeValidity, const Duration(minutes: 5));
    });

    test('다시 발급하면 코드가 교체되고 만료가 다시 계산된다', () async {
      final Group g = await newGroup();
      final Group first = await repo.issueInviteCode(groupId: g.id);

      clock = clock.add(const Duration(minutes: 2));
      final Group second = await repo.issueInviteCode(groupId: g.id);

      expect(second.inviteCode, isNot(first.inviteCode));
      expect(second.inviteCodeExpiresAt, clock.add(Group.inviteCodeValidity));
    });

    test('옛 코드는 교체 즉시 죽는다 — 그룹당 활성 코드는 하나다', () async {
      final Group g = await newGroup();
      final String old =
          (await repo.issueInviteCode(groupId: g.id)).inviteCode!;
      await repo.issueInviteCode(groupId: g.id);

      await asGuest();
      // 아직 만료 시각이 지나지 않았는데도 옛 코드는 통하지 않아야 한다.
      await expectLater(repo.requestToJoin(old), throwsStateError);
    });

    test('방장이 아니면 발급할 수 없다', () async {
      final Group g = await newGroup();
      await asGuest();
      await expectLater(
        repo.issueInviteCode(groupId: g.id),
        throwsStateError,
      );
      await asOwner();
    });

    test('없는 그룹은 StateError', () async {
      await expectLater(
        repo.issueInviteCode(groupId: 'g_nope'),
        throwsStateError,
      );
    });
  });

  group('requestToJoin — 코드로 참여 요청', () {
    test('살아 있는 코드로 요청이 접수된다', () async {
      final Group g = await newGroup();
      final Group issued = await repo.issueInviteCode(groupId: g.id);

      await asGuest();
      final JoinRequest req = await repo.requestToJoin(issued.inviteCode!);
      expect(req.groupId, g.id);
      expect(req.status, JoinRequestStatus.pending);
      // 요청일 뿐 멤버가 아니다 — 코드도 링크와 같은 등급의 자격증명이다.
      expect((await repo.getGroupById(g.id))!.isMember(req.userId), isFalse);
    });

    test('만료된 코드는 InviteExpiredException으로 거부한다', () async {
      final Group g = await newGroup();
      final Group issued = await repo.issueInviteCode(groupId: g.id);

      clock = clock.add(Group.inviteCodeValidity);

      await asGuest();
      await expectLater(
        repo.requestToJoin(issued.inviteCode!),
        throwsA(isA<InviteExpiredException>()),
      );
    });

    test('만료 예외는 StateError이기도 하다 — 기존 호출부가 그대로 잡는다', () async {
      // 계약의 "가드 위반은 StateError" 규약을 깨지 않으면서 화면만 구별할 수 있게
      // 하위 타입으로 좁힌 설계다. 이 관계가 끊기면 기존 `on StateError` 처리들이
      // 조용히 예외를 흘린다(아무 안내 없이 시트가 멈추는 그 실패 양상).
      expect(InviteExpiredException('482913'), isA<StateError>());
    });

    test('없는 코드는 만료가 아니라 평범한 StateError다', () async {
      // "없는 코드"를 "만료됐다"고 말하면 존재한 적 없는 그룹을 기다리게 만든다.
      await asGuest();
      await expectLater(
        repo.requestToJoin('000000'),
        throwsA(allOf(isA<StateError>(), isNot(isA<InviteExpiredException>()))),
      );
    });

    test('이미 멤버면 코드로도 요청할 수 없다', () async {
      final Group g = await newGroup();
      final Group issued = await repo.issueInviteCode(groupId: g.id);
      // 방장 본인이 자기 코드를 넣는 경로.
      await expectLater(
          repo.requestToJoin(issued.inviteCode!), throwsStateError);
    });
  });

  group('만료는 사용한 자격증명 기준이다 (핵심 불변식)', () {
    test('코드가 죽어도 링크는 살아 있다 — 그리고 그 반대는 성립하지 않는다', () async {
      final Group g = await newGroup();
      final Group issued = await repo.issueInviteCode(groupId: g.id);
      final String token = issued.inviteToken;
      final String code = issued.inviteCode!;

      // 코드는 죽고(5분) 링크는 아직 산 시점으로 민다(24시간).
      clock = clock.add(const Duration(minutes: 6));
      final Group now = (await repo.getGroupById(g.id))!;
      expect(now.hasActiveInviteCode(clock), isFalse, reason: '코드는 만료');
      expect(now.isInviteExpired(clock), isFalse, reason: '링크는 아직 유효');

      await asGuest();
      // ⚠️ 이 단언이 이 기능의 보안 전제 전체다. 만료를 그룹 단위로 판정하면 여기서
      //    코드가 링크의 남은 수명을 물려받아 통과한다 — 그 순간 "5분 만료"는 화면에만
      //    있는 문구가 되고, 6자리를 쓸 수 있게 해 준 근거(짧은 노출 창)가 사라진다.
      await expectLater(
        repo.requestToJoin(code),
        throwsA(isA<InviteExpiredException>()),
      );
      // 대조군 — 같은 그룹에 링크로는 여전히 들어갈 수 있다.
      final JoinRequest req = await repo.requestToJoin(token);
      expect(req.groupId, g.id);
    });

    test('링크가 죽어도 방금 발급한 코드는 산다', () async {
      final Group g = await newGroup();
      // 링크 24시간을 넘긴다.
      clock = clock.add(Group.inviteValidity + const Duration(minutes: 1));
      final Group issued = await repo.issueInviteCode(groupId: g.id);

      await asGuest();
      await expectLater(
        repo.requestToJoin(issued.inviteToken),
        throwsA(isA<InviteExpiredException>()),
      );
      final JoinRequest req = await repo.requestToJoin(issued.inviteCode!);
      expect(req.groupId, g.id);
    });

    test('링크 재발급이 활성 코드를 죽이지 않는다 — 두 자격증명은 독립이다', () async {
      final Group g = await newGroup();
      final Group issued = await repo.issueInviteCode(groupId: g.id);
      final String code = issued.inviteCode!;

      final Group after = await repo.regenerateInviteToken(groupId: g.id);
      expect(after.inviteCode, code, reason: '재발급은 링크만 갈아 끼운다');
      expect(after.hasActiveInviteCode(clock), isTrue);

      await asGuest();
      expect((await repo.requestToJoin(code)).groupId, g.id);
    });

    test('코드 발급이 링크를 갈아 끼우지 않는다', () async {
      final Group g = await newGroup();
      final String token = g.inviteToken;
      final Group issued = await repo.issueInviteCode(groupId: g.id);
      expect(issued.inviteToken, token);
    });
  });
}
