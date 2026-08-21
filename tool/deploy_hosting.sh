#!/usr/bin/env bash
# KeepCon — Flutter 웹 빌드를 Firebase Hosting에 배포한다.
#
# ## 왜 스크립트인가 — 빌드와 배포를 떼어 놓을 수 없게 묶는다
# hosting 루트가 `build/web`(gitignore된 **빌드 산출물**)이라, 배포 내용물이 "직전에
# 어떤 플래그로 빌드했는가"에 달려 있다. 가장 자연스러운 형태인 `flutter build web`
# (플래그 없음)으로 빌드한 뒤 배포하면 **에뮬레이터 타깃 앱**이 올라가고, 방문자
# 브라우저에서 `isEmulatorReachable()`이 실패해 안내 화면만 뜬다 — 모든 초대 링크가
# 거기서 죽는다. 그런데 배포는 성공하고 `assetlinks.json`도 200이라 **아무 신호가 없다.**
#
# 문서에 "플래그를 맞추세요"라고 적는 것으로는 부족하다는 판정을 이 저장소가 이미
# 내렸다 — 규칙 검증을 조건부 사람 판단으로 뒀더니 PR #104에서 세 번 다 건너뛰었고,
# 그래서 `tool/verify.sh`가 생겼다. 판단을 사람에게 남겨 두면 그 판단이 실패한다.
#
# 그래서 이 스크립트는 **대상에서 플래그를 도출해 항상 빌드한 뒤 배포한다.**
# 빌드만 하거나 배포만 하는 경로를 제공하지 않는 것이 요점이다.
#
# 사용법:
#   bash tool/deploy_hosting.sh            # dev (기본)
#   bash tool/deploy_hosting.sh dev
#   bash tool/deploy_hosting.sh prod       # 실서비스. 확인 프롬프트 있음
#   bash tool/deploy_hosting.sh prod --yes # 확인 없이
#
# 에뮬레이터는 대상이 아니다 — 배포할 도메인이 없다(`inviteOriginFor` 참조).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

readonly DEV_PROJECT="keepcon-dev"
readonly PROD_PROJECT="keepcon-ab660"

target="${1:-dev}"
auto_yes=""
for arg in "$@"; do
  [[ "${arg}" == "--yes" ]] && auto_yes="1"
done

for cmd in firebase flutter; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "✋ ${cmd} 를 찾을 수 없습니다." >&2
    exit 1
  fi
done

# assetlinks.json은 빌드 산출물에 실려야 App Links가 검증된다. 없으면 배포해봐야
# 안드로이드 링크가 조용히 브라우저로 샌다 — 배포 전에 막는다.
if [[ ! -f web/.well-known/assetlinks.json ]]; then
  echo "✋ web/.well-known/assetlinks.json 이 없습니다 — App Links 검증이 실패합니다." >&2
  exit 1
fi

confirm_prod() {
  [[ -n "${auto_yes}" ]] && return 0
  echo "⚠️  실서비스 '${PROD_PROJECT}' 에 웹 앱을 배포합니다."
  read -r -p "   계속하려면 'prod' 를 입력하세요: " answer
  [[ "${answer}" == "prod" ]]
}

# 대상 → 빌드 플래그. **이 표가 짝을 강제하는 유일한 지점이다.**
build_and_deploy() {
  local project="$1" define="$2"

  echo "🔨 ${project} 용으로 웹 빌드 중… (${define})"
  # 옛 산출물이 남아 섞이지 않게 지운다 — 플래그가 다른 이전 빌드가 그대로 배포되는
  # 것이 이 스크립트가 막으려는 사고다.
  rm -rf build/web
  if ! flutter build web --release --dart-define="${define}"; then
    echo "✋ 빌드 실패 — 배포하지 않습니다." >&2
    return 1
  fi

  if [[ ! -f build/web/.well-known/assetlinks.json ]]; then
    echo "✋ 빌드 산출물에 assetlinks.json 이 없습니다(web/ 에서 복사되지 않음)." >&2
    return 1
  fi

  echo "🚀 ${project} 에 배포 중…"
  if ! firebase deploy --only hosting --project "${project}"; then
    echo "✋ ${project} 배포 실패." >&2
    return 1
  fi
  echo "✅ ${project} 완료."
}

case "${target}" in
  dev)
    build_and_deploy "${DEV_PROJECT}" "USE_FIREBASE=true" || exit 1
    host="keepcon-dev.web.app"
    ;;
  prod)
    if ! confirm_prod; then
      echo "취소했습니다."
      exit 0
    fi
    build_and_deploy "${PROD_PROJECT}" "USE_FIREBASE_PROD=true" || exit 1
    host="keepcon-ab660.web.app"
    ;;
  *)
    echo "✋ 알 수 없는 대상: '${target}'" >&2
    echo "   사용법: bash tool/deploy_hosting.sh [dev|prod] [--yes]" >&2
    exit 1
    ;;
esac

# 배포는 성공했는데 검증 파일이 404인 상태가 실제로 있었다(도메인을 매니페스트에만
# 넣고 배포하지 않았던 기간). 여기서 확인해 그 상태로 끝나지 않게 한다.
echo
echo "🔎 https://${host}/.well-known/assetlinks.json 확인…"
if command -v curl >/dev/null 2>&1; then
  code=$(curl -s -o /dev/null -w '%{http_code}' "https://${host}/.well-known/assetlinks.json")
  if [[ "${code}" == "200" ]]; then
    echo "✅ 200 — App Links 검증 준비 완료."
  else
    echo "✋ HTTP ${code} — App Links는 검증되지 않습니다. hosting 설정을 확인하세요." >&2
    exit 1
  fi
else
  echo "   (curl 없음 — 브라우저로 직접 확인하세요)"
fi
