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
#   같은 이유로 **떠 있는 에뮬레이터를 무조건 재사용하지 않는다.** 그 에뮬레이터가 낡은
#   `firestore.rules`를 물고 있으면 검증이 조용히 무의미해진다 — 2026-08-26 실측: 다른
#   체크아웃에서 띄운 에뮬레이터에 붙어 규칙 검증이 대량 실패했는데, 같은 스크립트를 새
#   인스턴스에 붙이니 전부 통과였다. 실패는 규칙 결함이 아니라 스테일 에뮬레이터였다.
#   **반대 방향이 더 위험하다** — 규칙을 느슨하게 바꾼 변경이 낡은(엄격한) 규칙 위에서
#   green으로 통과한다. 그래서 재사용 전에 에뮬레이터가 **실제로 적재한** 규칙 본문을
#   조회해 로컬 파일과 대조하고, 다르거나 확인할 수 없으면 재사용을 거부한 뒤 **다른
#   포트에 전용 인스턴스**를 띄운다. 개발용 에뮬레이터는 죽이지 않는다 —
#   `.emulator-local/` 개인 데이터는 정상 종료에만 export되므로(`tool/emulators.sh`)
#   강제 종료는 그 세션의 데이터를 통째로 버린다.
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

# ── 스테일 에뮬레이터 감지 ───────────────────────────────────────────────
# 프로젝트 id는 검증 스크립트와 **같은 방식으로** 정한다 — 다르게 정하면 여기서 대조한
# 규칙과 검증이 실제로 맞닥뜨리는 규칙이 어긋난다.
RULES_PROJECT="${FIRESTORE_PROJECT:-demo-keepcon}"
probe_ref_port=""

# 에뮬레이터가 **실제로 적재한** 규칙 본문을 조회해 로컬 `firestore.rules`와 대조하고
# `<MATCH|STALE|UNKNOWN>\t<사유>`를 돌려준다. (`GET /emulator/v1/projects/{p}:securityRules`)
#
# ⚠️ `emulators:start`는 자기 `firestore.rules`를 감시해 자동 재적재하므로 **같은
#    체크아웃**에서 띄운 에뮬레이터는 대개 MATCH다. 걸리는 것은 다른 체크아웃·다른
#    워크트리에서 띄운 인스턴스다 — 감시 대상이 남의 파일이라 이쪽 변경은 영원히
#    반영되지 않는다. 2026-08-26의 17건 실패가 정확히 그 모양이었고, 응답의 `name`
#    필드가 남의 경로를 가리켜 그 사실을 드러냈다(그래서 STALE 사유로 그 값을 찍는다).
# ⚠️ 정규화는 줄바꿈(CRLF→LF)까지만 한다. `.gitattributes`가 `*.sh`·`*.cmd`만 고정하고
#    `firestore.rules`는 기여자의 `core.autocrlf`에 맡기므로 체크아웃마다 줄바꿈이
#    다를 수 있는데 그건 규칙 의미와 무관하다. 그 이상은 손대지 않는다 — 공백 하나가
#    규칙 의미를 바꾸는 경우가 있어서, 더 관대한 비교는 이 감지 자체를 무의미하게 만든다.
# ⚠️ node가 없으면 빈 출력 → 호출부가 UNKNOWN으로 읽는다. 확인 못 한 것을 통과로
#    읽지 않는 쪽(전용 인스턴스)으로 닫힌다.
emulator_rules_state() {
  node -e '
    const fs = require("fs");
    // `node -e`의 argv는 파일 실행보다 한 칸 당겨있다(argv[1]부터 인자) —
    // 둘 다 안전하게 마지막 세 개를 집는다. slice(2)로 두면 인자가 한 칸씩 밀려
    // URL이 망가지고, 그 실패는 UNKNOWN으로 읽혀 **항상 전용 인스턴스**로 간다(실측).
    const [port, project, file] = process.argv.slice(-3);
    const norm = (s) => s.replace(/\r\n/g, "\n");
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 5000);
    const url = "http://127.0.0.1:" + port + "/emulator/v1/projects/" + project + ":securityRules";
    fetch(url, { signal: ac.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status))))
      .then((j) => {
        const files = (j.rules && j.rules.files) || [];
        if (files.length !== 1) throw new Error("적재된 규칙 파일이 " + files.length + "개");
        const loaded = norm(files[0].content || "");
        const local = norm(fs.readFileSync(file, "utf8"));
        process.stdout.write(loaded === local ? "MATCH\t" : "STALE\t" + (files[0].name || "경로 불명"));
      })
      .catch((e) => process.stdout.write("UNKNOWN\t" + (e.message || e)))
      .finally(() => clearTimeout(timer));
  ' "$1" "${RULES_PROJECT}" firestore.rules 2>/dev/null
}

# ── 전용 에뮬레이터(다른 포트) ───────────────────────────────────────────
# 재사용할 수 없을 때 **개발용 에뮬레이터를 죽이지 않고** 검증만 따로 돌린다.
tcp_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# 기본 포트 묶음이 막혀 있으면 +10씩 밀어 가며 빈 자리를 찾는다. 실제로 필요하다 —
# 앞선 인스턴스가 내려간 직후에도 Firestore 에뮬레이터(JVM)는 포트를 한동안 붙들고 있어
# 곧바로 재사용하면 `port taken`으로 죽는다(실측).
pick_alt_ports() {
  local off
  # ⚠️ `/dev/tcp`가 꺼진 bash 빌드에서는 **모든 포트가 비어 보인다** — 탐색이 조용히
  #    무의미해진다. 그래서 "떠 있는 것이 확실한 포트"로 기능부터 확인하고, 못 쓰면
  #    탐색을 포기하고 기본값으로 간다(충돌하면 firebase가 시끄럽게 죽는다 — 조용한
  #    오판보다 낫다).
  if [[ -z "${probe_ref_port}" ]] || ! tcp_in_use "${probe_ref_port}"; then
    ALT_FS=8181 ALT_AUTH=9199 ALT_HUB=4460 ALT_LOG=4560
    return 0
  fi
  for off in 0 10 20 30 40 50 60 70 80 90; do
    ALT_FS=$((8181 + off)); ALT_AUTH=$((9199 + off))
    ALT_HUB=$((4460 + off)); ALT_LOG=$((4560 + off))
    if ! tcp_in_use "${ALT_FS}" && ! tcp_in_use "${ALT_AUTH}" \
      && ! tcp_in_use "${ALT_HUB}" && ! tcp_in_use "${ALT_LOG}"; then
      return 0
    fi
  done
  return 1
}

rules_setup_failed=0

# 종료 코드만으로는 ‘규칙이 틀렸다’와 ‘돌리지도 못했다’를 가를 수 없어 플래그로 따로 알린다.
run_dedicated_rules() {
  local dir cfg rc
  rules_setup_failed=0
  if ! pick_alt_ports; then
    echo "  ✗ 전용 에뮬레이터를 띄울 빈 포트가 없다(8181/9199/4460/4560부터 +90까지 전부 사용 중)."
    rules_setup_failed=1
    return 1
  fi
  if ! dir=$(mktemp -d 2>/dev/null) || [[ -z "${dir}" ]]; then
    echo "  ✗ 임시 디렉터리를 만들지 못해 전용 에뮬레이터를 띄울 수 없다."
    rules_setup_failed=1
    return 1
  fi
  # 규칙·인덱스를 **복사해서** 상대경로로 참조한다. 원본을 절대경로로 가리키면 Windows
  # 경로 escaping이 JSON과 MSYS 두 겹으로 얽힌다 — 복사가 그 문제를 통째로 없앤다.
  # (`emulators:exec`의 자식 명령은 이 스크립트의 cwd, 즉 저장소 루트에서 돌므로
  #  `bash tool/verify_firestore_rules.sh`는 그대로 쓴다 — `--config`가 딴 데를 가리켜도
  #  cwd는 따라가지 않는다.)
  if ! cp firestore.rules firestore.indexes.json "${dir}/"; then
    echo "  ✗ 규칙·인덱스를 임시 디렉터리로 복사하지 못했다."
    rules_setup_failed=1
    rm -rf "${dir}"
    return 1
  fi
  # ui는 끈다 — 4000번이 개발용 에뮬레이터의 UI와 부딪힌다.
  cat > "${dir}/firebase.json" <<JSON
{
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "emulators": {
    "auth": { "port": ${ALT_AUTH} },
    "firestore": { "port": ${ALT_FS} },
    "hub": { "port": ${ALT_HUB} },
    "logging": { "port": ${ALT_LOG} },
    "ui": { "enabled": false },
    "singleProjectMode": true
  }
}
JSON
  cfg="${dir}/firebase.json"
  # firebase는 네이티브 Windows 프로세스라 MSYS 경로(`/tmp/...`)를 못 읽는다.
  command -v cygpath >/dev/null 2>&1 && cfg=$(cygpath -m "${cfg}")
  echo "  (전용 에뮬레이터를 띄운다 — firestore=${ALT_FS} auth=${ALT_AUTH} hub=${ALT_HUB} logging=${ALT_LOG})"
  # 여기서도 셸에 남은 `AUTH_EMULATOR_HOST`가 CLI 주입값을 이기면 죽은 포트로 붙는다.
  env -u AUTH_EMULATOR_HOST -u FIRESTORE_EMULATOR_HOST -u FIREBASE_AUTH_EMULATOR_HOST \
    firebase emulators:exec --config "${cfg}" --project "${RULES_PROJECT}" \
    --only auth,firestore "bash tool/verify_firestore_rules.sh"
  rc=$?
  rm -rf "${dir}"
  return "${rc}"
}

# `run`과 같은 일을 하되 **실패 이름을 나눈다.** 규칙 결함과 셋업 문제는 고치는 곳이
# 다른데, 요약 줄에 `✗ Firestore rules`만 남으면 포트가 없어서 못 돈 실행이 규칙 회귀처럼
# 읽힌다 — 예전 '절반만 떠 있음' 분기가 지키던 구분이라 여기서 그대로 이어받는다.
# (구분할 수 있는 것만 구분한다: `emulators:exec`가 기동에 실패한 경우는 자식의 종료
#  코드와 섞여 구별할 수 없으므로 규칙 실패로 둔다 — 그쪽은 firebase가 시끄럽게 찍는다.)
run_rules_dedicated() {
  local label="Firestore rules"
  if run_dedicated_rules; then
    echo "  ✓ ${label}"
    return 0
  fi
  [[ "${rules_setup_failed}" -eq 1 ]] && label="Firestore rules — 전용 에뮬레이터 셋업"
  echo "  ✗ ${label}"
  fail=1
  failed+=("${label}")
  return 1
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

  # 재사용 가부를 판단할 기준 포트 — 아래 `pick_alt_ports`가 `/dev/tcp` 사용 가능
  # 여부를 이 포트로 확인한다(떠 있는 것이 확실한 포트여야 판별이 성립한다).
  probe_ref_port=""
  if [[ "${fs_up}" -eq 1 ]]; then
    probe_ref_port="${FS_PORT}"
  elif [[ "${auth_up}" -eq 1 ]]; then
    probe_ref_port="${AUTH_PORT}"
  fi

  if [[ "${fs_up}" -eq 1 && "${auth_up}" -eq 1 ]]; then
    # ⚠️ **떠 있다는 것만으로는 재사용 조건이 아니다.** 적재된 규칙이 이 트리의
    #    `firestore.rules`와 같아야 한다 — 스크립트 상단 주석 참조.
    rules_probe=$(emulator_rules_state "${FS_PORT}")
    rules_state="${rules_probe%%$'\t'*}"
    rules_detail="${rules_probe#*$'\t'}"
    if [[ -z "${rules_state}" ]]; then
      rules_state="UNKNOWN"
      rules_detail="node를 실행하지 못했다(node 부재 등)"
    fi

    if [[ "${rules_state}" == "MATCH" ]]; then
      echo "  (실행 중인 에뮬레이터 사용: localhost:${FS_PORT} / ${AUTH_PORT} — 적재된 규칙이 firestore.rules와 일치)"
      # 재사용 경로에는 `emulators:exec`가 없으므로 호스트를 직접 넘긴다 — 안 넘기면 검증
      # 스크립트가 자기 기본값(8080/9099)으로 붙어, 포트를 바꾼 순간 여기만 조용히 깨진다.
      # auth는 `AUTH_EMULATOR_HOST`(저장소 자체 노브)로 넘긴다. 수신 측이 그것을
      # `FIREBASE_AUTH_EMULATOR_HOST`(CLI가 주입하는 이름)보다 **먼저** 보므로, 사용자 셸에
      # 그 변수가 남아 있어도 여기서 넘긴 값이 이긴다 — 낮은 쪽으로 넘기면 조용히 진다.
      run "Firestore rules" env \
        "FIRESTORE_EMULATOR_HOST=localhost:${FS_PORT}" \
        "AUTH_EMULATOR_HOST=localhost:${AUTH_PORT}" \
        bash tool/verify_firestore_rules.sh
    else
      if [[ "${rules_state}" == "STALE" ]]; then
        echo "  ⚠️ 실행 중인 에뮬레이터가 **낡은 규칙**을 물고 있다 — 재사용하지 않는다."
        echo "     (그 에뮬레이터가 적재한 규칙의 출처: ${rules_detail})"
      else
        echo "  ⚠️ 실행 중인 에뮬레이터가 적재한 규칙을 확인하지 못했다(${rules_detail}) — 재사용하지 않는다."
      fi
      echo "     낡은 규칙 위에서 돈 검증은 통과도 실패도 근거가 되지 못한다."
      run_rules_dedicated
    fi
  elif [[ "${fs_up}" -eq 1 || "${auth_up}" -eq 1 ]]; then
    # 한쪽만 떠 있으면 기본 포트로는 반드시 충돌한다. 예전에는 그래서 여기서 셋업 실패로
    # 끝냈지만, 이제 다른 포트에 전용 인스턴스를 띄울 수 있으므로 그 전제가 사라졌다.
    echo "  ⚠️ 에뮬레이터가 절반만 떠 있다(firestore=${fs_up} auth=${auth_up}) — 재사용하지 않는다."
    run_rules_dedicated
  else
    echo "  (에뮬레이터를 직접 띄운다)"
    # ⚠️ 여기서는 함정이 **반대 방향**이다. CLI는 `FIREBASE_AUTH_EMULATOR_HOST`만 주입하는데
    #    수신 측은 `AUTH_EMULATOR_HOST`를 먼저 보므로, 셸에 남은 값이 CLI를 이겨 죽은 포트로
    #    붙는다(`tool/seed_emulator.sh`가 쓰는 노브라 실제로 남아 있을 수 있다). 지워서 넘긴다.
    run "Firestore rules" env -u AUTH_EMULATOR_HOST \
      firebase emulators:exec --project "${RULES_PROJECT}" --only auth,firestore "bash tool/verify_firestore_rules.sh"
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
