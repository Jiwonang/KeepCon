@echo off
rem ============================================================================
rem KeepCon - Firebase emulators launcher (Windows cmd / PowerShell).
rem
rem This is the cmd counterpart of tool/emulators.sh. Both do the same thing:
rem   - keep YOUR data on YOUR PC in .emulator-local\ (gitignored), so the
rem     account you register stays available across restarts
rem   - bootstrap from the committed emulator-seed\ on the very first run
rem   - work no matter which directory you run them from
rem
rem Usage (from anywhere in the repo):
rem   tool\emulators.cmd
rem   tool\emulators.cmd --fresh    (throw away local data, start from the seed)
rem
rem Shut down with Ctrl+C. Closing the window kills the process without the
rem clean-exit signal, and nothing from that session gets saved.
rem
rem Why a separate file:
rem   In cmd/PowerShell, `bash tool/emulators.sh` resolves `bash` to WSL
rem   (C:\Windows\System32\bash.exe), not Git Bash, and fails. Making it work in
rem   the shell people already use beats telling them to switch shells.
rem
rem IMPORTANT - THIS FILE MUST STAY PURE ASCII, COMMENTS INCLUDED.
rem   Korean text anywhere in a .cmd file (even in rem lines) is decoded with the
rem   console code page, and the resulting bytes make the batch parser try to run
rem   fragments of the comment as commands. Adding `chcp 65001` does not fix it -
rem   it corrupts parsing of the remaining lines instead. Korean explanations
rem   belong in docs/GETTING_STARTED.md, not here.
rem ============================================================================
setlocal

rem Move to the repo root. %~dp0 is this file's directory (tool\).
cd /d "%~dp0.." || exit /b 1

if not defined FIRESTORE_PROJECT set "FIRESTORE_PROJECT=demo-keepcon"
if not defined SEED_DIR set "SEED_DIR=emulator-seed"
if not defined LOCAL_DIR set "LOCAL_DIR=.emulator-local"

where firebase >nul 2>&1
if errorlevel 1 (
  echo [KeepCon] ERROR: firebase CLI not found.
  echo [KeepCon] Install it first:  npm install -g firebase-tools
  echo [KeepCon] See docs/GETTING_STARTED.md
  exit /b 1
)

if "%~1"=="" goto :choose_import
if /i "%~1"=="--fresh" goto :fresh
echo [KeepCon] ERROR: unknown option "%~1"  (supported: --fresh)
exit /b 2

:fresh
if exist "%LOCAL_DIR%\" (
  rmdir /s /q "%LOCAL_DIR%"
  echo [KeepCon] Removed "%LOCAL_DIR%" - starting from the committed seed.
) else (
  echo [KeepCon] "%LOCAL_DIR%" not found - already at seed state.
)

rem Decide where to import from: your local data first, then the committed seed.
rem Passing a non-existent path to --import stops the emulator from starting, so
rem each branch only names a directory it has just verified exists.
:choose_import
if exist "%LOCAL_DIR%\" goto :with_local
if exist "%SEED_DIR%\" goto :with_seed

echo [KeepCon] WARNING: "%SEED_DIR%" not found - starting with an EMPTY emulator.
echo [KeepCon] The shared test accounts will NOT be available.
echo [KeepCon] Run this from a repo clone that includes "%SEED_DIR%".
echo [KeepCon] Your data will be saved to "%LOCAL_DIR%" on Ctrl+C.
call firebase emulators:start --project "%FIRESTORE_PROJECT%" --export-on-exit="%LOCAL_DIR%"
exit /b %errorlevel%

:with_local
echo [KeepCon] Starting with YOUR data: %LOCAL_DIR%
echo [KeepCon] Saved back to "%LOCAL_DIR%" on Ctrl+C.
call firebase emulators:start --project "%FIRESTORE_PROJECT%" --import="%LOCAL_DIR%" --export-on-exit="%LOCAL_DIR%"
exit /b %errorlevel%

:with_seed
echo [KeepCon] First run - starting from the committed seed: %SEED_DIR%
echo [KeepCon] Accounts: owner@keepcon.test / member@keepcon.test  (password: test1234)
echo [KeepCon] From now on your data lives in "%LOCAL_DIR%" (saved on Ctrl+C).
call firebase emulators:start --project "%FIRESTORE_PROJECT%" --import="%SEED_DIR%" --export-on-exit="%LOCAL_DIR%"
exit /b %errorlevel%
