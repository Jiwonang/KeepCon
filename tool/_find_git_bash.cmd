@echo off
rem ============================================================================
rem KeepCon - internal helper: locate Git Bash and set GIT_BASH.
rem
rem Not meant to be run directly. Wrappers call it like this:
rem   call "%~dp0_find_git_bash.cmd" || exit /b 1
rem   "%GIT_BASH%" tool/some_script.sh
rem
rem Deliberately has NO `setlocal` - the caller needs GIT_BASH to survive the
rem call. Exits 1 with an install hint when Git Bash cannot be found.
rem
rem Why this file exists:
rem   Two wrappers (seed_emulator.cmd, verify_firestore_rules.cmd) need the same
rem   detection. Copy-pasting it means a fix to the search order lands in one
rem   file and not the other, and the two silently disagree about which bash to
rem   use. One copy, one behaviour.
rem
rem IMPORTANT - THIS FILE MUST STAY PURE ASCII, COMMENTS INCLUDED.
rem   See the note in tool/emulators.cmd for why.
rem ============================================================================

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
  echo [KeepCon] Install Git for Windows: https://git-scm.com/downloads
  echo [KeepCon] See docs/GETTING_STARTED.md
  exit /b 1
)

exit /b 0
