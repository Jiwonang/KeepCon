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
/// 스트림 **error**는 조용히 접힌다(별도 안내 없음) — 정본이 이전에 방출된 목록을
/// 갖고 있으면 그 목록을 유지하고(AsyncValue의 이전 값 보존), 첫 방출부터 에러면
/// 빈 목록이 된다. 저장은 부분 실패 정책이 백스톱이고, 에러 표시/재시도 UI는
/// 후속 과제로 남긴다.
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
