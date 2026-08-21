@echo off
rem ============================================================================
rem KeepCon - deploy the Flutter web build to Firebase Hosting (Windows).
rem
rem Thin wrapper: locates Git Bash and runs tool/deploy_hosting.sh, which builds
rem with the flag that matches the target and only then deploys. Keeping build
rem and deploy welded together is the whole point - see the .sh header.
rem
rem Usage (from anywhere in the repo):
rem   tool\deploy_hosting.cmd
rem   tool\deploy_hosting.cmd dev
rem   tool\deploy_hosting.cmd prod
rem   tool\deploy_hosting.cmd prod --yes
rem
rem IMPORTANT - THIS FILE MUST STAY PURE ASCII, COMMENTS INCLUDED.
rem   See the note in tool/emulators.cmd for why.
rem ============================================================================
setlocal

cd /d "%~dp0.." || exit /b 1

call "%~dp0_find_git_bash.cmd" || exit /b 1

echo [KeepCon] Using Git Bash: %GIT_BASH%
"%GIT_BASH%" tool/deploy_hosting.sh %*
exit /b %errorlevel%
