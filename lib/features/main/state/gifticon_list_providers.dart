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
import '../../../shared/providers/raw_gifticons_provider.dart';
import '../../../shared/providers/session_provider.dart';
import 'gifticon_filter.dart';
import 'gifticon_sorter.dart';
import '../../../shared/providers/now_provider.dart';

// 원천 목록 `rawGifticonsProvider`는 계약 정본으로 승격됐다
// (`lib/shared/providers/raw_gifticons_provider.dart`) — 앱 조립부의 만료 알림 동기화에
// 이어 알림 센터의 **파생 만료 알림**까지 소비자가 페이지 밖으로 나갔고, 계약이 페이지를
// 향해 의존할 수는 없기 때문이다. 공개 이름은 그대로라 아래 파생들의 호출은 무수정이다.

/// id로 찾은 기프티콘 한 장. 상세 화면이 소비한다. 없으면 null.
///
/// **[visibleGifticonsProvider]가 아니라 원천 목록([rawGifticonsProvider])에서 찾는다.**
/// 표시 목록은 필터를 통과한 것만 담으므로, 상태 필터('사용가능')가 걸린 채 상세에서
/// 사용 완료를 누르면 그 항목이 표시 목록에서 빠지고 — **보고 있던 화면이 그 자리에서
/// "찾을 수 없어요"로 바뀐다.** 방금 성공한 조작이 오류처럼 읽히는 셈이다. 상세는 목록의
/// 필터·정렬과 무관한 화면이므로 원천을 본다.
///
/// 로딩 중과 부재를 둘 다 null로 접는다. 진입 경로가 목록 카드 탭뿐이라 이 provider를
/// 읽는 시점엔 원천 스트림이 이미 값을 낸 뒤이고, 상세 화면도 진입 시점 스냅샷을
/// 폴백으로 들고 있어 빈 화면이 뜨지 않는다. 알림→상세 직행 같은 콜드 진입이 생기면
/// 그때 로딩을 구분해야 한다.
/// `autoDispose`인 이유: family는 id마다 별도 인스턴스를 만들고, 일반 family는 컨테이너가
/// 사는 동안 그 인스턴스를 모두 붙들고 있다 — 상세를 열어 본 기프티콘 수만큼 구독이
/// 쌓인다. 상세를 닫으면 정리되도록 둔다.
final gifticonByIdProvider =
    Provider.autoDispose.family<Gifticon?, String>((ref, String id) {
  final List<Gifticon> raw =
      ref.watch(rawGifticonsProvider).valueOrNull ?? const <Gifticon>[];
  for (final Gifticon g in raw) {
    if (g.id == id) return g;
  }
  return null;
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
