#!/usr/bin/env bash
# KeepCon — Firebase 에뮬레이터 실행 (커밋된 시드 계정을 불러온 상태로).
#
# 이 스크립트로 띄우면 `emulator-seed/`의 방장·파티원 계정이 이미 들어 있는 상태로
# 시작한다. 팀원 누구나 clone 직후 같은 계정·같은 uid로 로그인할 수 있다.
#
#   방장   owner@keepcon.test  / test1234
#   파티원 member@keepcon.test / test1234
#
# 사용법:
#   터미널 A: bash tool/emulators.sh
#   터미널 B: flutter run --dart-define=USE_FIREBASE_EMULATOR=true
#
# ## 왜 --export-on-exit를 쓰지 않는가
# 종료할 때마다 자동으로 내보내면, 각자 개발하며 만든 임시 데이터가 커밋된 시드를
# 덮어써서 `emulator-seed/`에 매번 diff가 생긴다(그리고 남의 테스트 데이터가 딸려
# 들어온다). 시드는 **의도적으로 바꿀 때만** `tool/seed_emulator.sh`로 갱신한다.
# 즉 이 스크립트에서 만든 데이터는 종료 시 사라지는 것이 정상이다.
set -uo pipefail

# 시드 경로가 저장소 루트 기준 상대경로라, 실행 위치에 따라 결과가 달라진다.
# 예: `cd tool && bash emulators.sh` 하면 emulator-seed/를 못 찾아 **시드 없이 빈 상태로**
# 조용히 시작한다 — 팀원은 "시드가 안 되네"로 오해하게 된다.
# 어디서 실행하든 같게 동작하도록 스크립트 위치 기준으로 저장소 루트로 이동한다.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

PROJECT="${FIRESTORE_PROJECT:-demo-keepcon}"
SEED_DIR="${SEED_DIR:-emulator-seed}"

if [[ -d "${SEED_DIR}" ]]; then
  exec firebase emulators:start --project "${PROJECT}" --import="${SEED_DIR}"
fi

echo "⚠️ ${SEED_DIR}/ 가 없습니다 — 시드 계정 없이 빈 상태로 시작합니다."
echo "   시드를 만들려면 이 에뮬레이터가 뜬 뒤 다른 터미널에서:"
echo "     bash tool/seed_emulator.sh"
exec firebase emulators:start --project "${PROJECT}"
