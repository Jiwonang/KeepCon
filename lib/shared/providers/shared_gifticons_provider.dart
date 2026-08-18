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
///
/// ## 수명 = autoDispose (의도) — **다만 절반만 놓아준다**
/// 주 소비자인 기프티콘 상세는 **일회성 플로우**다 — 카드를 눌러 바코드를 보고 닫는다.
/// keepAlive로 두면 이 provider가 [myGroupsProvider]를 붙잡아 `watchGroups` 구독이 앱
/// 수명 동안 잔존한다. 그것이 정확히 [myGroupsProvider]가 `autoDispose`인 이유이고
/// (그 파일의 "수명 설계 근거" 1항 — scan을 예로 든 같은 함정), 상세는 scan보다 훨씬 자주
/// 열린다. 그래서 이쪽도 `autoDispose`로 둔다.
///
/// ⚠️ **놓아주는 것은 [myGroupsProvider] 축뿐이다.** 이 provider가 그룹마다 `watch`하는
/// [sharedGifticonsProvider]는 `autoDispose`가 아닌 family라, 한 번 만들어진 인스턴스는
/// 리스너가 모두 떨어져도 스스로 dispose되지 않는다 — 즉 **상세를 한 번 열면 그룹 수만큼의
/// `watchSharedGifticons` 리스너는 앱이 끝날 때까지 남는다.** 여기서 `autoDispose`가 그것까지
/// 막아 준다고 읽지 말 것(주석이 실제보다 앞서가면 다음 사람이 다시 확인하지 않는다).
///
/// 그 축을 정말 닫으려면 [sharedGifticonsProvider] 자체를 `autoDispose`로 바꿔야 하는데,
/// share 도메인이 **non-autoDispose임을 전제로** 짜여 있어(예:
/// [retryFailedSharedGifticonStreams]의 "탈퇴한 그룹의 스테일 인스턴스" 주석,
/// `test/features/share/share_error_ui_test.dart`의 재시도 고정) 이 파일만 고쳐서 될 일이
/// 아니다. share 재검증을 포함한 별건으로 다룬다.
///
/// share 탭 자체의 체감 수명은 승격 전과 같다 — 그 페이지의 keepAlive 파생들이 정본을
/// 계속 붙잡는다.
final sharedGifticonIdsProvider =
    Provider.autoDispose<AsyncValue<Set<String>>>((ref) {
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

/// 에러인 그룹별 공유 스트림 인스턴스만 재구독한다(내 **현재** 그룹 범위).
///
/// family 전체 invalidate를 쓰지 않는 이유 둘: ① 실패하지 않은 그룹의 Firestore 리스너까지
/// 재시작돼 문서 읽기·과금이 그룹 수만큼 늘고(재시도가 필요한 건 에러 인스턴스뿐이다),
/// ② non-autoDispose family라 탈퇴한 그룹의 스테일 인스턴스도 재실행돼 비멤버 구독
/// (permission-denied)을 되살린다.
void retryFailedSharedGifticonStreams(WidgetRef ref) {
  final List<Group> groups =
      ref.read(myGroupsProvider).valueOrNull ?? const <Group>[];
  for (final Group g in groups) {
    if (ref.read(sharedGifticonsProvider(g.id)).hasError) {
      ref.invalidate(sharedGifticonsProvider(g.id));
    }
  }
}

/// 공유 여부 판정 경로([sharedGifticonIdsProvider])의 **수동** 재시도.
///
/// 판정은 그룹 목록 × 그룹별 공유 스트림을 가로지르므로 실패 원인이 두 축 중 어느 쪽이든
/// 될 수 있다. 두 축을 함께 되살리되, 각 축은 **에러인 계층만** 재구독한다
/// (계약 [retryMyGroups] + [retryFailedSharedGifticonStreams]).
///
/// ## 왜 이 훅이 반드시 있어야 하는가
/// [sharedGifticonIdsProvider]는 fail-closed다 — 확정 전에는 소비자가 액션을 막는다. 그런데
/// [StreamProvider]는 스스로 재구독하지 않고 [sharedGifticonsProvider]는 non-autoDispose라,
/// **콜드 스타트에서 한 번 실패하면 그 에러가 캐시된 채 남는다.** 재시도 경로가 없으면
/// 통신이 회복돼도 앱을 껐다 켜기 전까지 액션이 영구히 막힌다.
///
/// ## ⚠️ 사용자 액션에서만 호출할 것 (자동 재시도 금지 — #13)
/// `build`/`listen`에서 에러를 감지해 자동으로 부르면 장애 중 모든 화면이 동시에
/// 재구독하는 retry storm이 된다. 호출 지점은 버튼 콜백뿐이다.
void retrySharedGifticonIds(WidgetRef ref) {
  retryMyGroups(ref);
  retryFailedSharedGifticonStreams(ref);
}
