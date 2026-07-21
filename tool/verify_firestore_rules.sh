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
# 주의: 인증 헤더 없이 Firestore 에뮬레이터 REST를 호출하면 **관리자로 취급되어 규칙을
#   우회**한다. 그래서 모든 케이스는 반드시 사용자 ID 토큰을 붙여 호출한다.
set -uo pipefail

PROJECT="${FIRESTORE_PROJECT:-demo-keepcon}"
AUTH_HOST="${AUTH_EMULATOR_HOST:-localhost:9099}"
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

TOKEN_A=$(signup "rules-a@keepcon.test")
TOKEN_B=$(signup "rules-b@keepcon.test")
if [[ -z "${TOKEN_A}" || -z "${TOKEN_B}" ]]; then
  echo "✗ Auth 에뮬레이터에서 테스트 사용자를 만들지 못했습니다."
  exit 1
fi
UID_A=$(uid_of "${TOKEN_A}")
UID_B=$(uid_of "${TOKEN_B}")
echo "  테스트 사용자: A=${UID_A}, B=${UID_B}"

AUTH_A=(-H "Authorization: Bearer ${TOKEN_A}")
AUTH_B=(-H "Authorization: Bearer ${TOKEN_B}")
JSON=(-H 'Content-Type: application/json')

gifticon_doc() { # $1 = ownerId
  printf '{"fields":{"ownerId":{"stringValue":"%s"},"brand":{"stringValue":"스타벅스"},"productName":{"stringValue":"아메리카노"},"price":{"integerValue":"4500"},"category":{"stringValue":"카페"},"status":{"stringValue":"available"}}}' "$1"
}

group_doc() { # $1 = ownerId, $2 = memberId
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

echo
echo "결과: 통과 ${pass} / 실패 ${fail}"
[[ "${fail}" -eq 0 ]] || exit 1
