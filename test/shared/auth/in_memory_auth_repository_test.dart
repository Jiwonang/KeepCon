// InMemoryAuthRepository — 회원가입/로그인/로그아웃 계약 테스트.
//
// 실제 백엔드 없이 auth 계약 시맨틱(중복 가입 차단·자격 검증·세션 방출)을 검증한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:keepcon/shared/models/user.dart';
import 'package:keepcon/shared/repositories/auth_repository.dart';
import 'package:keepcon/shared/repositories/impl/in_memory_auth_repository.dart';

void main() {
  late InMemoryAuthRepository repo;

  setUp(() {
    // 로그아웃 상태로 시작해 로그인 플로우를 명확히 검증한다.
    repo = InMemoryAuthRepository(initialUser: null);
  });

  tearDown(() => repo.dispose());

  group('signUp', () {
    test('성공 시 로그인 상태가 되고 User를 반환한다', () async {
      final User user = await repo.signUp(
        email: 'a@b.com',
        password: 'secret1',
        displayName: '홍길동',
      );
      expect(user.email, 'a@b.com');
      expect(user.displayName, '홍길동');
      expect(repo.currentUser, user);
    });

    test('displayName이 비면 이메일 로컬파트로 폴백한다', () async {
      final User user = await repo.signUp(
        email: 'nick@b.com',
        password: 'secret1',
        displayName: '   ',
      );
      expect(user.displayName, 'nick');
    });

    test('이미 가입된 이메일이면 emailInUse', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      expect(
        () => repo.signUp(
            email: 'A@b.com', password: 'secret2', displayName: 'B'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.emailInUse)),
      );
    });

    test('약한 비밀번호면 weakPassword', () async {
      expect(
        () => repo.signUp(email: 'a@b.com', password: '123', displayName: 'A'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.weakPassword)),
      );
    });

    test('이메일 형식 오류면 invalidEmail', () async {
      expect(
        () => repo.signUp(
            email: 'not-an-email', password: 'secret1', displayName: 'A'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.invalidEmail)),
      );
    });
  });

  group('signIn', () {
    test('가입 후 같은 자격으로 로그인된다', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      await repo.signOut();
      expect(repo.currentUser, isNull);

      final User user =
          await repo.signIn(email: 'a@b.com', password: 'secret1');
      expect(user.email, 'a@b.com');
      expect(repo.currentUser, isNotNull);
    });

    test('비밀번호가 틀리면 invalidCredential', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      expect(
        () => repo.signIn(email: 'a@b.com', password: 'wrong'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.invalidCredential)),
      );
    });

    test('미가입 이메일이면 invalidCredential', () async {
      expect(
        () => repo.signIn(email: 'ghost@b.com', password: 'secret1'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.invalidCredential)),
      );
    });

    test('데모 기본 계정으로 로그인된다', () async {
      final User user = await repo.signIn(
        email: InMemoryAuthRepository.defaultUser.email,
        password: InMemoryAuthRepository.defaultPassword,
      );
      expect(user.id, InMemoryAuthRepository.defaultUser.id);
    });
  });

  group('watchCurrentUser', () {
    test('로그인/로그아웃 전이를 방출한다', () async {
      final List<User?> emitted = <User?>[];
      final sub = repo.watchCurrentUser().listen(emitted.add);
      // 초기 null 방출 + 브로드캐스트 컨트롤러 구독이 완료되도록 이벤트 큐를 비운다.
      await pumpEventQueue();

      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      await pumpEventQueue();
      await repo.signOut();
      await pumpEventQueue();
      await sub.cancel();

      expect(emitted.first, isNull); // 초기 로그아웃
      expect(emitted.any((User? u) => u?.email == 'a@b.com'), isTrue); // 로그인
      expect(emitted.last, isNull); // 로그아웃
    });
  });

  group('updateDisplayName', () {
    test('성공 시 갱신된 User를 반환하고 currentUser에 반영된다', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: '옛이름');
      final User updated = await repo.updateDisplayName(displayName: '새이름');
      expect(updated.displayName, '새이름');
      expect(repo.currentUser?.displayName, '새이름');
      expect(updated.email, 'a@b.com'); // 다른 필드는 불변.
    });

    test('watchCurrentUser가 갱신된 사용자를 방출한다', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: '옛이름');
      final List<User?> emitted = <User?>[];
      final sub = repo.watchCurrentUser().listen(emitted.add);
      await pumpEventQueue();

      await repo.updateDisplayName(displayName: '새이름');
      await pumpEventQueue();
      await sub.cancel();

      expect(emitted.last?.displayName, '새이름');
    });

    test('재로그인해도 새 이름이 유지된다(계정 저장소 반영)', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: '옛이름');
      await repo.updateDisplayName(displayName: '새이름');
      await repo.signOut();
      final User again =
          await repo.signIn(email: 'a@b.com', password: 'secret1');
      expect(again.displayName, '새이름');
    });

    test('트림 후 빈 문자열이면 unknown 예외(빈 문자열 금지 계약)', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      expect(
        () => repo.updateDisplayName(displayName: '   '),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.unknown)),
      );
    });

    test('미로그인 상태면 unknown 예외', () async {
      expect(
        () => repo.updateDisplayName(displayName: '이름'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.unknown)),
      );
    });
  });

  group('deleteAccount', () {
    test('성공 시 로그아웃 상태가 되고 같은 자격으로 재로그인 불가', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      await repo.deleteAccount(password: 'secret1');
      expect(repo.currentUser, isNull);
      expect(
        () => repo.signIn(email: 'a@b.com', password: 'secret1'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.invalidCredential)),
      );
    });

    test('watchCurrentUser가 null을 방출한다', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      final List<User?> emitted = <User?>[];
      final sub = repo.watchCurrentUser().listen(emitted.add);
      await pumpEventQueue();

      await repo.deleteAccount(password: 'secret1');
      await pumpEventQueue();
      await sub.cancel();

      expect(emitted.last, isNull);
    });

    test('비밀번호가 틀리면 invalidCredential — 계정과 세션은 유지', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      await expectLater(
        () => repo.deleteAccount(password: 'wrong'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.invalidCredential)),
      );
      expect(repo.currentUser, isNotNull); // 세션 유지.
      // 계정도 그대로 — 올바른 비밀번호로 여전히 로그인 가능.
      await repo.signOut();
      final User again =
          await repo.signIn(email: 'a@b.com', password: 'secret1');
      expect(again.email, 'a@b.com');
    });

    test('미로그인 상태면 unknown 예외', () async {
      expect(
        () => repo.deleteAccount(password: 'x'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.unknown)),
      );
    });
  });

  group('plan (watchPlan / updatePlan)', () {
    test('기본은 free — 가입 직후 watchPlan 첫 방출이 free다', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      expect(await repo.watchPlan().first, UserPlan.free);
    });

    test('updatePlan(premium) 후 watchPlan이 premium을 방출한다', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      final Future<UserPlan> next =
          repo.watchPlan().firstWhere((UserPlan p) => p == UserPlan.premium);
      await repo.updatePlan(plan: UserPlan.premium);
      expect(await next, UserPlan.premium);
      expect(await repo.watchPlan().first, UserPlan.premium);
    });

    test('플랜은 계정별로 유지된다 — 로그아웃/재로그인해도 premium', () async {
      await repo.signUp(
          email: 'a@b.com', password: 'secret1', displayName: 'A');
      await repo.updatePlan(plan: UserPlan.premium);
      await repo.signOut();
      await repo.signIn(email: 'a@b.com', password: 'secret1');
      expect(await repo.watchPlan().first, UserPlan.premium);
    });

    test('미로그인 watchPlan은 free, updatePlan은 unknown 예외', () async {
      expect(await repo.watchPlan().first, UserPlan.free);
      expect(
        () => repo.updatePlan(plan: UserPlan.premium),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AuthErrorCode.unknown)),
      );
    });
  });
}
