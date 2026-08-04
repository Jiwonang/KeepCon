#!/usr/bin/env bash
# KeepCon — Firebase 에뮬레이터 실행 (내 PC 전용 데이터가 유지되는 상태로).
#
# 이 에뮬레이터는 **내 PC 안에서만** 도는 진짜 Firebase다. 여기서 만든 계정·기프티콘은
# 팀 공유 dev 서버(`keepcon-dev`)와 아무 상관이 없다. 그래서 그룹 삭제·공유 취소 같은
# 파괴적 테스트를 마음껏 해도 남의 작업이 날아가지 않는다.
#
# ## 데이터가 어디에 남나
# 종료할 때(`Ctrl+C`) `.emulator-local/`에 내보내고, 다음에 켤 때 거기서 불러온다.
# 즉 **내가 만든 계정으로 계속 작업할 수 있다.** 이 폴더는 `.gitignore`에 있어
# 커밋되지 않는다 — 내 데이터가 남의 저장소로 흘러가지 않는다.
#
#   처음 실행    → 커밋된 `emulator-seed/`에서 시작 (아래 공용 계정이 이미 있음)
#   두 번째부터  → `.emulator-local/`에서 시작 (내가 만든 것 그대로)
#
#   방장   owner@keepcon.test  / test1234
#   파티원 member@keepcon.test / test1234
#
# ## 사용법
#   터미널 A: bash tool/emulators.sh
#   터미널 B: flutter run --dart-define=USE_FIREBASE_EMULATOR=true
#
#   처음 상태로 되돌리기: bash tool/emulators.sh --fresh
#     내 데이터를 버리고 커밋된 시드에서 다시 시작한다. 파괴적 테스트로 데이터가
#     엉켰을 때 쓴다.
#
# ## ⚠️ 반드시 Ctrl+C 로 끌 것
# `--export-on-exit`는 **정상 종료 신호를 받아야** 내보낸다. 터미널 창을 그냥 닫거나
# 프로세스를 강제 종료하면 그 세션에서 만든 데이터는 저장되지 않는다.
#
# ## 커밋된 시드(`emulator-seed/`)는 왜 따로인가
# 예전에는 `--export-on-exit`를 아예 쓰지 않았다. 그대로 켜면 각자 만든 임시 데이터가
# **커밋된 시드를 덮어써서** `emulator-seed/`에 매번 diff가 생기고 남의 테스트 데이터가
# 딸려 들어갔기 때문이다. 지금은 내보내는 곳을 개인 폴더로 분리해 그 문제 없이 유지된다.
# 시드 자체는 여전히 **의도적으로 바꿀 때만** `tool/seed_emulator.sh`로 갱신한다.
set -uo pipefail

# 시드 경로가 저장소 루트 기준 상대경로라, 실행 위치에 따라 결과가 달라진다.
# 예: `cd tool && bash emulators.sh` 하면 emulator-seed/를 못 찾아 **시드 없이 빈 상태로**
# 조용히 시작한다 — 팀원은 "시드가 안 되네"로 오해하게 된다.
# 어디서 실행하든 같게 동작하도록 스크립트 위치 기준으로 저장소 루트로 이동한다.
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

PROJECT="${FIRESTORE_PROJECT:-demo-keepcon}"
SEED_DIR="${SEED_DIR:-emulator-seed}"
LOCAL_DIR="${LOCAL_DIR:-.emulator-local}"

if [[ "${1:-}" == "--fresh" ]]; then
  if [[ -d "${LOCAL_DIR}" ]]; then
    rm -rf "${LOCAL_DIR}"
    echo "🧹 ${LOCAL_DIR}/ 를 지웠습니다 — 커밋된 시드에서 다시 시작합니다."
  else
    echo "🧹 ${LOCAL_DIR}/ 가 없습니다 — 이미 시드 상태입니다."
  fi
elif [[ -n "${1:-}" ]]; then
  echo "알 수 없는 옵션: $1 (쓸 수 있는 것: --fresh)" >&2
  exit 2
fi

# 불러올 곳을 정한다. 개인 폴더 > 커밋된 시드 > (없으면 빈 상태).
# 존재하지 않는 경로를 --import에 넘기면 에뮬레이터가 시작조차 못 하므로 반드시 확인한다.
if [[ -d "${LOCAL_DIR}" ]]; then
  echo "📂 내 데이터로 시작합니다: ${LOCAL_DIR}/"
  IMPORT_ARG=(--import="${LOCAL_DIR}")
elif [[ -d "${SEED_DIR}" ]]; then
  echo "🌱 커밋된 시드로 시작합니다: ${SEED_DIR}/ (owner@keepcon.test / member@keepcon.test — test1234)"
  echo "   여기서 만든 것은 종료 시 ${LOCAL_DIR}/ 에 저장되어 다음 실행부터 유지됩니다."
  IMPORT_ARG=(--import="${SEED_DIR}")
else
  echo "⚠️ ${SEED_DIR}/ 가 없습니다 — 시드 계정 없이 빈 상태로 시작합니다."
  echo "   시드를 만들려면 이 에뮬레이터가 뜬 뒤 다른 터미널에서:"
  echo "     bash tool/seed_emulator.sh"
  IMPORT_ARG=()
fi

echo "💾 종료(Ctrl+C) 시 ${LOCAL_DIR}/ 에 저장됩니다. 창을 그냥 닫으면 저장되지 않습니다."

# exec로 교체해야 Ctrl+C가 이 셸을 거치지 않고 firebase에 바로 전달된다.
# 중간에 셸이 끼면 종료 신호가 가로채여 --export-on-exit가 동작하지 않을 수 있다.
exec firebase emulators:start \
  --project "${PROJECT}" \
  "${IMPORT_ARG[@]}" \
  --export-on-exit="${LOCAL_DIR}"
