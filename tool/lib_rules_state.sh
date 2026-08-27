#!/usr/bin/env bash
# KeepCon — 규칙 계층 공용 헬퍼. **source 전용**(직접 실행하지 않는다).
#
# 두 가지를 제공한다:
#   read_rules_paths            `firebase.json`에서 규칙·인덱스 경로를 읽어 RULES_FILE·INDEX_FILE에 담는다
#   emulator_rules_state <host> <project>
#                               떠 있는 에뮬레이터가 **실제로 적재한** 규칙을 로컬 파일과 대조해
#                               `<MATCH|STALE|UNKNOWN>\t<사유>`를 표준출력으로 돌려준다
#
# 왜 공용인가: 규칙 검증기(`tool/verify_firestore_rules.sh`)는 `tool/verify.sh`만 부르는 것이
#   아니다. README가 단독 실행을 여러 곳에서 안내하고 `tool/deploy_rules.sh`는 **배포 직후
#   검증**으로 그 명령을 권한다. 스테일 가드를 호출자에만 두면 그 경로들이 전부 빈다 —
#   그리고 빈 경로 쪽이 하필 "배포 직전·직후"다.
#
# 경로는 전부 **이 파일 위치 기준**으로 잡는다. 호출자의 cwd가 저장소 루트가 아닐 수 있고
# (`cd tool && bash verify_firestore_rules.sh`), 상대경로로 두면 그때 조용히 UNKNOWN이 된다.
_RULES_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RULES_FILE="${_RULES_LIB_ROOT}/firestore.rules"
INDEX_FILE="${_RULES_LIB_ROOT}/firestore.indexes.json"
# 저장소 루트 기준 상대 이름 — `tool/verify.sh`의 변경 감지(`git diff --name-only`와 대조)가
# 이 형태를 쓴다. 절대경로만 내보내면 그쪽이 다시 이름을 박게 된다.
RULES_FILE_REL="firestore.rules"
INDEX_FILE_REL="firestore.indexes.json"

# 규칙·인덱스 **경로**도 `firebase.json`이 정본이다 — 포트만 정본을 따르고 여기는 박아 두면,
# 경로를 바꾼 순간 ①떠 있는 에뮬레이터와의 대조가 항상 STALE이 되고 ②전용 인스턴스가
# 배포되지도 않는 파일을 검증하고 통과를 찍는다(트리거는 되는데 검증이 공허해진다).
read_rules_paths() {
  local _paths _r _i
  if _paths=$(cd "${_RULES_LIB_ROOT}" && node -e '
    const c = require("./firebase.json").firestore || {};
    process.stdout.write(`${c.rules||"firestore.rules"} ${c.indexes||"firestore.indexes.json"}`);
  ' 2>/dev/null); then
    read -r _r _i <<<"${_paths}"
    RULES_FILE="${_RULES_LIB_ROOT}/${_r}"
    INDEX_FILE="${_RULES_LIB_ROOT}/${_i}"
    RULES_FILE_REL="${_r}"
    INDEX_FILE_REL="${_i}"
  else
    # 조용히 기본값으로 넘어가면 커스텀 경로 환경에서 "왜 항상 STALE이지"를 규칙에서 찾게 된다.
    echo "  ⚠️ firebase.json에서 규칙·인덱스 경로를 읽지 못했다(node 부재·firebase.json 파손) — 기본값으로 진행한다." >&2
  fi
}

# $1 = 호스트(`localhost:8080` 형태)  $2 = 프로젝트 id
#
# ⚠️ `emulators:start`는 자기 `firestore.rules`를 감시해 자동 재적재하므로 **같은 체크아웃**에서
#    띄운 에뮬레이터는 대개 MATCH다. 걸리는 것은 다른 체크아웃·다른 워크트리에서 띄운
#    인스턴스다 — 감시 대상이 남의 파일이라 이쪽 변경은 영원히 반영되지 않는다. 응답의 `name`
#    필드가 그 출처를 드러내므로 STALE 사유로 그 값을 찍는다.
# ⚠️ 정규화는 줄바꿈(CRLF→LF)까지만 한다. `.gitattributes`의 `* text=auto`가 저장소에는 LF로
#    고정하지만 **체크아웃 줄바꿈은 `core.autocrlf`/`core.eol`이 정하므로**(이 클론은
#    `core.autocrlf=true`) 플랫폼·설정에 따라 워킹트리가 CRLF일 수 있다(eol이 못박힌 것은\n#    `*.sh`·`*.cmd`뿐이다). 그건 규칙 의미와
#    무관하다. 그 이상은 손대지 않는다 — 공백 하나가 규칙 의미를 바꾸는 경우가 있어서,
#    더 관대한 비교는 이 감지 자체를 무의미하게 만든다.
# ⚠️ node가 없거나 응답이 예상과 다르면 빈 출력·UNKNOWN이 된다. 호출자는 그것을 통과로
#    읽지 말 것 — 확인하지 못한 것과 확인해서 괜찮은 것은 다른 사실이다.
emulator_rules_state() {
  local _state
  _state=$(node -e '
    const fs = require("fs");
    // `node -e`의 argv는 파일 실행보다 한 칸 당겨있다(argv[1]부터 인자) —
    // 둘 다 안전하게 마지막 세 개를 집는다. slice(2)로 두면 인자가 한 칸씩 밀려
    // URL이 망가지고, 그 실패는 UNKNOWN으로 읽혀 **항상 전용 인스턴스**로 간다(실측).
    const [host, project, file] = process.argv.slice(-3);
    const norm = (s) => s.replace(/\r\n/g, "\n");
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 5000);
    const url = "http://" + host + "/emulator/v1/projects/" + project + ":securityRules";
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
  ' "$1" "$2" "${RULES_FILE}" 2>/dev/null)
  # node 자체가 없거나 즉사하면 stdout이 비어 있다 — 그대로 넘기면 호출자가 사유를 빈
  # 괄호로 찍는다(실측). 여기서 사유를 붙여 어느 호출자든 같은 말을 하게 한다.
  if [[ -z "${_state}" ]]; then
    printf 'UNKNOWN\tnode를 실행하지 못했다(node 부재·구버전 등)'
  else
    printf '%s' "${_state}"
  fi
}
