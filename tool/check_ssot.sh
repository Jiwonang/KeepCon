#!/usr/bin/env bash
# SSOT guard — 공유 계약(lib/shared)에만 있어야 할 정의가 lib/features에서
# 재정의/재선언되는 것을 기계적으로 차단한다.
#
# 배경: `flutter analyze`는 공유 타입을 "잘못 호출"하면 잡아주지만,
# 페이지 폴더에 같은 이름의 모델/enum/provider를 "새로 정의"하는 것은
# 문법상 컴파일되어 통과한다. 이것이 승격 전 `Group`이 페이지마다 분산됐던
# 문제의 재발 경로다. 이 가드가 그 구멍을 CI에서 막는다. (CLAUDE.md 핵심 규약)
set -uo pipefail

FEATURES_DIR="lib/features"
fail=0

if [ ! -d "$FEATURES_DIR" ]; then
  echo "SSOT guard: $FEATURES_DIR 없음 — 스킵"
  exit 0
fi

# grep 래퍼 — exit 0(매칭)·1(매칭 없음)은 정상, **2 이상(파일/정규식 오류)은 가드 실패**다.
# `|| true`로 뭉개면 스캔 자체가 죽어도 "위반 없음 ✓"로 통과하는 침묵 실패가 된다.
scan() {
  local out st
  out=$(grep -rEn "$1" "$FEATURES_DIR" 2>&1)
  st=$?
  if [ "$st" -ge 2 ]; then
    echo "::error::[SSOT] grep 실행 오류(exit $st): $out" >&2
    return 2
  fi
  printf '%s' "$out"
  return 0
}

# 1) 공유 모델/enum/인터페이스 재정의 금지 (lib/shared 정본만 사용)
#
# `InlineErrorBanner`(`lib/shared/widgets/`)를 넣은 근거 — 이 목록의 유일한 위젯이다.
# 위젯이라서가 아니라 **행위 계약을 실어 나르기 때문에** 넣는다: 자동 재시도 금지
# (장애 중 전 화면 재구독 = retry storm, #13), 내부 예외 메시지 비노출, `onRetry`가
# null일 때 복구 안내 접미를 배너가 스스로 붙이는 분기. 사본은 이 셋을 **컴파일러에
# 안 잡힌 채** 떨어뜨리고, 그 결과가 정확히 이 가드가 막으려는 종류의 경계면 버그다.
# 타이밍도 지금이다 — 승격 직후 main·auth의 raw 예외 노출(`'$e'`) 교체가 예정돼 있어,
# "그냥 내 배너 하나 만들자"가 실제로 일어날 창이 열려 있다. 헤더 doc이 승격 전부터
# "새 배너를 만들지 말고 승격을 요청할 것"이라고 적어 뒀지만 그건 문서일 뿐 게이트가
# 아니었고, PR #116에서 신규 공유 타입을 이 목록에 빠뜨려 우회가 실제로 CI를 통과한
# 전례가 있다.
# ⚠️ 한계(provider 항목과 같다): 이름 기반이라 **다른 이름의 사본**(`_MainErrorBanner`)은
# 못 잡는다. 그리고 `lib/shared/widgets/`의 나머지 위젯(`NotificationBell` 등)은 아직
# 등록돼 있지 않다 — 그것들은 행위 계약이 아니라 표시 조각이라 우선순위가 낮다.
# ⚠️ 한계 2(별건으로 남김 — 줄바꿈 우회와 결함 종류가 다르다): 아래 목록의
# `ShareStatusTransition`·`GifticonStatusTransition`은 정본이 `extension`이라 이 규칙의
# `(class|enum|mixin)`에 **도달하지 않는다** — 페이지가 같은 이름의 extension을 선언해도
# 통과한다. 그리고 `MyGifticon`은 lib/shared에 정본이 없는 죽은 이름이다. 고칠 때는
# 키워드에 `extension`을 더하고 죽은 이름을 지운다(이름만 올려 두면 막았다고 착각한다).
SHARED_TYPES="AppNotification|GroupNotificationItem|ExpiryNotificationItem|ScheduledExpiryNotification|Group|GroupMember|SharedGifticon|UsageLog|GroupNotification|MyGifticon|Gifticon|User|JoinRequest|ShareStatus|MemberRole|JoinRequestStatus|GroupNotificationType|GifticonStatus|SortOption|FilterOption|ShareStatusTransition|GifticonStatusTransition|ShareRepository|GifticonRepository|AuthRepository|MyGroupsRetry|ErrorReporter|InviteExpiredException|JoinRequestUnreadableException|InlineErrorBanner"

# 선행 수식어 `([a-z]+ )*`로 Dart 3 클래스 수식어를 모두 포괄한다:
# abstract/base/interface/final/sealed/mixin(및 조합, 예: `abstract interface class`,
# `final class`, `sealed class`, `mixin class`). enum/mixin 선언도 포함.
# 이름 앞 `_?`는 **private 복제**(`class _Group`)까지 잡기 위한 것이다 — 페이지 안에서만
# 쓰는 복제라도 정본과 갈라지는 순간 경계면 버그가 된다. `_UserTile` 같은 무관한 이름은
# 뒤의 `\b` 때문에 매칭되지 않는다.
defs=$(scan "^[[:space:]]*([a-z]+[[:space:]]+)*(class|enum|mixin)[[:space:]]+_?(${SHARED_TYPES})\b") || exit 1
if [ -n "$defs" ]; then
  echo "::error::[SSOT] 공유 계약 타입을 lib/features에서 재정의했습니다. lib/shared의 정본만 import하세요:"
  echo "$defs"
  fail=1
fi

# 2) SSOT provider 재선언 금지 (소비 ref.watch(...)는 허용, 선언은 금지)
SSOT_PROVIDERS="nowProvider|allNotificationsProvider|rawGifticonsProvider|notificationsProvider|notificationsReadAtProvider|unreadNotificationCountProvider|authRepositoryProvider|gifticonRepositoryProvider|shareRepositoryProvider|themeModeProvider|myGroupsProvider|myGroupsRetryProvider|sharedGifticonsProvider|allSharedProvider|sharedGifticonIdsProvider|sessionUserProvider|errorReporterProvider|inviteOriginProvider|pendingDestinationProvider|expiryNotificationSchedulerProvider"

# 선택적 `late`, 선택적 타입(`Provider<T> ` 등)을 포괄해 `final NAME =`,
# `late final NAME =`, `final Provider<T> NAME =` 형태를 모두 잡는다.
# 이름 앞 `_?`는 **SSOT 이름의 언더스코어 접두 사본**(`final _sessionUserProvider = ...`)을
# 잡기 위한 것이다. ⚠️ 한계: 이 가드는 이름 기반이라 **다른 이름의 의미상 중복**
# (예: 과거의 `_currentUserProvider`·`_scanCurrentUserProvider`처럼 정본과 이름이 다른
# 세션 체인 재조립)은 잡지 못한다 — 그 방어선은 리뷰와 매트릭스의 잔여 소비자 표다.
prov=$(scan "^[[:space:]]*(late[[:space:]]+)?final[[:space:]]+([A-Za-z0-9_<>,.? ]+[[:space:]]+)?_?(${SSOT_PROVIDERS})[[:space:]]*=") || exit 1

# ⚠️ 위 규칙은 `final`과 이름이 **한 줄에** 있을 때만 잡는다. 긴 타입 주석이 붙으면
# `dart format`이 타입 뒤에서 줄을 끊어 이름을 다음 줄로 내린다:
#     final AutoDisposeStreamProviderFamily<List<GroupNotification>, String>
#         notificationsProvider = StreamProvider.family...
# 이름이 있는 줄에는 `final`이 없으니 위 규칙이 통과시킨다. CI가 `dart format`을
# 강제하므로 **긴 타입의 재선언은 예외가 아니라 기본형**이다 — 즉 이 구멍은 드물게
# 밟는 것이 아니라 타입을 길게 쓰기만 하면 항상 열린다(등록된 이름으로 실측 확인).
# 그래서 "줄의 첫 토큰이 SSOT 이름이고 곧바로 `=`"인 이어지는 줄도 함께 잡는다.
#  - 들여쓰기를 제한하지 않는 이유: 이어지는 줄의 들여쓰기는 **포매터 스타일에 따라
#    달라지고, 그 스타일은 언어 버전이 고른다.** 이 저장소는 `pubspec.yaml`의
#    `sdk: ">=3.6.0"`이라 구 스타일이고 실측하면 최상위 4칸·클래스 멤버 6칸인데,
#    제약을 3.7 이상으로 올리면 신(tall) 스타일이 되어 같은 코드가 0칸·2칸이 된다
#    (같은 파일을 패키지 안·밖에서 포맷해 두 결과를 모두 확인했다 — 패키지 밖에서
#    잰 값을 저장소 값으로 착각하기 쉽다). 즉 들여쓰기는 불변식이 아니고, 숫자를
#    박으면 SDK 제약을 올리는 날 조용히 뚫린다.
#  - 소비는 매칭되지 않는다 — `ref.watch(notificationsProvider)`는 이름 앞에 다른
#    토큰이 있고, 인자가 줄바꿈된 경우도 이름 뒤가 `=`가 아니라 `)`/`,`다.
#  - `([^=>]|$)`는 `==` 비교와 `=>`를 걸러낸다. `=>`를 빼는 이유는 Dart 3 switch 식의
#    상수 패턴(`expirySoonDays => ...` — 정상 소비)이 오탐으로 걸리기 때문이다(실측).
#    선언의 이어지는 줄은 언제나 `NAME = <초기화식>`이라 참 양성 손실이 없다.
#    줄 끝에서 끊긴 `NAME =`은 `$`가 그대로 잡는다.
prov_wrapped=$(scan "^[[:space:]]*_?(${SSOT_PROVIDERS})[[:space:]]*=([^=>]|\$)") || exit 1
if [ -n "$prov_wrapped" ]; then
  prov="${prov:+$prov
}$prov_wrapped"
fi

if [ -n "$prov" ]; then
  echo "::error::[SSOT] SSOT provider를 lib/features에서 재선언했습니다. lib/shared/providers/ 정본을 import해 소비만 하세요:"
  echo "$prov"
  fail=1
fi

# 3) SSOT 함수(계약 API) 재정의 금지 — 호출은 허용, 선언은 금지
#
# `daysUntilExpiry|isExpiringSoon|isExpiredByDate`를 넣은 근거: 승격 전 이 계산이
# lib/features 안에 **네 벌** 있었고(통계·그리드 카드·리치 카드·홈 배너), 그중 하나는
# 시분초를 절삭해 같은 기프티콘을 두고 화면과 통계가 다른 답을 냈다. 가정이 아니라
# 이미 발생한 재발이라 기계적 가드에 넣는다. 만료 임박 알림이 이 판정 위에 올라가므로
# 재분기하면 알림까지 어긋난다.
SSOT_FUNCTIONS="planExpiryNotifications|firedExpiryNotifications|retryNotifications|retrySessionIfFailed|retryMyGroups|retryFailedSharedGifticonStreams|retrySharedGifticonIds|foldSessionUser|daysUntilExpiry|isExpiringSoon|isExpiredByDate|inviteUrlFrom|inviteOriginFor|parseInviteToken|isSharableOrigin|newInviteToken|newInviteCode|isWellFormedInviteCode"

# 선언 형태 두 갈래를 잡는다(호출 `retryMyGroups(ref);`·`return foldSessionUser<...>(...)`는
# 둘 다 통과):
#  3a) 반환 타입이 앞서는 선언 — 선택적 `static`, `void/dynamic/소문자 내장 타입
#      (bool·int·double·num·String·Object)/Future<...>/Stream<...>/대문자 시작 타입`,
#      선택적 제네릭 파라미터(`foldSessionUser<T>(`)까지 포괄. `return`/`await` 같은
#      제어 키워드는 타입 후보에 없어 호출문이 매칭되지 않는다(내장 타입 키워드가
#      호출문 앞에 오는 문법은 없다).
#  3b) 반환 타입을 생략한 선언 — 이름으로 시작해 파라미터 뒤 `{`/`=>`로 이어지는 줄.
#      선택적 `static`을 허용한다: `static isExpiringSoon(...) {`처럼 **static이면서
#      반환 타입도 생략한** 클래스 멤버는 3a(타입이 있어야 매칭)와 이 규칙 사이로
#      빠져나간다. 최상위 함수에는 static을 붙일 수 없으므로 이 조합은 클래스 멤버뿐이다.
#      본문 앞의 `async`/`sync`는 `*`까지 받는다 — `async* {`는 `async` 뒤가 `*`라
#      `{`에 못 닿고 그룹을 비워도 `a`에서 막혀, 제너레이터 재정의가 통째로 빠져나갔다.
#      들여쓰기를 **0~2칸으로 제한**한다(최상위 함수 0칸·클래스 멤버 2칸). CI가
#      `dart format`을 강제하므로 이 들여쓰기는 신뢰할 수 있는 불변식이다.
#      제한이 없으면 여러 줄에 걸친 **호출**이 선언으로 오인된다 — 예를 들어
#        if (g.status == GifticonStatus.available &&
#            isExpiringSoon(g.expiryDate, now: now)) {
#      의 둘째 줄은 `이름(...) {` 형태라 규칙에 걸리지만 선언이 아니다(닫는 괄호가
#      하나 더 있다 = 바깥 `if (`의 것). 깊은 들여쓰기라 이 제한으로 걸러진다.
# ⚠️ 한계: 파라미터가 여러 줄에 걸친 선언·클래스 내부의 들여쓰기 없는 특수 배치는
# 줄 단위 정규식 밖이다 — 완전 강제가 아니라 흔한 실수 형태의 백스톱이다.
fns_typed=$(scan "^[[:space:]]*(static[[:space:]]+)?(void|dynamic|bool|int|double|num|String|Object|Future<[^>]*>|Stream<[^>]*>|[A-Z][A-Za-z0-9_<>,.? ]*)\??[[:space:]]+_?(${SSOT_FUNCTIONS})(<[^>]*>)?[[:space:]]*\(") || exit 1
fns_untyped=$(scan "^[[:space:]]{0,2}(static[[:space:]]+)?_?(${SSOT_FUNCTIONS})(<[^>]*>)?[[:space:]]*\([^;]*\)[[:space:]]*((async|sync)\*?[[:space:]]*)?(\{|=>)") || exit 1

# 3c) 가드 #2·#4와 **같은 줄바꿈 우회**가 여기에도 있다. 반환 타입이 줄 폭을 넘으면
#     `dart format`이 타입 뒤에서 끊어 이름을 다음 줄로 내리는데(이 저장소 스타일에서
#     최상위 4칸·클래스 멤버 6칸), 그 줄에는 타입이 없어 3a가, 들여쓰기가 3칸 이상이라
#     3b가 각각 통과시킨다(실측 — `retrySharedGifticonIds` 재정의가 exit 0이었다).
#     3b의 0~2칸 제한은 그대로 둔다(한 줄짜리 참 양성이 거기 걸려 있다). 대신 3칸 이상
#     전용 규칙을 더하고, 3b가 들여쓰기를 조여서 막던 "여러 줄 호출 오인"은 여기서
#     꼬리를 앵커해 대신 막는다:
#      - 파라미터의 괄호를 **한 겹까지만** 허용한다(`void Function() onDone` 같은
#        함수형 파라미터가 실재한다 — 3b는 `[^;]*`라 받는데 3c만 못 받으면, 시그니처가
#        길어 줄바꿈되는 상황과 괄호가 끼는 상황이 겹치는 구간에서 되레 약해진다).
#        여러 줄 호출을 거르는 실제 근거는 중첩 배제가 아니라 **불균형 닫는 괄호**다 →
#        아래 둘째 줄은 닫는 괄호가 하나 더 있어 걸리지 않는다:
#            if (g.status == GifticonStatus.available &&
#                isExpiringSoon(g.expiryDate, now: now)) {
#      - 꼬리를 **선언이 실제로 취하는 본문 형태**로 못박고 줄 끝을 요구한다:
#        `) {` / `) {}` / `) => 식;` / `) =>`(식이 다음 줄). 줄 끝 앵커가 `list.where((g) =>`
#        같은 람다 인자를 거른다. ⚠️ 처음엔 꼬리를 `(\{|=>)$`로만 뒀는데, 그러면
#        **빈 본문 `) {}`**과 **한 줄 화살표 본문 `) => 식;`**이 통째로 빠져나갔다
#        (프로브로 확인 — 무해해 보이는 앵커가 참 양성을 깎았다).
#     신(tall) 스타일에서는 같은 줄바꿈이 0~2칸으로 나오고 그쪽은 3b가 잡으므로,
#     두 규칙이 두 스타일을 나눠 덮는다(들여쓰기가 겹치지 않아 중복 보고도 없다).
fns_wrapped=$(scan "^[[:space:]]{3,}(static[[:space:]]+)?_?(${SSOT_FUNCTIONS})(<[^>]*>)?[[:space:]]*\(([^;()]*\([^;()]*\))*[^;()]*\)[[:space:]]*((async|sync)\*?[[:space:]]*)?(\{[[:space:]]*\}?|=>[^;]*;?)[[:space:]]*\$") || exit 1

# 셋을 합친다. 앞이 비었을 때 선행 빈 줄이 생기지 않도록 `:+` 이어붙이기 대신
# 조건으로 잇는다 — 기존 형태는 fns_typed가 비면 CI 출력 첫 줄이 빈 줄이었다.
fns="$fns_typed"
for part in "$fns_untyped" "$fns_wrapped"; do
  [ -n "$part" ] || continue
  fns="${fns:+$fns
}$part"
done
if [ -n "$fns" ]; then
  echo "::error::[SSOT] 계약 함수를 lib/features에서 재정의했습니다. lib/shared 정본을 import해 호출만 하세요:"
  echo "$fns"
  fail=1
fi

# 4) SSOT 상수 재선언 금지 — 임계값 사본이 정본과 갈라지는 것을 막는다.
#
# `expirySoonDays`는 승격 전 `gifticon_stats.dart`(공개)와 `gifticon_card.dart`
# (`_expirySoonDays` 사본)에 이중으로 있었다. 상수는 재정의해도 컴파일되고 값이 같으면
# 티도 안 나다가, 한쪽만 바뀌는 순간 조용히 갈라진다.
# 발송 격자(lead days × hour)와 상한은 예약과 복원이 **함께** 보는 값이다. 한쪽에
# 사본이 생기면 푸시와 알림 센터가 서로 다른 시각을 말한다.
SSOT_CONSTANTS="expirySoonDays|expiryNotifyLeadDays|expiryNotifyHour|expiryNotificationHistory|maxScheduledExpiryNotifications"

consts=$(scan "^[[:space:]]*(static[[:space:]]+)?const[[:space:]]+([A-Za-z0-9_<>,.? ]+[[:space:]]+)?_?(${SSOT_CONSTANTS})[[:space:]]*=") || exit 1

# 상수도 같은 줄바꿈 우회가 성립한다(실측: `static const Map<...>` 다음 줄에
# `      expiryNotificationHistory = ...` — **저장소 안에서** 포맷한 값이라 클래스 멤버
# 6칸이다. 2칸은 패키지 밖 tall 스타일 값이다). 근거·한계는 위 provider의 이어지는 줄 규칙과
# 같다. 형제 규칙 중 하나만 막으면 우회가 그쪽으로 옮겨갈 뿐이라 함께 닫는다.
# (가드 #1은 이름이 항상 `class`/`enum` 키워드 뒤에 붙어 이 우회가 성립하지 않는다.
#  가드 #3은 성립해서 3c로 함께 닫았다 — 처음엔 "3b가 이미 잡는다"고 적었는데,
#  패키지 밖에서 잰 들여쓰기(0·2칸)를 저장소 값으로 착각한 오판이었다.)
consts_wrapped=$(scan "^[[:space:]]*_?(${SSOT_CONSTANTS})[[:space:]]*=([^=>]|\$)") || exit 1
if [ -n "$consts_wrapped" ]; then
  consts="${consts:+$consts
}$consts_wrapped"
fi

if [ -n "$consts" ]; then
  echo "::error::[SSOT] 계약 상수를 lib/features에서 재선언(또는 지역 변수·필드로 같은 이름을 가림)했습니다. lib/shared 정본을 import해 참조만 하세요:"
  echo "$consts"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "규약(CLAUDE.md): 공유 모델·인터페이스·enum·provider는 lib/shared 단일 정의만 사용한다. 페이지 내부 재정의 금지."
  exit 1
fi

echo "SSOT guard: 위반 없음 ✓"
