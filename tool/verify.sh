#!/usr/bin/env bash
# KeepCon — 푸시 전 로컬 검증을 **명령 하나로**.
#
# 왜 필요한가:
#   CI가 보는 것들을 로컬에서도 돌리는 건 원래 하던 일이다. 문제는 **어떤 것을 돌릴지
#   매번 사람이 판단했다는 것**이다. 특히 `Firestore rules`는 "규칙을 바꿨을 때만" 돌리는
#   조건부라, PR #104에서 규칙을 세 번 고치는 동안 세 번 다 건너뛰었다 — 그 결과 규칙이
#   자기 픽스처를 깨거나(요청 시각 제한), 없는 문서 접근이 403이 되어 정리 경로가 통째로
#   죽는 결함이 매번 **다음 리뷰 라운드에 가서야** 드러났다.
#
#   그래서 판단을 없앤다. 이 스크립트는 항상 같은 것을 돌리고, `firestore.rules`가
#   바뀌었으면 규칙 검증을 **자동으로** 덧붙인다.
#
# 실행:
#   bash tool/verify.sh              # develop 기준으로 변경 감지
#   BASE=origin/main bash tool/verify.sh
#   SKIP_RULES=1 bash tool/verify.sh # 규칙 검증만 건너뛴다(에뮬레이터가 없을 때)
#
# 종료 코드: 하나라도 실패하면 1. 실패해도 나머지는 끝까지 돌린다 — 한 번에 다 보는 것이
#   이 스크립트의 목적이고, 첫 실패에서 멈추면 왕복이 늘어난다.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

BASE="${BASE:-origin/develop}"
fail=0
declare -a failed=()

step() {
  echo
  echo "▶ $1"
}

run() {
  local label="$1"
  shift
  if "$@"; then
    echo "  ✓ ${label}"
  else
    echo "  ✗ ${label}"
    fail=1
    failed+=("${label}")
  fi
}

# ── 항상 도는 것 — CI `Format · Analyze · Test`와 같은 축 ────────────────
step "dart format"
run "dart format" dart format --output=none --set-exit-if-changed .

step "flutter analyze"
run "flutter analyze" flutter analyze

step "flutter test"
run "flutter test" flutter test

step "SSOT guard"
run "SSOT guard" bash tool/check_ssot.sh

step "Markdown lint"
run "Markdown lint" npx --yes markdownlint-cli2@0.18.1 "**/*.md"

# ── 조건부 — 규칙이 바뀌었으면 반드시 ────────────────────────────────────
# 커밋된 변경(BASE 대비)과 아직 커밋 안 된 변경을 **둘 다** 본다. 커밋 전에 돌리는
# 경우가 흔하므로 한쪽만 보면 그 판단이 다시 사람에게 돌아온다.
#
# ⚠️ BASE를 못 찾으면 **건너뛰지 말고 돌린다.** 커밋된 변경은 `git status`에 안 잡히므로
#    감지가 전적으로 `git diff`에 달려 있는데, ref가 없으면(단일 브랜치 clone, 포크, 다른
#    기본 브랜치 이름) 그 diff가 조용히 빈 결과를 낸다 — 이 스크립트가 없애려는 침묵
#    실패가 바로 그 모양이다. 모를 때는 더 하는 쪽으로 닫는다.
rules_changed() {
  git status --porcelain -- firestore.rules 2>/dev/null | grep -q . && return 0
  if ! git rev-parse --verify --quiet "${BASE}" >/dev/null; then
    echo "  ⚠️ BASE(${BASE})를 찾을 수 없다 — 커밋된 규칙 변경을 판별할 수 없으므로 규칙 검증을 돌린다."
    echo "     (BASE=origin/main 처럼 지정하거나 \`git fetch\` 하면 이 경고가 사라진다)"
    return 0
  fi
  git diff --name-only "${BASE}...HEAD" | grep -qx 'firestore.rules' && return 0
  return 1
}

if [[ "${SKIP_RULES:-}" == "1" ]]; then
  echo
  echo "▶ Firestore rules — SKIP_RULES=1 로 건너뜀"
  echo "  ⚠️ 규칙 계층은 Dart 테스트가 원리상 못 잡는다. 푸시 전에 반드시 한 번은 돌려라."
elif rules_changed; then
  step "Firestore rules (firestore.rules 변경 감지 — 에뮬레이터로 실검증)"
  # 이미 떠 있는 에뮬레이터가 있으면 그걸 쓰고, 없으면 직접 띄운다.
  # 규칙 스크립트는 Auth로 사용자 셋을 만들고 그 토큰으로 Firestore를 친다 — **둘 다**
  # 떠 있어야 재사용할 수 있다. Firestore만 보고 판단하면(`--only firestore`로 띄운 흔한
  # 경우) 셋업 문제가 규칙 실패처럼 보고된다.
  fs_up=1; auth_up=1
  curl -s -o /dev/null --max-time 3 "http://localhost:8080/" || fs_up=0
  curl -s -o /dev/null --max-time 3 "http://localhost:9099/" || auth_up=0

  if [[ "${fs_up}" -eq 1 && "${auth_up}" -eq 1 ]]; then
    echo "  (실행 중인 에뮬레이터 사용: localhost:8080 / 9099)"
    run "Firestore rules" bash tool/verify_firestore_rules.sh
  else
    if [[ "${fs_up}" -eq 1 || "${auth_up}" -eq 1 ]]; then
      # 한쪽만 떠 있으면 직접 띄우는 것도 포트 충돌로 실패한다. 셋업 문제를 규칙
      # 실패처럼 보고하지 않도록 무엇이 문제인지 먼저 말한다.
      echo "  ⚠️ 에뮬레이터가 절반만 떠 있다(firestore=${fs_up} auth=${auth_up})."
      echo "     둘 다 띄우거나 둘 다 내려라 — 지금 상태로는 포트 충돌로 실패한다."
    else
      echo "  (에뮬레이터를 직접 띄운다)"
    fi
    run "Firestore rules" firebase emulators:exec --project demo-keepcon --only auth,firestore "bash tool/verify_firestore_rules.sh"
  fi
else
  echo
  echo "▶ Firestore rules — firestore.rules 변경 없음, 건너뜀"
fi

# ── 요약 ─────────────────────────────────────────────────────────────────
echo
if [[ "${fail}" -eq 0 ]]; then
  echo "✓ 로컬 검증 통과 — 푸시해도 된다."
else
  echo "✗ 실패: ${failed[*]}"
  echo "  고친 뒤 이 스크립트를 다시 돌려라(부분 실행은 이 스크립트가 막으려는 바로 그것이다)."
fi
exit "${fail}"
