#!/usr/bin/env bash
# KeepCon — firestore.rules 실동작 검증 (Firebase 에뮬레이터 대상).
#
# 왜 필요한가:
#   `firestore.rules`는 배포하기 전까지 "문법만 맞는 문서"다. 규칙이 실제로 남의
#   기프티콘을 막는지, 소유자 위조(ownerId 스푸핑)를 막는지는 **실행해봐야** 안다.
#   이 스크립트는 Auth 에뮬레이터로 실제 사용자 두 명을 만들고, 그 사용자의 ID 토큰으로
#   Firestore REST에 요청해 규칙이 허용/거부하는지를 확인한다.
#
# 선행 조건 (별도 터미널):
#   firebase emulators:start --project demo-keepcon
#
# 실행:
#   bash tool/verify_firestore_rules.sh
#
# CI: `.github/workflows/ci.yml`의 `Firestore rules` 잡이 에뮬레이터를 직접 띄워 이 스크립트를
#   돌린다(`firebase emulators:exec`). Dart 테스트는 in-memory 구현을 쓰므로 규칙 계층을
#   검증하지 못한다 — 이 스크립트가 그 계층의 유일한 회귀 방어선이다.
#
# 주의: 인증 헤더 없이 Firestore 에뮬레이터 REST를 호출하면 **관리자로 취급되어 규칙을
#   우회**한다. 그래서 모든 케이스는 반드시 사용자 ID 토큰을 붙여 호출한다.
set -uo pipefail

PROJECT="${FIRESTORE_PROJECT:-demo-keepcon}"
# `emulators:exec`가 자식에게 넘기는 이름은 **`FIREBASE_` 접두가 붙은 쪽**이다 —
# Firestore(`FIRESTORE_EMULATOR_HOST`)와 이름 규칙이 다르다. 접두 없는 이름만 읽으면
# `firebase.json`에서 auth 포트를 바꾼 순간 죽은 9099로 붙어 토큰이 빈 문자열이 되고
# 전 케이스가 401/403으로 무너진다(오늘은 기본값이 9099라 우연히 가려져 있었다).
AUTH_HOST="${AUTH_EMULATOR_HOST:-${FIREBASE_AUTH_EMULATOR_HOST:-localhost:9099}}"
FS_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8080}"
DOCS="http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents"

pass=0
fail=0

# 사용자를 만들고 ID 토큰을 표준출력으로 돌려준다(이미 있으면 로그인).
signup() {
  local email="$1"
  local body="{\"email\":\"${email}\",\"password\":\"test1234\",\"returnSecureToken\":true}"
  local res
  res=$(curl -s -X POST \
    "http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key" \
    -H 'Content-Type: application/json' -d "${body}")
  if ! grep -q idToken <<<"${res}"; then
    res=$(curl -s -X POST \
      "http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-api-key" \
      -H 'Content-Type: application/json' -d "${body}")
  fi
  sed -n 's/.*"idToken": *"\([^"]*\)".*/\1/p' <<<"${res}"
}

# ID 토큰의 주인 uid를 조회한다.
uid_of() {
  local res
  res=$(curl -s -X POST \
    "http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:lookup?key=demo-api-key" \
    -H 'Content-Type: application/json' -d "{\"idToken\":\"$1\"}")
  sed -n 's/.*"localId": *"\([^"]*\)".*/\1/p' <<<"${res}"
}

# check <설명> <기대 HTTP 코드> <curl 인자...>
check() {
  local label="$1" want="$2"; shift 2
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  if [[ "${code}" == "${want}" ]]; then
    echo "  ✓ ${label} (HTTP ${code})"
    pass=$((pass + 1))
  else
    echo "  ✗ ${label} — 기대 ${want}, 실제 ${code}"
    fail=$((fail + 1))
  fi
}

echo "Firestore rules 검증 (project=${PROJECT}, auth=${AUTH_HOST}, firestore=${FS_HOST})"

if ! curl -s -o /dev/null --max-time 3 "http://${FS_HOST}/"; then
  echo "✗ Firestore 에뮬레이터에 연결할 수 없습니다. 먼저 실행하세요:"
  echo "    firebase emulators:start --project ${PROJECT}"
  exit 1
fi

# ⚠️ **연결됐다는 것만으로는 검증 조건이 아니다.** 붙은 에뮬레이터가 실제로 적재한 규칙이
#    이 트리의 `firestore.rules`와 같아야 한다. 다른 체크아웃·워크트리에서 띄운 인스턴스는
#    남의 파일을 감시하므로 이쪽 변경이 영원히 반영되지 않고, 특히 **느슨하게 고친 규칙이
#    옛 엄격한 규칙 위에서 green으로 통과한다**(2026-08-26 실측).
#    가드를 호출자가 아니라 여기 두는 이유: 이 스크립트를 직접 부르는 경로가 많다 —
#    README의 단독 실행 안내, `tool/verify_firestore_rules.cmd`, 그리고 `tool/deploy_rules.sh`의
#    **배포 직후 검증** 안내. 호출자에만 두면 하필 배포 근처 경로가 빈다.
# shellcheck source=tool/lib_rules_state.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib_rules_state.sh"
read_rules_paths
RULES_STATE=$(emulator_rules_state "${FS_HOST}" "${PROJECT}")
case "${RULES_STATE%%$'\t'*}" in
  MATCH) ;;
  STALE)
    echo "✗ 붙은 에뮬레이터가 **낡은 규칙**을 물고 있습니다 — 이 검증은 통과도 실패도 근거가 되지 못합니다."
    echo "   (그 에뮬레이터가 적재한 규칙의 출처: ${RULES_STATE#*$'\t'})"
    echo "   그 에뮬레이터를 내리고 이 체크아웃에서 다시 띄우거나, \`bash tool/verify.sh\`로 돌리세요"
    echo "   (verify.sh는 이 경우 다른 포트에 전용 인스턴스를 띄웁니다)."
    exit 1
    ;;
  *)
    # 단독 실행에는 '전용 인스턴스'라는 대피로가 없고, 이 스크립트는 지금까지 node를 요구하지
    # 않았다. 그래서 여기서만 경고로 둔다 — 확인하지 못한 것을 통과로 **부르지는** 않는다.
    echo "⚠️ 적재된 규칙을 확인하지 못했습니다(${RULES_STATE#*$'\t'}) — 결과를 근거로 쓰기 전에"
    echo "   \`bash tool/verify.sh\`로 한 번 더 돌리세요."
    ;;
esac

TOKEN_A=$(signup "rules-a@keepcon.test")
TOKEN_B=$(signup "rules-b@keepcon.test")
# C는 어느 그룹에도 속하지 않는 제3자다 — 참여 요청의 행위자는 정의상 비멤버라
# 멤버 역할을 겸하는 B로는 그 경로를 검증할 수 없다.
TOKEN_C=$(signup "rules-c@keepcon.test")
if [[ -z "${TOKEN_A}" || -z "${TOKEN_B}" || -z "${TOKEN_C}" ]]; then
  echo "✗ Auth 에뮬레이터에서 테스트 사용자를 만들지 못했습니다."
  exit 1
fi
UID_A=$(uid_of "${TOKEN_A}")
UID_B=$(uid_of "${TOKEN_B}")
UID_C=$(uid_of "${TOKEN_C}")
# uid_of는 응답을 sed로 긁는다 — 형식이 바뀌거나 조회가 실패하면 빈 문자열이 되고,
# 그러면 문서 id·memberIds가 통째로 어긋나 이후 케이스가 엉뚱한 이유로 결과를 낸다.
if [[ -z "${UID_A}" || -z "${UID_B}" || -z "${UID_C}" ]]; then
  echo "✗ 테스트 사용자 uid를 조회하지 못했습니다(A='${UID_A}' B='${UID_B}' C='${UID_C}')."
  exit 1
fi
echo "  테스트 사용자: A=${UID_A}, B=${UID_B}, C=${UID_C}"

AUTH_A=(-H "Authorization: Bearer ${TOKEN_A}")
AUTH_B=(-H "Authorization: Bearer ${TOKEN_B}")
AUTH_C=(-H "Authorization: Bearer ${TOKEN_C}")
JSON=(-H 'Content-Type: application/json')

# Firestore REST 형식의 기프티콘 문서를 만든다. $1 = ownerId(이 값이 규칙 판정 대상).
gifticon_doc() {
  printf '{"fields":{"ownerId":{"stringValue":"%s"},"brand":{"stringValue":"스타벅스"},"productName":{"stringValue":"아메리카노"},"price":{"integerValue":"4500"},"category":{"stringValue":"카페"},"status":{"stringValue":"available"}}}' "$1"
}

# Firestore REST 형식의 그룹 문서를 만든다. $1 = ownerId(방장), $2 = memberIds에 넣을 멤버.
group_doc() {
  printf '{"fields":{"ownerId":{"stringValue":"%s"},"name":{"stringValue":"가족"},"memberIds":{"arrayValue":{"values":[{"stringValue":"%s"}]}}}}' "$1" "$2"
}

echo "gifticons — 소유자만"
check "A가 자기 기프티콘 생성" 200 -X PATCH "${DOCS}/gifticons/rules-g-a" "${AUTH_A[@]}" "${JSON[@]}" -d "$(gifticon_doc "${UID_A}")"
check "A가 자기 기프티콘 조회" 200 -X GET "${DOCS}/gifticons/rules-g-a" "${AUTH_A[@]}"
check "B가 A의 기프티콘 조회 → 차단" 403 -X GET "${DOCS}/gifticons/rules-g-a" "${AUTH_B[@]}"
check "B가 A의 기프티콘 수정 → 차단" 403 -X PATCH "${DOCS}/gifticons/rules-g-a" "${AUTH_B[@]}" "${JSON[@]}" -d "$(gifticon_doc "${UID_A}")"
check "A가 ownerId를 B로 위조해 생성 → 차단" 403 -X PATCH "${DOCS}/gifticons/rules-g-spoof" "${AUTH_A[@]}" "${JSON[@]}" -d "$(gifticon_doc "${UID_B}")"

echo "users — 본인 프로필만"
check "A가 자기 프로필 생성" 200 -X PATCH "${DOCS}/users/${UID_A}" "${AUTH_A[@]}" "${JSON[@]}" -d '{"fields":{"displayName":{"stringValue":"A"}}}'
check "B가 A의 프로필 조회 → 차단" 403 -X GET "${DOCS}/users/${UID_A}" "${AUTH_B[@]}"

echo "groups — 멤버만"
check "A가 그룹 생성(본인이 방장·멤버)" 200 -X PATCH "${DOCS}/groups/rules-grp" "${AUTH_A[@]}" "${JSON[@]}" -d "$(group_doc "${UID_A}" "${UID_A}")"
check "A가 그룹 조회" 200 -X GET "${DOCS}/groups/rules-grp" "${AUTH_A[@]}"
check "B(비멤버)가 그룹 조회 → 차단" 403 -X GET "${DOCS}/groups/rules-grp" "${AUTH_B[@]}"
check "B가 남을 방장으로 그룹 생성 → 차단" 403 -X PATCH "${DOCS}/groups/rules-grp-2" "${AUTH_B[@]}" "${JSON[@]}" -d "$(group_doc "${UID_A}" "${UID_A}")"

echo "groups — 변경 권한 (방장 운영 vs 멤버 나가기)"

# 같은 문서를 두 번 쓰면 앞선 실행이 남긴 상태(소유권 이전 등) 때문에 시드가 막힌다.
# 실행마다 새 문서 id를 쓴다.
RUN="$$-${RANDOM}"

# members 배열 원소 하나(REST mapValue). $1=userId $2=표시이름 $3=role
member_val() {
  printf '{"mapValue":{"fields":{"userId":{"stringValue":"%s"},"displayName":{"stringValue":"%s"},"avatarEmoji":{"stringValue":"🙂"},"role":{"stringValue":"%s"}}}}' "$1" "$2" "$3"
}

# 그룹 전체 문서. $1=ownerId, $2=members 원소들(콤마 구분), $3=memberIds 원소들, $4=초대코드
group_full() {
  printf '{"fields":{"ownerId":{"stringValue":"%s"},"name":{"stringValue":"가족"},"emoji":{"stringValue":"🎁"},"inviteToken":{"stringValue":"%s"},"inviteOwnerOnly":{"booleanValue":false},"inviteExpiresAt":{"timestampValue":"2030-01-01T00:00:00Z"},"maxMembers":{"integerValue":"10"},"members":{"arrayValue":{"values":[%s]}},"memberIds":{"arrayValue":{"values":[%s]}}}}' "$1" "$4" "$2" "$3"
}

# memberIds만 바꾸는 부분 갱신 — 앱의 '나가기'가 보내는 형태. $1=memberIds 원소들
ids_patch() {
  printf '{"fields":{"memberIds":{"arrayValue":{"values":[%s]}}}}' "$1"
}

# members와 memberIds를 함께 바꾸는 부분 갱신. $1=members 원소들, $2=memberIds 원소들
members_patch() {
  printf '{"fields":{"members":{"arrayValue":{"values":[%s]}},"memberIds":{"arrayValue":{"values":[%s]}}}}' "$1" "$2"
}

# Firestore REST의 PATCH는 **updateMask가 없으면 문서 전체를 교체**한다(요청에 없는
# 필드는 삭제된다). 앱은 `tx.update`로 일부 필드만 바꾸므로, 마스크를 붙이지 않으면
# 규칙이 보는 "변경 후 문서"가 실제와 전혀 달라진다 — 예컨대 초대코드만 보낸 요청이
# ownerId·memberIds가 사라진 문서로 판정돼 방장조차 거부당한다.
MASK_MEMBERS='updateMask.fieldPaths=members&updateMask.fieldPaths=memberIds'
MASK_IDS='updateMask.fieldPaths=memberIds'
MASK_OWNER_MEMBERS="updateMask.fieldPaths=ownerId&${MASK_MEMBERS}"
MASK_NAME='updateMask.fieldPaths=name'
MASK_CODE='updateMask.fieldPaths=inviteToken'
MASK_OWNER='updateMask.fieldPaths=ownerId'

M_A=$(member_val "${UID_A}" "A" "owner")
M_B=$(member_val "${UID_B}" "B" "member")
M_B_OWNER=$(member_val "${UID_B}" "B" "owner")
ID_A="{\"stringValue\":\"${UID_A}\"}"
ID_B="{\"stringValue\":\"${UID_B}\"}"

# seed_group <문서 id 접미사> <members> <memberIds> — A가 방장으로 그룹을 만든다.
#
# 만든 문서 경로는 전역 ${SEEDED_DOC}에 담는다. 명령 치환으로 돌려주지 않는 이유:
# check()가 결과 줄을 표준출력에 쓰므로 $(seed_group ...)은 그 줄까지 함께 삼킨다.
SEEDED_DOC=""
seed_group() {
  local suffix="$1" members="$2" ids="$3"
  SEEDED_DOC="groups/rules-grp-${suffix}-${RUN}"
  check "  (준비) ${suffix} 그룹 생성" 200 -X PATCH "${DOCS}/${SEEDED_DOC}" \
    "${AUTH_A[@]}" "${JSON[@]}" -d "$(group_full "${UID_A}" "${members}" "${ids}" "482913")"
}

# ── 비멤버는 스스로 합류할 수 없다(이번 수정의 핵심) ──────────────────────
seed_group join "${M_A}" "${ID_A}"
G_JOIN="${SEEDED_DOC}"
check "B(비멤버)가 자신을 멤버로 추가 → 차단" 403 -X PATCH "${DOCS}/${G_JOIN}?${MASK_MEMBERS}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(members_patch "${M_A},${M_B}" "${ID_A},${ID_B}")"
check "B(비멤버)가 자신을 방장 role로 추가 → 차단" 403 -X PATCH "${DOCS}/${G_JOIN}?${MASK_MEMBERS}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(members_patch "${M_A},${M_B_OWNER}" "${ID_A},${ID_B}")"

# ── 일반 멤버는 '자기 나가기'만 할 수 있다 ────────────────────────────────
seed_group leave "${M_A},${M_B}" "${ID_A},${ID_B}"
G_LEAVE="${SEEDED_DOC}"
check "B(멤버)가 memberIds에서 자기만 빼고 나가기" 200 -X PATCH "${DOCS}/${G_LEAVE}?${MASK_IDS}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(ids_patch "${ID_A}")"

seed_group kick "${M_A},${M_B}" "${ID_A},${ID_B}"
G_KICK="${SEEDED_DOC}"
check "B(멤버)가 방장을 memberIds에서 제거 → 차단" 403 -X PATCH "${DOCS}/${G_KICK}?${MASK_IDS}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(ids_patch "${ID_B}")"

# 나가기가 members까지 건드릴 수 있으면, memberIds에서는 자기를 빼면서 members에서는
# **남을** 지우는 조합이 크기·포함 검사를 모두 통과한다(두 필드가 갈라져, 지워진 멤버는
# 화면에서 사라지지만 memberIds 기반 규칙·쿼리에서는 살아 있는 유령이 된다).
# 그래서 나가기는 memberIds 한 필드로 못박혀 있다 — 이 케이스가 그 못을 지킨다.
seed_group splitleave "${M_A},${M_B}" "${ID_A},${ID_B}"
G_SPLIT="${SEEDED_DOC}"
check "B(멤버)가 나가면서 members에서는 방장을 지우기 → 차단" 403 -X PATCH "${DOCS}/${G_SPLIT}?${MASK_MEMBERS}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(members_patch "${M_B}" "${ID_A}")"

seed_group promote "${M_A},${M_B}" "${ID_A},${ID_B}"
G_PROMO="${SEEDED_DOC}"
check "B(멤버)가 자기 role을 방장으로 승격 → 차단" 403 -X PATCH "${DOCS}/${G_PROMO}?${MASK_MEMBERS}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(members_patch "${M_A},${M_B_OWNER}" "${ID_A},${ID_B}")"

seed_group meta "${M_A},${M_B}" "${ID_A},${ID_B}"
G_META="${SEEDED_DOC}"
check "B(멤버)가 그룹 이름 변경 → 차단" 403 -X PATCH "${DOCS}/${G_META}?${MASK_NAME}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d '{"fields":{"name":{"stringValue":"납치된 그룹"}}}'
check "A(방장)가 초대코드 재발급" 200 -X PATCH "${DOCS}/${G_META}?${MASK_CODE}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d '{"fields":{"inviteToken":{"stringValue":"771205"}}}'

# ── 방장은 운영 전반을 할 수 있지만, 방장 자리를 비울 수는 없다 ──────────
seed_group remove "${M_A},${M_B}" "${ID_A},${ID_B}"
G_RM="${SEEDED_DOC}"
check "A(방장)가 B를 내보내기" 200 -X PATCH "${DOCS}/${G_RM}?${MASK_MEMBERS}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(members_patch "${M_A}" "${ID_A}")"

seed_group transfer "${M_A},${M_B}" "${ID_A},${ID_B}"
G_TR="${SEEDED_DOC}"
check "A(방장)가 멤버 아닌 사람에게 소유권 이전 → 차단" 403 -X PATCH "${DOCS}/${G_TR}?${MASK_OWNER}" \
  "${AUTH_A[@]}" "${JSON[@]}" \
  -d "{\"fields\":{\"ownerId\":{\"stringValue\":\"ghost-uid\"}}}"
check "A(방장)가 그냥 나가서 방장 자리를 비움 → 차단" 403 -X PATCH "${DOCS}/${G_TR}?${MASK_MEMBERS}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(members_patch "${M_B}" "${ID_B}")"
check "A(방장)가 B에게 소유권을 넘기고 나가기" 200 -X PATCH "${DOCS}/${G_TR}?${MASK_OWNER_MEMBERS}" \
  "${AUTH_A[@]}" "${JSON[@]}" \
  -d "{\"fields\":{\"ownerId\":{\"stringValue\":\"${UID_B}\"},\"members\":{\"arrayValue\":{\"values\":[${M_B_OWNER}]}},\"memberIds\":{\"arrayValue\":{\"values\":[${ID_B}]}}}}"

echo "inviteTokens / joinRequests — 초대 링크 참여 요청"

# 참여 요청 계층은 문서 두 종류가 맞물린다.
#   inviteTokens/{token} : 비멤버가 토큰으로 그룹을 찾는 유일한 다리(groupId + 만료만)
#   joinRequests/{groupId}_{userId} : 승인 대기 문서
# 규칙이 잘못되면 두 방향으로 샌다 — 토큰 목록을 훑어 모든 그룹 id를 얻거나,
# 대기자 명단(아직 멤버가 아닌 사람들의 이름)이 일반 멤버에게 열린다.

# 만료 시각. 미래/과거 두 개를 쓴다.
FUT='2035-01-01T00:00:00Z'
PAST='2020-01-01T00:00:00Z'

# 그룹 문서(방장 A). $1=memberIds 원소들, $2=members 원소들, $3=만료, $4=groupId(토큰 접미)
jr_group_doc() {
  printf '{"fields":{"ownerId":{"stringValue":"%s"},"name":{"stringValue":"가족"},"emoji":{"stringValue":"🎁"},"inviteToken":{"stringValue":"tok-%s"},"inviteOwnerOnly":{"booleanValue":false},"inviteExpiresAt":{"timestampValue":"%s"},"maxMembers":{"integerValue":"10"},"members":{"arrayValue":{"values":[%s]}},"memberIds":{"arrayValue":{"values":[%s]}}}}' \
    "${UID_A}" "$4" "$3" "$2" "$1"
}

jr_token_doc() {
  printf '{"fields":{"groupId":{"stringValue":"%s"},"expiresAt":{"timestampValue":"%s"}}}' "$1" "$2"
}

# 요청 시각 — 규칙이 `request.time` 근처만 허용하므로(대기 순서 조작 방지)
# 픽스처도 고정값이 아니라 실행 시각을 쓴다. 하드코딩하면 규칙이 조여지는 순간 깨진다.
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 참여 요청 문서. $1=groupId $2=userId $3=status
jr_request_doc() {
  printf '{"fields":{"groupId":{"stringValue":"%s"},"userId":{"stringValue":"%s"},"displayName":{"stringValue":"손님"},"avatarEmoji":{"stringValue":"🙂"},"requestedAt":{"timestampValue":"'"${NOW_TS}"'"},"status":{"stringValue":"%s"}}}' "$1" "$2" "$3"
}

# 대기 목록 질의(방장 전용이어야 한다). $1=groupId
jr_pending_query() {
  printf '{"structuredQuery":{"from":[{"collectionId":"joinRequests"}],"where":{"compositeFilter":{"op":"AND","filters":[{"fieldFilter":{"field":{"fieldPath":"groupId"},"op":"EQUAL","value":{"stringValue":"%s"}}},{"fieldFilter":{"field":{"fieldPath":"status"},"op":"EQUAL","value":{"stringValue":"pending"}}}]}},"orderBy":[{"field":{"fieldPath":"requestedAt"}}]}}' "$1"
}

JR_RUN="jr-$$-${RANDOM}"
G_JR="grp-${JR_RUN}"          # A 방장 · B 멤버
G_EXP="grpexp-${JR_RUN}"      # 만료된 초대

# 시드 — A가 만든다(생성 규칙: ownerId==본인 && 본인이 멤버).
check "  (준비) 참여요청용 그룹 생성" 200 -X PATCH "${DOCS}/groups/${G_JR}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_group_doc "${ID_A},${ID_B}" "${M_A},${M_B}" "${FUT}" "${G_JR}")"
check "  (준비) 만료 그룹 생성" 200 -X PATCH "${DOCS}/groups/${G_EXP}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_group_doc "${ID_A}" "${M_A}" "${PAST}" "${G_EXP}")"

# ── inviteTokens ─────────────────────────────────────────────────────
check "방장이 토큰 조회 문서 발급" 200 -X PATCH "${DOCS}/inviteTokens/tok-${G_JR}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_token_doc "${G_JR}" "${FUT}")"
check "방장이 만료 그룹 토큰 발급" 200 -X PATCH "${DOCS}/inviteTokens/tok-${G_EXP}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_token_doc "${G_EXP}" "${PAST}")"
check "비멤버가 토큰 문서를 id로 조회(다리 역할)" 200 -X GET "${DOCS}/inviteTokens/tok-${G_JR}" "${AUTH_C[@]}"
check "비방장이 토큰 문서 발급 → 차단" 403 -X PATCH "${DOCS}/inviteTokens/tok-forged-${JR_RUN}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_token_doc "${G_JR}" "${FUT}")"
check "토큰 문서에 여분 필드 → 차단" 403 -X PATCH "${DOCS}/inviteTokens/tok-extra-${JR_RUN}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "{\"fields\":{\"groupId\":{\"stringValue\":\"${G_JR}\"},\"expiresAt\":{\"timestampValue\":\"${FUT}\"},\"name\":{\"stringValue\":\"가족\"}}}"
check "기존 토큰을 다른 그룹으로 돌려쓰기 → 차단" 403 -X PATCH "${DOCS}/inviteTokens/tok-${G_JR}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_token_doc "${G_EXP}" "${FUT}")"

# ── joinRequests 생성 ────────────────────────────────────────────────
check "비멤버(C)가 참여 요청 생성" 200 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_C}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_JR}" "${UID_C}" pending)"
check "남의 이름으로 요청 생성 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_B}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_JR}" "${UID_B}" pending)"
check "문서 id 규약을 어긴 요청 → 차단" 403 -X PATCH "${DOCS}/joinRequests/wrong-${JR_RUN}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_JR}" "${UID_C}" pending)"
check "처음부터 승인 상태로 생성 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_EXP}_${UID_C}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_EXP}" "${UID_C}" approved)"
check "이미 멤버(B)가 요청 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_B}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_JR}" "${UID_B}" pending)"
check "만료된 초대로 요청 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_EXP}_${UID_C}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_EXP}" "${UID_C}" pending)"

# ── joinRequests 읽기 — 요청자 본인과 방장만 ─────────────────────────
check "방장이 대기 목록 질의" 200 -X POST "${DOCS}:runQuery" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_pending_query "${G_JR}")"
check "일반 멤버(B)가 대기 목록 질의 → 차단" 403 -X POST "${DOCS}:runQuery" \
  "${AUTH_B[@]}" "${JSON[@]}" -d "$(jr_pending_query "${G_JR}")"
check "요청자 본인이 자기 요청 조회" 200 -X GET "${DOCS}/joinRequests/${G_JR}_${UID_C}" "${AUTH_C[@]}"
check "일반 멤버(B)가 남의 요청 조회 → 차단" 403 -X GET "${DOCS}/joinRequests/${G_JR}_${UID_C}" "${AUTH_B[@]}"

# ── joinRequests 결정 — 방장만, 대기 중인 것만, status 한 필드만 ─────
MASK_STATUS='updateMask.fieldPaths=status'
check "요청자가 자기 요청을 승인 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_C}?${MASK_STATUS}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d '{"fields":{"status":{"stringValue":"approved"}}}'
check "일반 멤버(B)가 승인 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_C}?${MASK_STATUS}" \
  "${AUTH_B[@]}" "${JSON[@]}" -d '{"fields":{"status":{"stringValue":"approved"}}}'
check "방장이 status 외 필드까지 변경 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_C}?updateMask.fieldPaths=status&updateMask.fieldPaths=userId" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "{\"fields\":{\"status\":{\"stringValue\":\"approved\"},\"userId\":{\"stringValue\":\"${UID_B}\"}}}"
check "방장이 승인" 200 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_C}?${MASK_STATUS}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d '{"fields":{"status":{"stringValue":"approved"}}}'
check "이미 처리된 요청을 방장이 다시 결정 → 차단" 403 -X PATCH "${DOCS}/joinRequests/${G_JR}_${UID_C}?${MASK_STATUS}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d '{"fields":{"status":{"stringValue":"rejected"}}}'

# ── joinRequests 삭제 — 요청자의 취소, 방장의 정리 ───────────────────
# ── inviteTokens 열거·삭제 — 설계의 핵심 불변식 ──────────────────────
# `list`를 막는 것이 이 스키마의 전제다(토큰을 몰라도 훑으면 모든 그룹 id를 얻는다).
Q_TOKENS='{"structuredQuery":{"from":[{"collectionId":"inviteTokens"}]}}'
check "토큰 컬렉션 훑기(list) → 차단" 403 -X POST "${DOCS}:runQuery"   "${AUTH_C[@]}" "${JSON[@]}" -d "${Q_TOKENS}"
check "방장도 토큰 컬렉션은 훑을 수 없다" 403 -X POST "${DOCS}:runQuery"   "${AUTH_A[@]}" "${JSON[@]}" -d "${Q_TOKENS}"
check "비방장이 토큰 문서 삭제 → 차단" 403 -X DELETE "${DOCS}/inviteTokens/tok-${G_EXP}" "${AUTH_C[@]}"
# 레거시 그룹에는 이 문서가 아예 없다. no-op 삭제가 막히면 그룹 삭제·나가기·재발급이
# 통째로 죽는다 — 규칙에서 `resource == null`을 빠뜨리면 여기서 잡힌다.
check "없는 토큰 문서 삭제는 no-op" 200 -X DELETE "${DOCS}/inviteTokens/tok-absent-${JR_RUN}" "${AUTH_A[@]}"
check "방장이 토큰 문서 삭제" 200 -X DELETE "${DOCS}/inviteTokens/tok-${G_EXP}" "${AUTH_A[@]}"

# ── 재요청(거절 → 대기)과 방장의 정리 ───────────────────
# 전용 그룹을 쓴다 — 재요청자는 비멤버여야 하고(canRequestJoin), 문서 id는
# `{groupId}_{userId}` 규약을 지켜야 한다.
G_RE="grpre-${JR_RUN}"
check "  (준비) 재요청용 그룹 생성" 200 -X PATCH "${DOCS}/groups/${G_RE}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_group_doc "${ID_A}" "${M_A}" "${FUT}" "${G_RE}")"
check "  (준비) 재요청용 토큰 발급" 200 -X PATCH "${DOCS}/inviteTokens/tok-${G_RE}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d "$(jr_token_doc "${G_RE}" "${FUT}")"
check "  (준비) C가 요청" 200 -X PATCH "${DOCS}/joinRequests/${G_RE}_${UID_C}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_RE}" "${UID_C}" pending)"
check "방장이 거절" 200 -X PATCH "${DOCS}/joinRequests/${G_RE}_${UID_C}?${MASK_STATUS}" \
  "${AUTH_A[@]}" "${JSON[@]}" -d '{"fields":{"status":{"stringValue":"rejected"}}}'
check "요청자가 거절된 요청을 다시 대기로(재요청)" 200 -X PATCH "${DOCS}/joinRequests/${G_RE}_${UID_C}" \
  "${AUTH_C[@]}" "${JSON[@]}" -d "$(jr_request_doc "${G_RE}" "${UID_C}" pending)"
check "방장이 남의 요청 삭제(그룹 소멸 캐스케이드 경로)" 200 -X DELETE \
  "${DOCS}/joinRequests/${G_RE}_${UID_C}" "${AUTH_A[@]}"

# 없는 요청 문서의 read·delete는 **403이 맞다**(규칙이 `resource.data`를 만진다).
# 그 사실을 고정해 둔다 — 이걸 모르고 `get`으로 존재를 확인하려다 정리 경로가 통째로 죽었다.
# 클라이언트(`_dropJoinRequest`)는 그래서 바로 지우고 권한 거부를 정상 종료로 삼는다.
check "없는 요청 문서 조회 → 403" 403 -X GET "${DOCS}/joinRequests/absent-${JR_RUN}" "${AUTH_A[@]}"
check "없는 요청 문서 삭제 → 403" 403 -X DELETE "${DOCS}/joinRequests/absent-${JR_RUN}" "${AUTH_A[@]}"
check "일반 멤버(B)가 남의 요청 삭제 → 차단" 403 -X DELETE "${DOCS}/joinRequests/${G_JR}_${UID_C}" "${AUTH_B[@]}"
check "요청자 본인이 취소" 200 -X DELETE "${DOCS}/joinRequests/${G_JR}_${UID_C}" "${AUTH_C[@]}"

echo
echo "결과: 통과 ${pass} / 실패 ${fail}"
[[ "${fail}" -eq 0 ]] || exit 1
