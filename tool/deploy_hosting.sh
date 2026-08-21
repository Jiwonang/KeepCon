#!/usr/bin/env bash
# KeepCon — Flutter 웹 빌드를 Firebase Hosting에 배포한다.
#
# ## 빌드는 여기서 하지 않는다 — predeploy 훅이 한다
# hosting 루트가 `build/web`(gitignore된 빌드 산출물)이라, 배포 내용물이 "직전에 어떤
# 플래그로 빌드했는가"에 달려 있다. 그 짝을 이 스크립트가 강제하면 **규약**일 뿐이고,
# 맨손 `firebase deploy`가 그대로 우회로가 된다. 그래서 강제는 `firebase.json`의
# `hosting.predeploy`(→ `tool/predeploy_hosting.js`)에 두었다 — CLI가 어느 경로로 불리든
# 배포 직전에 돈다. 대상→플래그 표도 거기 한 벌만 있다.
#
# 그러면 이 스크립트는 무엇을 하는가:
#   - 대상 이름(dev/prod)을 프로젝트 id로 옮기고, prod에는 확인을 받는다
#   - **매니페스트 대조** — 링크를 받는 쪽(App Links 필터)에 이 도메인이 있는지
#   - 배포 후 `assetlinks.json`이 200인지 확인
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
readonly MANIFEST="android/app/src/main/AndroidManifest.xml"

target="${1:-dev}"
auto_yes=""
for arg in "$@"; do
  [[ "${arg}" == "--yes" ]] && auto_yes="1"
done

if ! command -v firebase >/dev/null 2>&1; then
  echo "✋ firebase CLI 를 찾을 수 없습니다." >&2
  exit 1
fi

confirm_prod() {
  [[ -n "${auto_yes}" ]] && return 0
  echo "⚠️  실서비스 '${PROD_PROJECT}' 에 웹 앱을 배포합니다."
  read -r -p "   계속하려면 'prod' 를 입력하세요: " answer
  [[ "${answer}" == "prod" ]]
}

case "${target}" in
  dev)
    project="${DEV_PROJECT}"; host="keepcon-dev.web.app"
    ;;
  prod)
    if ! confirm_prod; then
      echo "취소했습니다."
      exit 0
    fi
    project="${PROD_PROJECT}"; host="keepcon-ab660.web.app"
    ;;
  *)
    echo "✋ 알 수 없는 대상: '${target}'" >&2
    echo "   사용법: bash tool/deploy_hosting.sh [dev|prod] [--yes]" >&2
    exit 1
    ;;
esac

# `host`는 이 도메인을 아는 네 번째 자리다(`inviteOriginFor`·매니페스트·assetlinks·여기).
# 링크를 **받는** 곳은 매니페스트이므로, 거기 없는 도메인의 200을 확인해봐야 의미가 없다 —
# 다른 도메인을 검사하고 ✅를 내는 것이 아무것도 안 하는 것보다 나쁘다.
# (`inviteOriginFor`와의 대조는 셸에서 못 하므로
#  test/shared/providers/invite_link_providers_test.dart 가 맡는다.)
if ! grep -q "android:host=\"${host}\"" "${MANIFEST}"; then
  echo "✋ ${host} 가 ${MANIFEST} 의 App Links 필터에 없습니다 — 안드로이드 링크가 브라우저로 샙니다." >&2
  exit 1
fi

echo "🚀 ${project} 에 배포 중… (빌드는 predeploy 훅이 합니다)"
if ! firebase deploy --only hosting --project "${project}"; then
  echo "✋ ${project} 배포 실패." >&2
  exit 1
fi
echo "✅ ${project} 완료."

# 배포는 성공했는데 검증 파일이 404인 상태가 실제로 있었다(도메인을 매니페스트에만 넣고
# 배포하지 않았던 기간). 여기서 확인해 그 상태로 끝나지 않게 한다.
echo
echo "🔎 https://${host}/.well-known/assetlinks.json 확인…"
if command -v curl >/dev/null 2>&1; then
  code=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' \
    "https://${host}/.well-known/assetlinks.json")
  if [[ "${code}" == "200" ]]; then
    echo "✅ 200 — App Links 검증 준비 완료."
  else
    echo "✋ HTTP ${code} — App Links 는 검증되지 않습니다. hosting 설정을 확인하세요." >&2
    exit 1
  fi
else
  # 배포는 됐으므로 실패로 만들지는 않는다. 다만 "확인했다"와 구분되게 stderr 로 낸다 —
  # 미검증이 성공 로그에 섞이는 것이 이 스크립트가 막으려는 무증상의 모양이다.
  echo "⚠️  curl 이 없어 검증을 건너뛰었습니다 — 브라우저로 직접 확인하세요:" >&2
  echo "    https://${host}/.well-known/assetlinks.json" >&2
fi
