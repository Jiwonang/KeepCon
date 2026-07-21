@echo off
rem ============================================================================
rem KeepCon - Firebase emulators launcher (Windows cmd / PowerShell).
rem
rem This is the cmd counterpart of tool/emulators.sh. Both do the same thing:
rem   - start the emulators with the committed emulator-seed/ imported
rem   - work no matter which directory you run them from
rem
rem Why a separate file:
rem   In cmd/PowerShell, `bash tool/emulators.sh` resolves `bash` to WSL
rem   (C:\Windows\System32\bash.exe), not Git Bash, and fails. Making it work in
rem   the shell people already use beats telling them to switch shells.
rem
rem Usage (from anywhere in the repo):
rem   tool\emulators.cmd
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

where firebase >nul 2>&1
if errorlevel 1 (
  echo [KeepCon] ERROR: firebase CLI not found.
  echo [KeepCon] Install it first:  npm install -g firebase-tools
  echo [KeepCon] See docs/GETTING_STARTED.md
  exit /b 1
)

if exist "%SEED_DIR%\" goto :with_seed

echo [KeepCon] WARNING: "%SEED_DIR%" not found - starting with an EMPTY emulator.
echo [KeepCon] The shared test accounts will NOT be available.
echo [KeepCon] Run this from a repo clone that includes "%SEED_DIR%".
call firebase emulators:start --project "%FIRESTORE_PROJECT%"
exit /b %errorlevel%

:with_seed
echo [KeepCon] Starting emulators with seed: %SEED_DIR%
echo [KeepCon] Accounts: owner@keepcon.test / member@keepcon.test  (password: test1234)
call firebase emulators:start --project "%FIRESTORE_PROJECT%" --import="%SEED_DIR%"
exit /b %errorlevel%
