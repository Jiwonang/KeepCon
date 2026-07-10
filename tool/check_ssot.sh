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

# 1) 공유 모델/enum/인터페이스 재정의 금지 (lib/shared 정본만 사용)
SHARED_TYPES="Group|GroupMember|SharedGifticon|UsageLog|GroupNotification|MyGifticon|Gifticon|User|ShareStatus|MemberRole|InviteExpiry|GroupNotificationType|GifticonStatus|SortOption|FilterOption|ShareStatusTransition|GifticonStatusTransition|ShareRepository|GifticonRepository|AuthRepository"

defs=$(grep -rEn "^[[:space:]]*(abstract[[:space:]]+)?(class|enum|mixin)[[:space:]]+(${SHARED_TYPES})\b" "$FEATURES_DIR" 2>/dev/null || true)
if [ -n "$defs" ]; then
  echo "::error::[SSOT] 공유 계약 타입을 lib/features에서 재정의했습니다. lib/shared의 정본만 import하세요:"
  echo "$defs"
  fail=1
fi

# 2) SSOT provider 재선언 금지 (소비 ref.watch(...)는 허용, final 선언은 금지)
SSOT_PROVIDERS="authRepositoryProvider|gifticonRepositoryProvider|shareRepositoryProvider|themeModeProvider"

prov=$(grep -rEn "^[[:space:]]*final[[:space:]]+(${SSOT_PROVIDERS})[[:space:]]*=" "$FEATURES_DIR" 2>/dev/null || true)
if [ -n "$prov" ]; then
  echo "::error::[SSOT] SSOT provider를 lib/features에서 재선언했습니다. lib/shared/providers/ 정본을 import해 소비만 하세요:"
  echo "$prov"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "규약(CLAUDE.md): 공유 모델·인터페이스·enum·provider는 lib/shared 단일 정의만 사용한다. 페이지 내부 재정의 금지."
  exit 1
fi

echo "SSOT guard: 위반 없음 ✓"
