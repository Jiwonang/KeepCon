#!/usr/bin/env bash
# KeepCon — Firestore 보안 규칙·인덱스를 실제 프로젝트에 배포한다.
#
# ## 왜 스크립트인가
# 프로젝트가 dev·prod 둘로 나뉘면서, 규칙을 고쳤을 때 **양쪽에 배포해야** 한다.
# 한쪽만 하면 "dev에선 되는데 실서비스에선 막힘"(또는 그 반대)이 생기고, 원인이
# 코드가 아니라 배포 누락이라 찾는 데 오래 걸린다. 사람 기억에 맡기지 않는다.
#
# 에뮬레이터는 대상이 아니다 — `firebase.json`을 통해 `firestore.rules`를 파일에서
# 직접 읽으므로 배포라는 단계 자체가 없다(에뮬레이터 재시작이면 반영된다).
#
# 사용법:
#   bash tool/deploy_rules.sh            # dev 에만 배포 (기본)
#   bash tool/deploy_rules.sh dev
#   bash tool/deploy_rules.sh prod       # 실서비스. 확인 프롬프트 있음
#   bash tool/deploy_rules.sh all        # dev -> prod 순서로 둘 다
#   bash tool/deploy_rules.sh all --yes  # 확인 없이 (CI용)
#
# ## 순서가 dev 먼저인 이유
# `all`은 dev에 먼저 배포하고, 실패하면 prod로 넘어가지 않는다. 규칙에 문법 오류나
# 의도치 않은 차단이 있으면 dev에서 먼저 드러나게 하려는 것이다.
set -uo pipefail

# 실행 위치와 무관하게 저장소 루트 기준으로 동작하게 한다.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

readonly DEV_PROJECT="keepcon-dev"
readonly PROD_PROJECT="keepcon-ab660"
readonly ONLY="firestore:rules,firestore:indexes"

target="${1:-dev}"
auto_yes=""
for arg in "$@"; do
  [[ "${arg}" == "--yes" ]] && auto_yes="1"
done

if ! command -v firebase >/dev/null 2>&1; then
  echo "✋ firebase CLI를 찾을 수 없습니다. 설치: npm install -g firebase-tools" >&2
  exit 1
fi

for f in firestore.rules firestore.indexes.json; do
  if [[ ! -f "${f}" ]]; then
    echo "✋ ${f} 를 찾을 수 없습니다. 저장소 루트에서 실행했는지 확인하세요." >&2
    exit 1
  fi
done

# 실서비스 배포는 되돌리기 어렵다(잘못된 규칙 = 실사용자 차단). 명시적 확인을 받는다.
confirm_prod() {
  [[ -n "${auto_yes}" ]] && return 0
  echo "⚠️  실서비스 '${PROD_PROJECT}' 에 보안 규칙을 배포합니다."
  echo "   잘못된 규칙은 실사용자의 접근을 즉시 차단합니다."
  read -r -p "   계속하려면 'prod' 를 입력하세요: " answer
  [[ "${answer}" == "prod" ]]
}

deploy_to() {
  local project="$1"
  echo "🚀 ${project} 에 규칙·인덱스 배포 중…"
  if ! firebase deploy --only "${ONLY}" --project "${project}"; then
    echo "✋ ${project} 배포 실패." >&2
    return 1
  fi
  echo "✅ ${project} 완료."
}

case "${target}" in
  dev)
    deploy_to "${DEV_PROJECT}" || exit 1
    ;;
  prod)
    if ! confirm_prod; then
      echo "취소했습니다."
      exit 0
    fi
    deploy_to "${PROD_PROJECT}" || exit 1
    ;;
  all)
    # dev를 먼저 — 여기서 깨지면 prod는 건드리지 않는다.
    deploy_to "${DEV_PROJECT}" || exit 1
    if ! confirm_prod; then
      echo "dev 만 배포하고 종료합니다(prod 취소)."
      exit 0
    fi
    deploy_to "${PROD_PROJECT}" || exit 1
    ;;
  *)
    echo "✋ 알 수 없는 대상: '${target}'" >&2
    echo "   사용법: bash tool/deploy_rules.sh [dev|prod|all] [--yes]" >&2
    exit 1
    ;;
esac

echo ""
echo "ℹ️  에뮬레이터는 배포 대상이 아닙니다 — firestore.rules 를 파일에서 직접 읽습니다."
echo "   규칙 변경을 에뮬레이터에 반영하려면 재시작하세요: bash tool/emulators.sh"
echo "   규칙이 의도대로 막는지 검증: bash tool/verify_firestore_rules.sh"
