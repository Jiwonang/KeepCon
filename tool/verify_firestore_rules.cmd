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

call "%~dp0_find_git_bash.cmd" || exit /b 1

echo [KeepCon] Using Git Bash: %GIT_BASH%
"%GIT_BASH%" tool/verify_firestore_rules.sh
exit /b %errorlevel%
