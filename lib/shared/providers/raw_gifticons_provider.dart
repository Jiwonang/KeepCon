/// KeepCon 공유 계약 — 현재 사용자의 원천 기프티콘 목록 provider (SSOT).
///
/// main 페이지 전용이던 것을 승격했다. 이 체인의 소비자가 페이지 밖으로 두 번 나갔기
/// 때문이다 — 앱 조립부의 만료 알림 동기화(`lib/app/expiry_notification_sync.dart`)가
/// 예약을 다시 계산하려고 이미 이것을 구독하고 있었고, 알림 센터가 **이미 울린** 만료
/// 알림을 복원하려면 계약 계층(`lib/shared`)에서도 같은 목록이 필요해졌다.
///
/// 계약이 페이지를 향해 거꾸로 의존할 수는 없으므로(`lib/shared` → `lib/features` 금지)
/// 선언이 이쪽으로 와야 한다. 공개 이름은 `rawGifticonsProvider` 그대로 둔다 — 소비처
/// 20여 곳의 호출을 바꿔 얻는 것이 없다(v2.5 승격이 "공개 이름 불변"으로 간 것과 같은 판단).
///
/// **"raw"의 뜻:** 필터·정렬이 걸리지 않은 원천 목록이다. 화면용 파생
/// (`visibleGifticonsProvider` 등)은 페이지가 이것 위에 얹는다.
///
/// ⚠️ share 페이지의 공유 후보 체인(`shareableGifticonsProvider`)은 **합치지 않았다.**
/// 그쪽은 `foldSessionUser` 규약으로 세션 순단에 로딩/에러를 보존하는데, 이 provider는
/// uid가 없으면 빈 목록을 방출한다 — 합치면 세션이 잠깐 끊긴 것만으로 공유 시트에
/// "후보 없음"이 뜬다(share QA [medium 1]이 막아 둔 경로). 같은 사용자에 대해
/// `watchGifticons` 구독이 둘인 상태가 남지만, 그것을 없애려면 폴딩 규약을 먼저
/// 통일해야 하므로 별도 작업이다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/gifticon.dart';
import '../models/user.dart';
import 'repositories.dart';
import 'session_provider.dart';

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
