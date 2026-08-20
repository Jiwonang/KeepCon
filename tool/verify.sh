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
#   그래서 판단을 없앤다. 이 스크립트는 항상 같은 것을 돌리고, **규칙 계층 입력**
#   (`firestore.rules`·`tool/verify_firestore_rules.sh`·`firebase.json`)이 바뀌었으면
#   규칙 검증을 **자동으로** 덧붙인다.
#
# 실행:
#   bash tool/verify.sh              # develop 기준으로 변경 감지
#   BASE=origin/main bash tool/verify.sh
#   SKIP_RULES=1 bash tool/verify.sh # 규칙 검증을 건너뛴다. **규칙 입력이 바뀐 상태라면
#                                    #   이 실행은 실패로 끝난다** — 검증하지 않은 것에
#                                    #   통과 판정을 내지 않는다.
#
# 종료 코드: 하나라도 실패하면 1(규칙 입력이 바뀐 채 검증을 건너뛴 경우 포함). 실패해도 나머지는 끝까지 돌린다 — 한 번에 다 보는 것이
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
# 글로브·제외는 `.markdownlint-cli2.jsonc`가 정본이다 — CI와 완전히 같은 명령을 쓴다.
run "Markdown lint" npx --yes markdownlint-cli2@0.18.1

# ── 조건부 — 규칙 계층 입력이 바뀌었으면 반드시 ─────────────────────────
# 커밋된 변경(BASE 대비)과 아직 커밋 안 된 변경을 **둘 다** 본다. 커밋 전에 돌리는
# 경우가 흔하므로 한쪽만 보면 그 판단이 다시 사람에게 돌아온다.
#
# 보는 파일이 `firestore.rules` 하나가 아닌 이유: CI의 `Firestore rules` 잡은 경로
# 필터가 없어 **모든 PR에서** 돈다. 로컬 트리거를 규칙 파일 하나로 좁히면, 검증 케이스나
# 에뮬레이터 설정만 고친 변경이 로컬에서는 건너뛰어지고 **CI에서 처음 빨개진다** —
# 실제로 이 저장소가 그렇게 당했다(케이스 33건을 더한 PR이 그 파일만 건드렸다).
#
# ⚠️ BASE 기준을 판별하지 못하면 **건너뛰지 말고 돌린다.** 커밋된 변경은 `git status`에
#    안 잡히므로 감지가 전적으로 `git diff`에 달려 있는데, 그 diff는 두 가지 이유로 조용히
#    빈 결과를 낸다 — ①ref가 없거나(단일 브랜치 clone, 포크, 다른 기본 브랜치 이름)
#    ②ref는 있는데 merge base가 없다(얕은 클론, 관련 없는 히스토리). 둘 다 이 스크립트가
#    없애려는 침묵 실패의 모양이다. 모를 때는 더 하는 쪽으로 닫는다.
# ⚠️ `tool/verify.sh`(자기 자신)도 목록에 있다 — 검증기에 넘기는 호스트·환경변수 이름이
#    여기 있어서 이 파일이 곧 규칙 계층의 **호출 계약**이다. 게다가 CI의 `Firestore rules`
#    잡은 이 스크립트를 거치지 않고 `emulators:exec`를 직접 부르므로, 여기가 깨져도
#    **아무 데서도 빨개지지 않는다**(70-73행의 "로컬이 좁으면 CI에서 빨개진다"가 여기서는
#    성립하지 않는다).
RULES_INPUTS=(firestore.rules tool/verify_firestore_rules.sh firebase.json tool/verify.sh)

rules_changed() {
  git status --porcelain -- "${RULES_INPUTS[@]}" 2>/dev/null | grep -q . && return 0
  if ! git rev-parse --verify --quiet "${BASE}" >/dev/null; then
    base_unknown=1
    base_unknown_why="ref 부재"
    # 처방은 **없다고 말한 그 ref**를 만들어야 한다. develop을 하드코딩하면
    # `BASE=origin/main`으로 돌린 사람에게 "origin/main을 지정하라"면서 develop을 받아오라는
    # 자기모순 안내가 나가고, 그대로 실행해도 다음 번에 같은 메시지가 반복된다.
    if [[ "${BASE}" == origin/* ]]; then
      base_unknown_fix="git fetch origin ${BASE#origin/}:refs/remotes/${BASE}"
    else
      base_unknown_fix="BASE=<이 클론에 존재하는 ref> 로 지정"
    fi
    return 0
  fi
  # ⚠️ ref가 **있어도** merge base가 없으면(얕은 클론, 관련 없는 히스토리) triple-dot이
  #    exit 128로 죽으면서 stdout은 비어 있다 — 그대로 두면 "변경 없음"으로 읽혀 조용히
  #    건너뛴다. ref 존재 검사만으로는 이 경우를 못 거른다(실측: `no merge base`).
  local changed path
  if ! changed=$(git diff --name-only "${BASE}...HEAD" 2>/dev/null); then
    base_unknown=1
    # 이 분기도 원인이 둘이고 **처방이 정반대다** — 얕은 클론에만 `--unshallow`가 통하고,
    # 완전 클론(orphan 브랜치·무관한 remote)에서는 같은 명령이 fatal로 거부된다. 바로 위
    # 분기에서 고친 것과 똑같은 결함이라, 여기서도 기계적으로 가른다.
    if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
      base_unknown_why="merge base 없음(얕은 클론)"
      base_unknown_fix="git fetch --unshallow"
    else
      base_unknown_why="merge base 없음(무관한 히스토리 — 완전 클론)"
      base_unknown_fix="BASE=<HEAD와 공통 조상이 있는 ref> 로 지정"
    fi
    return 0
  fi
  for path in "${RULES_INPUTS[@]}"; do
    grep -qxF "${path}" <<<"${changed}" && return 0
  done
  return 1
}

# 포트는 `firebase.json`이 정본이다. 8080/9099를 스크립트에 박아 두면 포트를 바꾼 순간
# ①떠 있는 에뮬레이터를 못 찾고 ②재사용 경로가 죽은 기본 포트로 붙는다(`emulators:exec`
# 경로는 CLI가 환경변수를 주입하므로 살아 있어, 한쪽만 조용히 깨진다).
#
# ⚠️ 지금 이 정본을 따르는 것은 **이 스크립트뿐**이다. `tool/seed_emulator.sh`(9099/8080
#    기본값), `tool/verify_firestore_rules.sh`(같은 기본값 — README가 안내하는 **단독 실행**
#    에서는 아무도 env를 안 넘기므로 그 값이 곧 판정이다), 그리고
#    `lib/shared/firebase/firebase_bootstrap.dart`의 `kAuthEmulatorPort`·
#    `kFirestoreEmulatorPort`는 아직 각자 값을 들고 있어, 포트를 바꾸면 그 셋은 따로 고쳐야
#    한다. 주석은 게이트가 아니므로 이것만으로는 부족하다 — 셸 쪽 파싱 공용화와
#    `tool/check_ssot.sh`의 포트 대조는 별도 PR로 뺀다.
read_emulator_ports() {
  if ! _ports=$(node -e '
    const c = require("./firebase.json").emulators || {};
    process.stdout.write(`${(c.firestore||{}).port||8080} ${(c.auth||{}).port||9099}`);
  ' 2>/dev/null); then
    # 폴백이 조용하면 커스텀 포트 환경에서 "에뮬레이터가 절반만 떠 있다"는 엉뚱한 진단이 나온다
    # — 원인은 포트를 못 읽은 것인데 진단은 에뮬레이터를 가리킨다.
    echo "  ⚠️ firebase.json에서 에뮬레이터 포트를 읽지 못했다(node 부재·firebase.json 부재·JSON 파손) — 기본값 8080/9099로 진행한다." >&2
    _ports="8080 9099"
  fi
  read -r FS_PORT AUTH_PORT <<<"${_ports}"
}

base_unknown=0
base_unknown_why=""
base_unknown_fix=""

if [[ "${SKIP_RULES:-}" == "1" ]]; then
  step "Firestore rules — SKIP_RULES=1 로 건너뜀"
  echo "  ⚠️ 규칙 계층은 Dart 테스트가 원리상 못 잡는다."
  if rules_changed; then
    # 검증하지 않은 상태에 통과 판정을 내면 이 스크립트의 산출물(푸시 가부)이 거짓이 된다.
    # 단 "바뀌었다"와 "판별하지 못했다"는 다른 사실이므로 섞어 말하지 않는다 — 후자에게
    # 전자의 진단을 주면 있지도 않은 규칙 변경을 자기 diff에서 찾게 된다.
    if [[ "${base_unknown}" -eq 1 ]]; then
      echo "  ✗ BASE(${BASE}) 기준 변경을 판별하지 못했다(${base_unknown_why}) — 건너뛴 채로는 푸시 가부를 판정할 수 없다."
      echo "     (BASE=origin/main 처럼 지정하거나 \`${base_unknown_fix}\` 하면 판별이 정확해진다)"
    else
      echo "  ✗ 규칙 입력이 바뀌었는데 검증을 건너뛰었다 — 이 실행으로는 푸시 가부를 판정할 수 없다."
    fi
    # 별도 플래그가 아니라 `failed`에 넣는다 — 다른 스텝이 함께 실패하면 요약 줄에서
    # 이 건만 사라져, 고치고 다시 돌린 다음 라운드에야 드러난다.
    fail=1
    failed+=("Firestore rules — SKIP_RULES=1 로 미검증")
  fi
elif rules_changed; then
  if [[ "${base_unknown}" -eq 1 ]]; then
    step "Firestore rules (BASE 판별 불가 — 안전하게 실검증)"
    echo "  ⚠️ BASE(${BASE}) 기준 변경을 판별할 수 없다(${base_unknown_why}) — 그냥 돌린다."
    echo "     (BASE=origin/main 처럼 지정하거나 \`${base_unknown_fix}\` 하면 이 경고가 사라진다)"
  else
    step "Firestore rules (규칙 계층 입력 변경 감지 — 에뮬레이터로 실검증)"
  fi

  # 포트는 여기서 읽는다 — 규칙 검증을 안 돌리는 실행(대다수)에서는 쓰이지도 않는데
  # 폴백 경고만 떠서 "무엇이 잘못됐나" 오해를 부른다.
  read_emulator_ports

  # 규칙 스크립트는 Auth로 사용자 셋을 만들고 그 토큰으로 Firestore를 친다 — **둘 다**
  # 떠 있어야 재사용할 수 있다.
  fs_up=1; auth_up=1
  curl -s -o /dev/null --max-time 3 "http://localhost:${FS_PORT}/" || fs_up=0
  curl -s -o /dev/null --max-time 3 "http://localhost:${AUTH_PORT}/" || auth_up=0

  if [[ "${fs_up}" -eq 1 && "${auth_up}" -eq 1 ]]; then
    echo "  (실행 중인 에뮬레이터 사용: localhost:${FS_PORT} / ${AUTH_PORT})"
    # 재사용 경로에는 `emulators:exec`가 없으므로 호스트를 직접 넘긴다 — 안 넘기면 검증
    # 스크립트가 자기 기본값(8080/9099)으로 붙어, 포트를 바꾼 순간 여기만 조용히 깨진다.
    # auth는 `AUTH_EMULATOR_HOST`(저장소 자체 노브)로 넘긴다. 수신 측이 그것을
    # `FIREBASE_AUTH_EMULATOR_HOST`(CLI가 주입하는 이름)보다 **먼저** 보므로, 사용자 셸에
    # 그 변수가 남아 있어도 여기서 넘긴 값이 이긴다 — 낮은 쪽으로 넘기면 조용히 진다.
    run "Firestore rules" env \
      "FIRESTORE_EMULATOR_HOST=localhost:${FS_PORT}" \
      "AUTH_EMULATOR_HOST=localhost:${AUTH_PORT}" \
      bash tool/verify_firestore_rules.sh
  elif [[ "${fs_up}" -eq 1 || "${auth_up}" -eq 1 ]]; then
    # 한쪽만 떠 있으면 직접 띄우는 것도 **반드시** 포트 충돌로 죽는다. 그대로 돌리면
    # 그 실패가 요약에 `✗ Firestore rules`로 찍혀 규칙 결함처럼 읽힌다 — 셋업 문제는
    # 셋업 문제로 이름 붙인다(그렇다고 통과로 넘기지는 않는다).
    echo "  ✗ 에뮬레이터가 절반만 떠 있다(firestore=${fs_up} auth=${auth_up}) — 규칙 검증을 돌릴 수 없다."
    echo "     둘 다 띄우거나(bash tool/emulators.sh) 둘 다 내린 뒤 다시 돌려라."
    fail=1
    failed+=("Firestore rules — 에뮬레이터 셋업")
  else
    echo "  (에뮬레이터를 직접 띄운다)"
    # ⚠️ 여기서는 함정이 **반대 방향**이다. CLI는 `FIREBASE_AUTH_EMULATOR_HOST`만 주입하는데
    #    수신 측은 `AUTH_EMULATOR_HOST`를 먼저 보므로, 셸에 남은 값이 CLI를 이겨 죽은 포트로
    #    붙는다(`tool/seed_emulator.sh`가 쓰는 노브라 실제로 남아 있을 수 있다). 지워서 넘긴다.
    run "Firestore rules" env -u AUTH_EMULATOR_HOST \
      firebase emulators:exec --project demo-keepcon --only auth,firestore "bash tool/verify_firestore_rules.sh"
  fi
else
  echo
  echo "▶ Firestore rules — 규칙 계층 입력 변경 없음, 건너뜀"
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
