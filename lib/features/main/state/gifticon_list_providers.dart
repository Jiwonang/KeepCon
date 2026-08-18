/// main 페이지 — 기프티콘 목록 상태(Riverpod).
///
/// 파이프라인:
///   1. [sessionUserProvider]      : **세션 계약 정본**(`lib/shared/providers/session_provider.dart`)
///                                   → 현재 User? (main은 자체 세션 구독을 열지 않는다)
///   2. [rawGifticonsProvider]     : 정본에서 **id만 `select`** 해 watchGifticons(uid) 구독 → 원천 목록
///   3. [sortOptionProvider]/[filterProvider] : UI가 고른 정렬/필터(계약 enum)
///   4. [visibleGifticonsProvider] : 원천 목록에 필터→정렬을 적용한 최종 표시 목록
///
/// 계약 준수:
/// - 세션은 계약 정본 [sessionUserProvider]를 소비한다. 승격 전에는 이 파일이
///   `currentUserProvider`로 [AuthRepository.watchCurrentUser]를 **직접 구독**해, 같은
///   스트림이 정본과 별도 인스턴스로 한 번 더 열렸다(매트릭스 #13 잔여 소비자). 인스턴스가
///   갈리면 계정 전환 프레임에서 main과 share/그룹 목록이 한 프레임 어긋나고, 세션 실패 시
///   캐시된 에러가 소스마다 생겨 재시도가 절반만 먹힌다. 별칭(재export shim)을 남기지 않고
///   **선언 삭제 + 정본 직수입**으로 옮겼다(#13 규약).
/// - 조회는 계약 시그니처 그대로 구독: watchGifticons(String ownerId).
/// - 정렬/필터는 소비자(main)에서 수행(계약 매트릭스 3항). Repository엔 정렬 파라미터 요구 안 함.
/// - scan이 추가/변경하거나 share가 상태 동기화하면 watchGifticons 스트림이 새 목록을 방출 →
///   [visibleGifticonsProvider]가 자동 재계산되어 화면에 반영된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';
import '../../../shared/providers/session_provider.dart';
import 'gifticon_filter.dart';
import 'gifticon_sorter.dart';
import 'now_provider.dart';

/// 현재 사용자의 원천 기프티콘 목록.
///
/// 세션 정본 [sessionUserProvider]에서 **사용자 id만** 읽어
/// GifticonRepository.watchGifticons(ownerId)를 구독한다.
/// 미로그인(null)이면 빈 목록 스트림을 방출한다.
///
/// **왜 `select`로 좁히는가.** 이 provider가 세션에서 쓰는 값은 id 하나뿐인데, 정본은
/// [StreamProvider]라 값이 같은 data→data 재방출도 무조건 통지한다(riverpod 2.6.1
/// `handleUpdateShouldNotify`). 통째로 watch하면 세션이 재방출될 때마다 create가 재실행돼
/// **`watchGifticons` 스트림이 teardown/재수립**된다 — share의 `select` 6곳은 재계산이
/// 끝이지만 이쪽은 Firestore 목록 리스너를 끊었다 붙이는 것이라 쿼리가 통째로 다시 읽힌다.
/// 실제 트리거는 가설이 아니다: `userChanges()`의 토큰 갱신(약 1시간)과 **mypage 프로필
/// 편집**(`updateDisplayName` + `reload` → **같은 uid·다른 displayName** 재방출)이다.
/// 후자는 승격 전 `currentUserProvider`의 `==` 필터로도 걸러지지 않던 경로라, id 기준
/// `select`가 엄격히 낫다(QA v2.7 [medium 1]).
///
/// 폴딩 의미는 좁히기 전과 **동일**하다 — `valueOrNull == null` ⇔ `uid == null`
/// (로딩·미로그인 확정·값 없는 에러 3경우 모두 일치). `.value`가 아니라 **`valueOrNull`**
/// 인 것도 그대로다(#13 규약): `.value`는 이전 값이 없는 [AsyncError]에서 rethrow하고,
/// `valueOrNull`은 순단 에러가 `copyWithPrevious`로 보존한 이전 사용자를 돌려주므로
/// **세션이 잠깐 끊겨도 목록이 사라지지 않는다**.
final rawGifticonsProvider = StreamProvider<List<Gifticon>>((ref) {
  final String? uid = ref.watch(
    sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
  );
  if (uid == null) {
    return Stream<List<Gifticon>>.value(const <Gifticon>[]);
  }
  final repo = ref.watch(gifticonRepositoryProvider);
  return repo.watchGifticons(uid);
});

/// 현재 선택된 정렬 옵션(계약 [SortOption]). 기본값: 만료임박순.
final sortOptionProvider =
    StateProvider<SortOption>((ref) => SortOption.expiryAsc);

/// 현재 활성 필터 상태(상태별/카테고리별/만료임박/검색어). 기본값: 필터 없음.
///
/// **계정이 바뀌면 스스로 초기화한다.** 이 provider는 앱 수명 내내 살아 있어 로그아웃해도
/// 값이 남는데, 필터 값 중 카테고리와 검색어는 *그 사용자의 기프티콘*에서 온 것이라
/// 다음 사용자에게는 의미가 없다. 남겨 두면 두 가지가 깨진다:
/// - 새 사용자가 이유 없이 걸러진 목록을 본다(자기가 건 적 없는 필터라 원인을 못 찾는다).
/// - 정렬/필터 시트의 카테고리 드롭다운이 **선택지에 없는 값**을 받아 `DropdownButton`
///   단언으로 죽는다(선택지는 새 사용자의 목록에서 파생되므로 옛 카테고리가 없다).
///
/// 두 번째는 시트 쪽에서도 "선택지에 없으면 전체로 접기"로 막아 두었지만, 그건 증상
/// 차단이다. 값이 계정 경계를 넘지 않게 하는 것이 원인 쪽 수정이다.
final filterProvider = StateProvider<GifticonFilter>((ref) {
  ref.listen<String?>(
    sessionUserProvider.select((AsyncValue<User?> s) => s.valueOrNull?.id),
    (String? previous, String? next) {
      if (previous != next) ref.controller.state = GifticonFilter.none;
    },
  );
  return GifticonFilter.none;
});

/// 원천 목록에서 도출한, 현재 사용자의 모든 카테고리(중복 제거·정렬).
///
/// 카테고리 필터 드롭다운의 선택지로 쓴다. 원천 목록에서 계약 [Gifticon.category]만 참조.
final availableCategoriesProvider = Provider<List<String>>((ref) {
  final List<Gifticon> raw =
      ref.watch(rawGifticonsProvider).valueOrNull ?? const [];
  final Set<String> cats = <String>{for (final g in raw) g.category};
  final List<String> sorted = cats.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return sorted;
});

/// 최종 표시 목록 = 원천 목록에 필터 적용 후 정렬 적용.
///
/// 원천 목록이 로딩/에러일 때 그 상태를 그대로 전파한다(UI가 스피너/에러를 표시).
final visibleGifticonsProvider = Provider<AsyncValue<List<Gifticon>>>((ref) {
  final AsyncValue<List<Gifticon>> rawAsync = ref.watch(rawGifticonsProvider);
  final GifticonFilter filter = ref.watch(filterProvider);
  final SortOption sort = ref.watch(sortOptionProvider);

  // 시각은 [nowProvider] 정본에서 받는다. 항목마다 읽으면 자정을 넘기는 순간 같은 목록
  // 안에서 "오늘"이 갈리고, 여기서 따로 읽으면 배너 목록과 이 목록이 갈린다 —
  // 둘 다 같은 값을 봐야 "배너가 센 개수 == 필터가 남긴 목록"이 성립한다.
  final DateTime now = ref.watch(nowProvider);

  return rawAsync.whenData((List<Gifticon> raw) {
    final List<Gifticon> filtered = raw
        .where((Gifticon g) => filter.matches(g, now: now))
        .toList(growable: false);
    return sortGifticons(filtered, sort);
  });
});
