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
SSOT_PROVIDERS="nowProvider|allNotificationsProvider|rawGifticonsProvider|notificationsProvider|notificationsReadAtProvider|unreadNotificationCountProvider|authRepositoryProvider|gifticonRepositoryProvider|shareRepositoryProvider|themeModeProvider|myGroupsProvider|myGroupsRetryProvider|sessionUserProvider|errorReporterProvider|inviteOriginProvider"

# 선택적 `late`, 선택적 타입(`Provider<T> ` 등)을 포괄해 `final NAME =`,
# `late final NAME =`, `final Provider<T> NAME =` 형태를 모두 잡는다.
# 이름 앞 `_?`는 **SSOT 이름의 언더스코어 접두 사본**(`final _sessionUserProvider = ...`)을
# 잡기 위한 것이다. ⚠️ 한계: 이 가드는 이름 기반이라 **다른 이름의 의미상 중복**
# (예: 과거의 `_currentUserProvider`·`_scanCurrentUserProvider`처럼 정본과 이름이 다른
# 세션 체인 재조립)은 잡지 못한다 — 그 방어선은 리뷰와 매트릭스의 잔여 소비자 표다.
prov=$(scan "^[[:space:]]*(late[[:space:]]+)?final[[:space:]]+([A-Za-z0-9_<>,.? ]+[[:space:]]+)?_?(${SSOT_PROVIDERS})[[:space:]]*=") || exit 1
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
SSOT_FUNCTIONS="planExpiryNotifications|firedExpiryNotifications|retryNotifications|retrySessionIfFailed|retryMyGroups|foldSessionUser|daysUntilExpiry|isExpiringSoon|isExpiredByDate|inviteUrlFrom|inviteOriginFor|parseInviteToken|isSharableOrigin|newInviteToken|newInviteCode|isWellFormedInviteCode"

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
fns_untyped=$(scan "^[[:space:]]{0,2}(static[[:space:]]+)?_?(${SSOT_FUNCTIONS})(<[^>]*>)?[[:space:]]*\([^;]*\)[[:space:]]*(async[[:space:]]*)?(\{|=>)") || exit 1
fns="${fns_typed}${fns_untyped:+
$fns_untyped}"
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
if [ -n "$consts" ]; then
  echo "::error::[SSOT] 계약 상수를 lib/features에서 재선언했습니다. lib/shared 정본을 import해 참조만 하세요:"
  echo "$consts"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "규약(CLAUDE.md): 공유 모델·인터페이스·enum·provider는 lib/shared 단일 정의만 사용한다. 페이지 내부 재정의 금지."
  exit 1
fi

echo "SSOT guard: 위반 없음 ✓"
