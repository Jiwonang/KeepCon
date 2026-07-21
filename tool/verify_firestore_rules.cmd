@echo off
rem ============================================================================
rem KeepCon - verify firestore.rules against the emulator (Windows cmd/PowerShell).
rem
rem Thin wrapper: locates Git Bash and runs tool/verify_firestore_rules.sh.
rem Same reasoning as tool/seed_emulator.cmd - the .sh is a long script of HTTP
rem calls and assertions, and a batch port would be a second implementation that
rem drifts. One implementation, one behaviour.
rem
rem Usage (from anywhere in the repo), with the emulators already running:
rem   tool\verify_firestore_rules.cmd
rem
rem IMPORTANT - THIS FILE MUST STAY PURE ASCII, COMMENTS INCLUDED.
rem   See the note in tool/emulators.cmd for why.
rem ============================================================================
setlocal

cd /d "%~dp0.." || exit /b 1

set "GIT_BASH="

rem Preferred: derive Git Bash from git.exe on PATH.
rem   C:\...\Git\cmd\git.exe  ->  C:\...\Git\bin\bash.exe
for /f "delims=" %%I in ('where git 2^>nul') do (
  if not defined GIT_BASH (
    for %%A in ("%%~dpI.") do (
      for %%B in ("%%~dpA.") do (
        if exist "%%~fB\bin\bash.exe" set "GIT_BASH=%%~fB\bin\bash.exe"
      )
    )
  )
)

rem Fallbacks for common install locations.
if not defined GIT_BASH if exist "%ProgramFiles%\Git\bin\bash.exe" set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GIT_BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "GIT_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined GIT_BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "GIT_BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"

if not defined GIT_BASH (
  echo [KeepCon] ERROR: Git Bash not found.
  echo [KeepCon] This script needs it to run tool/verify_firestore_rules.sh.
  echo [KeepCon] Install Git for Windows: https://git-scm.com/downloads
  echo [KeepCon] See docs/GETTING_STARTED.md
  exit /b 1
)

echo [KeepCon] Using Git Bash: %GIT_BASH%
"%GIT_BASH%" tool/verify_firestore_rules.sh
exit /b %errorlevel%
