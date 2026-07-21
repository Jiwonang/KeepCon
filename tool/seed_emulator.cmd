@echo off
rem ============================================================================
rem KeepCon - regenerate the committed emulator seed (Windows cmd / PowerShell).
rem
rem This is a thin wrapper that locates Git Bash and runs tool/seed_emulator.sh.
rem
rem Why delegate instead of porting to batch:
rem   seed_emulator.sh is ~300 lines of HTTP calls, JSON payloads and read-back
rem   verification. A batch port would be a SECOND implementation of the same
rem   logic, and the two would drift apart - one gets a fix, the other does not,
rem   and the seed silently differs depending on who regenerated it. One
rem   implementation, one behaviour.
rem
rem   tool/emulators.cmd is native batch instead, because it is a single command
rem   with no logic to duplicate - so the common path needs no Git Bash at all.
rem
rem Usage (from anywhere in the repo), with the emulators already running:
rem   tool\seed_emulator.cmd
rem
rem IMPORTANT - THIS FILE MUST STAY PURE ASCII, COMMENTS INCLUDED.
rem   See the same note in tool/emulators.cmd for why.
rem ============================================================================
setlocal

cd /d "%~dp0.." || exit /b 1

call "%~dp0_find_git_bash.cmd" || exit /b 1

echo [KeepCon] Using Git Bash: %GIT_BASH%
"%GIT_BASH%" tool/seed_emulator.sh
exit /b %errorlevel%
