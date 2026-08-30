/// scan — 저장 대상 그룹 선택용 상태(공유 계약 소비).
///
/// 스캔/추가 화면은 "이 기프티콘을 내 지갑에 둘지, 어느 그룹에 공유할지"를 저장 전에
/// 고르게 한다. 그 선택지를 만들기 위해 그룹 목록을 계약에서 읽어 온다.
///
/// 계약 준수 포인트:
/// - 그룹 목록은 계약 정본 [myGroupsProvider](`lib/shared/providers/my_groups_provider.dart`)를
///   `watch`해 소비한다. 세션→`ShareRepository.watchGroups(userId)` 체인을 페이지에서
///   다시 조립하지 않는다 — share 페이지와 **같은 provider 인스턴스**를 봐야 두 페이지의
///   구독이 하나로 합쳐진다(승격 전에는 같은 사용자에 대해 `watchGroups`가 2번 구독됐다).
/// - `Group`은 계약 모델을 그대로 쓴다(재정의 금지).
///
/// 여기 남는 provider는 **scan 페이지 로컬 파생**이다 — 정본의 [AsyncValue]를 이 화면에
/// 맞는 표현(빈 목록 폴딩)으로 접는 얇은 층이며, 그룹 도메인 정본이 아니다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/group.dart';
import '../../../shared/providers/my_groups_provider.dart';

/// 저장 대상으로 고를 수 있는 내 그룹 목록.
///
/// 로딩 중·미로그인·그룹 없음은 모두 **빈 목록**으로 접는다. 선택 UI가 항상
/// '내 지갑'(그룹 공유 없음) 타일을 첫 번째로 두기 때문에, 빈 목록도 그 자체로
/// 정상 상태이며 사용자는 언제나 저장을 진행할 수 있다(로딩 스피너 불필요).
///
/// 스트림 **error**도 빈 목록으로 접힌다 — 정본이 이전에 방출된 목록을 갖고 있으면
/// 그 목록을 유지하고(AsyncValue의 이전 값 보존), 첫 방출부터 에러면 빈 목록이 된다.
/// 그래서 이 목록만으로는 "그룹이 없다"와 "그룹을 못 불러왔다"를 **구분할 수 없다** —
/// 그 구분은 아래 [scanGroupsUnavailableProvider]가 맡는다(화면은 둘을 함께 본다).
///
/// `.value`가 아니라 `valueOrNull`을 쓴다 — Riverpod의 `.value`는 이전 값이
/// 없는 AsyncError에서 에러를 **rethrow**하므로, 첫 방출이 에러면 폴백(`?? []`)에
/// 도달하지 못하고 이 provider 자체가 throw해 선택 UI가 깨진다.
///
/// **autoDispose인 이유:** 스캔 화면은 상시 탭이 아니라 일회성 추가 플로우이므로,
/// 선택 UI가 사라지면 이 파생도 함께 해제돼야 한다. 정본도 autoDispose라, share가
/// 보고 있지 않은 상태라면 실제 `watchGroups` 구독까지 함께 해제된다(수명 근거는
/// 정본 파일 doc 참조).
final AutoDisposeProvider<List<Group>> scanTargetGroupsProvider =
    Provider.autoDispose<List<Group>>((ref) {
  return ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
});

/// 그룹 목록을 **못 불러온** 상태인가 — 에러 배너를 띄울지의 단일 판정점.
///
/// [scanTargetGroupsProvider]가 에러를 빈 목록으로 접기 때문에, 화면은 이 값 없이는
/// "그룹이 없어요"와 "그룹을 못 불러왔어요"를 구분해 말할 수 없다. 선택 UI에서 그
/// 차이는 크다 — 전자는 정상이고(내 지갑에 저장하면 된다), 후자는 **골라야 할 그룹이
/// 화면에 없는데 사용자는 그 사실조차 모르는** 상태다.
///
/// **판정식이 `hasError && !hasValue`인 이유**(share의 `myGroupListUnavailableProvider`와
/// 같은 규칙 — 그 파일 doc이 근거를 길게 적어 뒀다): 이전 값이 보존된 순단 에러는 목록이
/// 그대로 표시·선택되므로 사용자가 취할 행동이 없다. 멀쩡히 동작하는 목록 위에 실패
/// 문구를 얹지 않고, 다음 방출이 성공하면 조용히 회복시킨다. 값도 없는 에러만 배너 대상이다.
///
/// ⚠️ **share에 같은 규칙의 provider가 따로 있다**(`myGroupListUnavailableProvider`).
/// 여기 한 벌 더 두는 것은 페이지가 서로를 import하지 않기 위해서다 — 판정식이 갈라지면
/// 두 화면의 에러 표시 기준이 달라진다.
///
/// 📌 **승격 트리거는 이미 당겨졌다 — 미룬 것이 아니라 이 담당이 실행할 수 없을 뿐이다.**
/// CLAUDE.md 승격 규칙 ③의 방아쇠는 "셋째"가 아니라 **실제 두 번째 소비자**이고,
/// share가 첫째·이 선언이 둘째다(`InlineErrorBanner` 승격도 같은 근거를 썼다).
/// 실행에 필요한 파일이 전부 이 담당의 수정 금지 영역이라(`lib/shared`·`tool/`·
/// `lib/features/share`) 인계한다. 인계 항목 둘:
///   1. `contract-architect`에게 `lib/shared`로의 승격 요청(두 선언을 하나로).
///   2. 승격 전까지는 `tool/check_ssot.sh`의 `SSOT_PROVIDERS`에 두 이름을 등록해
///      갈라짐을 CI가 잡게 할 것 — 지금은 **어느 가드도 이 복제를 보지 않는다**.
///
/// autoDispose 근거는 [scanTargetGroupsProvider]와 같다.
final AutoDisposeProvider<bool> scanGroupsUnavailableProvider =
    Provider.autoDispose<bool>((ref) {
  final AsyncValue<List<Group>> groups = ref.watch(myGroupsProvider);
  return groups.hasError && !groups.hasValue;
});

/// 그룹 목록이 **아직 첫 방출 전**(값 없는 로딩)인가 — 로딩을 '그룹 없음'으로
/// 위장하지 않기 위한 게이트.
///
/// [scanGroupsUnavailableProvider]와 **같은 문제의 다른 축**이다. 이 화면에서
/// '그룹 없음'은 타일의 **부재**로 표현되므로, 원인이 로딩이어도 확정 부재와 똑같이
/// 보인다(실측: 콜드 스타트에서 배너 0·타일 0·진행표시 0 — "정말 그룹이 없을 때"와
/// 픽셀 단위로 같았다). 에러 축만 막고 이 축을 두면 같은 위장이 절반 남는다.
///
/// share에도 같은 규칙이 있다 — `groupsPending`(`share_page.dart`),
/// `sharedGifticonsPendingProvider`, `usage_log_page`의 `isPending`.
///
/// ⚠️ 이 값과 [scanGroupsUnavailableProvider]는 **동시에 참일 수 있다.** `invalidate`가
/// 만드는 재시도 상태는 `AsyncError(isLoading: true)`이기 때문이다 — 계약 정본이
/// `hasError`를 `isLoading`보다 **먼저** 검사해 그렇게 유지한다(`session_provider.dart`:
/// 로딩을 먼저 보면 재시도를 누르는 순간 배너가 사라졌다 재등장하는 왕복 깜빡임이 된다).
/// 그때는 배너(원인)와 진행 표시(지금 뭔가 하고 있음)가 **함께** 떠야 맞다 —
/// 배너를 숨기지 말 것.
final AutoDisposeProvider<bool> scanGroupsPendingProvider =
    Provider.autoDispose<bool>((ref) {
  final AsyncValue<List<Group>> groups = ref.watch(myGroupsProvider);
  return groups.isLoading && !groups.hasValue;
});
