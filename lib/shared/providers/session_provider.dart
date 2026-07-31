/// KeepCon 공유 계약 — "현재 로그인 사용자 세션 스트림" Riverpod provider (단일 정본 / SSOT).
///
/// ⚠️ 이 파일이 **세션 스트림의 유일한 정본**이다. [AuthRepository.watchCurrentUser]
/// 구독은 앞으로 [sessionUserProvider] **하나로 수렴**한다. 페이지(`lib/features/*`)와
/// 앱 조립부는 `ref.watch(authRepositoryProvider).watchCurrentUser()`를 다시 조립하지
/// 말고 이 provider를 import 해서 소비하고, 페이지 고유 표현(표시 이름·권한 판정 등)은
/// 그 위에 **파생**으로 얹는다.
///
/// ---
/// ## 왜 계약(lib/shared)에 있어야 하는가
/// 세션 체인은 승격 전 **5곳**에 각자 선언돼 있었다 — 앱 조립부(`authStateProvider`),
/// main(`currentUserProvider`), mypage, share(`shareCurrentUserProvider`), 그리고
/// `my_groups_provider.dart` 내부(`_currentUserProvider`). provider 인스턴스가 다르면
/// Riverpod은 스트림을 각각 열기 때문에 같은 `watchCurrentUser()`가 그 수만큼 구독된다.
///
/// 다만 이득의 성격이 `myGroupsProvider`와 다르다:
/// - **과금 이득은 작다.** Firebase의 `userChanges()`는 인증 상태 리스너라 Firestore
///   문서 읽기가 아니다(그룹 목록의 `arrayContains` 리스너와 달리 구독 수가 곧 비용이
///   되지 않는다).
/// - **진짜 이득은 인스턴스/타이밍 일관성이다.** 소스가 여럿이면 계정 전환·로그아웃
///   프레임에서 화면마다 **한 프레임 어긋난 세션**을 볼 수 있다(실제로 share의
///   `memberNamesProvider`가 두 세션 소스를 혼합해 이 위험을 안고 있었다). 또한 세션이
///   실패했을 때 **캐시된 에러가 소스 수만큼** 생겨, 화면의 재시도 훅이 자기 소스만
///   되살리고 나머지는 앱 재시작 전까지 죽은 채 남는다(#13의 "재시도 불가"가 그 경로다).
///
/// ---
/// ## 노출 형태 = `AsyncValue<User?>` (로딩/에러 구분 보존)
/// 정본은 [StreamProvider]가 만드는 [AsyncValue]를 그대로 노출한다. `User?`로 미리 접지
/// 않는 이유는 "세션 확인 중"과 "미로그인 확정"을 소비자가 구분해야 하기 때문이다
/// (정본이 null로 접어 버리면 그 정보는 복구할 수 없다 — 정보를 잃는 변환은 파생에서
/// 한다). 앱 게이트는 이 구분으로 스플래시/로그인 화면을 가르고, `myGroupsProvider`는
/// 로딩을 그대로 전파한다.
///
/// ### ⚠️ `.value` 대신 `valueOrNull`
/// 접을 때는 반드시 `valueOrNull`을 쓴다. Riverpod의 `.value`는 **이전 값이 없는
/// [AsyncError]에서 에러를 rethrow** 하므로, 첫 방출이 에러면 폴백(`?? ...`)에 도달하지
/// 못하고 소비 provider가 throw 한다(lib 전수 규약 — 매트릭스 #13).
///
/// ---
/// ## 수명(autoDispose) 설계 근거
/// `myGroupsProvider`와 **같은 근거·같은 수명**을 쓴다.
/// 1. **동작 불변.** 정본화 전 `my_groups_provider.dart`의 내부 세션 provider가 이미
///    `autoDispose`였다. 같은 수명을 유지해야 그룹 목록 체인의 콜드/웜 동작이 그대로다
///    (수명을 keepAlive로 올리면 "마지막 소비자가 사라져도 리스너가 남는" 새 동작이 된다).
/// 2. **구독 수 0 또는 1.** 아무도 보지 않으면 0, 그 외에는 1이다. keepAlive 소비자
///    (share 파생 등)가 이 autoDispose 정본을 `watch` 하면 그 소비자가 수명을 붙잡으므로,
///    상시 화면의 체감 수명은 승격 전(keepAlive 체인)과 같다. 전환 완결(v2.7) 이후로는
///    **앱 게이트(`auth_gate`)가 루트에서 정본을 상시 `watch` 하므로 수명 앵커가 게이트다** —
///    실효 수명은 앱 수명, 구독은 항상 1개다(테스트로 고정: `main_session_consumer_test`).
/// 3. keepAlive provider가 autoDispose 정본을 `watch` 하는 조합은 허용된다(Riverpod 2.6
///    확인 — `test/shared/providers/my_groups_provider_test.dart`가 고정).
///
/// ---
/// ## 소비 전환 완료 (v2.7 — 수렴 완료)
/// 승격 전 5곳이 각자 열던 세션 구독은 **전부 이 정본으로 옮겨왔다.** 지금
/// [AuthRepository.watchCurrentUser]를 구독하는 코드는 **이 파일 하나뿐**이다:
/// 앱 조립부(`lib/app/auth_gate.dart`) · main(`gifticon_list_providers.dart`·`main_page.dart`) ·
/// mypage · share(`share_providers.dart` 파생과 화면들) · `my_groups_provider.dart` —
/// 모두 페이지 선언 없이 이 provider를 직접 `watch`/`read` 한다.
/// 페이지 별칭·재export shim은 두지 않는다(경과 조치였던 share의 `shareCurrentUserProvider`
/// 별칭도 제거됐다 — 매트릭스 #13).
///
/// 새로 세션이 필요하면 **만들지 말고 이 provider를 소비한다.** 일부 필드만 쓰는 소비자는
/// `sessionUserProvider.select((s) => s.valueOrNull?.id)`처럼 좁혀 구독하면, 값이 같은
/// 재방출(예: Firebase `userChanges()`의 토큰 갱신)에서 불필요한 리빌드를 피할 수 있다 —
/// [StreamProvider]는 data→data 재방출도 무조건 통지하기 때문이다.
///
/// ⚠️ 이름 기반 CI 가드(`tool/check_ssot.sh`)는 이 provider의 **재선언**은 잡지만
/// *다른 이름으로 다시 조립한 세션 체인*은 잡지 못한다. 그 방어선은 이 규약과 리뷰다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../repositories/auth_repository.dart';
import 'repositories.dart';

/// 현재 로그인 사용자 세션 스트림. **SSOT provider.**
///
/// 체인: [authRepositoryProvider].[AuthRepository.watchCurrentUser].
///
/// 상태 규약:
/// - [AsyncLoading] = 세션 확인 중(미로그인으로 단정하지 않는다).
/// - [AsyncData]`(null)` = **미로그인 확정**.
/// - [AsyncData]`(user)` = 로그인 확정.
/// - [AsyncError] = 세션 조회 실패. 스트림이 값을 방출한 뒤 실패하면 Riverpod이
///   `copyWithPrevious`로 이전 값을 보존하므로, "순단(이전 사용자 보존)"과 "확정
///   로그아웃(data(null))"은 서로 구분된다 — 이 구분에 기대는 소비자는 `hasValue`를
///   함께 본다(예: `myGroupsProvider`).
///
/// 동기 getter [AuthRepository.currentUser]가 아니라 스트림을 쓰는 이유: 화면이 떠 있는
/// 동안 로그인/로그아웃/계정 전환에 반응해야 하기 때문이다.
///
/// 실패 시 재구독(수동 재시도)은 **사용자 액션에서만** 한다 — 자동 재시도는 장애 중
/// retry storm이 된다(#13). 그룹 목록과 묶인 재시도 훅은 `myGroupsRetryProvider` /
/// `retryMyGroups`(`my_groups_provider.dart`)를 참조.
final AutoDisposeStreamProvider<User?> sessionUserProvider =
    StreamProvider.autoDispose<User?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

/// 세션 [AsyncValue]를 "사용자별 하위 스트림"으로 접는 **계약 폴딩 함수**(정본).
///
/// [myGroupsProvider]와 share의 세션 파생들이 같은 이 함수를 소비한다 — 동형 폴딩을
/// 산문 규약이 아니라 한 구현으로 기계화해, 같은 세션 순단에 화면 축마다 반대로
/// 반응하는 비대칭(QA v2.6 [medium 1])이 규칙 차원에서 재발하지 않게 한다.
///
/// 분기(순서가 규약이다):
/// - **알려진 user 있음**(확정 방출 또는 순단 중 `copyWithPrevious` 보존) →
///   [forUser]의 [AsyncValue] 그대로. `when`을 쓰지 않는 이유: `when`은 `skipError`
///   기본 false라 보존된 순단 에러에서도 error 분기를 타 하위의 멀쩡한 데이터를 버린다.
/// - 알려진 user 없이 **에러**(값 없는 재시도 중 로딩 포함) → [AsyncError] 전파.
///   `isLoading`보다 **먼저** 검사한다 — `invalidate`(refresh)는 이전 에러를 보존한
///   로딩 상태를 만들므로, 로딩을 먼저 보면 재시도를 누르는 순간 에러 표시(배너)가
///   사라졌다가 실패 시 재등장하는 왕복 깜빡임이 생긴다. 구 `.when`의
///   `skipLoadingOnRefresh`(기본 true)와 동형인 동작이다.
/// - 세션 `data(null)` = **미로그인 확정** → [AsyncData]([signedOut]). 재조회 중이라도
///   확정 값이 보존돼 있으면(`hasValue`) 이 분기를 유지한다 — 무효화(refresh)가
///   `data(null)`을 "로딩"으로 되돌리면 확정 부재에 의존하는 소비자(알림 읽음 가드의
///   `StateError` 복원 경로 등)가 흔들린다(#13 규약: 이 경로는 반드시 보존).
/// - 알려진 user 없이 **로딩**(값도 에러도 없는 첫 구독) → [AsyncLoading] 전파(빈
///   값으로 접지 않는다 — 소비자가 로딩과 확정 부재를 구분해야 한다).
///
/// 순단(값 보존) 중 무배너 유지가 안전한 전제: 두 구현 모두 세션 스트림이 에러로
/// **종료되지 않는다**(InMemory는 에러 방출 자체가 없고, Firebase `userChanges().map`은
/// 변환 에러를 이벤트로 전달한 뒤 구독을 유지) — 다음 인증 이벤트가 오면 자동 회복된다.
/// 에러로 종료되는 구현을 들일 때는 이 전제를 재검토할 것.
AsyncValue<T> foldSessionUser<T>(
  AsyncValue<User?> session,
  AsyncValue<T> Function(User user) forUser, {
  required T signedOut,
}) {
  // 순단(loading/error에 이전 user 보존)과 로그아웃(확정 null)은 여기서 갈린다.
  final User? user = session.valueOrNull;
  if (user != null) return forUser(user);
  if (session.hasError) {
    return AsyncError<T>(
      session.error!,
      session.stackTrace ?? StackTrace.current,
    );
  }
  // hasValue인데 user가 null = 미로그인 "확정"(재조회 로딩 중 보존 포함).
  if (session.hasValue) return AsyncData<T>(signedOut);
  return AsyncLoading<T>();
}
