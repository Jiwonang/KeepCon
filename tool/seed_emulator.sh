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

# ⚠️ 한글이 든 요청 본문은 **반드시 파일로** 넘긴다(`-d @파일`).
#    Windows의 네이티브 curl에 한글을 인자로 직접 주면(`-d '{"displayName":"방장"}'`)
#    프로세스 경계에서 재인코딩되어 U+FFFD로 깨진다 — bash 안에서는 멀쩡한데 curl에
#    전달되며 손상되므로 눈에 잘 안 띈다. 파일 경유는 바이트가 그대로 전달된다.
#    (경로는 상대경로로 둔다. MSYS가 절대경로를 Windows 경로로 바꾸는 문제를 피한다.)
PAYLOAD='./.seed-payload.tmp.json'
trap 'rm -f "${PAYLOAD}"' EXIT

# 계정을 만들고 표시 이름을 설정한 뒤, users/{uid} 프로필 문서까지 쓴다.
# 앱의 FirebaseAuthRepository.signUp이 하는 일과 같은 결과를 만든다.
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
  curl -s -o /dev/null -X POST "${IDP}/accounts:update?key=demo-api-key" \
    -H 'Content-Type: application/json' -d @"${PAYLOAD}"

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

  echo "  ✓ ${name} <${email}> uid=${uid}"
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
seed_account 'member@keepcon.test' '파티원' || exit 1

echo "내보내는 중 → ${SEED_DIR}/"
rm -rf "${SEED_DIR}"
if ! firebase emulators:export "${SEED_DIR}" --project "${PROJECT}" --force; then
  echo "✗ 내보내기 실패."
  exit 1
fi

echo
echo "완료. ${SEED_DIR}/ 를 커밋하면 팀원 전원이 같은 계정으로 시작합니다."
echo "  방장   owner@keepcon.test  / ${SEED_PASSWORD}"
echo "  파티원 member@keepcon.test / ${SEED_PASSWORD}"
