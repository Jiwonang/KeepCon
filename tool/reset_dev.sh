#!/usr/bin/env bash
# KeepCon — 팀 개발 프로젝트(keepcon-dev)의 Firestore 데이터를 통째로 비운다.
#
# 실서버 팀 개발에는 "리셋"이 없다. 에뮬레이터는 껐다 켜면 시드 상태로 돌아가지만
# 실제 Firestore에는 브랜치도 롤백도 없어서, 테스트 데이터가 계속 쌓이고 누군가
# 지운 그룹은 그냥 사라진다. 그래서 **주기적으로 다 밀고 새로 시작**하는 방법이 필요하다.
#
# 사용법:
#   bash tool/reset_dev.sh          # 확인 프롬프트 후 삭제
#   bash tool/reset_dev.sh --yes    # 확인 없이 삭제 (CI·스크립트용)
#
# ## 무엇이 지워지나
# Firestore의 **모든 컬렉션**(users·gifticons·groups·sharedGifticons·usageLogs·
# notifications·shareLocks). **Auth 계정은 지우지 않는다** — 팀원이 매번 회원가입을
# 다시 하는 것보다 로그인 상태를 유지하는 편이 낫기 때문이다. 계정까지 정리하려면
# 콘솔의 Authentication 탭에서 직접 지운다.
#
# ⚠️ 프로필 문서(users/{uid})는 지워지므로, 리셋 후 첫 로그인 시 프로필이 비어 있을
#    수 있다. 회원가입을 다시 하거나 앱에서 프로필을 갱신하면 복구된다.
set -uo pipefail

# 실행 위치와 무관하게 저장소 루트 기준으로 동작하게 한다.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# ⚠️ 하드코딩이 의도적이다. 환경변수로 프로젝트를 바꿀 수 있게 만들면 언젠가
#    누군가 실서비스 프로젝트를 넘기게 된다. 이 스크립트는 dev 전용이다.
readonly DEV_PROJECT="keepcon-dev"
readonly PROD_PROJECT="keepcon-ab660"

# 방어선: .firebaserc나 CLI 기본 프로젝트가 어떻게 설정돼 있든 항상 --project로
# dev를 명시한다. 아래 확인은 "혹시 상수가 잘못 편집됐나"에 대한 마지막 백스톱이다.
if [[ "${DEV_PROJECT}" == "${PROD_PROJECT}" ]]; then
  echo "✋ 중단: 삭제 대상이 실서비스 프로젝트(${PROD_PROJECT})로 설정돼 있습니다." >&2
  echo "   이 스크립트는 dev 전용입니다. 상수를 확인하세요." >&2
  exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "✋ firebase CLI를 찾을 수 없습니다. 설치: npm install -g firebase-tools" >&2
  exit 1
fi

if [[ "${1:-}" != "--yes" ]]; then
  echo "⚠️  '${DEV_PROJECT}' 의 Firestore 데이터를 전부 삭제합니다."
  echo "   (Auth 계정은 유지됩니다. 실서비스 '${PROD_PROJECT}' 는 건드리지 않습니다.)"
  read -r -p "   계속하려면 'yes' 를 입력하세요: " answer
  if [[ "${answer}" != "yes" ]]; then
    echo "취소했습니다."
    exit 0
  fi
fi

echo "🧹 ${DEV_PROJECT} Firestore 비우는 중…"
if ! firebase firestore:delete --all-collections --force --project "${DEV_PROJECT}"; then
  echo "✋ 삭제에 실패했습니다. 'firebase login' 상태와 프로젝트 권한을 확인하세요." >&2
  exit 1
fi

echo "✅ 완료. 앱을 다시 실행하면 빈 상태로 시작합니다:"
echo "   flutter run -d chrome --dart-define=USE_FIREBASE=true"
