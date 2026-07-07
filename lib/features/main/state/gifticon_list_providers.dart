/// main 페이지 — 기프티콘 목록 상태(Riverpod).
///
/// 파이프라인:
///   1. [currentUserProvider]      : AuthRepository.watchCurrentUser() 구독 → 현재 User?
///   2. [rawGifticonsProvider]     : GifticonRepository.watchGifticons(user.id) 구독 → 원천 목록
///   3. [sortOptionProvider]/[filterProvider] : UI가 고른 정렬/필터(계약 enum)
///   4. [visibleGifticonsProvider] : 원천 목록에 필터→정렬을 적용한 최종 표시 목록
///
/// 계약 준수:
/// - 조회는 계약 시그니처 그대로 구독: watchCurrentUser() / watchGifticons(String ownerId).
/// - 정렬/필터는 소비자(main)에서 수행(계약 매트릭스 3항). Repository엔 정렬 파라미터 요구 안 함.
/// - scan이 추가/변경하거나 share가 상태 동기화하면 watchGifticons 스트림이 새 목록을 방출 →
///   [visibleGifticonsProvider]가 자동 재계산되어 화면에 반영된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/gifticon.dart';
import '../../../shared/models/user.dart';
import '../../../shared/providers/repositories.dart';
import 'gifticon_filter.dart';
import 'gifticon_sorter.dart';

/// 현재 로그인 사용자. AuthRepository.watchCurrentUser()를 반응형으로 구독한다.
final currentUserProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return auth.watchCurrentUser();
});

/// 현재 사용자의 원천 기프티콘 목록.
///
/// 사용자 id로 GifticonRepository.watchGifticons(ownerId)를 구독한다.
/// 미로그인(null)이면 빈 목록 스트림을 방출한다.
final rawGifticonsProvider = StreamProvider<List<Gifticon>>((ref) {
  final User? user = ref.watch(currentUserProvider).value;
  if (user == null) {
    return Stream<List<Gifticon>>.value(const <Gifticon>[]);
  }
  final repo = ref.watch(gifticonRepositoryProvider);
  return repo.watchGifticons(user.id);
});

/// 현재 선택된 정렬 옵션(계약 [SortOption]). 기본값: 만료임박순.
final sortOptionProvider =
    StateProvider<SortOption>((ref) => SortOption.expiryAsc);

/// 현재 활성 필터 상태(상태별/카테고리별). 기본값: 필터 없음.
final filterProvider =
    StateProvider<GifticonFilter>((ref) => GifticonFilter.none);

/// 원천 목록에서 도출한, 현재 사용자의 모든 카테고리(중복 제거·정렬).
///
/// 카테고리 필터 드롭다운의 선택지로 쓴다. 원천 목록에서 계약 [Gifticon.category]만 참조.
final availableCategoriesProvider = Provider<List<String>>((ref) {
  final List<Gifticon> raw = ref.watch(rawGifticonsProvider).value ?? const [];
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

  return rawAsync.whenData((List<Gifticon> raw) {
    final List<Gifticon> filtered =
        raw.where(filter.matches).toList(growable: false);
    return sortGifticons(filtered, sort);
  });
});
