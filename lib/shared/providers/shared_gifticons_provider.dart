/// KeepCon 공유 계약 — "내 그룹들의 공유 기프티콘" Riverpod provider (단일 정본 / SSOT).
///
/// ⚠️ [sharedGifticonsProvider]·[allSharedProvider]·[sharedGifticonIdsProvider]는 오직
/// 여기에만 존재한다. 페이지(`lib/features/*`)는 같은 체인을 다시 조립하지 말고 이
/// 파일을 import 해서 소비한다.
///
/// ---
/// ## 왜 계약(lib/shared)으로 승격했는가
/// 승격 전에는 share 페이지의 `state/share_providers.dart`에만 있었다. 그런데 main의
/// 기프티콘 상세가 **두 번째 소비자**가 됐다 — "이 기프티콘이 지금 그룹에 공유돼 있는가"를
/// 알아야 사용 완료 버튼을 내보낼지 정할 수 있기 때문이다(아래 참조).
///
/// 처음엔 그 판정을 [Gifticon.targetGroupId]로 했는데 **틀린 근거였다.** 그 필드는 scan이
/// *등록 시점에* 그룹을 지정한 경우에만 채워지고, 정작 흔한 경로인 "이미 등록한 기프티콘을
/// 공유 탭에서 그룹에 공유"는 [ShareRepository.shareGifticon]이 [SharedGifticon] 레코드만
/// 만들 뿐 원본 [Gifticon]을 건드리지 않아 끝까지 null이다. 게다가 Firestore 매핑이 이
/// 필드를 읽지도 쓰지도 않아 dev/prod에서는 **항상** null이다. 즉 가드가 죽어 있었다.
///
/// 공유 여부의 진짜 정본은 [SharedGifticon.gifticonId] 집합이므로, 그 집합을 계약으로
/// 올려 두 페이지가 같은 구독을 나눠 쓰게 한다(CLAUDE.md 승격 규칙 ②·③ — 실제 두 번째
/// 소비자가 생겼을 때 승격).
///
/// ---
/// ## 왜 [sharedGifticonIdsProvider]가 `AsyncValue`인가 (fail-closed)
/// 이 집합의 소비자는 "공유 중이면 개인 화면에서 사용 완료를 막는다"는 **안전 가드**다.
/// 로딩 중을 빈 집합으로 접으면 가드가 **fail-open** 한다 — 그룹 목록이 도착하기 전
/// 몇 프레임 동안 "공유된 것이 하나도 없다"로 보여 버튼이 잠깐 열리고, 그 창에서 누르면
/// 원본만 `used`가 되고 그룹 항목은 '사용 가능'으로 남는다. 그래서 **확정된 집합만**
/// `AsyncData`로 내보내고, 하나라도 아직 안 왔거나 실패했으면 로딩/에러를 그대로
/// 전파한다. 소비자는 확정 전까지 버튼을 내보내지 않으면 된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../models/share.dart';
import 'my_groups_provider.dart';
import 'repositories.dart';

/// 특정 그룹의 공유 기프티콘 스트림.
final sharedGifticonsProvider =
    StreamProvider.family<List<SharedGifticon>, String>((ref, groupId) {
  return ref.watch(shareRepositoryProvider).watchSharedGifticons(groupId);
});

/// 내 모든 그룹을 가로지른 공유 기프티콘(공유 메인 요약용).
///
/// 각 그룹별 [sharedGifticonsProvider]를 `watch`해 합친다. 어느 그룹의 스트림이 바뀌거나
/// 내 그룹 집합이 바뀌면 자동 재계산된다(리액티브 결합).
///
/// 표시용이라 로딩/에러를 빈 목록으로 접는다. **판정에 쓰려면 이쪽이 아니라
/// [sharedGifticonIdsProvider]를 쓴다**(위 fail-closed 절 참조).
final allSharedProvider = Provider<List<SharedGifticon>>((ref) {
  final List<Group> groups =
      ref.watch(myGroupsProvider).valueOrNull ?? const <Group>[];
  final List<SharedGifticon> out = <SharedGifticon>[];
  for (final Group g in groups) {
    out.addAll(
      ref.watch(sharedGifticonsProvider(g.id)).valueOrNull ??
          const <SharedGifticon>[],
    );
  }
  return out;
});

/// 내 전 그룹에 공유돼 있는 원본 기프티콘 id 집합. **판정용 정본.**
///
/// 그룹 목록과 그룹별 공유 스트림이 **모두** 값을 낸 뒤에만 [AsyncData]가 된다. 하나라도
/// 로딩이면 [AsyncLoading], 에러면 그 에러를 전파한다(파일 상단 fail-closed 절 참조).
final sharedGifticonIdsProvider = Provider<AsyncValue<Set<String>>>((ref) {
  final AsyncValue<List<Group>> groupsAsync = ref.watch(myGroupsProvider);
  final List<Group>? groups = groupsAsync.valueOrNull;
  if (groups == null) {
    // 값이 없는 상태를 그대로 옮긴다. `whenData`를 못 쓰는 것은 아래에서 그룹마다
    // 스트림을 하나씩 더 `watch`해야 하기 때문이다(중첩 AsyncValue 평탄화).
    return groupsAsync.hasError
        ? AsyncValue<Set<String>>.error(
            groupsAsync.error!,
            groupsAsync.stackTrace ?? StackTrace.empty,
          )
        : const AsyncValue<Set<String>>.loading();
  }

  final Set<String> ids = <String>{};
  for (final Group g in groups) {
    final AsyncValue<List<SharedGifticon>> perGroup =
        ref.watch(sharedGifticonsProvider(g.id));
    final List<SharedGifticon>? list = perGroup.valueOrNull;
    if (list == null) {
      return perGroup.hasError
          ? AsyncValue<Set<String>>.error(
              perGroup.error!,
              perGroup.stackTrace ?? StackTrace.empty,
            )
          : const AsyncValue<Set<String>>.loading();
    }
    for (final SharedGifticon s in list) {
      ids.add(s.gifticonId);
    }
  }
  return AsyncValue<Set<String>>.data(ids);
});
