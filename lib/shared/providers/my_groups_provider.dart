/// KeepCon 공유 계약 — "현재 사용자의 그룹 목록" Riverpod provider (단일 정본 / SSOT).
///
/// ⚠️ 이 파일이 **내 그룹 목록 스트림의 유일한 정본**이다. [myGroupsProvider]는 오직
/// 여기에만 존재한다. 페이지(`lib/features/*`)는 같은 체인을 다시 조립하지 말고 이
/// provider를 import 해서 소비하고, 페이지 고유 표현은 그 위에 **파생**으로 얹는다.
///
/// ---
/// ## 왜 계약(lib/shared)에 있어야 하는가 (중복 구독 방어)
/// 승격 전에는 scan(`_scanCurrentUserProvider`/`_scanGroupsByUserProvider`)과
/// share(`shareCurrentUserProvider`/`_groupsByUserProvider`)가 **본문이 사실상 동일한**
/// 체인을 각자 선언했다. provider 인스턴스가 다르면 Riverpod은 두 스트림을 각각 열기
/// 때문에, 같은 사용자에 대해 [ShareRepository.watchGroups]가 **두 번 구독**됐다.
/// in-memory 구현에서는 조용히 넘어가지만, Firestore에서는
/// `where('memberIds', arrayContains: uid)` 리스너가 2개 붙어 **문서 읽기와 과금이
/// 그대로 두 배**가 된다(초기 스냅샷 + 이후 모든 변경분).
///
/// 두 페이지가 **같은 provider 인스턴스**를 `watch`하면 Riverpod이 구독을 하나로
/// 합쳐 주므로(공유 provider = 공유 구독), 정본화 자체가 중복 구독의 해법이다.
/// 이것이 이 승격의 목적이며, `test/shared/providers/my_groups_provider_test.dart`가
/// "두 소비자 동시 watch → `watchGroups` 구독 1회"를 회귀로 고정한다.
///
/// ---
/// ## 노출 형태 = `AsyncValue` (로딩/에러 구분 보존)
/// 정본은 [AsyncValue]를 그대로 노출한다. 목록을 바로 내주지 않는 이유는, "로딩 중"과
/// "그룹이 하나도 없음"을 소비자가 구분할 수 있어야 하기 때문이다(정본이 미리 빈 목록으로
/// 접어 버리면 그 정보는 복구할 수 없다 — 정보를 잃는 방향의 변환은 파생에서 한다).
///
/// 페이지별 파생은 각 페이지에 남긴다:
/// - share: `groupByIdProvider`는 [AsyncValue]를 구분 소비(whenData — 로딩 중
///   pop 방지)하고, 목록/요약 소비 지점들은 `valueOrNull ?? []` 빈 목록 폴딩을
///   쓴다(로딩/에러 시 빈 상태로 표시 — 에러 표시 UI는 후속 과제).
/// - scan: `valueOrNull ?? const <Group>[]`로 **빈 목록 폴딩**
///   (`lib/features/scan/state/scan_target_group_state.dart`의 `scanTargetGroupsProvider`).
///   선택 UI가 항상 '내 지갑' 타일을 갖기 때문에 빈 목록도 정상 상태다.
///
/// ### ⚠️ `.value` 대신 `valueOrNull`
/// 이 provider의 결과를 접을 때는 반드시 `valueOrNull`을 쓴다. Riverpod의 `.value`는
/// **이전 값이 없는 [AsyncError]에서 에러를 rethrow** 하므로, 첫 방출이 에러면 폴백
/// (`?? const <Group>[]`)에 도달하지 못하고 소비 provider가 throw 한다. 정본도, 파생도
/// 이 함정을 재도입하지 않는다.
///
/// ---
/// ## 수명(autoDispose) 설계 근거
/// 정본과 내부 체인은 모두 `autoDispose`다. 근거:
/// 1. **일회성 플로우 보호(scan).** 스캔/추가는 상시 탭이 아닌 일회성 플로우다. keepAlive면
///    화면을 한 번 열기만 해도 실서버 리스너가 앱 수명 동안 잔존하고, userId family는
///    로그아웃→다른 계정 로그인 시 이전 사용자의 구독이 누적된다.
/// 2. **상시 소비자 보호(share).** 공유 탭의 파생 provider들은 keepAlive이므로, 공유
///    화면이 한 번 열리면 그 파생이 정본을 계속 `watch`해 **구독을 붙잡는다**(리스너가
///    떨어져도 keepAlive는 스스로 dispose되지 않는다). 즉 share 쪽 체감 수명은 승격 전
///    (keepAlive 체인)과 동일하고, scan이 뒤늦게 진입하면 따뜻한 캐시를 재사용한다(추가 읽기 0).
/// 3. 따라서 구독 수는 **0 또는 1**이다 — 아무도 보지 않고 keepAlive 소비자도 만들어지지
///    않았으면 0, 그 외에는 1. 승격 전의 최댓값(2개)보다 항상 적거나 같다.
///
/// keepAlive provider가 이 autoDispose 정본을 `watch` 하는 것은 허용된다(Riverpod 2.6
/// 확인 — share 파생이 그 형태다). 수명 규약과 이 조합은
/// `test/shared/providers/my_groups_provider_test.dart`가 고정한다.
///
/// ---
/// ## 세션 스트림 = 계약 정본 소비 (v2.6)
/// 이 파일은 세션을 더 이상 자기 안에서 조립하지 않고
/// [sessionUserProvider](`session_provider.dart`)를 소비한다. 승격 전에는 내부
/// `_currentUserProvider`가 [AuthRepository.watchCurrentUser]의 **두 번째 구독**이었고,
/// 그 결과 인증 스트림이 실패하면 **캐시된 에러가 두 곳**(share의
/// `shareCurrentUserProvider` + 이 파일 내부)에 생겨 페이지 재시도 훅이 절반만 되살릴
/// 수 있었다(매트릭스 #13 / QA [minor 5]). 정본 소비로 그 절반이 사라지고, 남은 절반
/// (그룹 스트림 계층)은 아래 [myGroupsRetryProvider]가 담당한다.
///
/// 세션 정본의 소비 전환은 아직 진행 중이다(앱 조립부·main·mypage는 각자 구독 —
/// `session_provider.dart`의 잔여 목록 참조).
///
/// ---
/// ## 수동 재시도 훅
/// [myGroupsRetryProvider]/[retryMyGroups]는 이 체인(세션 + 그룹 스트림) 중
/// **에러인 계층만** 되살린다. 자동 재시도는 없다 — 훅은 사용자 액션에서만 호출된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../models/user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/share_repository.dart';
import 'repositories.dart';
import 'session_provider.dart';

/// 특정 사용자의 그룹 스트림(정본 조립용 — 확정된 userId로만 구독).
///
/// family 인자를 `userId`로 못 박아, 세션이 확정되기 전에는 구독이 시작되지 않게 한다.
final AutoDisposeStreamProviderFamily<List<Group>, String>
    _groupsByUserProvider =
    StreamProvider.autoDispose.family<List<Group>, String>((ref, userId) {
  return ref.watch(shareRepositoryProvider).watchGroups(userId);
});

/// 내가 멤버로 속한 그룹 목록. **SSOT provider.**
///
/// 체인: [sessionUserProvider](= [authRepositoryProvider].[AuthRepository.watchCurrentUser]) →
/// [shareRepositoryProvider].[ShareRepository.watchGroups]`(user.id)`.
///
/// 상태 규약:
/// - 세션에서 **알려진 user가 있으면**(확정 방출 또는 일시 로딩/에러 중 이전 값 보존)
///   그 user의 그룹 스트림 [AsyncValue]를 그대로 반환한다. `when`이 아니라
///   `valueOrNull` 기반으로 접는 이유가 이것이다 — `when`의 loading/error 분기는
///   이전 값 없는 fresh [AsyncValue]를 새로 만들어, 세션 스트림이 잠깐 순단해도
///   이미 로드된 그룹 목록이 화면에서 사라진다(AsyncValue의 이전 값 보존을 버리는 셈).
/// - 알려진 user가 없고 세션 **에러**면(값 없는 재시도 중 로딩 포함) [AsyncError]
///   전파 — 재시도 중에도 에러 표시가 유지된다([foldSessionUser]의 순서 규약 참조).
/// - 알려진 user가 없고 세션 **로딩 중**이면 [AsyncLoading] 전파(빈 목록으로 접지
///   않는다 — 소비자가 로딩과 "멤버십 사라짐"을 구분할 수 있어야 한다).
/// - 세션이 `data(null)`(미로그인 확정)이면 [AsyncData]`(<Group>[])`.
/// - 접는 판단은 소비자 몫이며, 접을 때는 `valueOrNull`을 쓴다(파일 doc의
///   `.value` 함정 참조).
///
/// 폴딩 본문은 계약 정본 [foldSessionUser]를 소비한다 — share의 세션 파생들과 같은
/// 한 구현을 쓰므로 축 간 비대칭이 구조적으로 불가능하다.
final AutoDisposeProvider<AsyncValue<List<Group>>> myGroupsProvider =
    Provider.autoDispose<AsyncValue<List<Group>>>((ref) {
  return foldSessionUser<List<Group>>(
    ref.watch(sessionUserProvider),
    (User user) => ref.watch(_groupsByUserProvider(user.id)),
    signedOut: const <Group>[],
  );
});

/// [myGroupsProvider] 체인의 **수동 재시도 훅**(계약 API).
///
/// 페이지에서 `ref.invalidate(myGroupsProvider)`를 해도 그룹 목록은 되살아나지 않는다 —
/// Riverpod의 `invalidate`는 **dependents 방향으로만** 전파되고 dependencies(여기서는
/// [sessionUserProvider]와 [_groupsByUserProvider])로는 전파되지 않기 때문에, 재실행된
/// 본문이 **여전히 캐시된 [AsyncError]를 다시 읽는다**(#13 실측 / QA #4). 그래서 실제
/// 원천을 아는 이 파일이 재시도 진입점을 제공한다.
///
/// 사용(share 등 소비 화면):
/// ```dart
/// ShareErrorBanner(
///   // 이제 재시도 경로가 있으므로 onRetry를 null로 낮추지 않아도 된다.
///   onRetry: () => retryMyGroups(ref), // 또는 ref.read(myGroupsRetryProvider).retry()
/// );
/// ```
///
/// - **provider 형태인 이유:** private 원천([_groupsByUserProvider])에 접근하려면 이
///   파일 안의 `Ref`가 필요하다. 값으로 노출하면 화면([WidgetRef])·다른 provider([Ref])·
///   테스트([ProviderContainer]) 어디서든 같은 한 가지 방법으로 호출된다.
/// - **수명 = keepAlive(의도).** 이 provider는 스트림을 구독하지 않는 순수 행위 객체이며,
///   화면이 콜백에 담아 두는 동안 `Ref`가 살아 있어야 하므로 `autoDispose`로 두지 않는다.
final Provider<MyGroupsRetry> myGroupsRetryProvider =
    Provider<MyGroupsRetry>((Ref ref) => MyGroupsRetry._(ref));

/// [myGroupsRetryProvider]가 노출하는 재시도 실행기.
class MyGroupsRetry {
  const MyGroupsRetry._(this._ref);

  final Ref _ref;

  /// [myGroupsProvider] 체인에서 **에러인 계층만** 재구독한다.
  ///
  /// 되살리는 두 계층(둘 다 필요하다 — 어느 한쪽만 되살리면 절반만 해소된다):
  /// 1. [sessionUserProvider] — 세션이 죽으면 그 아래 그룹 스트림은 시작조차 못 한다.
  /// 2. [_groupsByUserProvider]`(user.id)` — **현재 사용자 인스턴스만**.
  ///
  /// ## 스코프 원칙: 에러인 계층만
  /// 멀쩡한 스트림을 재구독하면 Firestore 리스너가 해제·재시작돼 **문서 읽기와 과금이
  /// 늘고**(초기 스냅샷 재수신), 화면은 이유 없이 로딩으로 깜빡인다. share의
  /// `_retrySessionIfFailed`/`_retryFailedSharedInstances`와 같은 규약이다.
  /// family 전체(`invalidate(_groupsByUserProvider)`)를 쓰지 않는 이유도 같다 —
  /// 되살릴 대상은 지금 보고 있는 사용자 인스턴스뿐이다.
  ///
  /// ## ⚠️ 사용자 액션에서만 호출할 것 (자동 재시도 금지 — #13)
  /// `build`/`listen`에서 에러를 감지해 자동으로 부르면, 장애 중 모든 화면이 동시에
  /// 재구독하는 retry storm이 된다. 호출 지점은 버튼 콜백(당김 새로고침 포함)뿐이다.
  ///
  /// 세션에 **알려진 user가 없으면**(한 번도 확정된 적 없는 에러/로딩, 또는 미로그인
  /// 확정) 그룹 계층은 건드리지 않는다 — 그 사용자에 대한 family 인스턴스가 만들어진
  /// 적이 없어 되살릴 대상 자체가 없고, 세션이 회복되면 하위가 함께 재구성된다.
  /// (세션이 값을 가진 적이 있으면 에러/로딩 전이에도 `copyWithPrevious`로 값이
  /// 보존되므로 `valueOrNull`이 그 user를 계속 돌려준다. 세션 에러의 원인이 계정
  /// 무효화 계열이면 보존 uid로의 그룹 재구독이 한 번 헛돌 수 있지만, 훨씬 흔한
  /// 순단-동일-사용자 회복에는 이 보존 uid가 정확히 맞는 대상이다 — 감수하는 트레이드오프.)
  ///
  /// 검사용 read는 [Ref.exists]로 가드한다: `read`는 살아 있지 않은 autoDispose
  /// 인스턴스를 **새로 만들어 실제 스트림을 구독**하므로(그룹 축은 Firestore 초기
  /// 스냅샷 읽기·과금), 체인이 마운트되지 않은 컨텍스트에서 훅이 호출되면 검사가
  /// 곧 낭비 구독이 된다. 존재하지 않는 인스턴스는 에러가 캐시돼 있을 수도 없으므로
  /// 건너뛰는 것이 판정으로도 정확하다.
  void retry() {
    if (!_ref.exists(sessionUserProvider)) return;
    final AsyncValue<User?> session = _ref.read(sessionUserProvider);
    if (session.hasError) {
      _ref.invalidate(sessionUserProvider);
    }

    final User? user = session.valueOrNull;
    if (user == null) return;

    final AutoDisposeStreamProvider<List<Group>> groups =
        _groupsByUserProvider(user.id);
    if (_ref.exists(groups) && _ref.read(groups).hasError) {
      _ref.invalidate(groups);
    }
  }
}

/// [MyGroupsRetry.retry]의 화면용 얇은 진입점(share의 `retry*(WidgetRef)` 관용구와 동형).
///
/// `retryMyGroups(ref)` == `ref.read(myGroupsRetryProvider).retry()`.
/// 동작·규약은 [MyGroupsRetry.retry]와 완전히 같다(자동 재시도 금지 포함).
void retryMyGroups(WidgetRef ref) => ref.read(myGroupsRetryProvider).retry();
