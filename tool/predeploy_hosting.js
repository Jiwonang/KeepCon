#!/usr/bin/env node
/**
 * KeepCon — Hosting 배포 직전에 **대상에 맞는 웹 빌드를 강제**하는 게이트.
 *
 * ## 왜 스크립트가 아니라 predeploy 훅인가
 * hosting 루트가 `build/web`(gitignore된 **빌드 산출물**)이라, 배포 내용물이 "직전에 어떤
 * 플래그로 빌드했는가"에 달려 있다. `tool/deploy_hosting.sh`가 그 짝을 강제하지만 그건
 * **규약이지 게이트가 아니다** — 맨손 `firebase deploy`가 그대로 우회로다:
 *
 *   1. `keepcon-run` 스킬이 정적 서버 차선책으로 무플래그 `flutter build web`을 지시
 *      → `build/web`이 **에뮬레이터 타깃** 빌드가 된다
 *   2. 나중에 `firebase deploy`(`.firebaserc` default = keepcon-dev)를 치면
 *   3. dev 도메인에 그 빌드가 올라가 방문자 브라우저에서 `isEmulatorReachable()`이 실패,
 *      **모든 초대 링크가 안내 화면에서 죽는다.** 배포는 성공하고 `assetlinks.json`도
 *      200이라 **아무 신호가 없다.**
 *
 * 이 저장소는 "폴더 삭제는 게이트가 아니다"(iOS 제거), "판단을 사람에게 남겨 두면 그
 * 판단이 실패한다"(`tool/verify.sh`)로 같은 교훈을 이미 두 번 적었다. predeploy는 CLI가
 * 어느 경로로 불리든 배포 직전에 돌므로, 여기서만 짝이 강제된다.
 *
 * ## 왜 node인가
 * predeploy는 Windows에서 `cmd.exe`를 통해 실행된다. 이 저장소 README가 못박았듯 거기서
 * `bash`는 **WSL로 잡혀** Git Bash 스크립트가 실행되지 않는다. node는 firebase CLI 자신이
 * node 앱이라 항상 존재하고 플랫폼을 가리지 않는다.
 *
 * ## 대상은 어떻게 아는가
 * firebase CLI가 훅 프로세스에 `GCLOUD_PROJECT`를 넣어 준다(lifecycleHooks.js). 그 값을
 * 표로 옮겨 플래그를 고른다 — 표가 **여기 한 벌만** 있어야 짝이 갈라지지 않는다.
 */
'use strict';

const { spawnSync } = require('node:child_process');
const { existsSync } = require('node:fs');

/** 대상 프로젝트 → 빌드 플래그. 이 표가 짝을 강제하는 유일한 지점이다. */
const DEFINE_BY_PROJECT = {
  'keepcon-dev': 'USE_FIREBASE=true',
  'keepcon-ab660': 'USE_FIREBASE_PROD=true',
};

function fail(message) {
  console.error(`\n✋ [predeploy] ${message}\n`);
  process.exit(1);
}

const project = process.env.GCLOUD_PROJECT;
if (!project) {
  // 대상을 모르면 어떤 플래그로 빌드해야 할지도 모른다. 추측해서 올리지 않는다.
  fail('GCLOUD_PROJECT 가 비어 있습니다 — --project 로 대상을 지정하세요.');
}

const define = DEFINE_BY_PROJECT[project];
if (!define) {
  fail(
    `알 수 없는 배포 대상 '${project}'.\n` +
      `   빌드 플래그를 정할 수 없습니다. tool/predeploy_hosting.js 의 표에 추가하세요.`
  );
}

// assetlinks.json 이 빌드 산출물에 실려야 App Links 가 검증된다. 없으면 배포해봐야
// 안드로이드 링크가 조용히 브라우저로 샌다 — 배포 전에 막는다.
if (!existsSync('web/.well-known/assetlinks.json')) {
  fail('web/.well-known/assetlinks.json 이 없습니다 — App Links 검증이 실패합니다.');
}

console.log(`\n🔨 [predeploy] ${project} 용으로 웹 빌드 (${define})`);
const build = spawnSync(
  'flutter',
  ['build', 'web', '--release', `--dart-define=${define}`],
  { stdio: 'inherit', shell: true }
);
if (build.error) fail(`flutter 를 실행할 수 없습니다: ${build.error.message}`);
if (build.status !== 0) fail('웹 빌드 실패 — 배포하지 않습니다.');

// 빌드가 dot 디렉터리를 옮기지 않으면 검증 파일 없이 배포된다. 산출물에서 다시 본다.
if (!existsSync('build/web/.well-known/assetlinks.json')) {
  fail('빌드 산출물에 assetlinks.json 이 없습니다(web/ 에서 복사되지 않음).');
}

console.log(`✅ [predeploy] ${project} 용 빌드 완료 — 배포를 진행합니다.\n`);
