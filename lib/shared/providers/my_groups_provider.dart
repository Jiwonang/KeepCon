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
/// ## 세션 스트림은 아직 내부(private)
/// 이 파일의 `_currentUserProvider`는 정본 조립에만 쓰이는 **내부** provider다.
/// [AuthRepository.watchCurrentUser] 구독은 현재 앱 조립부·main·mypage·share에도
/// 각각 존재하지만(승격 후보), 세션 스트림 자체의 승격은 소비자가 훨씬 많아 이번 범위
/// 밖이다. 세션 스트림이 정본화되면 이 파일은 그것을 소비하도록 바꾼다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../models/user.dart';
import '../repositories/auth_repository.dart';
import '../repositories/share_repository.dart';
import 'repositories.dart';

/// 현재 로그인 사용자 스트림(정본 조립용 — 이 파일 내부 전용).
///
/// 그룹 목록은 화면에 떠 있는 동안 세션 변화(로그인/로그아웃)에 반응해야 하므로
/// 동기 getter [AuthRepository.currentUser]가 아니라 스트림을 구독한다.
final AutoDisposeStreamProvider<User?> _currentUserProvider =
    StreamProvider.autoDispose<User?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

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
/// 체인: [authRepositoryProvider].[AuthRepository.watchCurrentUser] →
/// [shareRepositoryProvider].[ShareRepository.watchGroups]`(user.id)`.
///
/// 상태 규약:
/// - 세션에서 **알려진 user가 있으면**(확정 방출 또는 일시 로딩/에러 중 이전 값 보존)
///   그 user의 그룹 스트림 [AsyncValue]를 그대로 반환한다. `when`이 아니라
///   `valueOrNull` 기반으로 접는 이유가 이것이다 — `when`의 loading/error 분기는
///   이전 값 없는 fresh [AsyncValue]를 새로 만들어, 세션 스트림이 잠깐 순단해도
///   이미 로드된 그룹 목록이 화면에서 사라진다(AsyncValue의 이전 값 보존을 버리는 셈).
/// - 알려진 user가 없고 세션 **로딩 중**이면 [AsyncLoading] 전파(빈 목록으로 접지
///   않는다 — 소비자가 로딩과 "멤버십 사라짐"을 구분할 수 있어야 한다).
/// - 알려진 user가 없고 세션 **에러**면 [AsyncError] 전파.
/// - 세션이 `data(null)`(미로그인 확정)이면 [AsyncData]`(const <Group>[])`.
/// - 접는 판단은 소비자 몫이며, 접을 때는 `valueOrNull`을 쓴다(파일 doc의
///   `.value` 함정 참조).
final AutoDisposeProvider<AsyncValue<List<Group>>> myGroupsProvider =
    Provider.autoDispose<AsyncValue<List<Group>>>((ref) {
  final AsyncValue<User?> session = ref.watch(_currentUserProvider);

  // 이전 값 보존을 활용한다(위 상태 규약 참조). 로그아웃은 data(null) "확정"
  // 방출이므로 여기서 null이 되어 아래 분기로 내려간다 — 순단(loading/error에
  // 이전 user 보존)과 로그아웃(확정 null)이 올바르게 구분된다.
  final User? user = session.valueOrNull;

  if (user != null) {
    return ref.watch(_groupsByUserProvider(user.id));
  }

  if (session.isLoading) {
    return const AsyncLoading<List<Group>>();
  }

  if (session.hasError) {
    return AsyncError<List<Group>>(
      session.error!,
      session.stackTrace ?? StackTrace.current,
    );
  }

  // 미로그인 확정 — "그룹 없음".
  return const AsyncData<List<Group>>(<Group>[]);
});
