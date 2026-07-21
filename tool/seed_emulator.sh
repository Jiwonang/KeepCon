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

# 오늘로부터 $1일 뒤(음수면 앞)의 자정을 ISO 문자열로 돌려준다.
#
# GNU date(리눅스·Git Bash)와 BSD date(macOS)는 상대 날짜 문법이 다르다
# (`-d '5 days'` vs `-v+5d`). 팀에 macOS가 있으면 한쪽만 지원해서는 시드를 다시 만들 수
# 없으므로 양쪽을 모두 처리한다.
iso_day() {
  local days="$1" out
  if out=$(date -u -d "${days} days" +%Y-%m-%dT00:00:00Z 2>/dev/null); then
    printf '%s' "${out}"
    return 0
  fi
  # BSD/macOS: 부호를 그대로 붙인다(-3 → -v-3d, 5 → -v+5d).
  local sign='+'
  [[ "${days}" == -* ]] && sign=''
  if out=$(date -u -v"${sign}${days}d" +%Y-%m-%dT00:00:00Z 2>/dev/null); then
    printf '%s' "${out}"
    return 0
  fi
  echo "✗ date 명령으로 상대 날짜를 계산하지 못했습니다(GNU/BSD 둘 다 실패)." >&2
  return 1
}

# 기프티콘 유효기간은 **시드를 만드는 시점 기준 상대 날짜**로 잡는다.
# 절대 날짜로 박으면 시간이 지나며 전부 만료 상태가 되어, D-day 뱃지·만료임박 정렬 같은
# 화면을 확인할 수 없게 된다. 대신 시드를 다시 만들면 이 값들 때문에 diff가 난다 —
# 화면 확인 가능성이 diff 안정성보다 중요하다고 보고 이쪽을 택했다.
# (시드가 오래되어 날짜가 현실과 어긋나면 이 스크립트를 다시 돌려 갱신하면 된다.)
EXP_SOON=$(iso_day 5) || exit 1    # 만료임박 — D-day 뱃지 확인용
EXP_MID=$(iso_day 12) || exit 1
EXP_FAR=$(iso_day 90) || exit 1
EXP_PAST=$(iso_day -3) || exit 1   # 이미 지남 — expired 상태 확인용

# 기프티콘 속성은 **한 곳에만** 적는다.
# 공유(sharedGifticons) 문서는 브랜드·상품명·유효기간·바코드를 원본에서 복사해 들고 가는
# 역정규화 구조라, 두 곳에 따로 적으면 한쪽만 고쳤을 때 공유 카드와 원본의 정보가
# 어긋난다 — 앱은 두 문서를 각각 그려서 보여주므로 조용히 불일치가 드러난다.
STAR_BRAND='스타벅스';     STAR_NAME='아메리카노 T';       STAR_BARCODE='1234-5678-9012'
BASKIN_BRAND='배스킨라빈스'; BASKIN_NAME='파인트 아이스크림'; BASKIN_BARCODE='9876-5432-1098'

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

# 개인 기프티콘 문서를 만든다(FirebaseGifticonRepository._toDoc과 같은 스키마).
# imagePath는 넣지 않는다 — 아직 이미지 획득/업로드 경로가 없어 항상 null이다.
# 소유자 토큰으로 써서 보안 규칙(ownerId==본인)을 실제로 통과시킨다.
# $1=문서id $2=소유자uid $3=소유자토큰 $4=브랜드 $5=상품명 $6=가격 $7=카테고리
# $8=바코드(빈 문자열이면 필드 생략) $9=유효기간(ISO) $10=상태
seed_gifticon() {
  local id="$1" uid="$2" token="$3" brand="$4" product="$5" price="$6"
  local category="$7" barcode="$8" expiry="$9" status="${10}"
  local barcode_field='' code

  # 바코드는 nullable — 없으면 필드 자체를 빼서 `as String?`가 null을 읽게 한다.
  if [[ -n "${barcode}" ]]; then
    barcode_field=$(printf '"barcode":{"stringValue":"%s"},' "${barcode}")
  fi

  printf '{"fields":{"ownerId":{"stringValue":"%s"},"brand":{"stringValue":"%s"},"productName":{"stringValue":"%s"},"price":{"integerValue":"%s"},%s"category":{"stringValue":"%s"},"expiryDate":{"timestampValue":"%s"},"registeredAt":{"timestampValue":"%s"},"status":{"stringValue":"%s"}}}' \
    "${uid}" "${brand}" "${product}" "${price}" "${barcode_field}" \
    "${category}" "${expiry}" "${SEED_CREATED_AT}" "${status}" >"${PAYLOAD}"

  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "${DOCS}/gifticons/${id}" \
    -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' \
    -d @"${PAYLOAD}")
  if [[ "${code}" != "200" ]]; then
    echo "  ✗ 기프티콘 '${brand} ${product}' 생성 실패 (HTTP ${code})"
    return 1
  fi
  echo "  ✓ ${brand} ${product} (${status}, ~${expiry%%T*})"
}

# 기프티콘을 그룹에 공유한다 — sharedGifticons 문서 + **shareLocks 잠금 문서**.
#
# 잠금 문서를 빼먹으면 안 된다: 앱의 shareGifticon은 `shareLocks/{gifticonId}` 존재
# 여부로 "한 기프티콘은 최대 1회만 공유" 불변식을 강제한다. 잠금 없이 공유 문서만
# 넣으면 시드된 기프티콘을 앱에서 한 번 더 공유할 수 있어 중복 공유가 생긴다.
# $1=공유문서id $2=기프티콘id $3=공유자uid $4=공유자토큰 $5=브랜드 $6=상품명
# $7=유효기간(ISO) $8=바코드(빈 문자열이면 생략)
seed_share() {
  local share_id="$1" gifticon_id="$2" uid="$3" token="$4"
  local brand="$5" product="$6" expiry="$7" barcode="$8"
  local barcode_field='' code

  if [[ -n "${barcode}" ]]; then
    barcode_field=$(printf '"barcode":{"stringValue":"%s"},' "${barcode}")
  fi

  printf '{"fields":{"groupId":{"stringValue":"%s"},"gifticonId":{"stringValue":"%s"},"sharedByUserId":{"stringValue":"%s"},"brand":{"stringValue":"%s"},"productName":{"stringValue":"%s"},"expiryDate":{"timestampValue":"%s"},%s"status":{"stringValue":"available"}}}' \
    "${SEED_GROUP_ID}" "${gifticon_id}" "${uid}" "${brand}" "${product}" \
    "${expiry}" "${barcode_field}" >"${PAYLOAD}"
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    "${DOCS}/sharedGifticons/${share_id}" \
    -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' \
    -d @"${PAYLOAD}")
  if [[ "${code}" != "200" ]]; then
    echo "  ✗ 공유 '${brand} ${product}' 생성 실패 (HTTP ${code})"
    return 1
  fi

  printf '{"fields":{"sharedGifticonId":{"stringValue":"%s"},"groupId":{"stringValue":"%s"}}}' \
    "${share_id}" "${SEED_GROUP_ID}" >"${PAYLOAD}"
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    "${DOCS}/shareLocks/${gifticon_id}" \
    -H "Authorization: Bearer ${token}" -H 'Content-Type: application/json' \
    -d @"${PAYLOAD}")
  if [[ "${code}" != "200" ]]; then
    echo "  ✗ 공유 잠금(${gifticon_id}) 생성 실패 (HTTP ${code})"
    return 1
  fi
  echo "  ✓ 공유: ${brand} ${product} (잠금 포함)"
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

echo "개인 기프티콘 생성 중…"
seed_gifticon 'seed-gift-star' "${OWNER_UID}" "${OWNER_TOKEN}" \
  "${STAR_BRAND}" "${STAR_NAME}" 4500 '카페' "${STAR_BARCODE}" "${EXP_SOON}" 'available' || exit 1
seed_gifticon 'seed-gift-bbq' "${OWNER_UID}" "${OWNER_TOKEN}" \
  'BBQ' '황금올리브 치킨' 20000 '치킨' '' "${EXP_FAR}" 'available' || exit 1
seed_gifticon 'seed-gift-cu' "${OWNER_UID}" "${OWNER_TOKEN}" \
  'CU' '도시락 교환권' 4800 '편의점' '' "${EXP_PAST}" 'expired' || exit 1
seed_gifticon 'seed-gift-baskin' "${MEMBER_UID}" "${MEMBER_TOKEN}" \
  "${BASKIN_BRAND}" "${BASKIN_NAME}" 8900 '디저트' "${BASKIN_BARCODE}" "${EXP_MID}" 'available' || exit 1

# 공유 문서는 위 기프티콘과 **같은 변수**를 넘긴다(값을 다시 적지 않는다).
echo "그룹 공유 중…"
seed_share 'seed-share-star' 'seed-gift-star' "${OWNER_UID}" "${OWNER_TOKEN}" \
  "${STAR_BRAND}" "${STAR_NAME}" "${EXP_SOON}" "${STAR_BARCODE}" || exit 1
seed_share 'seed-share-baskin' 'seed-gift-baskin' "${MEMBER_UID}" "${MEMBER_TOKEN}" \
  "${BASKIN_BRAND}" "${BASKIN_NAME}" "${EXP_MID}" "${BASKIN_BARCODE}" || exit 1

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

  # 개인 기프티콘 — 소유자는 읽히고, 남은 막혀야 한다.
  res=$(curl -s -X GET "${DOCS}/gifticons/seed-gift-star" \
    -H "Authorization: Bearer ${OWNER_TOKEN}")
  expect_contains '기프티콘(스타벅스)' "${res}" '아메리카노 T'

  # 공유 기프티콘 — 그룹 멤버 양쪽 다 읽혀야 한다.
  res=$(curl -s -X GET "${DOCS}/sharedGifticons/seed-share-baskin" \
    -H "Authorization: Bearer ${OWNER_TOKEN}")
  expect_contains '공유 기프티콘(파티원이 공유한 것을 방장이 조회)' \
    "${res}" '파인트 아이스크림'

  # 공유 문서는 원본의 브랜드·상품명을 복사해 들고 가는 역정규화 구조다.
  # 원본과 어긋나면 공유 카드가 실제와 다른 상품을 보여준다.
  res=$(curl -s -X GET "${DOCS}/sharedGifticons/seed-share-star" \
    -H "Authorization: Bearer ${OWNER_TOKEN}")
  expect_contains '공유 문서가 원본과 같은 상품명' "${res}" "${STAR_NAME}"
  expect_contains '공유 문서가 원본과 같은 브랜드' "${res}" "${STAR_BRAND}"

  # 공유 잠금 — 없으면 앱에서 같은 기프티콘을 한 번 더 공유할 수 있다.
  res=$(curl -s -X GET "${DOCS}/shareLocks/seed-gift-star" \
    -H "Authorization: Bearer ${OWNER_TOKEN}")
  expect_contains '공유 잠금(중복 공유 방지)' "${res}" 'seed-share-star'

  # $1 = 설명, $2 = 기대 HTTP 코드, 나머지 = curl 인자
  expect_code() {
    local label="$1" want="$2"; shift 2
    local got
    got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
    if [[ "${got}" == "${want}" ]]; then
      echo "  ✓ ${label}"
    else
      echo "  ✗ ${label} — 기대 ${want}, 실제 ${got}"
      ok=1
    fi
  }

  # 파티원도 그룹을 읽을 수 있어야 한다(멤버십 규칙).
  expect_code '파티원의 그룹 접근(멤버십 규칙)' 200 \
    -X GET "${DOCS}/groups/${SEED_GROUP_ID}" \
    -H "Authorization: Bearer ${MEMBER_TOKEN}"
  # 개인 기프티콘은 그룹 멤버라도 남의 것을 볼 수 없어야 한다(공유와 구분되는 지점).
  expect_code '파티원은 방장의 개인 기프티콘 조회 불가' 403 \
    -X GET "${DOCS}/gifticons/seed-gift-star" \
    -H "Authorization: Bearer ${MEMBER_TOKEN}"

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
echo "  기프티콘 4개(방장 3 · 파티원 1), 그중 2개는 그룹에 공유됨"
