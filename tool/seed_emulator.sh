#!/usr/bin/env bash
# KeepCon — 에뮬레이터 시드 계정 생성 + `emulator-seed/`로 내보내기.
#
# 왜 필요한가:
#   에뮬레이터 데이터는 프로세스를 끄면 사라진다. 그러면 팀원마다 각자 회원가입을
#   해야 하고, uid가 달라 "방장 A / 파티원 B" 같은 시나리오를 공유할 수 없다.
#   이 스크립트로 만든 계정을 `emulator-seed/`에 내보내 **git으로 커밋**하면,
#   clone한 팀원 누구나 같은 계정·같은 uid로 즉시 로그인할 수 있다.
#
# 언제 실행하나:
#   시드 계정을 **바꾸고 싶을 때만**. 평소 개발에서는 실행할 필요가 없다
#   (`tool/emulators.sh`가 커밋된 시드를 읽어서 띄운다).
#   ⚠️ 실행하면 에뮬레이터의 기존 Auth/Firestore 데이터를 **전부 지운다.**
#
# 사용법:
#   1) 터미널 A: bash tool/emulators.sh   (또는 firebase emulators:start …)
#   2) 터미널 B: bash tool/seed_emulator.sh
#   3) 생성된 emulator-seed/ 를 커밋
#
# 비밀번호는 공개 저장소에 그대로 적힌 **테스트 전용 값**이다. 실제 서비스 계정에
# 절대 재사용하지 마라(에뮬레이터는 실제 Google 백엔드와 연결되지 않는다).
set -uo pipefail

PROJECT="${FIRESTORE_PROJECT:-demo-keepcon}"
AUTH_HOST="${AUTH_EMULATOR_HOST:-localhost:9099}"
FS_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8080}"
SEED_DIR="${SEED_DIR:-emulator-seed}"
IDP="http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1"
DOCS="http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents"
# 데이터 전체 삭제는 **에뮬레이터 전용 엔드포인트**(`/emulator/v1/`)를 써야 한다.
# 일반 REST 경로(`/v1/`)로 DELETE를 보내면 조용히 아무것도 지워지지 않아,
# 예전 시드가 남은 채로 export되는 사고가 난다.
FS_CLEAR="http://${FS_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents"

# 시드 계정 공통 비밀번호(테스트 전용).
SEED_PASSWORD='test1234'

# 프로필 문서의 createdAt 고정값 — 시드를 다시 만들어도 diff가 안 나게 한다.
SEED_CREATED_AT='2026-01-01T00:00:00Z'

# 시드 그룹. 문서 id·초대코드를 **고정**해 팀원 전원이 같은 값을 공유하게 한다
# (앱의 createGroup은 문서 id 해시로 코드를 만들지만, 시드는 재현 가능해야 한다).
SEED_GROUP_ID='seed-group-family'
SEED_GROUP_INVITE_CODE='482913'
# GroupMember.avatarEmoji 기본값 — FirebaseShareRepository._defaultAvatar와 같은 값.
SEED_AVATAR='🙂'

# ⚠️ 한글이 든 요청 본문은 **반드시 파일로** 넘긴다(`-d @파일`).
#    Windows의 네이티브 curl에 한글을 인자로 직접 주면(`-d '{"displayName":"방장"}'`)
#    프로세스 경계에서 재인코딩되어 U+FFFD로 깨진다 — bash 안에서는 멀쩡한데 curl에
#    전달되며 손상되므로 눈에 잘 안 띈다. 파일 경유는 바이트가 그대로 전달된다.
#    (경로는 상대경로로 둔다. MSYS가 절대경로를 Windows 경로로 바꾸는 문제를 피한다.)
PAYLOAD='./.seed-payload.tmp.json'
trap 'rm -f "${PAYLOAD}"' EXIT

# 계정을 만들고 표시 이름을 설정한 뒤, users/{uid} 프로필 문서까지 쓴다.
# 앱의 FirebaseAuthRepository.signUp이 하는 일과 같은 결과를 만든다.
# 성공 시 호출부가 쓰도록 SEED_UID / SEED_TOKEN에 결과를 남긴다.
# $1 = email, $2 = displayName
seed_account() {
  local email="$1" name="$2"
  local res token uid code

  printf '{"email":"%s","password":"%s","returnSecureToken":true}' \
    "${email}" "${SEED_PASSWORD}" >"${PAYLOAD}"
  res=$(curl -s -X POST "${IDP}/accounts:signUp?key=demo-api-key" \
    -H 'Content-Type: application/json' -d @"${PAYLOAD}")
  token=$(sed -n 's/.*"idToken": *"\([^"]*\)".*/\1/p' <<<"${res}")
  uid=$(sed -n 's/.*"localId": *"\([^"]*\)".*/\1/p' <<<"${res}")
  if [[ -z "${token}" || -z "${uid}" ]]; then
    echo "  ✗ ${email} 계정 생성 실패: ${res}"
    return 1
  fi

  # 표시 이름 갱신(앱의 updateDisplayName과 동일 — authStateChanges에 반영된다).
  # accounts:update 응답에는 새 idToken이 없다 — 아래 Firestore 요청은 signUp에서 받은
  # 토큰을 계속 써야 한다(응답에서 다시 뽑으면 빈 값이 되어 500이 난다).
  printf '{"idToken":"%s","displayName":"%s"}' "${token}" "${name}" >"${PAYLOAD}"
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    "${IDP}/accounts:update?key=demo-api-key" \
    -H 'Content-Type: application/json' -d @"${PAYLOAD}")
  if [[ "${code}" != "200" ]]; then
    echo "  ✗ ${email} 표시 이름 설정 실패 (HTTP ${code})"
    return 1
  fi

  # 프로필 문서 — 본인 토큰으로 쓴다(보안 규칙 users/{uid} 경로를 실제로 통과).
  printf '{"fields":{"email":{"stringValue":"%s"},"displayName":{"stringValue":"%s"},"createdAt":{"timestampValue":"%s"}}}' \
    "${email}" "${name}" "${SEED_CREATED_AT}" >"${PAYLOAD}"
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "${DOCS}/users/${uid}" \
    -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' \
    -d @"${PAYLOAD}")
  if [[ "${code}" != "200" ]]; then
    echo "  ✗ ${email} 프로필 문서 저장 실패 (HTTP ${code})"
    return 1
  fi

  SEED_UID="${uid}"
  SEED_TOKEN="${token}"
  echo "  ✓ ${name} <${email}> uid=${uid}"
}

# 방장·파티원이 함께 속한 그룹 문서를 만든다.
# 앱의 FirebaseShareRepository._groupToDoc이 쓰는 것과 **같은 스키마**여야 한다:
#   members(맵 배열) + memberIds(조회용 역정규화) + ownerId(보안 규칙 방장 판정용).
# 셋 중 하나라도 빠지면 목록 조회나 규칙 판정이 조용히 어긋난다.
# $1 = 방장 uid, $2 = 방장 토큰, $3 = 방장 이름, $4 = 파티원 uid, $5 = 파티원 이름
seed_group() {
  local owner_uid="$1" owner_token="$2" owner_name="$3"
  local member_uid="$4" member_name="$5"
  local code

  printf '{"fields":{"name":{"stringValue":"%s"},"emoji":{"stringValue":"%s"},"inviteCode":{"stringValue":"%s"},"inviteOwnerOnly":{"booleanValue":false},"members":{"arrayValue":{"values":[{"mapValue":{"fields":{"userId":{"stringValue":"%s"},"displayName":{"stringValue":"%s"},"avatarEmoji":{"stringValue":"%s"},"role":{"stringValue":"owner"}}}},{"mapValue":{"fields":{"userId":{"stringValue":"%s"},"displayName":{"stringValue":"%s"},"avatarEmoji":{"stringValue":"%s"},"role":{"stringValue":"member"}}}}]}},"memberIds":{"arrayValue":{"values":[{"stringValue":"%s"},{"stringValue":"%s"}]}},"ownerId":{"stringValue":"%s"}}}' \
    '우리 가족' '👪' "${SEED_GROUP_INVITE_CODE}" \
    "${owner_uid}" "${owner_name}" "${SEED_AVATAR}" \
    "${member_uid}" "${member_name}" "${SEED_AVATAR}" \
    "${owner_uid}" "${member_uid}" \
    "${owner_uid}" >"${PAYLOAD}"

  # 방장 토큰으로 쓴다 — 보안 규칙의 그룹 생성 조건(ownerId==본인 && 본인이 멤버)을
  # 실제로 통과하는지 여기서 같이 검증된다.
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    "${DOCS}/groups/${SEED_GROUP_ID}" \
    -H "Authorization: Bearer ${owner_token}" -H 'Content-Type: application/json' \
    -d @"${PAYLOAD}")
  if [[ "${code}" != "200" ]]; then
    echo "  ✗ 그룹 생성 실패 (HTTP ${code})"
    return 1
  fi

  echo "  ✓ 그룹 '우리 가족' id=${SEED_GROUP_ID} 초대코드=${SEED_GROUP_INVITE_CODE}"
}

echo "에뮬레이터 시드 생성 (project=${PROJECT})"

if ! curl -s -o /dev/null --max-time 3 "http://${FS_HOST}/"; then
  echo "✗ 에뮬레이터에 연결할 수 없습니다. 먼저 실행하세요:"
  echo "    bash tool/emulators.sh"
  exit 1
fi

echo "기존 데이터 삭제 중…"
fs_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "${FS_CLEAR}")
auth_code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE \
  "http://${AUTH_HOST}/emulator/v1/projects/${PROJECT}/accounts")
if [[ "${fs_code}" != "200" || "${auth_code}" != "200" ]]; then
  echo "✗ 기존 데이터 삭제 실패 (firestore=${fs_code}, auth=${auth_code})."
  echo "  그대로 진행하면 예전 시드가 섞인 채 export됩니다. 중단합니다."
  exit 1
fi

echo "계정 생성 중…"
seed_account 'owner@keepcon.test' '방장' || exit 1
OWNER_UID="${SEED_UID}"
OWNER_TOKEN="${SEED_TOKEN}"
seed_account 'member@keepcon.test' '파티원' || exit 1
MEMBER_UID="${SEED_UID}"
MEMBER_TOKEN="${SEED_TOKEN}"

echo "그룹 생성 중…"
seed_group "${OWNER_UID}" "${OWNER_TOKEN}" '방장' "${MEMBER_UID}" '파티원' || exit 1

# 내보내기 **전에** 저장된 내용을 다시 읽어 대조한다.
#
# 왜 필요한가: 이 스크립트가 실제로 겪은 실패 두 건이 모두 "HTTP 200인데 데이터가
# 틀린" 형태였다 — 한글이 U+FFFD로 깨진 채 저장된 적, 삭제가 안 먹어 예전 시드가
# 섞인 채 export된 적. 상태 코드만 보면 둘 다 통과한다. 값을 되읽어 대조해야 잡힌다.
#
# 비교는 bash 내장 패턴 매칭(`[[ == *…* ]]`)으로 한다. grep 같은 네이티브 바이너리에
# 한글을 인자로 넘기면 위에 적은 그 인코딩 문제를 그대로 다시 밟는다.
verify_seed() {
  local ok=0

  # $1 = 설명, $2 = 응답 본문, $3 = 들어 있어야 할 문자열
  expect_contains() {
    if [[ "$2" == *"$3"* ]]; then
      echo "  ✓ $1"
    else
      echo "  ✗ $1 — '$3' 를 찾지 못했습니다."
      ok=1
    fi
  }

  local res
  # Auth 프로필(표시 이름)이 온전한지.
  printf '{"idToken":"%s"}' "${OWNER_TOKEN}" >"${PAYLOAD}"
  res=$(curl -s -X POST "${IDP}/accounts:lookup?key=demo-api-key" \
    -H 'Content-Type: application/json' -d @"${PAYLOAD}")
  expect_contains 'Auth 표시 이름(방장)' "${res}" '방장'

  # Firestore 프로필 문서.
  res=$(curl -s -X GET "${DOCS}/users/${OWNER_UID}" \
    -H "Authorization: Bearer ${OWNER_TOKEN}")
  expect_contains 'users 프로필(방장)' "${res}" '방장'

  # 그룹 문서 — 이름·양쪽 멤버·역할·역정규화 필드가 모두 있어야 한다.
  res=$(curl -s -X GET "${DOCS}/groups/${SEED_GROUP_ID}" \
    -H "Authorization: Bearer ${OWNER_TOKEN}")
  # Firestore REST 응답은 들여쓴 JSON이라 `"role":{"stringValue":...}` 같은 압축 패턴이
  # 그대로는 안 맞는다. 구조 검사용으로 공백·줄바꿈을 지운 사본을 따로 만든다.
  # (tr에는 ASCII만 인자로 주고 데이터는 stdin으로 흘리므로 인코딩 문제가 없다.)
  local compact
  compact=$(tr -d ' \n\r' <<<"${res}")
  expect_contains '그룹 이름'           "${res}"     '우리 가족'
  expect_contains '그룹 멤버(방장)'     "${res}"     "${OWNER_UID}"
  expect_contains '그룹 멤버(파티원)'   "${res}"     "${MEMBER_UID}"
  expect_contains '방장 역할(owner)'    "${compact}" '"role":{"stringValue":"owner"}'
  expect_contains '파티원 역할(member)' "${compact}" '"role":{"stringValue":"member"}'
  # 역정규화 필드 — 빠지면 목록 조회·규칙 판정이 조용히 어긋난다.
  expect_contains 'memberIds 역정규화'  "${compact}" '"memberIds":{"arrayValue"'
  expect_contains 'ownerId 역정규화'    "${compact}" "\"ownerId\":{\"stringValue\":\"${OWNER_UID}\"}"

  # 파티원도 그룹을 읽을 수 있어야 한다(멤버십 규칙).
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X GET \
    "${DOCS}/groups/${SEED_GROUP_ID}" -H "Authorization: Bearer ${MEMBER_TOKEN}")
  if [[ "${code}" == "200" ]]; then
    echo "  ✓ 파티원의 그룹 접근(멤버십 규칙)"
  else
    echo "  ✗ 파티원이 그룹을 읽지 못합니다 (HTTP ${code})"
    ok=1
  fi

  return "${ok}"
}

echo "저장 내용 검증 중…"
if ! verify_seed; then
  echo "✗ 검증 실패. 깨진 데이터를 export하지 않도록 중단합니다."
  exit 1
fi

echo "내보내는 중 → ${SEED_DIR}/"
rm -rf "${SEED_DIR}"
if ! firebase emulators:export "${SEED_DIR}" --project "${PROJECT}" --force; then
  echo "✗ 내보내기 실패."
  exit 1
fi

echo
echo "완료. ${SEED_DIR}/ 를 커밋하면 팀원 전원이 같은 계정·같은 그룹으로 시작합니다."
echo "  방장   owner@keepcon.test  / ${SEED_PASSWORD}"
echo "  파티원 member@keepcon.test / ${SEED_PASSWORD}"
echo "  그룹   '우리 가족' (초대코드 ${SEED_GROUP_INVITE_CODE}) — 방장·파티원 모두 소속"
