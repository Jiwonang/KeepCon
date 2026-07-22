@echo off
rem ============================================================================
rem KeepCon - wipe the shared dev project's Firestore data (Windows cmd/PowerShell).
rem
rem This is the cmd counterpart of tool/reset_dev.sh. Both do the same thing:
rem   - delete ALL Firestore collections in the dev project (keepcon-dev)
rem   - never touch the production project (keepcon-ab660)
rem   - leave Auth accounts alone, so nobody has to sign up again
rem
rem Why this exists:
rem   Real Firestore has no branches and no rollback, so shared dev data only
rem   accumulates. The emulator resets on restart; the dev project needs a script.
rem
rem Usage (from anywhere in the repo):
rem   tool\reset_dev.cmd            - asks for confirmation
rem   tool\reset_dev.cmd --yes      - no prompt
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

rem Hardcoded on purpose. Making the target configurable via an environment
rem variable would eventually let someone point this at production.
set "DEV_PROJECT=keepcon-dev"
set "PROD_PROJECT=keepcon-ab660"

if "%DEV_PROJECT%"=="%PROD_PROJECT%" (
  echo [KeepCon] STOP: delete target is the production project. This script is dev-only.
  exit /b 1
)

where firebase >nul 2>&1
if errorlevel 1 (
  echo [KeepCon] ERROR: firebase CLI not found.
  echo [KeepCon] Install it first:  npm install -g firebase-tools
  exit /b 1
)

if "%~1"=="--yes" goto :run

echo [KeepCon] WARNING: this deletes ALL Firestore data in "%DEV_PROJECT%".
echo [KeepCon] Auth accounts are kept. Production "%PROD_PROJECT%" is not touched.
set "ANSWER="
set /p "ANSWER=Type yes to continue: "
if /i not "%ANSWER%"=="yes" (
  echo [KeepCon] Cancelled.
  exit /b 0
)

:run
echo [KeepCon] Wiping Firestore in %DEV_PROJECT% ...
call firebase firestore:delete --all-collections --force --project "%DEV_PROJECT%"
if errorlevel 1 (
  echo [KeepCon] ERROR: delete failed. Check 'firebase login' and project access.
  exit /b 1
)

echo [KeepCon] Done. Run the app again to start from an empty state:
echo [KeepCon]   flutter run -d chrome --dart-define=USE_FIREBASE=true
exit /b 0
