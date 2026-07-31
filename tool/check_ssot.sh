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
SHARED_TYPES="Group|GroupMember|SharedGifticon|UsageLog|GroupNotification|MyGifticon|Gifticon|User|ShareStatus|MemberRole|InviteExpiry|GroupNotificationType|GifticonStatus|SortOption|FilterOption|ShareStatusTransition|GifticonStatusTransition|ShareRepository|GifticonRepository|AuthRepository|MyGroupsRetry"

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
SSOT_PROVIDERS="authRepositoryProvider|gifticonRepositoryProvider|shareRepositoryProvider|themeModeProvider|myGroupsProvider|myGroupsRetryProvider|sessionUserProvider"

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
SSOT_FUNCTIONS="retryMyGroups|foldSessionUser"

# 선언 형태 두 갈래를 잡는다(호출 `retryMyGroups(ref);`·`return foldSessionUser<...>(...)`는
# 둘 다 통과):
#  3a) 반환 타입이 앞서는 선언 — 선택적 `static`, `void/dynamic/소문자 내장 타입
#      (bool·int·double·num·String·Object)/Future<...>/Stream<...>/대문자 시작 타입`,
#      선택적 제네릭 파라미터(`foldSessionUser<T>(`)까지 포괄. `return`/`await` 같은
#      제어 키워드는 타입 후보에 없어 호출문이 매칭되지 않는다(내장 타입 키워드가
#      호출문 앞에 오는 문법은 없다).
#  3b) 반환 타입을 생략한 선언 — 이름으로 시작해 파라미터 뒤 `{`/`=>`로 이어지는 줄.
#      호출문은 `);`로 끝나 매칭되지 않는다.
# ⚠️ 한계: 파라미터가 여러 줄에 걸친 선언·클래스 내부의 들여쓰기 없는 특수 배치는
# 줄 단위 정규식 밖이다 — 완전 강제가 아니라 흔한 실수 형태의 백스톱이다.
fns_typed=$(scan "^[[:space:]]*(static[[:space:]]+)?(void|dynamic|bool|int|double|num|String|Object|Future<[^>]*>|Stream<[^>]*>|[A-Z][A-Za-z0-9_<>,.? ]*)\??[[:space:]]+_?(${SSOT_FUNCTIONS})(<[^>]*>)?[[:space:]]*\(") || exit 1
fns_untyped=$(scan "^[[:space:]]*_?(${SSOT_FUNCTIONS})(<[^>]*>)?[[:space:]]*\([^;]*\)[[:space:]]*(async[[:space:]]*)?(\{|=>)") || exit 1
fns="${fns_typed}${fns_untyped:+
$fns_untyped}"
if [ -n "$fns" ]; then
  echo "::error::[SSOT] 계약 함수를 lib/features에서 재정의했습니다. lib/shared 정본을 import해 호출만 하세요:"
  echo "$fns"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "규약(CLAUDE.md): 공유 모델·인터페이스·enum·provider는 lib/shared 단일 정의만 사용한다. 페이지 내부 재정의 금지."
  exit 1
fi

echo "SSOT guard: 위반 없음 ✓"
