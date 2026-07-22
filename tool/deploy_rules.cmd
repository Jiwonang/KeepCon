@echo off
rem ============================================================================
rem KeepCon - deploy Firestore rules and indexes (Windows cmd / PowerShell).
rem
rem This is the cmd counterpart of tool/deploy_rules.sh. Both do the same thing:
rem   - deploy firestore.rules + firestore.indexes.json to a real project
rem   - default to dev, require an explicit confirmation for production
rem   - with "all", deploy dev first and stop if it fails
rem
rem Why this exists:
rem   With dev and prod split, a rules change has to reach BOTH. Deploying only
rem   one produces "works on dev, blocked on prod" bugs whose cause is a missed
rem   deploy rather than the code. Do not leave that to memory.
rem
rem The emulator is NOT a deploy target - it reads firestore.rules from disk via
rem firebase.json. Restart the emulator to pick up rule changes.
rem
rem Usage (from anywhere in the repo):
rem   tool\deploy_rules.cmd              - dev only (default)
rem   tool\deploy_rules.cmd dev
rem   tool\deploy_rules.cmd prod         - production, asks for confirmation
rem   tool\deploy_rules.cmd all          - dev then prod
rem   tool\deploy_rules.cmd all --yes    - no prompt (CI)
rem
rem IMPORTANT - THIS FILE MUST STAY PURE ASCII, COMMENTS INCLUDED.
rem   Korean text anywhere in a .cmd file (even in rem lines) is decoded with the
rem   console code page, and the resulting bytes make the batch parser try to run
rem   fragments of the comment as commands. Korean explanations belong in
rem   docs/GETTING_STARTED.md, not here.
rem ============================================================================
setlocal

rem Move to the repo root. %~dp0 is this file's directory (tool\).
cd /d "%~dp0.." || exit /b 1

set "DEV_PROJECT=keepcon-dev"
set "PROD_PROJECT=keepcon-ab660"
set "ONLY=firestore:rules,firestore:indexes"

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=dev"

set "AUTO_YES="
if /i "%~1"=="--yes" set "AUTO_YES=1"
if /i "%~2"=="--yes" set "AUTO_YES=1"
if /i "%~3"=="--yes" set "AUTO_YES=1"
if "%TARGET%"=="--yes" set "TARGET=dev"

where firebase >nul 2>&1
if errorlevel 1 (
  echo [KeepCon] ERROR: firebase CLI not found.
  echo [KeepCon] Install it first:  npm install -g firebase-tools
  exit /b 1
)

if not exist "firestore.rules" (
  echo [KeepCon] ERROR: firestore.rules not found. Run from a repo clone.
  exit /b 1
)
if not exist "firestore.indexes.json" (
  echo [KeepCon] ERROR: firestore.indexes.json not found. Run from a repo clone.
  exit /b 1
)

if /i "%TARGET%"=="dev"  goto :do_dev
if /i "%TARGET%"=="prod" goto :do_prod
if /i "%TARGET%"=="all"  goto :do_all

echo [KeepCon] ERROR: unknown target "%TARGET%".
echo [KeepCon] Usage: tool\deploy_rules.cmd [dev^|prod^|all] [--yes]
exit /b 1

:do_dev
call :deploy "%DEV_PROJECT%" || exit /b 1
goto :footer

:do_prod
call :confirm_prod || goto :cancelled
call :deploy "%PROD_PROJECT%" || exit /b 1
goto :footer

:do_all
rem dev first - if it breaks here, production is left untouched.
call :deploy "%DEV_PROJECT%" || exit /b 1
call :confirm_prod || goto :dev_only
call :deploy "%PROD_PROJECT%" || exit /b 1
goto :footer

:confirm_prod
if defined AUTO_YES exit /b 0
echo [KeepCon] WARNING: deploying security rules to PRODUCTION "%PROD_PROJECT%".
echo [KeepCon] Bad rules block real users immediately.
set "ANSWER="
set /p "ANSWER=Type prod to continue: "
if /i "%ANSWER%"=="prod" exit /b 0
exit /b 1

:deploy
echo [KeepCon] Deploying rules and indexes to %~1 ...
call firebase deploy --only "%ONLY%" --project "%~1"
if errorlevel 1 (
  echo [KeepCon] ERROR: deploy to %~1 failed.
  exit /b 1
)
echo [KeepCon] Done: %~1
exit /b 0

:cancelled
echo [KeepCon] Cancelled.
exit /b 0

:dev_only
echo [KeepCon] Deployed dev only (production cancelled).
exit /b 0

:footer
echo.
echo [KeepCon] The emulator is not a deploy target - it reads firestore.rules directly.
echo [KeepCon] Restart it to pick up changes:  tool\emulators.cmd
echo [KeepCon] Verify the rules actually block: tool\verify_firestore_rules.cmd
exit /b 0
